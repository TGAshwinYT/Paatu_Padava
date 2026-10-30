import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/ui/screens/search_screen.dart';
import 'package:paatu_padava_mobile/ui/widgets/search/search_playlists_grid.dart';
import 'package:paatu_padava_mobile/logic/track_quality_filter.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
  group('Playlists Search & Auto-Generation Tests', () {
    test('generateAutoPlaylistsFromAlbums converts movie albums into All Songs playlists', () {
      final albums = [
        {
          'id': 'alb_101',
          'title': 'Idhayam Murali',
          'name': 'Idhayam Murali',
          'image': 'https://c.saavncdn.com/101.jpg',
          'artist': 'Ilaiyaraaja',
          'song_count': 6,
        },
        {
          'id': 'alb_102',
          'title': 'Master',
          'name': 'Master',
          'image': 'https://c.saavncdn.com/102.jpg',
          'artist': 'Anirudh Ravichander',
          'song_count': 8,
        },
      ];

      final autoPlaylists = SearchService.generateAutoPlaylistsFromAlbums(albums);

      expect(autoPlaylists.length, 2);
      expect(autoPlaylists[0]['title'], 'Idhayam Murali (All Songs)');
      expect(autoPlaylists[0]['source'], 'auto_album');
      expect(autoPlaylists[0]['song_count'], 6);
      expect(autoPlaylists[0]['subtitle'], contains('6 Tracks'));

      expect(autoPlaylists[1]['title'], 'Master (All Songs)');
      expect(autoPlaylists[1]['source'], 'auto_album');
    });

    test('mergePlaylists deduplicates duplicate title playlists across providers', () {
      final primary = [
        {
          'id': 's_1',
          'title': 'Tamil 90s Hits',
          'source': 'saavn',
          'image': 'https://img.saavn/1.jpg',
        },
        {
          'id': 's_2',
          'title': 'Anirudh Party Mix',
          'source': 'saavn',
          'image': 'https://img.saavn/2.jpg',
        },
      ];

      final secondary = [
        {
          'id': 'yt_1',
          'title': 'Tamil 90s Hits', // Duplicate title
          'source': 'youtube',
          'image': 'https://img.yt/1.jpg',
        },
        {
          'id': 'yt_2',
          'title': 'ARR Melodies Special',
          'source': 'youtube',
          'image': 'https://img.yt/2.jpg',
        },
      ];

      final merged = SearchService.mergePlaylists(primary, secondary);

      expect(merged.length, 3);
      expect(merged[0]['title'], 'Tamil 90s Hits');
      expect(merged[0]['source'], 'saavn'); // First provider retained
      expect(merged[1]['title'], 'Anirudh Party Mix');
      expect(merged[2]['title'], 'ARR Melodies Special');
    });

    test('SearchResults & SearchResultsState contain playlists without being marked empty', () {
      final state = SearchResultsState(
        playlists: [
          {'id': 'p1', 'title': 'Test Playlist', 'source': 'saavn'}
        ],
      );

      expect(state.isEmpty, isFalse);
      expect(state.playlists.length, 1);
      expect(state.playlists.first['title'], 'Test Playlist');

      final searchResults = SearchResults(
        playlists: [
          {'id': 'p2', 'title': 'Another Playlist', 'source': 'youtube'}
        ],
      );
      expect(searchResults.isEmpty, isFalse);
      expect(searchResults.playlists.length, 1);
    });

    test('TrackQualityFilter filters out non-stop hour-long playlist mixes', () {
      final playlistTracks = [
        Song(id: 's1', title: 'Normal Track', artist: 'Artist', coverUrl: '', duration: 240, source: 'youtube'),
        Song(id: 's2', title: '3 Hours Non Stop Jukebox', artist: 'Artist', coverUrl: '', duration: 10800, source: 'youtube'),
        Song(id: 's3', title: 'Tamil Hits 2024 Full Album', artist: 'Artist', coverUrl: '', duration: 7200, source: 'youtube'),
        Song(id: 's4', title: 'Melody Song', artist: 'Artist', coverUrl: '', duration: 310, source: 'youtube'),
      ];

      final filtered = TrackQualityFilter.filterSongs(playlistTracks);

      expect(filtered.length, 2);
      expect(filtered.map((s) => s.id), containsAll(['s1', 's4']));
      expect(filtered.map((s) => s.id), isNot(contains('s2')));
      expect(filtered.map((s) => s.id), isNot(contains('s3')));
    });

    testWidgets('SearchPlaylistsGrid displays playlist tiles and source badges', (WidgetTester tester) async {
      final testPlaylists = [
        {
          'id': 'pl_saavn',
          'title': 'Ilaiyaraaja Evergreens',
          'subtitle': '30 Songs • JioSaavn',
          'image': '',
          'source': 'saavn',
        },
        {
          'id': 'pl_yt',
          'title': 'Anirudh Concert Vibes',
          'subtitle': '25 tracks • YouTube',
          'image': '',
          'source': 'youtube',
        },
        {
          'id': 'pl_mix',
          'title': 'Idhayam Murali (All Songs)',
          'subtitle': '6 Tracks • Movie Playlist',
          'image': '',
          'source': 'auto_album',
        },
      ];

      bool clicked = false;
      Map<String, dynamic>? tappedPlaylist;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchPlaylistsGrid(
              playlists: testPlaylists,
              query: 'Tamil',
              onRecordClick: () {
                clicked = true;
              },
              onPlaylistTap: (pl) {
                tappedPlaylist = pl;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Ilaiyaraaja Evergreens'), findsOneWidget);
      expect(find.text('Anirudh Concert Vibes'), findsOneWidget);
      expect(find.text('Idhayam Murali (All Songs)'), findsOneWidget);

      // Verify badges: 'Saavn', 'YT', 'Mix'
      expect(find.text('Saavn'), findsOneWidget);
      expect(find.text('YT'), findsOneWidget);
      expect(find.text('Mix'), findsOneWidget);

      // Tap on first playlist
      await tester.tap(find.text('Ilaiyaraaja Evergreens'));
      await tester.pump();
      expect(clicked, isTrue);
      expect(tappedPlaylist?['id'], 'pl_saavn');
    });
  });
}
