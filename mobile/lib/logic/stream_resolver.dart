import 'dart:async';
import 'dart:io';
import '../models/song.dart';
import '../domain/models/track_entity.dart';
import '../services/app_logger.dart';
import '../services/youtube_client.dart';
import '../services/saavn_client.dart';
import '../services/audius_client.dart';
import '../services/artist_sanitizer.dart';
import '../services/download_manager.dart';

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

  static const Duration _overallTimeout = Duration(seconds: 25);
  static const Duration _saavnSearchTimeout = Duration(seconds: 6);
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

  Future<String?> _resolveStreamUrlInternal(Song song) async {
    if (song.source == 'audius') {
      final audiusUrl = (song.streamUrl != null && song.streamUrl!.isNotEmpty)
          ? song.streamUrl!
          : AudiusClient.getStreamUrl(song.id);
      song.streamUrl = audiusUrl;
      return audiusUrl;
    }

    if (song.source == 'youtube' || song.id.length == 11) {
      // 1. Direct YouTube stream resolution (User explicitly selected YouTube)
      try {
        final ytUrl = await _youtubeClient.getStreamUrl(song.id, title: song.title, artist: song.artist);
        if (ytUrl != null && ytUrl.isNotEmpty) {
          return ytUrl;
        }
      } catch (e) {
        AppLogger.log('StreamResolver', 'Direct YouTube stream resolution notice: $e');
      }

      // 2. Fallback: Search JioSaavn if YouTube direct extraction returns null
      try {
        final cleanTitle = YouTubeClient.cleanTitle(song.title);
        final cleanArtist = (song.artist.isNotEmpty && !ArtistSanitizer.isRecordLabelOrChannel(song.artist))
            ? song.artist
            : '';
        final query = cleanArtist.isNotEmpty ? '$cleanTitle $cleanArtist' : cleanTitle;
        AppLogger.log('StreamResolver', 'Attempting JioSaavn fallback for YouTube track "$cleanTitle" with query: "$query"');
        final saavnMatches = await SaavnClient.search(query, limit: 5).timeout(_saavnSearchTimeout);
        for (final match in saavnMatches) {
          if (match.streamUrl != null && match.streamUrl!.isNotEmpty && verifyAudioMatch(match, song)) {
            AppLogger.log('StreamResolver', 'JioSaavn fallback matched for YouTube track "${song.title}": "${match.title}"');
            song.streamUrl = match.streamUrl;
            return match.streamUrl;
          }
        }
        if (saavnMatches.isNotEmpty && saavnMatches.first.streamUrl != null && saavnMatches.first.streamUrl!.isNotEmpty) {
          song.streamUrl = saavnMatches.first.streamUrl;
          return saavnMatches.first.streamUrl;
        }
      } catch (e) {
        AppLogger.log('StreamResolver', 'Saavn match fallback notice: $e');
      }
    } else {
      // Direct JioSaavn stream
      try {
        final isInvalidated = _invalidatedSongIds.contains(song.id);
        if (!isInvalidated && song.streamUrl != null && song.streamUrl!.isNotEmpty && !isStreamExpired(song.id)) {
          return song.streamUrl;
        }
        final cleanTitle = YouTubeClient.cleanTitle(song.title);
        final query = song.artist.isNotEmpty ? '$cleanTitle ${song.artist}' : cleanTitle;
        final matches = await SaavnClient.search(query, limit: 5).timeout(_saavnSearchTimeout);
        for (final match in matches) {
          if (match.streamUrl != null && match.streamUrl!.isNotEmpty && verifyAudioMatch(match, song)) {
            _invalidatedSongIds.remove(song.id);
            return match.streamUrl;
          }
        }
        // Second pass: relaxed check for same ID or direct title match before falling back to YouTube
        for (final match in matches) {
          if (match.streamUrl != null && match.streamUrl!.isNotEmpty) {
            if (match.id == song.id || normalizeForComparison(match.title) == normalizeForComparison(song.title)) {
              _invalidatedSongIds.remove(song.id);
              return match.streamUrl;
            }
          }
        }
      } catch (e) {
        AppLogger.log('StreamResolver', 'Direct Saavn stream resolution notice: $e');
      }

      // 3. Fallback: If JioSaavn has no stream, attempt to resolve via YouTube
      try {
        final query = '${YouTubeClient.cleanTitle(song.title)} ${song.artist} audio';
        final ytMatches = await YouTubeClient.search(query, limit: 3);
        for (final yt in ytMatches) {
          final ytUrl = await YouTubeClient.getAudioStreamUrl(yt.id, title: song.title, artist: song.artist);
          if (ytUrl != null && ytUrl.isNotEmpty) {
            _invalidatedSongIds.remove(song.id);
            return ytUrl;
          }
        }
      } catch (e) {
        AppLogger.log('StreamResolver', 'Saavn to YouTube fallback notice: $e');
      }
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
