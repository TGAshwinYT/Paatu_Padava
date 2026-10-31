import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/search_query_planner.dart';

void main() {
  group('SearchQueryPlanner', () {
    test('recent search / artist chip is searched EXACTLY (no "Tamil" prefix)', () {
      expect(SearchQueryPlanner.forExactQuery('Believer'), 'Believer');
      expect(SearchQueryPlanner.forExactQuery('  Taylor Swift  '), 'Taylor Swift');
      expect(SearchQueryPlanner.forExactQuery('Arijit Singh'), isNot(contains('Tamil')));
    });

    test('category tiles get the preferred language when none is named', () {
      expect(SearchQueryPlanner.forCategory('Workout', preferredLanguage: 'Tamil'), 'Tamil Workout');
    });

    test('category already naming the language is left alone', () {
      expect(SearchQueryPlanner.forCategory('Top Tamil Hits', preferredLanguage: 'Tamil'), 'Top Tamil Hits');
    });

    test('explicit other language is never overridden', () {
      expect(
        SearchQueryPlanner.forCategory('Hindi Romance', preferredLanguage: 'Tamil', explicitLanguage: 'Hindi'),
        'Hindi Romance',
      );
    });

    test('no preferred language -> unchanged', () {
      expect(SearchQueryPlanner.forCategory('Party', preferredLanguage: ''), 'Party');
    });
    test('category for known artist is not mutated with language prefix', () {
      expect(SearchQueryPlanner.forCategory('Anirudh Ravichander', preferredLanguage: 'Tamil'), 'Anirudh Ravichander');
      expect(SearchQueryPlanner.forCategory('A.R. Rahman', preferredLanguage: 'Tamil'), 'A.R. Rahman');
      expect(SearchQueryPlanner.forCategory('Ilaiyaraaja', preferredLanguage: 'Tamil'), 'Ilaiyaraaja');
    });

    test('extractCoreSubject strips descriptor intent tokens', () {
      expect(SearchQueryPlanner.extractCoreSubject('Anirudh Ravichander Vibe Hits'), 'Anirudh Ravichander');
      expect(SearchQueryPlanner.extractCoreSubject('Harris Jayaraj Songs'), 'Harris Jayaraj');
      expect(SearchQueryPlanner.extractCoreSubject('Best of Yuvan'), 'Yuvan');
      expect(SearchQueryPlanner.extractCoreSubject('SPB All Hits'), 'SPB');
    });
  });
}
