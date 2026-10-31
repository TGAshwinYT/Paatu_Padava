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
}
