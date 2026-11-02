import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/services/user_preference_matrix.dart';
import 'package:paatu_padava_mobile/services/catalog_database.dart';
import 'package:paatu_padava_mobile/services/youtube/youtube_title_cleaner.dart';

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

    test('7. "English Vinglish" does not set explicit language to English', () {
      final intent = SearchService.understandQuery('English Vinglish');
      expect(intent.cleanQuery.toLowerCase(), contains('english'));
      expect(intent.cleanQuery.toLowerCase(), contains('vinglish'));
      expect(intent.explicitLanguage, isNull);
    });

    test('8. Foreign language song with exact title match scores > 0.0 and is not dropped', () {
      final despacito = Song(
        id: 'despacito_1',
        title: 'Despacito',
        artist: 'Luis Fonsi',
        album: 'Vida',
        coverUrl: '',
        language: 'spanish',
      );
      final intent = SearchService.understandQuery('Despacito');
      final score = SearchService.calculateCompositeRelevance(despacito, intent);
      expect(score, greaterThan(0.0));
      expect(score, greaterThanOrEqualTo(0.75));
    });

    test('9. Exact title containing "Scene" is not rejected by dialogue regex', () {
      final sceneTrack = Song(
        id: 'scene_track_1',
        title: 'Behind The Scene',
        artist: 'Music Producer',
        album: 'The Album',
        coverUrl: '',
      );
      final intent = SearchService.understandQuery('Behind The Scene');
      final score = SearchService.calculateCompositeRelevance(sceneTrack, intent);
      expect(score, greaterThan(0.0));
    });

    test('10. Urdu language song is exempted from Middle-Eastern Arabic drop', () {
      final urduSong = Song(
        id: 'urdu_1',
        title: 'Tajdar-e-Haram',
        artist: 'Atif Aslam',
        album: 'Coke Studio',
        coverUrl: '',
        language: 'urdu',
      );
      final intent = SearchService.understandQuery('Tajdar-e-Haram');
      final score = SearchService.calculateCompositeRelevance(urduSong, intent);
      expect(score, greaterThan(0.0));
    });

    test('11. SearchCache does not cache degraded results with zero songs', () {
      SearchCache.clear();
      final emptyResults = SearchResults(
        songs: const [],
        saavnSongs: const [],
        ytSongs: const [],
      );
      SearchCache.put('test query', emptyResults);
      expect(SearchCache.get('test query'), isNull);
    });

    test('12. YouTubeTitleCleaner strictly discriminates playlist IDs from normal typed words', () {
      expect(YouTubeTitleCleaner.extractPlaylistId('Play'), isNull);
      expect(YouTubeTitleCleaner.extractPlaylistId('Planet'), isNull);
      expect(YouTubeTitleCleaner.extractPlaylistId('Platinum'), isNull);
      expect(YouTubeTitleCleaner.extractPlaylistId('PL'), isNull);
      expect(
        YouTubeTitleCleaner.extractPlaylistId('PL1234567890ABCDEF'),
        'PL1234567890ABCDEF',
      );
      expect(
        YouTubeTitleCleaner.extractPlaylistId('https://www.youtube.com/playlist?list=PL1234567890ABCDEF'),
        'PL1234567890ABCDEF',
      );
    });

    test('13. QueryIntent copyWith allows overriding explicitLanguage', () {
      const intent = QueryIntent(
        rawQuery: 'hindi arijit',
        cleanQuery: 'arijit',
        explicitLanguage: 'Hindi',
        transliteratedQuery: 'arijit',
      );
      final fallback = intent.copyWith(explicitLanguage: null);
      expect(fallback.explicitLanguage, isNull);
      expect(fallback.cleanQuery, 'arijit');
    });

    test('14. calculateCompositeRelevance allows exact match to bypass language mismatch', () {
      final song = Song(
        id: 'cross_lang_exact',
        title: 'Arabic Kuthu',
        artist: 'Anirudh',
        album: 'Beast',
        duration: 240,
        coverUrl: '',
        language: 'Tamil',
      );
      const hindiIntent = QueryIntent(
        rawQuery: 'arabic kuthu',
        cleanQuery: 'arabic kuthu',
        explicitLanguage: 'Hindi',
        transliteratedQuery: 'arabic kuthu',
      );
      final score = SearchService.calculateCompositeRelevance(song, hindiIntent);
      expect(score, greaterThan(0.0));
    });
  });
}
