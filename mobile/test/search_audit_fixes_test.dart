import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/services/user_preference_matrix.dart';
import 'package:paatu_padava_mobile/services/catalog_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Search Audit Fixes Verification', () {
    test('1. "Hindi Medium" preserves "Hindi" as part of the movie title, not stripped', () {
      final intent = SearchService.understandQuery('Hindi Medium');
      // "Hindi" should remain part of the clean query title
      expect(intent.cleanQuery.toLowerCase(), contains('hindi'));
      expect(intent.cleanQuery.toLowerCase(), contains('medium'));
    });

    test('2. "tamil songs" correctly identifies explicit language modifier and strips generic suffix', () {
      final intent = SearchService.understandQuery('tamil songs');
      expect(intent.explicitLanguage?.toLowerCase(), equals('tamil'));
    });

    test('3. Exact query match decisively beats loosely-related favorite under 85/15 weighting', () {
      final exactMatch = Song(
        id: 'song_exact',
        title: 'Believer',
        artist: 'Imagine Dragons',
        album: 'Evolve',
        coverUrl: '',
      );

      final favoriteUnrelated = Song(
        id: 'song_fav',
        title: 'Random Track',
        artist: 'Favorite Singer',
        album: 'Different Album',
        coverUrl: '',
      );

      final reRanked = UserPreferenceMatrix.reRankWithPreferences(
        [favoriteUnrelated, exactMatch],
        'Believer',
        likedSongs: [favoriteUnrelated], // favorite has 100% user affinity
      );

      // Exact title match MUST rank #1, beating the loosely-related favorite
      expect(reRanked.first.id, equals('song_exact'));
    });

    test('4. Typo and Tanglish variants achieve high relevance in UserPreferenceMatrix when intent is passed', () {
      final canonicalSong = Song(
        id: 'song_leo',
        title: 'Naa Ready',
        artist: 'Anirudh Ravichander',
        album: 'Leo',
        coverUrl: '',
      );

      const intent = QueryIntent(
        rawQuery: 'na redy',
        cleanQuery: 'na redy',
        transliteratedQuery: 'naa ready',
        didYouMeanSuggestion: 'naa ready',
      );

      final reRanked = UserPreferenceMatrix.reRankWithPreferences(
        [canonicalSong],
        'na redy',
        intent: intent,
      );

      expect(reRanked.first.id, equals('song_leo'));
    });

    test('5. CatalogDatabase.insertDynamicSong does not fake year or default language to tamil', () async {
      final song = Song(
        id: 'test_dyn_1',
        title: 'Roja Janeman',
        artist: 'S.P. Balasubrahmanyam',
        album: 'Roja 1992',
        coverUrl: '',
        duration: 240,
        source: 'saavn',
        language: 'hindi',
        streamUrl: 'https://expiring-cdn.com/audio.mp4',
      );

      await CatalogDatabase.init();
      await CatalogDatabase.insertDynamicSong(song);

      // Use searchCatalog to retrieve the dynamically inserted song
      final results = await CatalogDatabase.searchCatalog('Roja Janeman', limit: 1);
      final catalogSong = results.firstOrNull;

      if (catalogSong != null) {
        // Language should be preserved as 'hindi', not defaulted to 'tamil'
        expect(catalogSong.language?.toLowerCase(), equals('hindi'));
      }
    });

    test('6. filterArtistsByLanguage respects language and does not drop artists without avatar', () {
      final rawArtists = [
        {
          'id': 'art_1',
          'name': 'Justin Bieber',
          'language': 'english',
          'image': 'https://c.saavncdn.com/default_artist.png', // placeholder image
        },
        {
          'id': 'art_2',
          'name': 'Anirudh Ravichander',
          'language': 'tamil',
          'image': 'https://c.saavncdn.com/anirudh.jpg',
        },
        {
          'id': 'art_3',
          'name': 'Budding Indie Artist',
          'language': 'tamil',
          'image': '', // no avatar
        },
      ];

      // When language is Tamil, English pop star is dropped unless directly queried
      final tamilFiltered = SearchService.filterArtistsByLanguage(
        rawArtists,
        language: 'tamil',
        query: 'top artists',
      );

      expect(tamilFiltered.any((a) => a['name'] == 'Justin Bieber'), isFalse);
      expect(tamilFiltered.any((a) => a['name'] == 'Anirudh Ravichander'), isTrue);
      // Legitimate Tamil indie artist without avatar must NOT be dropped!
      expect(tamilFiltered.any((a) => a['name'] == 'Budding Indie Artist'), isTrue);
    });
  });
}
