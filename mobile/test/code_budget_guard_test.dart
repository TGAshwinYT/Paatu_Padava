import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/cache_manager.dart';

void main() {
  group('Architecture & Performance Budget Guard Tests', () {
    final libDir = Directory('lib');

    test('1. GoogleFonts Call Budget Guard: calls must not exceed baseline budget of 383', () {
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      int googleFontsCount = 0;
      final RegExp gfRegex = RegExp(r'\bGoogleFonts\.');

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final matches = gfRegex.allMatches(content);
        googleFontsCount += matches.length;
      }

      const int maxAllowedGoogleFonts = 383;
      expect(
        googleFontsCount,
        lessThanOrEqualTo(maxAllowedGoogleFonts),
        reason:
            'GoogleFonts calls ($googleFontsCount) exceed the performance budget of $maxAllowedGoogleFonts. Bundle font families instead of making runtime dynamic lookups.',
      );
    });

    test('2. File Length Budget Guard: files over 400 lines must not exceed budget of 50', () {
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      int filesOver400Lines = 0;
      final List<String> offendingFiles = [];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        if (lines.length > 400) {
          filesOver400Lines++;
          offendingFiles.add('${file.path} (${lines.length} lines)');
        }
      }

      const int maxFilesOver400 = 55;
      expect(
        filesOver400Lines,
        lessThanOrEqualTo(maxFilesOver400),
        reason:
            'Too many giant files ($filesOver400Lines > $maxFilesOver400). Break up large files into modular components:\n${offendingFiles.join('\n')}',
      );
    });

    test('3. UI Layer Decoupling Guard: UI screens must never import API clients directly', () {
      final uiDir = Directory('lib/ui');
      if (!uiDir.existsSync()) return;

      final uiFiles = uiDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final forbiddenImports = [
        'services/saavn_client.dart',
        'services/youtube_client.dart',
        'services/audius_client.dart',
        'services/api_client.dart',
      ];

      final violations = <String>[];

      for (final file in uiFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('import ')) {
            for (final forbidden in forbiddenImports) {
              if (line.contains(forbidden)) {
                violations.add('${file.path}:${i + 1} imports $forbidden directly');
              }
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'UI Layer must remain completely dumb. Route all data fetches through SongRepository or SearchService:\n${violations.join('\n')}',
      );
    });

    test('4. Memory & Disk Cache Guard: enforces 64MB memory / 100MB disk budget', () {
      expect(CacheManager.maxMemoryImageCacheSizeBytes, equals(64 * 1024 * 1024),
          reason: 'Memory image cache cap must be strictly 64 MB');
      expect(CacheManager.maxMemoryImageCacheCount, equals(100),
          reason: 'Memory image cache count must be strictly 100 items');
      expect(CacheManager.maxCacheSizeBytesCap, equals(100 * 1024 * 1024),
          reason: 'Disk audio cache cap must be strictly 100 MB');
    });
  });
}
