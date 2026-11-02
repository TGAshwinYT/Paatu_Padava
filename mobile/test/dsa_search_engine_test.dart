import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/core/dsa/trigram_index.dart';
import 'package:paatu_padava_mobile/core/dsa/symspell.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/lyrics_search_service.dart';

void main() {
  group('TrigramIndex (Tanglish & Regional Phonetic Search)', () {
    late TrigramIndex<String> index;

    setUp(() {
      index = TrigramIndex<String>();
      index.insert('Kannaadi Kannaadi', payload: 'track_1');
      index.insert('Vaathi Coming', payload: 'track_2');
      index.insert('Rowdy Baby', payload: 'track_3');
      index.insert('Mersal Arasan', payload: 'track_4');
      index.insert('Samayama', payload: 'track_5');
      index.insert('Nee Paartha Vizhigal', payload: 'track_6');
    });

    test('matches phonetic Tanglish spelling variants with high similarity', () {
      // User types "kannadi" with one 'a' instead of "kannaadi"
      final results = index.search('kannadi', threshold: 0.50);
      expect(results.isNotEmpty, isTrue);
      expect(results.first.term, equals('Kannaadi Kannaadi'));
      expect(results.first.payload, equals('track_1'));
      expect(results.first.similarity, greaterThan(0.55));
    });

    test('matches "vathi" to "Vaathi Coming"', () {
      final results = index.search('vathi', threshold: 0.40);
      expect(results.isNotEmpty, isTrue);
      expect(results.first.term, equals('Vaathi Coming'));
    });

    test('matches "samayamaa" to "Samayama"', () {
      final results = index.search('samayamaa', threshold: 0.60);
      expect(results.isNotEmpty, isTrue);
      expect(results.first.term, equals('Samayama'));
    });

    test('computes symmetric Jaccard similarity accurately', () {
      final j1 = TrigramIndex.jaccard('kannaadi', 'kannadi');
      final j2 = TrigramIndex.jaccard('kannadi', 'kannaadi');
      expect(j1, equals(j2));
      expect(j1, greaterThan(0.60));
    });
  });

  group('SymSpell (O(1) Typo Spelling Correction)', () {
    late SymSpell symSpell;

    setUp(() {
      symSpell = SymSpell(maxEditDistance: 2);
      symSpell.insert('mersal', count: 100);
      symSpell.insert('maari', count: 80);
      symSpell.insert('anirudh', count: 120);
      symSpell.insert('rahman', count: 150);
    });

    test('returns exact match with distance 0', () {
      final results = symSpell.lookup('mersal');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.term, equals('mersal'));
      expect(results.first.distance, equals(0));
    });

    test('corrects 1-character typo "marsal" -> "mersal" in distance 1', () {
      final results = symSpell.lookup('marsal');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.term, equals('mersal'));
      expect(results.first.distance, equals(1));
    });

    test('corrects transposition "merals" -> "mersal"', () {
      final results = symSpell.lookup('merals');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.term, equals('mersal'));
      expect(results.first.distance, equals(1));
    });

    test('corrects 2-edit typo "aniruth" -> "anirudh"', () {
      final results = symSpell.lookup('aniruth');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.term, equals('anirudh'));
      expect(results.first.distance, equals(1));
    });
  });

  group('LyricsSearchService (On-Device Lyrics Inversion)', () {
    late LyricsSearchService lyricsService;

    setUp(() {
      lyricsService = LyricsSearchService.instance;
      lyricsService.clear();

      final song1 = Song(
        id: 's_samayama',
        title: 'Samayama',
        artist: 'Hesham Abdul Wahab, Anurag Kulkarni',
        album: 'Hi Nanna',
        coverUrl: 'https://example.com/cover.jpg',
      );
      lyricsService.indexLyrics(
        song1,
        '''[00:15.20] Samayama aagipova
[00:20.10] Ee kshaname nilichipova
[00:25.50] Manasuke theliyani maayalo
[00:30.00] Kalayika modalaye velalo''',
      );

      final song2 = Song(
        id: 's_neethanae',
        title: 'Neethanae',
        artist: 'A.R. Rahman, Shreya Ghoshal',
        album: 'Mersal',
        coverUrl: 'https://example.com/cover2.jpg',
      );
      lyricsService.indexLyrics(
        song2,
        '''[00:12.00] Kannaadi kannaadi paarthu
[00:16.50] Kangalil kanavugal serthu
[00:21.00] Neethanae en jeevan endru
[00:26.00] Sollaamal solgindra anbu''',
      );
    });

    test('matches song by memorable lyric hook and extracts snippet', () {
      final results = lyricsService.searchLyrics('kannaadi kannaadi');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.songId, equals('s_neethanae'));
      expect(results.first.matchingSnippet.toLowerCase(), contains('kannaadi'));
      expect(results.first.score, equals(1.0));
    });

    test('matches Telugu lyric line "aagipova" to Samayama', () {
      final results = lyricsService.searchLyrics('aagipova');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.songId, equals('s_samayama'));
      expect(results.first.matchingSnippet, contains('Samayama aagipova'));
    });
  });
}
