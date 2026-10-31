import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'download_manager.dart';
import 'settings_manager.dart';
import 'smart_cache_service.dart';
import 'app_logger.dart';

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
  static const int maxCacheSizeBytesCap = 100 * 1024 * 1024; // 100 MB LRU eviction threshold cap
  static const int maxMemoryImageCacheSizeBytes = 64 * 1024 * 1024; // 64 MB memory image cache cap
  static const int maxMemoryImageCacheCount = 100; // 100 images cap

  static int get maxCacheSizeBytes {
    final configured = SettingsManager.maxCacheSizeMb * 1024 * 1024;
    return (configured > maxCacheSizeBytesCap || configured <= 0) ? maxCacheSizeBytesCap : configured;
  }
  static const int maxCacheAgeDays = 7;

  static DateTime? _lastEvictionTime;

  /// Restricts Flutter image cache memory usage to 100 MB.
  static void configureMemoryLimits() {
    try {
      PaintingBinding.instance.imageCache.maximumSizeBytes = maxMemoryImageCacheSizeBytes;
      PaintingBinding.instance.imageCache.maximumSize = maxMemoryImageCacheCount;
    } catch (_) {}
  }

  /// Runs background cache audit and true LRU eviction.
  /// Throttled to run at most once every 24 hours, or immediately if [force] is true.
  /// Strictly restricted to the audio cache folder to avoid touching other app assets.
  static Future<void> autoEvictOldCache({bool force = false}) async {
    configureMemoryLimits();
    final now = DateTime.now();

    // Check throttle unless forced
    if (!force) {
      if (_lastEvictionTime != null && now.difference(_lastEvictionTime!).inHours < 24) {
        return;
      }
      try {
        final box = Hive.isBoxOpen(SettingsManager.boxName) ? Hive.box(SettingsManager.boxName) : null;
        final savedMs = box?.get('last_cache_eviction_ms') as int?;
        if (savedMs != null) {
          final savedTime = DateTime.fromMillisecondsSinceEpoch(savedMs);
          if (now.difference(savedTime).inHours < 24) {
            _lastEvictionTime = savedTime;
            return;
          }
        }
      } catch (_) {}
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final audioCacheDir = Directory('${tempDir.path}/just_audio_cache');
      if (!audioCacheDir.existsSync()) {
        _lastEvictionTime = now;
        return;
      }

      const maxAgeDuration = Duration(days: maxCacheAgeDays);
      int totalSize = 0;
      final List<MapEntry<File, FileStat>> fileStats = [];

      // Asynchronously inspect only the audio cache directory
      await for (final entity in audioCacheDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            totalSize += stat.size;
            fileStats.add(MapEntry(entity, stat));
          } catch (_) {}
        }
      }

      final exceedsLimit = totalSize > maxCacheSizeBytes;
      AppLogger.log(
        'CacheManager',
        'Audio cache size: ${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB / ${SettingsManager.maxCacheSizeMb} MB limit (exceeds=$exceedsLimit)',
      );

      final int targetReductionSize = (maxCacheSizeBytes * 0.75).round();

      // Sort files by modified date ascending (oldest first = true LRU)
      fileStats.sort((a, b) => a.value.modified.compareTo(b.value.modified));

      int evictedCount = 0;
      for (final entry in fileStats) {
        final file = entry.key;
        final stat = entry.value;
        final age = now.difference(stat.modified);

        // Delete if older than 7 days OR if overall cache exceeds limit
        if (age > maxAgeDuration || (exceedsLimit && totalSize > targetReductionSize)) {
          try {
            await file.delete();
            totalSize -= stat.size;
            evictedCount++;
          } catch (_) {}
        }

        // If we reduced below target, stop
        if (exceedsLimit && totalSize <= targetReductionSize) {
          break;
        }
      }

      _lastEvictionTime = now;
      try {
        if (Hive.isBoxOpen(SettingsManager.boxName)) {
          await Hive.box(SettingsManager.boxName).put('last_cache_eviction_ms', now.millisecondsSinceEpoch);
        }
      } catch (_) {}

      if (evictedCount > 0) {
        AppLogger.log('CacheManager', 'Evicted $evictedCount stale/overflow audio cache files');
      }
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'CacheManager.autoEvictOldCache');
    }
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

  /// Retrieves cached Home Feed JSON for [language] from persistent storage
  static Future<Map<String, dynamic>?> getCachedHomeFeed(String language) async {
    try {
      final box = Hive.isBoxOpen('home_feed_cache')
          ? Hive.box('home_feed_cache')
          : await Hive.openBox('home_feed_cache');
      final raw = box.get('feed_${language.toLowerCase()}');
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      debugPrint('[CacheManager] Error reading cached home feed: $e');
    }
    return null;
  }

  /// Synchronously retrieves cached Home Feed JSON if box is already open in memory (0ms)
  static Map<String, dynamic>? getCachedHomeFeedSync(String language) {
    try {
      if (Hive.isBoxOpen('home_feed_cache')) {
        final raw = Hive.box('home_feed_cache').get('feed_${language.toLowerCase()}');
        if (raw is Map) {
          return Map<String, dynamic>.from(raw);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Saves cached Home Feed JSON for [language] to persistent storage
  static Future<void> saveCachedHomeFeed(String language, Map<String, dynamic> data) async {
    try {
      final box = Hive.isBoxOpen('home_feed_cache')
          ? Hive.box('home_feed_cache')
          : await Hive.openBox('home_feed_cache');
      await box.put('feed_${language.toLowerCase()}', data);
    } catch (e) {
      debugPrint('[CacheManager] Error saving cached home feed: $e');
    }
  }

  /// Manually clears all temporary cache, predictive smart cache, and image files
  static Future<void> clearAllCache() async {
    await clearImageCache();
    try {
      await SmartCacheService.instance.clearCache();
    } catch (_) {}
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
