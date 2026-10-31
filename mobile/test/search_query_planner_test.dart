import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/search_query_planner.dart';

void main() {
  group('SearchQueryPlanner', () {
    test('recent search / artist chip is searched EXACTLY (no "Tamil" prefix)', () {
      expect(SearchQueryPlanner.forExactQuery('Believer'), 'Believer');
      expect(SearchQueryPlanner.forExactQuery('  Taylor Swift  '), 'Taylor Swift');
      expect(SearchQueryPlanner.forExactQuery('Arijit Singh'), isNot(contains('Tamil')));
    });

    test('category tiles preserve clean query without mutating language prefix', () {
      expect(SearchQueryPlanner.forCategory('Workout', preferredLanguage: 'Tamil'), 'Workout');
      expect(SearchQueryPlanner.forCategory('Top Tamil Hits', preferredLanguage: 'Tamil'), 'Top Tamil Hits');
      expect(
        SearchQueryPlanner.forCategory('Hindi Romance', preferredLanguage: 'Tamil', explicitLanguage: 'Hindi'),
        'Hindi Romance',
      );
      expect(SearchQueryPlanner.forCategory('Party', preferredLanguage: ''), 'Party');
      expect(SearchQueryPlanner.forCategory('Anirudh Ravichander', preferredLanguage: 'Tamil'), 'Anirudh Ravichander');
    });

    test('extractCoreSubject strips descriptor intent tokens', () {
      expect(SearchQueryPlanner.extractCoreSubject('Anirudh Ravichander Vibe Hits'), 'Anirudh Ravichander');
      expect(SearchQueryPlanner.extractCoreSubject('Harris Jayaraj Songs'), 'Harris Jayaraj');
      expect(SearchQueryPlanner.extractCoreSubject('Best of Yuvan'), 'Yuvan');
      expect(SearchQueryPlanner.extractCoreSubject('SPB All Hits'), 'SPB');
    });
  });
}
