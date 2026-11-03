import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/ui/screens/search_screen.dart';
import 'package:paatu_padava_mobile/ui/widgets/search/search_pre_content.dart';
import 'package:paatu_padava_mobile/ui/widgets/search/search_active_typing_suggestions.dart';
import 'package:paatu_padava_mobile/ui/widgets/search/search_all_results_view.dart';
import 'package:paatu_padava_mobile/ui/widgets/search/search_song_tile.dart';
import 'package:paatu_padava_mobile/ui/widgets/search/search_top_result_card.dart';

void main() {
  group('3-State Progressive Search UI Tests', () {
    testWidgets('State A (Zero-Query) renders SearchPreContent with Quick Vibes & Recent searches', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // State A: Must display SearchPreContent
      expect(find.byType(SearchPreContent), findsOneWidget);
      expect(find.text('Quick Vibes & Eras'), findsOneWidget);
      expect(find.text('90s Melody'), findsOneWidget);
      expect(find.text('Anirudh Vibe'), findsOneWidget);
      // Trending Artists and Recent Searches removed from zero-query search view
      expect(find.text('Trending Artists'), findsNothing);
      expect(find.text('Recent Searches'), findsNothing);
    });

    testWidgets('State B (Active Typing) displays instant local matches and query completions', (tester) async {
      final sampleSong = Song(
        id: 'test_s1',
        title: 'Hukum',
        artist: 'Anirudh Ravichander',
        album: 'Jailer',
        duration: 210,
        source: 'saavn',
        coverUrl: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchActiveTypingSuggestions(
              localSongMatches: [sampleSong],
              queryCompletions: const ['hukum audio', 'hukum ringtone'],
              onPlaySong: (_) {},
              onSelectQuery: (_) {},
              onAppendQuery: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // State B verification
      expect(find.text('INSTANT MATCHES'), findsOneWidget);
      expect(find.text('Hukum'), findsOneWidget);
      expect(find.text('SEARCH SUGGESTIONS'), findsOneWidget);
      expect(find.text('hukum audio'), findsOneWidget);
      expect(find.text('hukum ringtone'), findsOneWidget);
    });

    testWidgets('State C (Committed Results) renders sticky filter bar and clustered alternate versions', (tester) async {
      final officialTrack = Song(
        id: 's_main',
        title: 'Arabic Kuthu',
        artist: 'Anirudh Ravichander',
        album: 'Beast',
        duration: 280,
        source: 'saavn',
        coverUrl: '',
        versions: [
          Song(
            id: 's_lofi',
            title: 'Arabic Kuthu - Slowed + Reverb',
            artist: 'Anirudh Ravichander',
            album: 'Lofi',
            duration: 260,
            source: 'youtube',
            coverUrl: '',
          ),
        ],
      );

      final state = SearchResultsState(
        songs: [officialTrack],
        topResult: {
          'id': 's_main',
          'title': 'Arabic Kuthu',
          'artist': 'Anirudh Ravichander',
          'confidence': 0.95,
          'type': 'song',
          'image': '',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchAllResultsView(
              state: state,
              query: 'Arabic Kuthu',
              onDidYouMeanTap: (_) {},
              onArtistRecordClick: () {},
              onRecordClick: ([_]) {},
              onSongTap: (_) {},
              onShowOptions: (_) {},
              onShowVersions: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sticky Intent Filter pills
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Songs'), findsWidgets);
      expect(find.text('Mixes & BGM'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);

      // Top result hero card omitted from main view to prioritize songs and artists
      expect(find.byType(SearchTopResultCard), findsNothing);

      // Song tile with clustered alternate versions badge
      expect(find.byType(SearchSongTile), findsOneWidget);
      expect(find.text('+1 Mixes ▾'), findsOneWidget);

      // Switching to 'Mixes & BGM' filter in-memory (< 1ms)
      await tester.tap(find.text('Mixes & BGM'));
      await tester.pumpAndSettle();
      expect(find.text('Remixes, Mashups & BGMs'), findsOneWidget);
    });

    testWidgets('SearchTopResultCard skips rendering when confidence < 0.85 threshold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchTopResultCard(
              top: const {
                'id': 's_ambiguous',
                'title': 'Some Random Video',
                'confidence': 0.60,
              },
              onArtistClick: () {},
              onPlay: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Confidence 0.60 < 0.85 -> card omitted
      expect(find.text('TOP RESULT'), findsNothing);
    });

    testWidgets('SearchTopResultCard renders when confidence >= 0.85 threshold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchTopResultCard(
              top: const {
                'id': 's_main',
                'title': 'Arabic Kuthu',
                'confidence': 0.95,
              },
              onArtistClick: () {},
              onPlay: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TOP RESULT'), findsOneWidget);
    });

    testWidgets('State B remains visible indefinitely during typing pauses, transitions to State C only on explicit submission', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap search bar to activate
      await tester.tap(find.text('What do you want to play?'));
      await tester.pumpAndSettle();

      // Type 'Hi'
      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.pump();

      // State B: SearchActiveTypingSuggestions must be visible
      expect(find.byType(SearchActiveTypingSuggestions), findsOneWidget);
      expect(find.byType(SearchAllResultsView), findsNothing);

      // Simulate a typing pause of 1200ms
      await tester.pump(const Duration(milliseconds: 1200));

      // CRITICAL: SearchActiveTypingSuggestions MUST STILL BE VISIBLE!
      // It must NOT automatically switch to SearchAllResultsView or wipe suggestions
      expect(find.byType(SearchActiveTypingSuggestions), findsOneWidget);
      expect(find.byType(SearchAllResultsView), findsNothing);

      // Verify clearing text restores State A
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.byType(SearchPreContent), findsOneWidget);
      expect(find.byType(SearchActiveTypingSuggestions), findsNothing);
    });

    testWidgets('Pause-to-results & Debounce: typing pause of 450ms or 1200ms NEVER triggers full results or spinner', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Activate and type
      await tester.tap(find.text('What do you want to play?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'K');
      await tester.pump();

      // State B is visible
      expect(find.byType(SearchActiveTypingSuggestions), findsOneWidget);

      // Rapid keystroke before 150ms debounce (e.g. 50ms)
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'Ka');
      await tester.pump();

      // Wait 150ms for typeahead debounce
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(SearchActiveTypingSuggestions), findsOneWidget);

      // Wait 450ms (the old auto-search timer threshold)
      await tester.pump(const Duration(milliseconds: 450));

      // MUST NOT have transitioned to SearchAllResultsView or loading spinner!
      expect(find.byType(SearchActiveTypingSuggestions), findsOneWidget);
      expect(find.byType(SearchAllResultsView), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Wait an additional 1000ms (1.45s total pause)
      await tester.pump(const Duration(milliseconds: 1000));

      // STILL locked in State B
      expect(find.byType(SearchActiveTypingSuggestions), findsOneWidget);
      expect(find.byType(SearchAllResultsView), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Back-button / PopScope behavior: intercepts back when search is active or has text, canPop is true when clean', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('Base Screen')),
        ),
      );
      await tester.pumpAndSettle();

      // Push SearchScreen onto navigator
      navKey.currentState!.push(MaterialPageRoute(builder: (_) => const SearchScreen()));
      await tester.pumpAndSettle();

      // 1. Initial State A: search is inactive and text is empty -> canPop must be TRUE
      var popScope = tester.widgetList(find.byWidgetPredicate((w) => w is PopScope)).first as PopScope;
      expect(popScope.canPop, isTrue);
      expect(find.byType(SearchPreContent), findsOneWidget);

      // 2. Tap search bar to enter active search
      await tester.tap(find.text('What do you want to play?'));
      await tester.pumpAndSettle();

      // Active search with empty text -> canPop must be FALSE to protect against exiting
      popScope = tester.widgetList(find.byWidgetPredicate((w) => w is PopScope)).first as PopScope;
      expect(popScope.canPop, isFalse);

      // Trigger back button while active search is open
      await navKey.currentState!.maybePop();
      await tester.pumpAndSettle();

      // Must have intercepted back and returned to inactive State A, SearchScreen is still mounted!
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(find.byType(SearchPreContent), findsOneWidget);
      popScope = tester.widgetList(find.byWidgetPredicate((w) => w is PopScope)).first as PopScope;
      expect(popScope.canPop, isTrue);

      // 3. Enter active search and type a query
      await tester.tap(find.text('What do you want to play?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Anirudh');
      await tester.pump();

      // Active search with typed text -> canPop must be FALSE
      popScope = tester.widgetList(find.byWidgetPredicate((w) => w is PopScope)).first as PopScope;
      expect(popScope.canPop, isFalse);
      expect(find.byType(SearchActiveTypingSuggestions), findsOneWidget);

      // Trigger back button while text is present
      await navKey.currentState!.maybePop();
      await tester.pumpAndSettle();

      // Must have cleared text, exited active search, returned to State A, SearchScreen still mounted
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(find.byType(SearchPreContent), findsOneWidget);
      expect(find.byType(SearchActiveTypingSuggestions), findsNothing);
      popScope = tester.widgetList(find.byWidgetPredicate((w) => w is PopScope)).first as PopScope;
      expect(popScope.canPop, isTrue);

      // 4. Now in clean State A, back button SHOULD pop the screen and return to Base Screen
      await navKey.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsNothing);
      expect(find.text('Base Screen'), findsOneWidget);
    });
  });
}
