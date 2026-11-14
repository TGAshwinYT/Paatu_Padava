import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/domain/models/catalog_entry.dart';
import 'package:paatu_padava_mobile/services/fuzzy_search_service.dart';
import 'package:paatu_padava_mobile/services/semantic_search_service.dart';
import 'package:paatu_padava_mobile/services/sync_manager.dart';
import 'package:paatu_padava_mobile/services/dynamic_scraper_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('arch_perf_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('1. DSA & Isolate Typo Correction Tests', () {
    test('FuzzySearchService.findCorrectionAsync accurately corrects typo via compute', () async {
      final result = await FuzzySearchService.findCorrectionAsync('anirud');
      expect(result, isNotNull);
      expect(result!.corrected.toLowerCase(), contains('anirudh'));
    });

    test('FuzzySearchService.findCorrectionAsync returns null for exact match', () async {
      final result = await FuzzySearchService.findCorrectionAsync('Hukum');
      expect(result, isNull);
    });

    test('FuzzySearchService.findCorrectionAsync returns null for short query <= 3', () async {
      final result = await FuzzySearchService.findCorrectionAsync('leo');
      expect(result, isNull);
    });
  });

  group('2. Semantic Vector Cosine Ranking Isolate Tests', () {
    test('SemanticSearchService.rankBySemanticIntentAsync re-ranks small list (< 20)', () async {
      final songs = [
        TrackEntity(id: '1', title: 'Party Dance Kuthu', artist: 'Anirudh', coverUrl: ''),
        TrackEntity(id: '2', title: 'Sogam Sad Melody', artist: 'Sid Sriram', coverUrl: ''),
      ];

      final ranked = await SemanticSearchService.instance.rankBySemanticIntentAsync(songs, 'sad breakup');
      expect(ranked.first.id, equals('2'));
    });

    test('SemanticSearchService.rankBySemanticIntentAsync offloads batch (>= 20) to compute worker', () async {
      final songs = List.generate(25, (i) {
        if (i == 10) {
          return TrackEntity(id: 's_$i', title: 'Rainy Night Chill Sad Love', artist: 'Sid Sriram', coverUrl: '');
        }
        return TrackEntity(id: 's_$i', title: 'Gym Workout Energy Beats $i', artist: 'Anirudh', coverUrl: '');
      });

      final ranked = await SemanticSearchService.instance.rankBySemanticIntentAsync(songs, 'sad lonely night');
      expect(ranked.first.id, equals('s_10'));
    });
  });

  group('3. Clean Architecture Model Unification Tests', () {
    test('TrackEntity.fromCatalogSong creates complete runtime TrackEntity', () {
      const catalogSong = CatalogSong(
        id: 'cat_1',
        title: 'Naa Ready',
        movieTitle: 'Leo',
        composer: 'Anirudh Ravichander',
        singers: 'Thalapathy Vijay, Anirudh',
        starring: 'Vijay, Trisha',
        year: 2023,
        duration: 245,
        coverUrl: 'https://example.com/leo.jpg',
        audioUrl: 'https://example.com/audio.mp3',
        source: 'saavn',
        language: 'tamil',
        createdAt: 1700000000,
      );

      final track = TrackEntity.fromCatalogSong(catalogSong);
      expect(track.id, equals('cat_1'));
      expect(track.title, equals('Naa Ready'));
      expect(track.artist, equals('Thalapathy Vijay, Anirudh'));
      expect(track.album, equals('Leo'));
      expect(track.coverUrl, equals('https://example.com/leo.jpg'));
      expect(track.streamUrl, equals('https://example.com/audio.mp3'));
      expect(track.duration, equals(245));
      expect(track.source, equals('saavn'));
      expect(track.language, equals('tamil'));
    });

    test('CatalogSong.toSong() returns unified TrackEntity seamlessly', () {
      const catalogSong = CatalogSong(
        id: 'cat_2',
        title: 'Arabic Kuthu',
        movieTitle: 'Beast',
        composer: 'Anirudh',
        singers: '',
        starring: 'Vijay',
        year: 2022,
        coverUrl: 'https://example.com/beast.jpg',
        createdAt: 1700000000,
      );

      final song = catalogSong.toSong();
      expect(song.title, equals('Arabic Kuthu'));
      expect(song.artist, equals('Anirudh')); // Composer fallback when singers empty
      expect(song.album, equals('Beast'));
    });
  });

  group('4. SyncManager Mutex & Concurrency Tests', () {
    test('SyncManager.syncAll handles concurrent calls safely without state corruption', () async {
      // In unauthenticated test environment, SyncManager detects offline and completes cleanly
      final Future<void> future1 = SyncManager.syncAll();
      final Future<void> future2 = SyncManager.syncAll();

      await Future.wait<void>([future1, future2]);
      expect(SyncManager.isSyncing, isFalse);
      expect(SyncManager.status, equals(SyncStatus.offline));
    });
  });

  group('5. Scraper Health & Telemetry Reporting Tests', () {
    test('DynamicScraperConfigService.reportClientFailure demotes failing client', () {
      DynamicScraperConfigService.resetToDefaults();
      expect(DynamicScraperConfigService.healthyClientConfigs.any((c) => c['name'] == 'WEB_REMIX'), isTrue);

      DynamicScraperConfigService.reportClientFailure('WEB_REMIX', 'HTTP 403 Forbidden');
      expect(DynamicScraperConfigService.healthyClientConfigs.any((c) => c['name'] == 'WEB_REMIX'), isFalse);
      DynamicScraperConfigService.resetToDefaults();
    });
  });
}
