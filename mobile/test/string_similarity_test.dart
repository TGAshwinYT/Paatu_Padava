import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/core/dsa/string_similarity.dart';

void main() {
  group('StringSimilarity Pure Dart DSA Tests', () {
    test('ratio accurately calculates identical and divergent strings', () {
      expect(StringSimilarity.ratio('hello', 'hello'), 100);
      expect(StringSimilarity.ratio('hello', ''), 0);
      expect(StringSimilarity.ratio('', 'world'), 0);
      expect(StringSimilarity.ratio('anirudh', 'aniruth'), greaterThanOrEqualTo(80));
    });

    test('partialRatio matches substrings effectively', () {
      expect(StringSimilarity.partialRatio('harris', 'harris jayaraj hits'), 100);
      expect(StringSimilarity.partialRatio('ar rahman', 'a r rahman collection'), greaterThan(80));
    });

    test('tokenSetRatio handles word order permutations and punctuation', () {
      final sim = StringSimilarity.tokenSetRatio(
        'Harris Jayaraj - Vaaranam Aayiram',
        'Vaaranam Aayiram by Harris Jayaraj',
      );
      expect(sim, 100);

      final songScore = StringSimilarity.tokenSetRatio(
        'Hukum - Thalaivar Alappara',
        'Hukum Thalaivar Alappara (From "Jailer")',
      );
      expect(songScore, greaterThanOrEqualTo(85));
    });

    test('extractTop returns sorted bounded top results above cutoff', () {
      final choices = [
        'Anirudh Ravichander',
        'A.R. Rahman',
        'Harris Jayaraj',
        'Yuvan Shankar Raja',
        'Santhosh Narayanan',
      ];

      final results = StringSimilarity.extractTop<String>(
        query: 'anirudh',
        choices: choices,
        limit: 3,
        cutoff: 50,
      );

      expect(results.isNotEmpty, true);
      expect(results.first.choice, 'Anirudh Ravichander');
      expect(results.first.score, greaterThanOrEqualTo(70));
    });
  });
}
