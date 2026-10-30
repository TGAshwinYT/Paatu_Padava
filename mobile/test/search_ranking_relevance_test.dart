import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/logic/search_query_planner.dart';
import 'package:paatu_padava_mobile/core/dsa/prefix_trie.dart';
import 'package:paatu_padava_mobile/core/dsa/bk_tree.dart';

void main() {
  Song createSong({
    required String id,
    required String title,
    required String artist,
    String album = 'Studio Album',
    String coverUrl = 'https://c.saavncdn.com/123/album-500x500.jpg',
    int duration = 210,
    String source = 'saavn',
    String? language = 'tamil',
    List<TrackEntity> versions = const [],
  }) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      coverUrl: coverUrl,
      duration: duration,
      source: source,
      language: language,
      versions: versions,
    );
  }

  group('Stage 1: Instant Debounced Typeahead (< 150ms)', () {
    test('Empty or whitespace query returns empty suggestions immediately', () async {
      final suggestions = await SearchService.getTypeaheadSuggestions('');
      expect(suggestions, isEmpty);

      final wsSuggestions = await SearchService.getTypeaheadSuggestions('   ');
      expect(wsSuggestions, isEmpty);
    });

    test('Local PrefixTrie returns instant matches (< 1ms) prioritized first', () async {
      final trie = PrefixTrie<String>();
      trie.insert('Anirudh Ravichander', weight: 100);
      trie.insert('A.R. Rahman', weight: 90);
      trie.insert('Aalaporaan Thamizhan', weight: 80);
      trie.insert('Harris Jayaraj', weight: 50);

      final matches = await SearchService.getTypeaheadSuggestions('a', localTrie: trie, limit: 5);
      expect(matches, contains('Anirudh Ravichander'));
      expect(matches, contains('A.R. Rahman'));
      expect(matches, isNot(contains('Harris Jayaraj')));
    });

    test('Typeahead deduplicates suggestions across local and remote sources', () async {
      final trie = PrefixTrie<String>();
      trie.insert('Vaathi Coming', weight: 100);

      final suggestions = await SearchService.getTypeaheadSuggestions('vaathi', localTrie: trie);
      final occurrences = suggestions.where((s) => s.toLowerCase() == 'vaathi coming').length;
      expect(occurrences, equals(1));
    });
  });

  group('Stage 2: Parallel Multi-Source Query Planning', () {
    test('Plans targeted queries: adds explicit language for JioSaavn, keeps clean for YouTube Music', () {
      final queries = SearchQueryPlanner.planMultiSourceQueries('Hukum', explicitLanguage: 'Tamil');
      expect(queries['saavn'], equals('Tamil Hukum'));
      expect(queries['youtube'], equals('Hukum'));
    });

    test('Does not duplicate language in Saavn query if query already mentions it', () {
      final queries = SearchQueryPlanner.planMultiSourceQueries('Tamil Hits 2024', explicitLanguage: 'Tamil');
      expect(queries['saavn'], equals('Tamil Hits 2024'));
      expect(queries['youtube'], equals('Tamil Hits 2024'));
    });
  });

  group('Stage 3: Normalization & Cross-Source Deduplication', () {
    test('Cleans titles removing YouTube video tags, promotional markers, and bracketed film info', () {
      expect(
        SearchQueryPlanner.cleanTitle('Vaathi Coming Full Video Song | Master | Thalapathy Vijay | Anirudh'),
        equals('Vaathi Coming'),
      );
      expect(
        SearchQueryPlanner.cleanTitle('Hukum - Thalaivar Alappara (From "Jailer") [Official Video]'),
        equals('Hukum - Thalaivar Alappara'),
      );
      expect(
        SearchQueryPlanner.cleanTitle('Arabic Kuthu - Lyrical | Beast | Thalapathy Vijay | Sun Pictures'),
        equals('Arabic Kuthu'),
      );
    });

    test('Generates identical canonical fingerprint for same song from JioSaavn and YouTube', () {
      const saavnTitle = 'Vaathi Coming (From "Master")';
      const saavnArtist = 'Anirudh Ravichander, Thalapathy Vijay';

      const ytTitle = 'Vaathi Coming Official Video Song | Master | Anirudh';
      const ytArtist = 'Anirudh Ravichander - Topic';

      final fpSaavn = SearchQueryPlanner.generateCanonicalFingerprint(saavnTitle, saavnArtist);
      final fpYt = SearchQueryPlanner.generateCanonicalFingerprint(ytTitle, ytArtist);

      expect(fpSaavn, equals('vaathicoming|anirudhravichander'));
      expect(fpYt, equals('vaathicoming|anirudhravichander'));
      expect(fpSaavn, equals(fpYt));
    });

    test('isSameSong matches tracks across providers despite different bracket formatting', () {
      final same = SearchQueryPlanner.isSameSong(
        titleA: 'Kadhaippoma (From "Oh My Kadavule")',
        artistsA: 'Leon James, Sid Sriram',
        titleB: 'Kadhaippoma Video Song | Oh My Kadavule | Sid Sriram',
        artistsB: 'Sid Sriram',
      );
      expect(same, isTrue);
    });

    test('deduplicateAndRankUnified collapses Saavn and YouTube duplicates into a single entry with versions', () {
      final saavnSong = createSong(
        id: 'saavn_101',
        title: 'Vaathi Coming (From "Master")',
        artist: 'Anirudh Ravichander, Vijay',
        source: 'saavn',
        coverUrl: 'https://c.saavncdn.com/master/vaathi-500x500.jpg',
      );

      final ytSong = createSong(
        id: 'yt_202',
        title: 'Vaathi Coming Full Video Song | Master | Anirudh',
        artist: 'Anirudh Ravichander',
        source: 'youtube',
        coverUrl: 'https://i.ytimg.com/vi/yt_202/hqdefault.jpg',
      );

      final intent = SearchService.understandQuery('vaathi coming');
      final unified = SearchService.deduplicateAndRankUnified(
        saavnSongs: [saavnSong],
        ytSongs: [ytSong],
        audiusSongs: const [],
        intent: intent,
      );

      // Must collapse into exactly 1 song in results
      expect(unified.length, equals(1));
      // Primary should be the JioSaavn version (clean 320kbps + square studio art)
      expect(unified.first.id, equals('saavn_101'));
      expect(unified.first.source, equals('saavn'));
      // YouTube version is linked into versions
      expect(unified.first.versions.length, equals(1));
      expect(unified.first.versions.first.id, equals('yt_202'));
    });
  });

  group('Stage 4: Multi-Factor Relevance Scoring Formula', () {
    test('StringSimilarity: exact title match yields 1.0', () {
      final song = createSong(id: '1', title: 'Hukum', artist: 'Anirudh Ravichander');
      final intent = SearchService.understandQuery('hukum');

      final sim = SearchService.calculateStringSimilarity(song, intent);
      expect(sim, equals(1.0));
    });

    test('StringSimilarity: Tanglish / Romanized Tamil typo is resolved via BkTree levenshtein distance', () {
      final song = createSong(id: '1', title: 'Vaseegara', artist: 'Harris Jayaraj');

      // "waseegara" typo with 'w' instead of 'v'
      final intentTypoW = SearchService.understandQuery('waseegara');
      final simW = SearchService.calculateStringSimilarity(song, intentTypoW);
      expect(simW, greaterThanOrEqualTo(0.85));

      // "vasegara" missing middle 'e' (edit distance 1)
      final intentMissingE = SearchService.understandQuery('vasegara');
      final simE = SearchService.calculateStringSimilarity(song, intentMissingE);
      expect(simE, greaterThanOrEqualTo(0.85));

      // Distance check directly on BkTree metric space
      expect(BkTree.levenshteinDistance('waseegara', 'vaseegara'), equals(1));
      expect(BkTree.levenshteinDistance('vasegara', 'vaseegara'), equals(1));
    });

    test('SourcePopularity: JioSaavn studio release with official square artwork and standard duration gets top score', () {
      final highQualityStudioSong = createSong(
        id: '1',
        title: 'Naa Ready',
        artist: 'Anirudh Ravichander, Thalapathy Vijay',
        duration: 248,
        source: 'saavn',
        coverUrl: 'https://c.saavncdn.com/leo/naa-ready-500x500.jpg',
      );

      final popularity = SearchService.calculateSourcePopularity(highQualityStudioSong);
      expect(popularity, greaterThanOrEqualTo(0.90));
    });

    test('SourcePopularity: non-official short video clips (< 45s) are penalized', () {
      final teaserClip = createSong(
        id: 'teaser_1',
        title: 'Naa Ready 30s Promo',
        artist: 'Leo Movie Channel',
        duration: 30, // Short clip penalty
        source: 'youtube',
        coverUrl: 'https://i.ytimg.com/vi/teaser_1/default.jpg',
      );

      final popularity = SearchService.calculateSourcePopularity(teaserClip);
      expect(popularity, lessThan(0.50));
    });

    test('UserAffinity: boosts candidate when artist is present in favorites or history', () {
      final candidateSong = createSong(id: '1', title: 'Rowdy Baby', artist: 'Dhanush, Dhee');

      final favoriteSong = createSong(id: 'fav_1', title: 'Why This Kolaveri Di', artist: 'Dhanush');
      final historySong = createSong(id: 'hist_1', title: 'Maari Thara Local', artist: 'Dhanush');

      // 1. With artist in favorites -> full affinity 1.0
      final affinityFav = SearchService.calculateUserAffinity(
        candidateSong,
        favorites: [favoriteSong],
        history: const [],
      );
      expect(affinityFav, equals(1.0));

      // 2. With artist in history -> strong affinity 0.70 to 1.0
      final affinityHist = SearchService.calculateUserAffinity(
        candidateSong,
        favorites: const [],
        history: [historySong],
      );
      expect(affinityHist, greaterThanOrEqualTo(0.70));

      // 3. Unknown artist without history -> 0.0 affinity
      final affinityNone = SearchService.calculateUserAffinity(
        candidateSong,
        favorites: const [],
        history: const [],
      );
      expect(affinityNone, equals(0.0));
    });

    test('Multi-factor formula strictly computes: (0.45 * StringSimilarity) + (0.35 * SourcePopularity) + (0.20 * UserAffinity)', () {
      final song = createSong(
        id: '1',
        title: 'Chilla Chilla',
        artist: 'Anirudh Ravichander',
        duration: 220,
        source: 'saavn',
        coverUrl: 'https://c.saavncdn.com/thunivu/chilla-chilla-500x500.jpg',
      );

      final intent = SearchService.understandQuery('chilla chilla');
      final stringSim = SearchService.calculateStringSimilarity(song, intent); // 1.0
      final popularity = SearchService.calculateSourcePopularity(song); // 1.0
      final affinity = SearchService.calculateUserAffinity(
        song,
        favorites: [createSong(id: 'fav_anirudh', title: 'Hukum', artist: 'Anirudh Ravichander')],
      ); // 1.0

      final expectedScore = (0.45 * stringSim) + (0.35 * popularity) + (0.20 * affinity);
      final computedScore = SearchService.calculateCompositeRelevance(
        song,
        intent,
        favorites: [createSong(id: 'fav_anirudh', title: 'Hukum', artist: 'Anirudh Ravichander')],
      );

      expect(computedScore, closeTo(expectedScore, 0.01));
      expect(computedScore, closeTo(1.0, 0.01));
    });

    test('Cross-language mismatch is filtered to 0.0 when query has explicit language', () {
      final hindiSong = createSong(
        id: 'hindi_1',
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        language: 'hindi',
      );

      final intent = SearchService.understandQuery('tamil songs');
      final score = SearchService.calculateCompositeRelevance(hindiSong, intent);
      expect(score, equals(0.0));
    });
  });
}
