import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
import 'package:path_provider/path_provider.dart';
import 'download_manager.dart';
import 'settings_manager.dart';

class StorageBreakdown {
  final int offlineAudioBytes;
  final int offlineSongCount;
  final int tempCacheBytes;
  final int imageCacheBytes;
  final int hiveDatabaseBytes;
  final int totalAppBytes;

  const StorageBreakdown({
    required this.offlineAudioBytes,
    required this.offlineSongCount,
    required this.tempCacheBytes,
    required this.imageCacheBytes,
    required this.hiveDatabaseBytes,
    required this.totalAppBytes,
  });

  String get offlineAudioFormatted => formatBytes(offlineAudioBytes);
  String get tempCacheFormatted => formatBytes(tempCacheBytes);
  String get imageCacheFormatted => formatBytes(imageCacheBytes);
  String get hiveDatabaseFormatted => formatBytes(hiveDatabaseBytes);
  String get totalAppFormatted => formatBytes(totalAppBytes);

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Automatic cache eviction manager & storage metrics service:
/// Checks temporary cache directory size on app launch.
/// Enforces size-capped LRU cache eviction and deletes files older than 7 days
/// in the background without blocking the UI thread.
class CacheManager {
  static int get maxCacheSizeBytes => SettingsManager.maxCacheSizeMb * 1024 * 1024;
  static const int maxCacheAgeDays = 7;

  /// Runs background cache audit and true LRU eviction without blocking the UI
  static Future<void> autoEvictOldCache() async {
    Future.microtask(() async {
      try {
        final tempDir = await getTemporaryDirectory();
        if (!tempDir.existsSync()) return;

        final now = DateTime.now();
        const maxAgeDuration = Duration(days: maxCacheAgeDays);

        int totalSize = 0;
        final List<MapEntry<File, FileStat>> fileStats = [];

        // Restrict eviction strictly to audio cache (e.g. just_audio_cache or audio stream files)
        // to avoid clobbering Flutter engine assets, shaders, or image caches.
        final audioCacheDir = Directory('${tempDir.path}/just_audio_cache');
        final List<FileSystemEntity> entities;
        if (audioCacheDir.existsSync()) {
          entities = audioCacheDir.listSync(recursive: true, followLinks: false);
        } else {
          entities = tempDir.listSync(recursive: true, followLinks: false).where((entity) {
            final p = entity.path.toLowerCase();
            return p.contains('just_audio') ||
                p.contains('audio') ||
                p.endsWith('.mp3') ||
                p.endsWith('.m4a') ||
                p.endsWith('.aac') ||
                p.endsWith('.ogg') ||
                p.endsWith('.opus');
          }).toList();
        }

        for (final entity in entities) {
          if (entity is File) {
            try {
              final stat = entity.statSync();
              totalSize += stat.size;
              fileStats.add(MapEntry(entity, stat));
            } catch (_) {}
          }
        }

        debugPrint('[CacheManager] Current cache size: ${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB (Limit: ${SettingsManager.maxCacheSizeMb} MB)');

        // Check if eviction criteria is met: > limit or files older than 7 days
        final bool exceedsLimit = totalSize > maxCacheSizeBytes;
        final int targetReductionSize = (maxCacheSizeBytes * 0.75).round(); // Leave 25% headroom

        // Sort files by modified date ascending (oldest first = true LRU)
        fileStats.sort((a, b) => a.value.modified.compareTo(b.value.modified));

        for (final entry in fileStats) {
          final file = entry.key;
          final stat = entry.value;
          final age = now.difference(stat.modified);

          // Delete if older than 7 days OR if overall cache exceeds limit
          if (age > maxAgeDuration || (exceedsLimit && totalSize > targetReductionSize)) {
            try {
              file.deleteSync();
              totalSize -= stat.size;
              debugPrint('[CacheManager] LRU evicted stale cache file: ${file.path}');
            } catch (_) {}
          }

          // If we were over the limit and now reduced below target, we can stop
          if (exceedsLimit && totalSize <= targetReductionSize) {
            break;
          }
        }
      } catch (e) {
        debugPrint('[CacheManager] Background eviction error: $e');
      }
    });
  }

  /// Calculates a detailed breakdown of all storage used by the app
  static Future<StorageBreakdown> getDetailedBreakdown() async {
    int offlineBytes = 0;
    int offlineCount = 0;
    int tempBytes = 0;
    int imageBytes = 0;
    int hiveBytes = 0;

    // 1. Offline Audio Files
    try {
      offlineBytes = DownloadManager.getTotalOfflineSizeBytes();
      offlineCount = DownloadManager.getDownloadedSongs().length;
    } catch (_) {}

    // 2. Documents Directory (Hive boxes & app state)
    try {
      final docDir = await getApplicationDocumentsDirectory();
      if (docDir.existsSync()) {
        final docFiles = docDir.listSync(recursive: false);
        for (final file in docFiles) {
          if (file is File) {
            final name = file.path.toLowerCase();
            if (name.endsWith('.hive') || name.endsWith('.lock') || name.contains('box')) {
              try {
                hiveBytes += file.lengthSync();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}

    // 3. Temporary Directory & Streaming Caches
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final tempEntities = tempDir.listSync(recursive: true, followLinks: false);
        for (final entity in tempEntities) {
          if (entity is File) {
            try {
              final len = entity.lengthSync();
              final path = entity.path.toLowerCase();
              if (path.contains('image_picker') || path.contains('cached_image') || path.contains('libcachedimagedata')) {
                imageBytes += len;
              } else {
                tempBytes += len;
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    final totalApp = offlineBytes + tempBytes + imageBytes + hiveBytes;

    return StorageBreakdown(
      offlineAudioBytes: offlineBytes,
      offlineSongCount: offlineCount,
      tempCacheBytes: tempBytes,
      imageCacheBytes: imageBytes,
      hiveDatabaseBytes: hiveBytes,
      totalAppBytes: totalApp,
    );
  }

  /// Calculates current cache size string (e.g. "45.2 MB")
  static Future<String> getCacheSizeString() async {
    try {
      final breakdown = await getDetailedBreakdown();
      final cacheBytes = breakdown.tempCacheBytes + breakdown.imageCacheBytes;
      return StorageBreakdown.formatBytes(cacheBytes);
    } catch (_) {
      return '0.0 MB';
    }
  }

  /// Clears network and disk image caches
  static Future<void> clearImageCache() async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await fcm.DefaultCacheManager().emptyCache();
    } catch (e) {
      debugPrint('[CacheManager] Clear image cache error: $e');
    }
  }

  /// Manually clears all temporary cache and image files
  static Future<void> clearAllCache() async {
    await clearImageCache();
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final entities = tempDir.listSync(recursive: false);
        for (final entity in entities) {
          try {
            if (entity is File) {
              entity.deleteSync();
            } else if (entity is Directory) {
              entity.deleteSync(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
