import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../domain/models/track_entity.dart';
import '../services/app_logger.dart';
import '../services/youtube_client.dart';
import '../services/saavn_client.dart';
import '../services/audius_client.dart';
import '../services/artist_sanitizer.dart';
import '../services/download_manager.dart';
import '../core/app_config.dart';

/// Representation of an in-memory cached stream URL with a strict Time-To-Live (TTL).
class StreamCacheEntry {
  final String url;
  final DateTime expiresAt;
  final String source;

  StreamCacheEntry(this.url, this.expiresAt, {this.source = 'unknown'});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Abstract contract for audio stream URL resolution.
/// Decouples queue management from provider-specific extraction, timeouts, and fallbacks.
abstract class StreamResolver {
  factory StreamResolver({
    YoutubeClient? youtubeClient,
    SaavnClient? saavnClient,
  }) = DefaultStreamResolver;

  Future<String?> resolve(dynamic track, {bool forceSaavnFallback = false, bool forceYouTubeFallback = false});
  Future<String?> resolveStreamUrl(Song song, {bool forceSaavnFallback = false, bool forceYouTubeFallback = false});
  bool verifyAudioMatch(Song candidate, Song target);
  void invalidate(String songId);
  bool isExpired(String songId);
}

/// Production implementation of [StreamResolver] handling multi-tier resolution:
/// 1. Direct provider extraction (YouTube / JioSaavn)
/// 2. Cross-provider fallback matching with audio verification
/// 3. Resilient timeout management
/// 4. 3-hour TTL in-memory stream cache (Spotify/YT Music model)
class DefaultStreamResolver implements StreamResolver {
  final YoutubeClient _youtubeClient;

  DefaultStreamResolver({
    YoutubeClient? youtubeClient,
    SaavnClient? saavnClient,
  })  : _youtubeClient = youtubeClient ?? YoutubeClient();

  static const Duration _overallTimeout = Duration(seconds: 8);
  static const Duration _stageTimeout = Duration(seconds: 4);
  static const Duration cacheTtl = Duration(hours: 3);

  /// High-integrity HTTP headers for Googlevideo CDN streams (Range + modern User-Agent)
  static Map<String, String> get streamingHeaders => YouTubeClient.streamingHeaders;

  // In-memory stream cache enforcing 3-hour TTL to prevent HTTP 403 CDN expirations
  static final Map<String, StreamCacheEntry> _streamCache = {};
  static final Set<String> _invalidatedSongIds = {};
  static final Map<String, Future<String?>> _inFlightResolutions = {};

  /// Caches a resolved stream URL with a 3-hour TTL
  static void cacheStream(String songId, String url, {Duration ttl = cacheTtl, String source = 'unknown'}) {
    _invalidatedSongIds.remove(songId);
    _streamCache[songId] = StreamCacheEntry(url, DateTime.now().add(ttl), source: source);
  }

  /// Retrieves an unexpired cached stream URL, or null if expired/absent
  static String? getCachedStream(String songId) {
    if (_invalidatedSongIds.contains(songId)) return null;
    final entry = _streamCache[songId];
    if (entry != null) {
      if (!entry.isExpired) {
        if (YouTubeClient.isLinkExpired(entry.url)) {
          _streamCache.remove(songId);
          return null;
        }
        return entry.url;
      }
      _streamCache.remove(songId); // Purge expired entry
    }
    return null;
  }

  /// Invalidates cached stream URL for a given song (e.g. on playback error / HTTP 403)
  static void invalidateStream(String songId) {
    _streamCache.remove(songId);
    _inFlightResolutions.remove(songId);
    _invalidatedSongIds.add(songId);
    YouTubeClient.invalidateStream(songId);
  }

  /// Clears entire stream cache
  static void clearCache() {
    _streamCache.clear();
    _inFlightResolutions.clear();
    _invalidatedSongIds.clear();
  }

  /// Checks if a song's cached stream has expired
  static bool isStreamExpired(String songId) {
    if (_invalidatedSongIds.contains(songId)) return true;
    final entry = _streamCache[songId];
    return entry != null && entry.isExpired;
  }

  @override
  void invalidate(String songId) => invalidateStream(songId);

  @override
  bool isExpired(String songId) => isStreamExpired(songId);

  /// Silently resolves and caches stream URLs for the top tracks in the background
  static Future<void> prewarm(List<TrackEntity> tracks, {int limit = 3}) async {
    final toPrewarm = tracks.take(limit).toList();
    final resolver = DefaultStreamResolver();
    await Future.wait(
      toPrewarm.map((t) async {
        try {
          final s = t.toSong();
          if (getCachedStream(s.id) == null) {
            await resolver.resolveStreamUrl(s).timeout(const Duration(seconds: 4), onTimeout: () => null);
          }
        } catch (_) {}
      }),
    );
  }

  /// Silently resolves and caches stream URLs for the top songs in the background
  static Future<void> prewarmSongs(List<Song> songs, {int limit = 3}) async {
    final toPrewarm = songs.take(limit).toList();
    final resolver = DefaultStreamResolver();
    await Future.wait(
      toPrewarm.map((s) async {
        try {
          if (getCachedStream(s.id) == null) {
            await resolver.resolveStreamUrl(s).timeout(const Duration(seconds: 4), onTimeout: () => null);
          }
        } catch (_) {}
      }),
    );
  }

  @override
  Future<String?> resolve(dynamic track, {bool forceSaavnFallback = false, bool forceYouTubeFallback = false}) async {
    if (track is Song) {
      return resolveStreamUrl(track, forceSaavnFallback: forceSaavnFallback, forceYouTubeFallback: forceYouTubeFallback);
    } else if (track is TrackEntity) {
      final s = track.toSong();
      final u = await resolveStreamUrl(s, forceSaavnFallback: forceSaavnFallback, forceYouTubeFallback: forceYouTubeFallback);
      if (s.source == 'saavn') {
        track.source = 'saavn';
      } else if (s.source == 'youtube') {
        track.source = 'youtube';
      }
      return u;
    }
    return null;
  }

  @override
  Future<String?> resolveStreamUrl(Song song, {bool forceSaavnFallback = false, bool forceYouTubeFallback = false}) async {
    // 0. Check DownloadManager local file path first for offline playback
    if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
      return song.localFilePath;
    }
    final offlinePath = DownloadManager.getLocalFilePath(song.id);
    if (offlinePath != null && File(offlinePath).existsSync()) {
      song.localFilePath = offlinePath;
      return offlinePath;
    }

    // Return Audius stream URL directly without stripping or re-requesting
    if (song.source == 'audius' && song.streamUrl != null && song.streamUrl!.isNotEmpty) {
      cacheStream(song.id, song.streamUrl!, source: 'audius');
      return song.streamUrl;
    }

    // Check in-memory stream cache (3-hour TTL) unless forceSaavnFallback or forceYouTubeFallback is true
    if (!forceSaavnFallback && !forceYouTubeFallback) {
      final cached = getCachedStream(song.id);
      if (cached != null && cached.isNotEmpty) {
        AppLogger.log(
          'StreamResolver',
          'Stream cache HIT for "${song.title}" [id=${song.id}] (TTL valid)',
        );
        song.streamUrl = cached;
        return cached;
      }

      // If an identical request is already in-flight, share it instead of firing duplicate network requests
      final inFlight = _inFlightResolutions[song.id];
      if (inFlight != null) {
        AppLogger.log(
          'StreamResolver',
          'Sharing in-flight stream resolution for "${song.title}" [id=${song.id}]',
        );
        final sharedUrl = await inFlight;
        if (sharedUrl != null && sharedUrl.isNotEmpty) {
          song.streamUrl = sharedUrl;
        }
        return sharedUrl;
      }
    }

    final future = () async {
      final sw = Stopwatch()..start();
      AppLogger.log(
        'StreamResolver',
        'Resolving fresh stream for: "${song.title}" (${song.artist}) [source=${song.source}, id=${song.id}, forceSaavn=$forceSaavnFallback, forceYouTube=$forceYouTubeFallback]',
      );

      try {
        final url = await _resolveStreamUrlInternal(
          song,
          forceSaavnFallback: forceSaavnFallback,
          forceYouTubeFallback: forceYouTubeFallback,
        ).timeout(_overallTimeout);
        sw.stop();
        if (url != null && url.isNotEmpty) {
          if (url.contains('saavncdn.com')) {
            song.source = 'saavn';
          }
          cacheStream(song.id, url, source: song.source);
          song.streamUrl = url;
          AppLogger.log('StreamResolver', 'Resolved and cached stream for "${song.title}" in ${sw.elapsedMilliseconds}ms');
        } else {
          AppLogger.log('StreamResolver', 'Stream resolution returned empty for "${song.title}" after ${sw.elapsedMilliseconds}ms');
        }
        return url;
      } catch (e, stack) {
        sw.stop();
        AppLogger.recordError(e, stack, context: 'StreamResolver.resolveStreamUrl for "${song.title}" (${sw.elapsedMilliseconds}ms)');
        return null;
      }
    }();

    if (!forceSaavnFallback && !forceYouTubeFallback) {
      _inFlightResolutions[song.id] = future;
    }

    try {
      return await future;
    } finally {
      if (!forceSaavnFallback && !forceYouTubeFallback) {
        _inFlightResolutions.remove(song.id);
      }
    }
  }

  /// Extracts the base title before delimiters (-, |, /, (, [) and strips parentheticals/noise
  static String extractCleanBaseTitle(String title) {
    var cleaned = Song.sanitize(title);
    cleaned = cleaned.replaceAll(RegExp(r'["'']'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ');
    final splitParts = cleaned.split(RegExp(r'[-–—|/]|(?:\b(feat|ft)\b)', caseSensitive: false));
    if (splitParts.isNotEmpty && splitParts.first.trim().isNotEmpty) {
      cleaned = splitParts.first.trim();
    }
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(official|video|audio|lyric|lyrical|hd|4k|full video|song|teaser|trailer|remix|lofi)\b', caseSensitive: false),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : Song.sanitize(title);
  }

  /// Extracts the primary artist name/word (e.g. "Anirudh")
  static String extractFirstArtist(String artist) {
    var cleaned = Song.sanitize(artist);
    cleaned = cleaned.replaceAll(RegExp(r'["'']'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ');
    // Strip views, labels, channels like "Sony Music", "T-Series", etc.
    cleaned = cleaned.replaceAll(RegExp(r'\b\d+(\.\d+)?[kmb]?\s*views\b', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\b(sony\s*music|t-series|zeemusic|saregama|aditya\s*music|think\s*music|speed\s*records|yrf|tips\s*official)\b', caseSensitive: false), ' ');
    final parts = cleaned.split(RegExp(r'[,&|/]|(?:\b(feat|ft|and)\b)', caseSensitive: false));
    if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
      cleaned = parts.first.trim();
    }
    final words = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isNotEmpty) {
      if (words[0].length <= 3 && words.length > 1) {
        return '${words[0]} ${words[1]}'.trim();
      }
      return words[0].trim();
    }
    return cleaned.trim();
  }

  /// Extracts title only (retaining subtitle after '-' if present, but stripping parentheticals and noise)
  static String extractCleanTitleOnly(String title) {
    var cleaned = Song.sanitize(title);
    cleaned = cleaned.replaceAll(RegExp(r'["'']'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ');
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(official|video|audio|lyric|lyrical|hd|4k|full video|song|teaser|trailer|remix|lofi|music video|visualizer)\b', caseSensitive: false),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'[-–—|/_]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : Song.sanitize(title);
  }

  /// Queries backend stream proxy endpoints if direct extraction fails
  static Future<String?> _queryBackendStreamProxy(String trackId, String cleanTitle) async {
    try {
      final base = AppConfig.backendUrl.replaceAll(RegExp(r'/+$'), '');
      if (base.isEmpty) return null;

      final streamUri = Uri.parse('$base/music/stream/$trackId');
      final res = await http.get(streamUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['url'] != null && data['url'].toString().isNotEmpty) {
          return data['url'].toString();
        }
      }

      final searchUri = Uri.parse('$base/music/search?q=${Uri.encodeComponent(cleanTitle)}');
      final sRes = await http.get(searchUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 3));
      if (sRes.statusCode == 200) {
        final data = jsonDecode(sRes.body);
        if (data is Map && data['results'] is List && (data['results'] as List).isNotEmpty) {
          final first = (data['results'] as List).first;
          final u = first['stream_url'] ?? first['audio_url'] ?? first['url'];
          if (u != null && u.toString().isNotEmpty) {
            return u.toString();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Strips noise keywords, bracketed video tags, and delimiters from YouTube titles
  /// to form an optimal query for JioSaavn Smart Replace.
  static String cleanYouTubeTitle(String title, String artist) {
    var cleaned = YouTubeClient.cleanTitle(title);
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ');
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(official|video|audio|lyric|lyrical|hd|4k|full video|video song|song|teaser|trailer|remix|lofi|music video|visualizer)\b', caseSensitive: false),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'[\|\-–—:_]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) cleaned = title.trim();

    final cleanArtist = (artist.isNotEmpty && !ArtistSanitizer.isRecordLabelOrChannel(artist))
        ? artist.trim()
        : '';
    if (cleanArtist.isNotEmpty && !cleaned.toLowerCase().contains(cleanArtist.toLowerCase())) {
      return '$cleaned $cleanArtist'.trim();
    }
    return cleaned;
  }

  /// Checks if track is a long-form jukebox, compilation, or full album mix (> 10 minutes or keyword match).
  /// These must bypass Saavn single-track fuzzy matching and stream directly from YouTube InnerTube.
  static bool isLongFormOrCompilation(Song song) {
    if (song.duration > 600) return true; // > 10 minutes
    final titleLower = song.title.toLowerCase();
    const compilationKeywords = [
      'jukebox',
      'playlist',
      'all songs',
      'hit songs',
      'hits songs',
      'non stop',
      'non-stop',
      'full album',
      'audio songs',
      'top trending',
      'songs tamil',
      'best of',
      'mashup',
      'mega hit',
      'audio jukebox',
      'jukebox songs',
    ];
    for (final kw in compilationKeywords) {
      if (titleLower.contains(kw)) return true;
    }
    return false;
  }

  Future<String?> _resolveStreamUrlInternal(
    Song song, {
    bool forceSaavnFallback = false,
    bool forceYouTubeFallback = false,
  }) async {
    if (song.source == 'audius') {
      final audiusUrl = (song.streamUrl != null && song.streamUrl!.isNotEmpty)
          ? song.streamUrl!
          : AudiusClient.getStreamUrl(song.id);
      song.streamUrl = audiusUrl;
      return audiusUrl;
    }

    // Direct Saavn stream if already decrypted and valid
    if (!forceSaavnFallback &&
        !forceYouTubeFallback &&
        song.streamUrl != null &&
        song.streamUrl!.contains('saavncdn.com') &&
        !_invalidatedSongIds.contains(song.id) &&
        !isStreamExpired(song.id)) {
      song.source = 'saavn';
      return song.streamUrl;
    }

    final cleanTitleOnly = extractCleanTitleOnly(song.title);
    final bool isCompilation = isLongFormOrCompilation(song);
    final bool shouldBypassSaavnMatching = forceYouTubeFallback ||
        (isCompilation && (song.source == 'youtube' || song.duration > 600));

    if (shouldBypassSaavnMatching) {
      AppLogger.log(
        'StreamResolver',
        forceYouTubeFallback
            ? 'Bypassing Saavn search: forceYouTubeFallback is true for "${song.title}". Direct YouTube extraction prioritized.'
            : 'Bypassing Saavn Stage A/B search: "${song.title}" is a long-form compilation (${song.duration}s). Direct YouTube extraction prioritized.',
      );
    } else {
      // ── STAGE A (Exact Clean Title + Primary Artist on Saavn) ──
      // Strip parentheticals (From ...), [Official ...], quotes, and featured artists.
      // Take song title before '-' or '(' and first artist name (e.g. "Hukum Anirudh").
      final cleanBase = extractCleanBaseTitle(song.title);
      final firstArtist = extractFirstArtist(song.artist);
      final queryA = '$cleanBase $firstArtist'.trim();
      if (queryA.isNotEmpty) {
        try {
          AppLogger.log('StreamResolver', 'Stage A search on Saavn: "$queryA"');
          final saavnMatchesA = await SaavnClient.search(queryA, limit: 5)
              .timeout(_stageTimeout, onTimeout: () => <Song>[]);
          for (final match in saavnMatchesA) {
            if (match.streamUrl != null && match.streamUrl!.contains('saavncdn.com')) {
              // Ensure match doesn't have an extreme duration mismatch with target song (>60s)
              if (song.duration > 0 && match.duration > 0 && (song.duration - match.duration).abs() > 60) {
                continue;
              }
              AppLogger.log('StreamResolver', 'Stage A matched for "${song.title}": "${match.title}" -> ${match.streamUrl}');
              song.source = 'saavn';
              song.streamUrl = match.streamUrl;
              cacheStream(song.id, match.streamUrl!, source: 'saavn');
              return match.streamUrl;
            }
          }
        } catch (e) {
          AppLogger.log('StreamResolver', 'Stage A notice: $e');
        }
      }

      // ── STAGE B (Title-Only Search on Saavn) ──
      // If Stage A returns empty, search Saavn with cleanTitleOnly (e.g. "Hukum Thalaivar Alappara").
      if (cleanTitleOnly.isNotEmpty) {
        try {
          AppLogger.log('StreamResolver', 'Stage B search on Saavn: "$cleanTitleOnly"');
          final saavnMatchesB = await SaavnClient.search(cleanTitleOnly, limit: 5)
              .timeout(_stageTimeout, onTimeout: () => <Song>[]);
          for (final match in saavnMatchesB) {
            if (match.streamUrl != null && match.streamUrl!.contains('saavncdn.com')) {
              if (song.duration > 0 && match.duration > 0 && (song.duration - match.duration).abs() > 60) {
                continue;
              }
              AppLogger.log('StreamResolver', 'Stage B matched for "${song.title}": "${match.title}" -> ${match.streamUrl}');
              song.source = 'saavn';
              song.streamUrl = match.streamUrl;
              cacheStream(song.id, match.streamUrl!, source: 'saavn');
              return match.streamUrl;
            }
          }
        } catch (e) {
          AppLogger.log('StreamResolver', 'Stage B notice: $e');
        }
      }
    }

    // If forceSaavnFallback is true, do not call YouTube
    if (forceSaavnFallback) {
      AppLogger.log('StreamResolver', 'forceSaavnFallback is true; skipping YouTube stages for ${song.id}');
      return null;
    }

    // ── STAGE C (Direct YouTube InnerTube Stream) ──
    // If Stages A & B find nothing on Saavn, call YoutubeClient().getStreamUrl(track.id)
    try {
      AppLogger.log('StreamResolver', 'Stage C direct YouTube stream for: ${song.id}');
      String? ytVideoId = (song.source == 'youtube' && song.id.length == 11) ? song.id : null;
      ytVideoId ??= await YouTubeClient.resolveVideoIdForSong(song);
      if (ytVideoId != null && ytVideoId.isNotEmpty) {
        final ytUrl = await _youtubeClient
            .getStreamUrl(ytVideoId, title: song.title, artist: song.artist)
            .timeout(_stageTimeout, onTimeout: () => null);
        if (ytUrl != null && ytUrl.isNotEmpty) {
          song.source = 'youtube';
          song.streamUrl = ytUrl;
          cacheStream(song.id, ytUrl, source: 'youtube');
          return ytUrl;
        }
      }
    } catch (e) {
      AppLogger.log('StreamResolver', 'Stage C direct YouTube notice: $e');
    }

    // ── STAGE D (Backend Stream Proxy fallback) ──
    try {
      AppLogger.log('StreamResolver', 'Stage D backend stream proxy for: ${song.id}');
      final proxyUrl = await _queryBackendStreamProxy(song.id, cleanTitleOnly)
          .timeout(_stageTimeout, onTimeout: () => null);
      if (proxyUrl != null && proxyUrl.isNotEmpty) {
        song.streamUrl = proxyUrl;
        cacheStream(song.id, proxyUrl, source: 'backend');
        return proxyUrl;
      }
    } catch (e) {
      AppLogger.log('StreamResolver', 'Stage D proxy notice: $e');
    }

    return null;
  }

  @override
  bool verifyAudioMatch(Song candidate, Song target) {
    return verifyMatch(candidate, target);
  }

  /// Static helper for audio match verification (can be used directly across the app)
  static bool verifyMatch(Song candidate, Song target) {
    final normTargetTitle = normalizeForComparison(target.title);
    final normCandTitle = normalizeForComparison(candidate.title);
    if (normTargetTitle.isEmpty || normCandTitle.isEmpty) return false;

    final bool isDirectTitleMatch = (normTargetTitle == normCandTitle ||
        normTargetTitle.contains(normCandTitle) ||
        normCandTitle.contains(normTargetTitle));

    // 1. Duration check:
    // If titles match directly or tracks are from YouTube, allow up to 60 seconds tolerance
    // (YouTube music videos frequently include intros, outros, skits, and dialogue;
    // Saavn tracks can have silence or album/single duration variance up to 30s)
    if (target.duration > 0 && candidate.duration > 0) {
      final diff = (candidate.duration - target.duration).abs();
      final allowedTolerance = (isDirectTitleMatch || target.source == 'youtube' || candidate.source == 'youtube') ? 60 : 30;
      if (diff > allowedTolerance) {
        return false;
      }
    }

    // 2. Title similarity check
    if (isDirectTitleMatch) {
      return true;
    }

    // Token overlap: Check if at least 70% of candidate words exist in target
    final candWords = normCandTitle.split(' ').where((w) => w.length > 2).toSet();
    final targetWords = normTargetTitle.split(' ').where((w) => w.length > 2).toSet();
    if (candWords.isNotEmpty && targetWords.isNotEmpty) {
      final intersection = candWords.intersection(targetWords);
      final overlapRatio = intersection.length / candWords.length;
      if (overlapRatio >= 0.70) {
        return true;
      }
    }

    return false;
  }

  static String normalizeForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'^@[a-z0-9_.]+\s*[-:|~–—]?\s*'), ' ')
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
