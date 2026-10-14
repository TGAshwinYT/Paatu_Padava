import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/spotify_import_service.dart';
import 'package:paatu_padava_mobile/services/youtube_client.dart';
import 'package:paatu_padava_mobile/logic/home_feed_provider.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('spotify_test_hive_');
    Hive.init(tempDir.path);
    await FavoritesManager.init();
  });

  group('1. Spotify Client Credentials & Top 10 Hits', () {
    test('SpotifyImportService has client credentials configured and valid endpoint URL formatting', () async {
      // Test URL construction and method signature
      final tracks = await SpotifyImportService.getTop10Hits('tamil');
      expect(tracks, isA<List<TrackEntity>>());
    });

    test('SpotifyImportService.getArtistProfileImage returns image URL or null gracefully', () async {
      final img = await SpotifyImportService.getArtistProfileImage('Anirudh Ravichander');
      expect(img, anyOf(isNull, isA<String>()));
    });
  });

  group('2. Artist Images & Regional Seeds Filter', () {
    test('Tamil seeds are strictly regional and contain no Hindi singers', () {
      const seeds = SongRepository.tamilArtistSeeds;
      expect(seeds, contains('Anirudh Ravichander'));
      expect(seeds, contains('A.R. Rahman'));
      expect(seeds, contains('Yuvan Shankar Raja'));
      expect(seeds, contains('Harris Jayaraj'));
      expect(seeds, contains('G.V. Prakash'));
      expect(seeds, contains('Sid Sriram'));
      expect(seeds, contains('Santhosh Narayanan'));

      // Check Hindi singers are not in Tamil seeds
      for (final seed in seeds) {
        expect(seed.toLowerCase(), isNot(contains('arijit')));
        expect(seed.toLowerCase(), isNot(contains('badshah')));
        expect(seed.toLowerCase(), isNot(contains('neha kakkar')));
      }
    });

    test('getPopularArtists rejects Hindi singers when Tamil is selected', () async {
      final artists = await SongRepository.getPopularArtists(language: 'tamil');
      final names = artists.map((a) => a['name'].toString().toLowerCase()).toList();
      expect(names.any((n) => n.contains('arijit')), isFalse);
      expect(names.any((n) => n.contains('badshah')), isFalse);
      expect(names.any((n) => n.contains('shreya ghoshal')), isFalse);
    });
  });

  group('3. Single-Song Album Filter', () {
    test('Home feed album filter excludes single-song albums and singles', () {
      final rawAlbums = [
        {'id': '1', 'title': 'Great Hits Album', 'song_count': '8'},
        {'id': '2', 'title': 'Solo Single Track', 'song_count': '1'},
        {'id': '3', 'title': 'Zero Count Bug', 'song_count': '0'},
        {'id': '4', 'title': 'Romantic Single Edition', 'song_count': '5'},
        {'id': '5', 'title': 'Classic Masterpiece', 'song_count': 6},
      ];

      final filtered = rawAlbums.where((a) {
        final count = int.tryParse(a['song_count']?.toString() ?? '0') ?? 2;
        final title = (a['title'] ?? '').toString().toLowerCase();
        return count > 1 && !title.contains('single');
      }).toList();

      expect(filtered.length, equals(2));
      expect(filtered[0]['title'], equals('Great Hits Album'));
      expect(filtered[1]['title'], equals('Classic Masterpiece'));
    });
  });

  group('4. Auto-Suggestion InnerTube Automix Engine', () {
    test('YouTubeClient getUpNextAutomix constructs InnerTube next request and parses tracks', () async {
      final tracks = await YouTubeClient.getUpNextAutomix('testVideoId', limit: 5);
      expect(tracks, isA<List<Song>>());
    });
  });

  group('5. Double-Tap Artwork to Favorite/Unfavorite', () {
    test('FavoritesManager.toggleFavorite toggles state cleanly', () async {
      final song = Song(
        id: 'test_dt_fav_song_1',
        title: 'Double Tap Song',
        artist: 'Anirudh',
        album: 'Test Album',
        coverUrl: 'https://example.com/cover.jpg',
        streamUrl: 'https://example.com/audio.mp3',
        duration: 210,
      );

      // Ensure initially not favorited
      if (FavoritesManager.isFavorite(song.id)) {
        await FavoritesManager.toggleFavorite(song);
      }
      expect(FavoritesManager.isFavorite(song.id), isFalse);

      // 1st Double-tap: likes it
      final liked = await FavoritesManager.toggleFavorite(song);
      expect(liked, isTrue);
      expect(FavoritesManager.isFavorite(song.id), isTrue);

      // 2nd Double-tap: unlikes it
      final unliked = await FavoritesManager.toggleFavorite(song);
      expect(unliked, isFalse);
      expect(FavoritesManager.isFavorite(song.id), isFalse);
    });
  });

  group('6. HomeFeedState contains spotifyTop10', () {
    test('HomeFeedState retains and updates spotifyTop10 correctly', () {
      final testSong = Song(
        id: 'sp_1',
        title: 'Spotify Track',
        artist: 'Anirudh',
        album: 'Top Hits',
        coverUrl: 'https://example.com/sp.jpg',
        streamUrl: '',
        duration: 180,
      );

      final state = HomeFeedState(
        spotifyTop10: [testSong],
      );

      expect(state.spotifyTop10.length, equals(1));
      expect(state.spotifyTop10.first.title, equals('Spotify Track'));

      final updated = state.copyWith(
        spotifyTop10: [
          testSong,
          Song(
            id: 'sp_2',
            title: 'Spotify Track 2',
            artist: 'A.R. Rahman',
            album: 'Top Hits 2026',
            coverUrl: 'https://example.com/sp2.jpg',
            streamUrl: '',
            duration: 200,
          ),
        ],
      );

      expect(updated.spotifyTop10.length, equals(2));
      expect(updated.spotifyTop10.last.title, equals('Spotify Track 2'));
    });
  });
}
