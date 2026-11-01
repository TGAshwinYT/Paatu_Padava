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
  });
}
