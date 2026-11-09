import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/domain/models/home_feed_models.dart';
import 'package:paatu_padava_mobile/logic/client_home_feed_engine.dart';
import 'package:paatu_padava_mobile/logic/home_feed_provider.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
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
}
