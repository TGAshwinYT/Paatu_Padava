import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../domain/models/lyrics_state.dart';
import '../logic/stream_resolver.dart';
import 'lyrics_client.dart';
import 'app_logger.dart';
import 'download_manager.dart';

/// Spotify & Apple Music style Predictive Smart Caching Service.
/// Automatically pre-downloads upcoming tracks in the active queue and radio buffer
/// into an LRU-managed local cache so playback never stalls when mobile data drops.
class SmartCacheService {
  SmartCacheService._();
  static final SmartCacheService instance = SmartCacheService._();

  static const int maxCacheBytes = 150 * 1024 * 1024; // 150 MB smart cache cap (~30 tracks)
  static const int minValidAudioSizeBytes = 100 * 1024; // 100 KB sanity minimum

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  final Map<String, File> _cachedAudioMap = {};
  final Set<String> _activeDownloadingSongIds = {};
  Directory? _smartCacheDir;
  bool _isInitialized = false;

  /// In-memory reactive counter of cached songs for UI/diagnostic visibility
  final ValueNotifier<int> cachedSongsCountNotifier = ValueNotifier<int>(0);

  /// Initializes SmartCacheService and indexes existing cached files
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final baseDir = await getTemporaryDirectory();
      _smartCacheDir = Directory('${baseDir.path}/smart_cache');
      if (!_smartCacheDir!.existsSync()) {
        _smartCacheDir!.createSync(recursive: true);
      }
      await _indexCachedFiles();
      _isInitialized = true;
      AppLogger.log('SmartCacheService', 'Initialized with ${_cachedAudioMap.length} pre-cached songs');
    } catch (e) {
      AppLogger.log('SmartCacheService', 'Initialization notice: $e');
    }
  }

  /// Scans smart_cache directory and populates index
  Future<void> _indexCachedFiles() async {
    if (_smartCacheDir == null || !_smartCacheDir!.existsSync()) return;
    _cachedAudioMap.clear();

    try {
      final entities = _smartCacheDir!.listSync();
      for (final entity in entities) {
        if (entity is File && !entity.path.endsWith('.tmp')) {
          if (entity.lengthSync() >= minValidAudioSizeBytes) {
            final fileName = entity.uri.pathSegments.last;
            final songId = _decodeSongIdFromFileName(fileName);
            if (songId.isNotEmpty) {
              _cachedAudioMap[songId] = entity;
            }
          }
        }
      }
      cachedSongsCountNotifier.value = _cachedAudioMap.length;
    } catch (e) {
      AppLogger.log('SmartCacheService', 'Error indexing cache files: $e');
    }
  }

  String _encodeFileName(String songId) {
    final sanitized = songId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'cache_$sanitized.mp4';
  }

  String _decodeSongIdFromFileName(String fileName) {
    if (fileName.startsWith('cache_') && fileName.endsWith('.mp4')) {
      return fileName.substring(6, fileName.length - 4);
    }
    return '';
  }

  /// Returns true if the song is ready in offline smart cache
  bool isCached(String songId) {
    final sanitized = songId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = _cachedAudioMap[sanitized];
    return file != null && file.existsSync() && file.lengthSync() >= minValidAudioSizeBytes;
  }

  /// Returns the cached audio File if available, otherwise null
  File? getCachedAudioFile(String songId) {
    final sanitized = songId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = _cachedAudioMap[sanitized];
    if (file != null && file.existsSync() && file.lengthSync() >= minValidAudioSizeBytes) {
      // Touch file modified date for LRU recency
      try {
        file.setLastModifiedSync(DateTime.now());
      } catch (_) {}
      return file;
    }
    return null;
  }

  /// Triggered whenever the active track or queue updates:
  /// Identifies the next [preloadCount] upcoming tracks and caches them predictively in the background.
  void onQueueUpdated(Song? activeSong, List<Song> upcomingQueue, {int preloadCount = 3}) {
    if (upcomingQueue.isEmpty) return;

    // Run in unawaited background task so player audio thread is never impeded
    unawaited(() async {
      try {
        if (!_isInitialized) await init();

        // Find active index
        int activeIdx = 0;
        if (activeSong != null) {
          final idx = upcomingQueue.indexWhere((s) => s.id == activeSong.id);
          if (idx != -1) activeIdx = idx;
        }

        // Slice next 2-3 tracks
        final candidates = upcomingQueue
            .skip(activeIdx + 1)
            .take(preloadCount)
            .toList();

        for (final song in candidates) {
          // If already manually downloaded or already in smart cache, skip
          if (DownloadManager.isDownloaded(song.id) || isCached(song.id)) {
            continue;
          }
          await _cacheTrack(song);
        }

        // Run LRU eviction after caching
        await _enforceLruCap();
      } catch (e) {
        AppLogger.log('SmartCacheService', 'Queue predictive pre-caching notice: $e');
      }
    }());
  }

  /// Downloads and caches a single song (audio + lyrics) predictively
  Future<void> _cacheTrack(Song song) async {
    final sanitizedId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (_activeDownloadingSongIds.contains(sanitizedId)) return;
    _activeDownloadingSongIds.add(sanitizedId);

    if (_smartCacheDir == null) {
      _activeDownloadingSongIds.remove(sanitizedId);
      return;
    }

    try {
      // Pre-fetch lyrics simultaneously in background
      unawaited(LyricsClient.instance.fetchLyrics(
        trackId: song.id,
        title: song.title,
        artist: song.artist,
        durationSeconds: song.duration,
      ).catchError((_) => const LyricsState.idle()));

      // Resolve stream URL
      String? streamUrl = song.streamUrl;
      if (streamUrl == null || streamUrl.isEmpty || DefaultStreamResolver.isStreamExpired(song.id)) {
        streamUrl = await DefaultStreamResolver().resolveStreamUrl(song);
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        _activeDownloadingSongIds.remove(sanitizedId);
        return;
      }

      final fileName = _encodeFileName(song.id);
      final targetFile = File('${_smartCacheDir!.path}/$fileName');
      final tmpFile = File('${_smartCacheDir!.path}/$fileName.tmp');

      if (targetFile.existsSync() && targetFile.lengthSync() >= minValidAudioSizeBytes) {
        _cachedAudioMap[sanitizedId] = targetFile;
        _activeDownloadingSongIds.remove(sanitizedId);
        return;
      }

      AppLogger.log('SmartCacheService', 'Predictive caching started for: "${song.title}"');

      await _dio.download(
        streamUrl,
        tmpFile.path,
        options: Options(
          headers: DefaultStreamResolver.streamingHeaders,
        ),
      );

      if (tmpFile.existsSync() && tmpFile.lengthSync() >= minValidAudioSizeBytes) {
        if (targetFile.existsSync()) targetFile.deleteSync();
        tmpFile.renameSync(targetFile.path);
        _cachedAudioMap[sanitizedId] = targetFile;
        cachedSongsCountNotifier.value = _cachedAudioMap.length;
        AppLogger.log('SmartCacheService', 'Predictive caching complete for: "${song.title}" (${(targetFile.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
      } else {
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      }
    } catch (e) {
      AppLogger.log('SmartCacheService', 'Error pre-caching track "${song.title}": $e');
    } finally {
      _activeDownloadingSongIds.remove(sanitizedId);
    }
  }

  /// Enforces LRU size cap (150 MB)
  Future<void> _enforceLruCap() async {
    if (_smartCacheDir == null || !_smartCacheDir!.existsSync()) return;

    try {
      int totalBytes = 0;
      final fileList = <MapEntry<File, DateTime>>[];

      for (final entity in _smartCacheDir!.listSync()) {
        if (entity is File && !entity.path.endsWith('.tmp')) {
          final stat = entity.statSync();
          totalBytes += stat.size;
          fileList.add(MapEntry(entity, stat.modified));
        }
      }

      if (totalBytes <= maxCacheBytes) return;

      // Sort oldest accessed first
      fileList.sort((a, b) => a.value.compareTo(b.value));

      int evicted = 0;
      final targetBytes = (maxCacheBytes * 0.75).round();

      for (final entry in fileList) {
        if (totalBytes <= targetBytes) break;
        final file = entry.key;
        final size = file.lengthSync();
        final fileName = file.uri.pathSegments.last;
        final songId = _decodeSongIdFromFileName(fileName);

        // Don't evict currently downloading files
        if (_activeDownloadingSongIds.contains(songId)) continue;

        try {
          file.deleteSync();
          _cachedAudioMap.remove(songId);
          totalBytes -= size;
          evicted++;
        } catch (_) {}
      }

      cachedSongsCountNotifier.value = _cachedAudioMap.length;
      if (evicted > 0) {
        AppLogger.log('SmartCacheService', 'LRU cache eviction: purged $evicted old tracks, new cache size: ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB');
      }
    } catch (e) {
      AppLogger.log('SmartCacheService', 'LRU enforcement notice: $e');
    }
  }

  /// Clears entire smart cache folder
  Future<void> clearCache() async {
    if (_smartCacheDir == null || !_smartCacheDir!.existsSync()) return;
    try {
      for (final entity in _smartCacheDir!.listSync()) {
        if (entity is File) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
      _cachedAudioMap.clear();
      cachedSongsCountNotifier.value = 0;
      AppLogger.log('SmartCacheService', 'Smart cache cleared');
    } catch (e) {
      AppLogger.log('SmartCacheService', 'clearCache notice: $e');
    }
  }
}
