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

  Future<String?> resolve(dynamic track) async {
    if (track is Song) {
      return resolveStreamUrl(track);
    } else if (track is TrackEntity) {
      return resolveStreamUrl(track.toSong());
    }
    return null;
  }

  Future<String?> resolveStreamUrl(Song song);
  bool verifyAudioMatch(Song candidate, Song target);
  void invalidate(String songId) {}
  bool isExpired(String songId) => false;
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
  }) : _youtubeClient = youtubeClient ?? YoutubeClient();

  // YouTube extraction alone can legitimately take several seconds on mobile
  // data (4 client attempts + CDN probes), so the overall budget must be larger
  // than the old 25s, and the YouTube stage must NOT be capped at 4s.
  static const Duration _overallTimeout = Duration(seconds: 45);
  static const Duration _youtubeStageTimeout = Duration(seconds: 20);
  static const Duration _saavnSearchTimeout = Duration(seconds: 6);

  // One resolution per song at a time (prewarm + user tap used to run twice).
  static final Map<String, Future<String?>> _inFlight = {};
  static const Duration cacheTtl = Duration(hours: 3);

  /// High-integrity HTTP headers for Googlevideo CDN streams (Range + modern User-Agent)
  static Map<String, String> get streamingHeaders => YouTubeClient.streamingHeaders;

  // In-memory stream cache enforcing 3-hour TTL to prevent HTTP 403 CDN expirations
  static final Map<String, StreamCacheEntry> _streamCache = {};
  static final Set<String> _invalidatedSongIds = {};

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
        return entry.url;
      }
      _streamCache.remove(songId); // Purge expired entry
    }
    return null;
  }

  /// Invalidates cached stream URL for a given song (e.g. on playback error / HTTP 403)
  static void invalidateStream(String songId) {
    _streamCache.remove(songId);
    _invalidatedSongIds.add(songId);
    YouTubeClient.invalidateStream(songId);
  }

  /// Clears entire stream cache
  static void clearCache() {
    _streamCache.clear();
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
  Future<String?> resolve(dynamic track) async {
    if (track is Song) {
      return resolveStreamUrl(track);
    } else if (track is TrackEntity) {
      return resolveStreamUrl(track.toSong());
    }
    return null;
  }

  @override
  Future<String?> resolveStreamUrl(Song song) async {
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

    // Check in-memory stream cache (3-hour TTL)
    final cached = getCachedStream(song.id);
    if (cached != null && cached.isNotEmpty) {
      AppLogger.log(
        'StreamResolver',
        'Stream cache HIT for "${song.title}" [id=${song.id}] (TTL valid)',
      );
      song.streamUrl = cached;
      return cached;
    }

    final pending = _inFlight[song.id];
    if (pending != null) {
      final shared = await pending;
      if (shared != null && shared.isNotEmpty) song.streamUrl = shared;
      return shared;
    }
    final run = _resolveFresh(song);
    _inFlight[song.id] = run;
    try {
      return await run;
    } finally {
      _inFlight.remove(song.id);
    }
  }

  Future<String?> _resolveFresh(Song song) async {
    final sw = Stopwatch()..start();
    AppLogger.log(
      'StreamResolver',
      'Resolving fresh stream for: "${song.title}" (${song.artist}) [source=${song.source}, id=${song.id}]',
    );

    try {
      final url = await _resolveStreamUrlInternal(song).timeout(_overallTimeout);
      sw.stop();
      if (url != null && url.isNotEmpty) {
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
      final res = await http.get(streamUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['url'] != null && data['url'].toString().isNotEmpty) {
          return data['url'].toString();
        }
      }

      final searchUri = Uri.parse('$base/music/search?q=${Uri.encodeComponent(cleanTitle)}');
      final sRes = await http.get(searchUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 4));
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

  Future<String?> _resolveStreamUrlInternal(Song song) async {
    if (song.source == 'audius') {
      final audiusUrl = (song.streamUrl != null && song.streamUrl!.isNotEmpty)
          ? song.streamUrl!
          : AudiusClient.getStreamUrl(song.id);
      song.streamUrl = audiusUrl;
      return audiusUrl;
    }

    // Direct Saavn stream if already decrypted and valid
    if (song.streamUrl != null &&
        song.streamUrl!.contains('saavncdn.com') &&
        !_invalidatedSongIds.contains(song.id) &&
        !isStreamExpired(song.id)) {
      return song.streamUrl;
    }

    final cleanBase = extractCleanBaseTitle(song.title);
    final firstArtist = extractFirstArtist(song.artist);
    final queryA = '$cleanBase $firstArtist'.trim();
    final cleanTitleOnly = extractCleanTitleOnly(song.title);

    // A real YouTube video id is exactly 11 chars. (The "YT Music" chip can also
    // hold JioSaavn tracks relabelled as 'youtube'; those ids are NOT video ids.)
    final bool hasYouTubeId =
        song.source == 'youtube' && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(song.id);

    // ── YouTube-first for YouTube tracks ──
    // The YT Music tab must play the actual YouTube audio. JioSaavn is only a
    // verified fallback if YouTube refuses every client.
    if (hasYouTubeId) {
      final ytUrl = await _tryYouTube(song);
      if (ytUrl != null) return ytUrl;
    }

    // ── STAGE A (Exact Clean Title + Primary Artist on Saavn) ──
    final saavnA = await _trySaavn(song, queryA, 'A', requireMatch: hasYouTubeId);
    if (saavnA != null) return saavnA;

    // ── STAGE B (Title-Only Search on Saavn) ──
    final saavnB = await _trySaavn(song, cleanTitleOnly, 'B', requireMatch: hasYouTubeId);
    if (saavnB != null) return saavnB;

    // ── STAGE C (YouTube for non-YouTube tracks, e.g. Saavn miss) ──
    if (!hasYouTubeId && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(song.id)) {
      final ytUrl = await _tryYouTube(song);
      if (ytUrl != null) return ytUrl;
    }

    // ── STAGE D (Backend Stream Proxy) ──
    try {
      AppLogger.log('StreamResolver', 'Stage D backend stream proxy for: ${song.id}');
      final proxyUrl = await _queryBackendStreamProxy(song.id, cleanTitleOnly);
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

  /// Direct YouTube resolution. Has its own generous timeout (the old 4s cap
  /// aborted extractions that were about to succeed).
  Future<String?> _tryYouTube(Song song) async {
    try {
      AppLogger.log('StreamResolver', 'Direct YouTube stream for: ${song.id}');
      final ytUrl = await _youtubeClient
          .getStreamUrl(song.id, title: song.title, artist: song.artist)
          .timeout(_youtubeStageTimeout, onTimeout: () => null);
      if (ytUrl != null && ytUrl.isNotEmpty) {
        song.streamUrl = ytUrl;
        cacheStream(song.id, ytUrl, source: 'youtube');
        return ytUrl;
      }
      AppLogger.log('StreamResolver', 'YouTube returned no playable stream for ${song.id}');
    } catch (e) {
      AppLogger.log('StreamResolver', 'Direct YouTube notice: $e');
    }
    return null;
  }

  /// Searches JioSaavn for [query]. When [requireMatch] is true (we are replacing
  /// a YouTube track) the hit must actually be the same song - otherwise the old
  /// behaviour of taking "the first result" played unrelated tracks.
  Future<String?> _trySaavn(Song song, String query, String stage, {required bool requireMatch}) async {
    if (query.isEmpty) return null;
    try {
      AppLogger.log('StreamResolver', 'Stage $stage search on Saavn: "$query"');
      final matches = await SaavnClient.search(query, limit: 5)
          .timeout(_saavnSearchTimeout, onTimeout: () => <Song>[]);
      for (final match in matches) {
        final url = match.streamUrl;
        if (url == null || !url.contains('saavncdn.com')) continue;
        if (requireMatch && !verifyMatch(match, song)) continue;
        AppLogger.log('StreamResolver', 'Stage $stage matched for "${song.title}": "${match.title}"');
        song.streamUrl = url;
        cacheStream(song.id, url, source: 'saavn');
        return url;
      }
    } catch (e) {
      AppLogger.log('StreamResolver', 'Stage $stage notice: $e');
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
