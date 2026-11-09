import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/data/catalog_artists_seed.dart';
import 'package:paatu_padava_mobile/domain/models/home_feed_models.dart';
import 'package:paatu_padava_mobile/logic/client_home_feed_engine.dart';
import 'package:paatu_padava_mobile/logic/home_feed_provider.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/recent_containers_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Spotify-Grade Home Page & Client Feed Engine Tests', () {
    late ClientHomeFeedEngine engine;

    setUp(() {
      engine = ClientHomeFeedEngine();
    });

    test('generateQuickTiles returns exactly 6 Spotify-style tiles with 1-tap capability', () {
      final sampleTracks = List.generate(
        10,
        (i) => Song(
          id: 'sample_$i',
          title: 'Sample Track $i',
          artist: 'Anirudh Ravichander',
          album: 'Master',
          coverUrl: 'https://example.com/cover_$i.jpg',
        ),
      );

      final tiles = engine.generateQuickTiles(
        language: 'Tamil',
        feedTracks: sampleTracks,
      );

      expect(tiles.length, equals(6));
      expect(tiles[0].type, equals('liked'));
      expect(tiles[0].title, equals('Liked Songs'));
      expect(tiles[1].type, equals('mix'));
      expect(tiles[1].title, equals('Daily Mix 1'));
      expect(tiles[2].type, equals('history'));
      expect(tiles[2].title, equals('Recently Played'));
      expect(tiles[3].type, equals('hits'));
      expect(tiles[3].title, contains('Top Hits'));
      expect(tiles[4].type, equals('mix'));
      expect(tiles[4].title, equals('Daily Mix 2'));
      expect(tiles[5].type, equals('decade'));
    });

    test('DailyMix model serialization round-trip retains accent colors and artist subtitle', () {
      final mix = DailyMix(
        index: 1,
        title: 'Daily Mix 1',
        subtitle: 'Anirudh Ravichander, Yuvan Shankar Raja, Harris Jayaraj',
        coverUrl: 'https://c.saavncdn.com/123.jpg',
        accentColor: const Color(0xFF10B981),
        tracks: [
          Song(id: 't1', title: 'Hukum', artist: 'Anirudh', album: 'Jailer', coverUrl: 'https://c.saavncdn.com/123.jpg'),
        ],
      );

      final map = mix.toMap();
      final revived = DailyMix.fromMap(map);

      expect(revived.index, equals(1));
      expect(revived.title, equals('Daily Mix 1'));
      expect(revived.subtitle, contains('Anirudh Ravichander'));
      expect(revived.accentColor.value, equals(const Color(0xFF10B981).value));
      expect(revived.tracks.length, equals(1));
      expect(revived.tracks.first.title, equals('Hukum'));
    });

    test('DecadeMix model serialization round-trip retains decade identifier and gradient', () {
      final dec = DecadeMix(
        decade: '90s',
        title: '90s Golden Nostalgia',
        subtitle: 'Evergreen golden classics of the 90s',
        coverUrl: 'https://c.saavncdn.com/90s.jpg',
        gradient: const [Color(0xFF78350F), Color(0xFFD97706)],
        tracks: [
          Song(id: 'd1', title: 'Thendral Vanthu', artist: 'Ilaiyaraaja', album: 'Avatharam', coverUrl: 'https://c.saavncdn.com/90s.jpg'),
        ],
      );

      final map = dec.toMap();
      final revived = DecadeMix.fromMap(map);

      expect(revived.decade, equals('90s'));
      expect(revived.title, equals('90s Golden Nostalgia'));
      expect(revived.gradient.length, equals(2));
      expect(revived.tracks.length, equals(1));
    });

    test('HomeFeedState supports category filtering and client mixes', () {
      const state = HomeFeedState();
      expect(state.homeFilter, equals('all'));

      final updated = state.copyWith(homeFilter: 'playlists');
      expect(updated.homeFilter, equals('playlists'));

      final forYou = state.copyWith(homeFilter: 'for_you');
      expect(forYou.homeFilter, equals('for_you'));

      final moods = state.copyWith(homeFilter: 'moods');
      expect(moods.homeFilter, equals('moods'));
    });

    test('HomeFeedProvider switches home category filter and notifies', () {
      final provider = HomeFeedProvider.instance;
      provider.setHomeFilter('playlists');
      expect(provider.homeFilter, equals('playlists'));

      provider.setHomeFilter('all');
      expect(provider.homeFilter, equals('all'));
    });
  });

  group('CatalogArtistsSeed Multi-Language Tests', () {
    test('English artist seeds return verified global icons without bogus channels', () {
      final englishArtists = CatalogArtistsSeed.getArtistsForLanguage('english');
      expect(englishArtists.isNotEmpty, isTrue);
      final names = englishArtists.map((a) => a.name).toList();
      expect(names, contains('Taylor Swift'));
      expect(names, contains('Ed Sheeran'));
      expect(names, contains('The Weeknd'));
      expect(names, contains('Drake'));
      // Verify no bogus "Cartoon Studio English" or "English Yadav"
      expect(names.any((n) => n.contains('Cartoon') || n.contains('Yadav')), isFalse);
    });

    test('getArtistsForLanguages combines multi-preferred languages cleanly', () {
      final combined = CatalogArtistsSeed.getArtistsForLanguages(['tamil', 'english', 'punjabi']);
      final names = combined.map((a) => a.name).toList();
      expect(names, contains('Anirudh Ravichander'));
      expect(names, contains('Taylor Swift'));
      expect(names, contains('Diljit Dosanjh'));
    });
  });

  group('RecentContainersManager LRU Quick Grid Tests', () {
    test('recordContainer hoists new items to [0][0] and evicts [3][2] past max 6', () async {
      RecentContainersManager.containersNotifier.value = [];

      // Add 6 containers
      for (int i = 1; i <= 6; i++) {
        await RecentContainersManager.recordContainer(
          id: 'album_$i',
          title: 'Album $i',
          coverUrl: 'https://example.com/cover_$i.jpg',
          type: 'album',
        );
      }

      var current = RecentContainersManager.containersNotifier.value;
      expect(current.length, equals(6));
      expect(current.first.id, equals('album_6')); // Most recent at [0][0]
      expect(current.last.id, equals('album_1'));  // Oldest at [3][2]

      // Add 7th container: album_1 should be evicted, album_7 is at [0][0]
      await RecentContainersManager.recordContainer(
        id: 'album_7',
        title: 'Album 7',
        coverUrl: 'https://example.com/cover_7.jpg',
        type: 'album',
      );

      current = RecentContainersManager.containersNotifier.value;
      expect(current.length, equals(6));
      expect(current.first.id, equals('album_7'));
      expect(current.any((t) => t.id == 'album_1'), isFalse);

      // Re-playing album_2 hoists it to [0][0]
      await RecentContainersManager.recordContainer(
        id: 'album_2',
        title: 'Album 2',
        coverUrl: 'https://example.com/cover_2.jpg',
        type: 'album',
      );

      current = RecentContainersManager.containersNotifier.value;
      expect(current.length, equals(6));
      expect(current.first.id, equals('album_2'));
    });
  });
}
