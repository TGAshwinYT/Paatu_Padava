import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/fuzzy_search_service.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';

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

      // Hindi query
      final hindiIntent = SearchService.understandQuery('केसरिया');
      expect(hindiIntent.transliteratedQuery.toLowerCase(), startsWith('kesariya'));
      expect(hindiIntent.explicitLanguage?.toLowerCase(), equals('devanagari'));

      // Telugu query
      final teluguIntent = SearchService.understandQuery('చుట్టమల్లే');
      expect(teluguIntent.transliteratedQuery.toLowerCase(), startsWith('chuttamall'));
      expect(teluguIntent.explicitLanguage?.toLowerCase(), equals('telugu'));
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
}
