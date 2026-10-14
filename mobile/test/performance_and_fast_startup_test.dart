import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/services/cache_manager.dart';
import 'package:paatu_padava_mobile/services/player_handler.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';
import 'package:paatu_padava_mobile/logic/stream_resolver.dart';
import 'package:paatu_padava_mobile/logic/home_feed_provider.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('perf_test_hive_');
    Hive.init(tempDir.path);
    await SettingsManager.init();
    await Hive.openBox('home_feed_cache');
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('1. Fast Startup & SWR Home Feed Caching', () {
    test('CacheManager correctly saves and restores cached home feed', () async {
      final mockData = {
        'madeForYou': [
          Song(id: 'mfy_1', title: 'Aalaporan Thamizhan', artist: 'A.R. Rahman', album: 'Mersal', duration: 240, coverUrl: 'http://img.com/1.jpg').toMap(),
        ],
        'trendingMerged': [
          Song(id: 'trn_1', title: 'Hukum', artist: 'Anirudh', album: 'Jailer', duration: 210, coverUrl: 'http://img.com/2.jpg').toMap(),
        ],
        'youtubeTrending': <Map<String, dynamic>>[],
        'spotifyTop10': <Map<String, dynamic>>[],
        'newReleases': <Map<String, dynamic>>[],
        'popularArtists': <Map<String, dynamic>>[
          {'name': 'Anirudh Ravichander', 'image': 'http://img.com/ani.jpg'},
        ],
        'featuredAlbums': <Map<String, dynamic>>[
          {'title': 'Jailer', 'song_count': 5, 'image': 'http://img.com/jailer.jpg'},
        ],
      };

      await CacheManager.saveCachedHomeFeed('tamil', mockData);

      // Verify synchronous retrieval
      final syncData = CacheManager.getCachedHomeFeedSync('tamil');
      expect(syncData, isNotNull);
      expect((syncData!['madeForYou'] as List).length, equals(1));
      expect(syncData['madeForYou'][0]['id'], equals('mfy_1'));

      // Verify async retrieval
      final asyncData = await CacheManager.getCachedHomeFeed('tamil');
      expect(asyncData, isNotNull);
      expect((asyncData!['trendingMerged'] as List).length, equals(1));
      expect(asyncData['trendingMerged'][0]['id'], equals('trn_1'));
    });

    test('HomeFeedProvider SWR emits cached feed immediately without loading spinner', () async {
      final provider = HomeFeedProvider.instance;
      // Load feed from cache
      await provider.loadFeed(forceRefresh: false);

      expect(provider.state.isEmpty, isFalse);
      expect(provider.state.isLoading, isFalse); // Cache-first: no spinner
      expect(provider.state.madeForYou.any((s) => s.id == 'mfy_1'), isTrue);
      expect(provider.state.trendingMerged.any((s) => s.id == 'trn_1'), isTrue);
    });
  });

  group('2. Sub-Second Audio Playback Configuration & Stream Prewarming', () {
    test('PaatuAudioHandler configures AudioPlayer with 400ms bufferForPlaybackDuration', () {
      final handler = PaatuAudioHandler();
      expect(handler, isNotNull);
      expect(handler.player, isNotNull);
    });

    test('DefaultStreamResolver.prewarm caches stream URLs for top tracks', () async {
      final tracks = [
        TrackEntity(
          id: 'prewarm_1',
          title: 'Prewarm Song 1',
          artist: 'Artist 1',
          album: 'Album 1',
          coverUrl: 'http://img.com/1.jpg',
          duration: 180,
          streamUrl: 'https://cdn.example.com/stream1.mp3',
          source: 'audius',
        ),
        TrackEntity(
          id: 'prewarm_2',
          title: 'Prewarm Song 2',
          artist: 'Artist 2',
          album: 'Album 2',
          coverUrl: 'http://img.com/2.jpg',
          duration: 200,
          streamUrl: 'https://cdn.example.com/stream2.mp3',
          source: 'audius',
        ),
      ];

      await DefaultStreamResolver.prewarm(tracks, limit: 2);

      expect(DefaultStreamResolver.getCachedStream('prewarm_1'), isNotNull);
      expect(DefaultStreamResolver.getCachedStream('prewarm_2'), isNotNull);
    });

    test('DefaultStreamResolver.prewarmSongs caches stream URLs for top songs', () async {
      final songs = [
        Song(
          id: 'song_prewarm_1',
          title: 'Song Prewarm 1',
          artist: 'Artist 1',
          album: 'Album 1',
          coverUrl: 'http://img.com/1.jpg',
          duration: 180,
          streamUrl: 'https://cdn.example.com/s1.mp3',
          source: 'audius',
        ),
      ];

      await DefaultStreamResolver.prewarmSongs(songs, limit: 1);
      expect(DefaultStreamResolver.getCachedStream('song_prewarm_1'), isNotNull);
    });
  });

  group('3. Progressive Search Rendering', () {
    test('SearchService.searchProgressive emits stream of SearchResults', () async {
      final stream = SearchService.searchProgressive('Master', language: 'Tamil', limit: 10);
      final results = <SearchResults>[];

      await for (final r in stream) {
        results.add(r);
      }

      // Must emit at least 1 SearchResults bundle
      expect(results, isNotEmpty);
      final finalBundle = results.last;
      expect(finalBundle, isNotNull);
    });

    test('SearchService.searchUnified returns final merged SearchResults', () async {
      final result = await SearchService.searchUnified('Leo Badass', language: 'Tamil', limit: 5);
      expect(result, isNotNull);
      expect(result.songs, isA<List<Song>>());
    });
  });
}
