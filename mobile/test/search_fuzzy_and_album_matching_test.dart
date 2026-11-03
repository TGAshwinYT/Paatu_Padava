import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/fuzzy_search_service.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mersalSong = Song(
    id: 'mersal_neethanae',
    title: 'Neethanae',
    artist: 'A.R. Rahman, Shreya Ghoshal',
    album: 'Mersal',
    duration: 269,
    coverUrl: 'https://example.com/mersal.jpg',
    source: 'saavn',
    streamUrl: 'https://example.com/stream.m4a',
  );

  final hindiSong = Song(
    id: 'brahmastra_kesariya',
    title: 'Kesariya',
    artist: 'Arijit Singh, Pritam',
    album: 'Brahmastra',
    duration: 268,
    coverUrl: 'https://example.com/brahmastra.jpg',
    source: 'saavn',
    streamUrl: 'https://example.com/stream2.m4a',
  );

  group('FuzzySearchService.matchesSong (History & Favorites Matching)', () {
    test('matches song via album with exact substring', () {
      expect(FuzzySearchService.matchesSong(mersalSong, 'mersal'), isTrue);
      expect(FuzzySearchService.matchesSong(mersalSong, 'Mersal'), isTrue);
      expect(FuzzySearchService.matchesSong(hindiSong, 'brahmastra'), isTrue);
    });

    test('matches song via album with 1-character typo tolerance (Levenshtein <= 1)', () {
      // User typed "marsal" (typo for "mersal")
      expect(FuzzySearchService.matchesSong(mersalSong, 'marsal'), isTrue);
      // Hindi album typo
      expect(FuzzySearchService.matchesSong(hindiSong, 'brahmaster'), isTrue);
    });

    test('matches song via title and artist with typo tolerance', () {
      expect(FuzzySearchService.matchesSong(mersalSong, 'neethanae'), isTrue);
      // Typo in title: "nithanae"
      expect(FuzzySearchService.matchesSong(mersalSong, 'nithanae'), isTrue);
      // Artist match
      expect(FuzzySearchService.matchesSong(mersalSong, 'rahman'), isTrue);
      // Typo in artist: "rehman"
      expect(FuzzySearchService.matchesSong(mersalSong, 'rehman'), isTrue);
    });

    test('rejects completely unrelated search queries', () {
      expect(FuzzySearchService.matchesSong(mersalSong, 'anirudh'), isFalse);
      expect(FuzzySearchService.matchesSong(mersalSong, 'kabali'), isFalse);
      expect(FuzzySearchService.matchesSong(mersalSong, 'jailer'), isFalse);
    });
  });

  group('SearchService Universal Phonetic Variants (All Languages)', () {
    test('generates universal phonetic variants for vowel substitutions', () {
      final marsalVariants = SearchService.generateUniversalPhoneticVariants('marsal');
      expect(marsalVariants, contains('mersal'));

      final suryaVariants = SearchService.generateUniversalPhoneticVariants('surya');
      expect(suryaVariants, contains('soorya'));

      final sooryaVariants = SearchService.generateUniversalPhoneticVariants('soorya');
      expect(sooryaVariants, contains('surya'));

      final denceVariants = SearchService.generateUniversalPhoneticVariants('dence');
      expect(denceVariants, contains('dance'));
    });

    test('generates universal phonetic variants for consonants and aspirates', () {
      final aniruthVariants = SearchService.generateUniversalPhoneticVariants('aniruth');
      expect(aniruthVariants, contains('anirudh'));

      final waseegaraVariants = SearchService.generateUniversalPhoneticVariants('waseegara');
      expect(waseegaraVariants, contains('vaseegara'));

      final neruppuVariants = SearchService.generateUniversalPhoneticVariants('neruppu');
      expect(neruppuVariants, contains('nerupu'));

      // Intervocalic geminate doubling: doubles medial consonant between vowels, never word-initial
      final nerupuVariants = SearchService.generateUniversalPhoneticVariants('nerupu');
      expect(nerupuVariants, contains('neruppu'));

      final karkalamVariants = SearchService.generateUniversalPhoneticVariants('karkalam');
      // Must not double word-initial 'k' into junk 'kkarkkalam'
      expect(karkalamVariants, isNot(contains('kkarkkalam')));
    });
  });

  group('SearchService.understandQuery Fallback & DidYouMean', () {
    test('understands "marsal" and falls back to universal phonetic variant "mersal"', () {
      final intent = SearchService.understandQuery('Marsal');
      expect(intent.cleanQuery, 'Marsal');
      expect(intent.transliteratedQuery.toLowerCase(), 'mersal');
      expect(intent.universalPhoneticVariant?.toLowerCase(), 'mersal');
      expect(intent.didYouMeanSuggestion?.toLowerCase(), 'mersal');
    });

    test('calculates high string similarity for song when album matches query', () {
      final intent = SearchService.understandQuery('marsal');
      final similarity = SearchService.calculateStringSimilarity(mersalSong, intent);
      expect(similarity, greaterThanOrEqualTo(0.85));
    });
  });

  group('Multi-Language Indic Script & Phonetic Expansion (All Languages)', () {
    final tamilScriptSong = Song(
      id: 'tamil_ps1',
      title: 'பொன்னியின் செல்வன்',
      artist: 'ஏ.ஆர். ரஹ்மான்',
      album: 'பொன்னியின் செல்வன் 1',
      coverUrl: '',
    );

    final teluguScriptSong = Song(
      id: 'telugu_devara',
      title: 'చుట్టమల్లే',
      artist: 'అనిరుధ్ రవిచందర్',
      album: 'దేవర',
      coverUrl: '',
    );

    test('FuzzySearchService.matchesSong preserves and matches native Indic script tokens', () {
      // Tamil script tokens are not stripped by regex
      expect(FuzzySearchService.matchesSong(tamilScriptSong, 'பொன்னியின்'), isTrue);
      expect(FuzzySearchService.matchesSong(tamilScriptSong, 'செல்வன்'), isTrue);
      expect(FuzzySearchService.matchesSong(tamilScriptSong, 'ரஹ்மான்'), isTrue);

      // Telugu script tokens
      expect(FuzzySearchService.matchesSong(teluguScriptSong, 'చుట్టమల్లే'), isTrue);
      expect(FuzzySearchService.matchesSong(teluguScriptSong, 'దేవర'), isTrue);
    });

    test('SearchService.understandQuery transliterates native Indic scripts to Latin and detects language', () {
      // Tamil query
      final tamilIntent = SearchService.understandQuery('விக்ரம்');
      expect(tamilIntent.transliteratedQuery.toLowerCase(), equals('vikram'));
      expect(tamilIntent.explicitLanguage?.toLowerCase(), equals('tamil'));
      // Must NOT suggest English romanization as "did you mean" for native script
      expect(tamilIntent.didYouMeanSuggestion, isNull);

      // Hindi query: Devanagari script must resolve to 'hindi' language
      final hindiIntent = SearchService.understandQuery('केसरिया');
      expect(hindiIntent.transliteratedQuery.toLowerCase(), startsWith('kesariya'));
      expect(hindiIntent.explicitLanguage?.toLowerCase(), equals('hindi'));
      expect(hindiIntent.didYouMeanSuggestion, isNull);

      // Telugu query
      final teluguIntent = SearchService.understandQuery('చుట్టమల్లే');
      expect(teluguIntent.transliteratedQuery.toLowerCase(), startsWith('chuttamall'));
      expect(teluguIntent.explicitLanguage?.toLowerCase(), equals('telugu'));
      expect(teluguIntent.didYouMeanSuggestion, isNull);
    });

    test('FuzzySearchService.registerSongs learns up to 100 library songs and handles capacity bounding', () {
      final librarySongs = List.generate(
        120,
        (i) => Song(
          id: 'lib_song_$i',
          title: 'Unique Library Title $i',
          artist: 'Artist $i',
          album: 'Album $i',
          coverUrl: '',
        ),
      );

      // Registering 120 songs handles capacity without throwing or UI freeze
      FuzzySearchService.registerSongs(librarySongs);

      // Songs within the 100 quota should match
      expect(FuzzySearchService.matchesSong(librarySongs[10], 'Unique Library Title 10'), isTrue);
    });

    test('SearchService.expandPhoneticQuery handles multi-language transliterations without no-ops', () {
      // Eliminated no-ops: waseegara & vasikara -> vaseegara
      expect(SearchService.expandPhoneticQuery('waseegara').toLowerCase(), equals('vaseegara'));
      expect(SearchService.expandPhoneticQuery('vasikara').toLowerCase(), equals('vaseegara'));
      expect(SearchService.expandPhoneticQuery('oorum raththam').toLowerCase(), equals('oorum blood'));
      expect(SearchService.expandPhoneticQuery('oorum ratham').toLowerCase(), equals('oorum blood'));

      // Native Indic script input in expandPhoneticQuery
      expect(SearchService.expandPhoneticQuery('விக்ரம்').toLowerCase(), equals('vikram'));
      expect(SearchService.expandPhoneticQuery('பொன்னியின் செல்வன்').toLowerCase(), contains('ponniyin'));
    });
  });
  group('Search Engine Accuracy & Ranking Refinements', () {
    final vaathiSong = Song(
      id: 'z_track_master',
      title: 'Vaathi Coming',
      artist: 'Gana Balachandar',
      album: 'Master',
      coverUrl: '',
      duration: 230,
    );

    final aalaporanSong = Song(
      id: 'm_track_mersal',
      title: 'Aalaporan Thamizhan',
      artist: 'Kailash Kher, Sathya Prakash',
      album: 'Mersal',
      coverUrl: '',
      duration: 348,
    );

    final neethanaeSong = Song(
      id: 'a_track_mersal',
      title: 'Neethanae',
      artist: 'A.R. Rahman, Shreya Ghoshal',
      album: 'Mersal',
      coverUrl: '',
      duration: 269,
    );

    test('Short queries (< 3 chars) require word-start prefix match and eliminate noise', () {
      // Query "a":
      // "Vaathi Coming" has 'a' inside Vaathi, Gana, Balachandar, Master, but NO word starts with "a"
      expect(FuzzySearchService.matchesSong(vaathiSong, 'a'), isFalse);

      // "Aalaporan Thamizhan" title starts with "a"
      expect(FuzzySearchService.matchesSong(aalaporanSong, 'a'), isTrue);

      // Query "va": matches word-start in "Vaathi Coming"
      expect(FuzzySearchService.matchesSong(vaathiSong, 'va'), isTrue);
    });

    test('Album tracks preserve official tracklist arrival order instead of sorting by string ID', () {
      final intent = SearchService.understandQuery('Mersal');
      // Unpacked in album track order: track 1 (aalaporan), track 2 (neethanae)
      // Note IDs: aalaporan is 'm_track_mersal', neethanae is 'a_track_mersal'
      // If sorted by ID, 'a_track_mersal' would wrongly beat 'm_track_mersal'!
      final ranked = SearchService.deduplicateAndRankUnified(
        saavnSongs: [aalaporanSong, neethanaeSong],
        ytSongs: const [],
        intent: intent,
      );

      expect(ranked.length, equals(2));
      expect(ranked.first.id, equals('m_track_mersal'));
      expect(ranked.last.id, equals('a_track_mersal'));
    });

    test('Gated affinity: irrelevant song by favorite artist does not receive affinity bonus', () {
      final unrelatedAnirudhSong = Song(
        id: 'ani_unrelated',
        title: 'Random Track',
        artist: 'Anirudh Ravichander',
        album: 'Single',
        coverUrl: '',
        duration: 180,
      );

      final intent = SearchService.understandQuery('Shape of You');
      final scoreWithFavorites = SearchService.calculateCompositeRelevance(
        unrelatedAnirudhSong,
        intent,
        favorites: [Song(id: 'fav_ani', title: 'Hukum', artist: 'Anirudh Ravichander', coverUrl: '')],
      );

      final scoreWithoutFavorites = SearchService.calculateCompositeRelevance(
        unrelatedAnirudhSong,
        intent,
        favorites: [],
      );

      // Because string similarity < 0.25, effective affinity must be 0.0 (scores identical)
      expect(scoreWithFavorites, closeTo(scoreWithoutFavorites, 0.001));
    });

    test('Balanced source popularity allows verified YouTube tracks to compete on merit', () {
      final ytOfficial = Song(
        id: 'yt_official_1',
        title: 'Original Song',
        artist: 'Indie Artist - Topic',
        album: 'Indie Album',
        coverUrl: 'https://example.com/cover500.jpg',
        duration: 210,
        source: 'youtube',
      );

      final popularity = SearchService.calculateSourcePopularity(ytOfficial);
      expect(popularity, greaterThanOrEqualTo(0.80));
    });

    test('Hindi-script query retains and scores Hindi songs without cross-language rejection', () {
      final intent = SearchService.understandQuery('केसरिया');
      expect(intent.explicitLanguage?.toLowerCase(), equals('hindi'));

      final hindiSong = Song(
        id: 'saavn_kesariya_1',
        title: 'Kesariya',
        artist: 'Arijit Singh, Pritam',
        album: 'Brahmastra',
        language: 'hindi',
        source: 'saavn',
        coverUrl: 'https://example.com/kesariya.jpg',
        duration: 268,
      );

      // Verify isLanguageMismatch does NOT flag it as mismatch
      expect(SongRepository.isLanguageMismatch(hindiSong, intent.explicitLanguage!), isFalse);

      // Verify composite relevance score is high (> 0.70), not 0.0
      final score = SearchService.calculateCompositeRelevance(hindiSong, intent);
      expect(score, greaterThan(0.70));

      // Verify deduplicateAndRankUnified preserves Hindi songs
      final results = SearchService.deduplicateAndRankUnified(
        saavnSongs: [hindiSong],
        ytSongs: const [],
        intent: intent,
      );
      expect(results, isNotEmpty);
      expect(results.first.id, equals('saavn_kesariya_1'));
    });
  });
}
