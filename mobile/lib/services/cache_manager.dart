import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Automatic cache eviction manager:
/// Checks temporary cache directory size on app launch.
/// If cache size exceeds 400MB or files are older than 7 days,
/// automatically deletes cached files in the background without blocking the UI thread.
class CacheManager {
  static const int maxCacheSizeBytes = 400 * 1024 * 1024; // 400 MB
  static const int maxCacheAgeDays = 7;

  /// Runs background cache audit and eviction without blocking the UI
  static Future<void> autoEvictOldCache() async {
    // Run in background without awaiting on main thread
    Future.microtask(() async {
      try {
        final tempDir = await getTemporaryDirectory();
        if (!tempDir.existsSync()) return;

        final now = DateTime.now();
        const maxAgeDuration = Duration(days: maxCacheAgeDays);

        int totalSize = 0;
        final List<FileSystemEntity> allEntities = [];

        // Gather all files and measure size
        final entities = tempDir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is File) {
            allEntities.add(entity);
            try {
              totalSize += entity.lengthSync();
            } catch (_) {}
          }
        }

        debugPrint('[CacheManager] Current cache size: ${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB');

        // Check if eviction criteria is met: >400MB or files older than 7 days
        final bool exceedsLimit = totalSize > maxCacheSizeBytes;

        for (final entity in allEntities) {
          if (entity is! File) continue;

          try {
            final stat = entity.statSync();
            final age = now.difference(stat.modified);

            // Delete if older than 7 days OR if overall cache exceeds 400MB and file is older than 2 days
            if (age > maxAgeDuration || (exceedsLimit && age > const Duration(days: 2))) {
              entity.deleteSync();
              totalSize -= stat.size;
              debugPrint('[CacheManager] Evicted stale cache file: ${entity.path}');
            }
          } catch (_) {}

          // If we were over the limit and now reduced below 250MB, we can stop
          if (exceedsLimit && totalSize < 250 * 1024 * 1024) {
            break;
          }
        }
      } catch (e) {
        debugPrint('[CacheManager] Background eviction error: $e');
      }
    });
  }

  /// Calculates current cache size string (e.g. "45.2 MB")
  static Future<String> getCacheSizeString() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) return '0.0 MB';

      int totalBytes = 0;
      final entities = tempDir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          try {
            totalBytes += entity.lengthSync();
          } catch (_) {}
        }
      }

      final mb = totalBytes / (1024 * 1024);
      if (mb > 1024) {
        return '${(mb / 1024).toStringAsFixed(2)} GB';
      }
      return '${mb.toStringAsFixed(1)} MB';
    } catch (_) {
      return '0.0 MB';
    }
  }

  /// Manually clears all temporary cache files
  static Future<void> clearAllCache() async {
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
