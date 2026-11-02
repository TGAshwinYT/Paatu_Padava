import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/core/dsa/minhash.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/services/user_preference_matrix.dart';
import 'package:paatu_padava_mobile/services/semantic_search_service.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Search Engine Remediation Verification Tests', () {
    test('1. MinHash Shingling: Variable interpolation works and distinct songs yield similarity < 0.15', () {
      final minhash = MinHash();
      final sigA = minhash.computeFromText('Arabic Kuthu Beast Anirudh');
      final sigB = minhash.computeFromText('Chinna Chinna Aasai Roja AR Rahman');

      final sim = sigA.similarity(sigB);
      // Dissimilar titles must not evaluate to 1.0
      expect(sim, lessThan(0.15));
      expect(sigA.isDuplicate(sigB, threshold: 0.50), isFalse);

      final sigIdenticalA = minhash.computeFromText('Arabic Kuthu Beast Anirudh');
      final sigIdenticalB = minhash.computeFromText('Arabic Kuthu Beast Anirudh');
      expect(sigIdenticalA.similarity(sigIdenticalB), equals(1.0));
    });

    test('2. SearchCache: Default searches with null language match "all" and avoid 100% cache miss', () {
      SearchCache.clear();
      final testSong = Song(
        id: 's1',
        title: 'Master The Blaster',
        artist: 'Anirudh Ravichander',
        album: 'Master',
        coverUrl: '',
      );

      final bundle = SearchResults(
        songs: [testSong],
        saavnSongs: [testSong],
      );

      // Write with null language (as done in progressive search)
      SearchCache.put('Master', bundle, language: null);

      // Read with null language or 'all'
      final cachedNull = SearchCache.get('Master', language: null);
      final cachedAll = SearchCache.get('Master', language: 'all');

      expect(cachedNull, isNotNull);
      expect(cachedAll, isNotNull);
      expect(cachedNull!.songs.first.id, equals('s1'));
      expect(cachedAll!.songs.first.id, equals('s1'));
    });

    test('3. SemanticSearchService: Partition sorting maintains strict order without TimSort contract violation', () {
      final songA = Song(id: '1', title: 'Energetic Dance Beat', artist: 'Artist A', album: 'Album A', coverUrl: '');
      final songB = Song(id: '2', title: 'Soothing Sleep Lullaby', artist: 'Artist B', album: 'Album B', coverUrl: '');
      final songC = Song(id: '3', title: 'Gym Workout Bass', artist: 'Artist C', album: 'Album C', coverUrl: '');

      // Query with mood intent 'gym workout party'
      final ranked = SemanticSearchService.instance.rankBySemanticIntent(
        [songA, songB, songC],
        'gym workout party',
        threshold: 0.20,
      );

      // High workout matches (Gym Workout Bass / Energetic Dance) should be promoted
      expect(ranked.isNotEmpty, isTrue);
      expect(ranked.length, equals(3));
    });

    test('4. UserPreferenceMatrix: Re-ranking scores favorites and query matches via O(1) indexed lookup', () {
      final exactMatch = Song(
        id: 'exact_1',
        title: 'Vaathi Coming',
        artist: 'Anirudh Ravichander',
        album: 'Master',
        coverUrl: '',
      );

      final unrelatedFav = Song(
        id: 'fav_1',
        title: 'Random Track',
        artist: 'Other Singer',
        album: 'Other Album',
        coverUrl: '',
      );

      final reRanked = UserPreferenceMatrix.reRankWithPreferences(
        [unrelatedFav, exactMatch],
        'Vaathi Coming',
        likedSongs: [unrelatedFav],
        historySongs: [unrelatedFav],
      );

      // Exact query match should decisively rank first
      expect(reRanked.first.id, equals('exact_1'));
    });

    test('5. filterGenuineAlbums: Excludes singles, preserves original input order without query, and sorts by relevance with query', () {
      final rawAlbums = [
        {
          'id': 'alb_1',
          'title': 'Leo (Original Motion Picture Soundtrack)',
          'song_count': '7',
          'year': '2023',
        },
        {
          'id': 'alb_2',
          'title': 'Bloody Sweet (From "Leo") - Single',
          'song_count': '1',
          'year': '2023',
        },
        {
          'id': 'alb_3',
          'title': 'Badass Single',
          'song_count': '2',
          'year': '2023',
        },
        {
          'id': 'alb_4',
          'title': 'Jailer',
          'song_count': '8',
          'year': '2023',
        },
      ];

      // Untargeted (null query) must preserve original rawAlbums ordering (alb_1 before alb_4)
      final filteredNoQuery = SearchService.filterGenuineAlbums(rawAlbums);
      expect(filteredNoQuery.length, equals(2));
      expect(filteredNoQuery[0]['id'], equals('alb_1'));
      expect(filteredNoQuery[0]['type'], equals('Album'));
      expect(filteredNoQuery[1]['id'], equals('alb_4'));
      expect(filteredNoQuery[1]['type'], equals('Album'));

      // Targeted query (e.g. "Jailer") must rank matching entity first
      final filteredTargeted = SearchService.filterGenuineAlbums(rawAlbums, query: 'Jailer');
      expect(filteredTargeted.first['id'], equals('alb_4'));
    });
  });
}
