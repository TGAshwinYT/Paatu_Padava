import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/ui/widgets/search/search_active_typing_suggestions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchTypeaheadBundle & Typeahead Cache', () {
    test('SearchTypeaheadBundle correctly reports isEmpty and holds entities', () {
      const emptyBundle = SearchTypeaheadBundle(
        completions: [],
        songs: [],
        albums: [],
      );
      expect(emptyBundle.isEmpty, isTrue);

      final dummySong = Song(
        id: 's1',
        title: 'Thirudi',
        artist: 'Dhanush',
        album: 'Kiss',
        duration: 210,
        coverUrl: 'https://example.com/cover.jpg',
        source: 'saavn',
      );

      final populatedBundle = SearchTypeaheadBundle(
        completions: ['thirudi', 'thirudi song'],
        songs: [dummySong],
        albums: [
          {'id': 'kiss_album', 'title': 'Kiss', 'artist': 'Dhanush', 'type': 'Album'}
        ],
      );
      expect(populatedBundle.isEmpty, isFalse);
      expect(populatedBundle.completions.length, equals(2));
      expect(populatedBundle.songs.first.title, equals('Thirudi'));
      expect(populatedBundle.albums.first['title'], equals('Kiss'));
    });
  });

  group('Playlist Quality Filtering (Exclude Empty / Broken YouTube Playlists)', () {
    test('filterPlaylistsByRelevanceAndLanguage drops playlists with < 2 tracks', () {
      final playlists = [
        {
          'id': 'pl_empty',
          'title': 'Empty Tamil Hits',
          'song_count': 0,
          'source': 'youtube',
        },
        {
          'id': 'pl_single',
          'title': 'Single Track Playlist',
          'song_count': '1',
          'source': 'youtube',
        },
        {
          'id': 'pl_valid',
          'title': 'Tamil Hits 2024',
          'song_count': '25',
          'source': 'youtube',
        },
        {
          'id': 'pl_saavn_valid',
          'title': 'Tamil Hits Collection',
          'song_count': '50',
          'source': 'saavn',
        },
      ];

      final filtered = SearchService.filterPlaylistsByRelevanceAndLanguage(
        playlists,
        query: 'Tamil Hits',
      );

      // Verify empty and 1-track playlists are dropped
      expect(filtered.any((p) => p['id'] == 'pl_empty'), isFalse);
      expect(filtered.any((p) => p['id'] == 'pl_single'), isFalse);

      // Verify multi-track playlists are preserved
      expect(filtered.any((p) => p['id'] == 'pl_valid'), isTrue);
      expect(filtered.any((p) => p['id'] == 'pl_saavn_valid'), isTrue);
    });
  });

  group('SearchActiveTypingSuggestions UI Verification', () {
    testWidgets('renders completions, song matches, album matches, and NO artists', (tester) async {
      final dummySong = Song(
        id: 's_test',
        title: 'Thirudi Thirudi',
        artist: 'Yuvan Shankar Raja',
        album: 'Kiss',
        duration: 250,
        coverUrl: 'https://example.com/cover.jpg',
        source: 'saavn',
      );

      final dummyAlbums = [
        {
          'id': 'alb_kiss',
          'title': 'Kiss',
          'artist': 'Yuvan Shankar Raja',
          'image': 'https://example.com/kiss.jpg',
          'type': 'Album',
        }
      ];

      Song? playedSong;
      Map<String, dynamic>? selectedAlbum;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchActiveTypingSuggestions(
              query: 'thiru',
              queryCompletions: const ['thirudi', 'thiruda thirudi'],
              localSongMatches: [dummySong],
              matchingAlbums: dummyAlbums,
              onSelectQuery: (q) {},
              onPlaySong: (s) => playedSong = s,
              onSelectAlbum: (a) => selectedAlbum = a,
              onAppendQuery: (q) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Text completions rendered
      expect(find.text('thirudi'), findsOneWidget);
      expect(find.text('thiruda thirudi'), findsOneWidget);

      // 2. Matching Song rendered with subtitle "Song • $cleanArtist"
      expect(find.text('Thirudi Thirudi'), findsOneWidget);
      expect(find.textContaining('Song •'), findsOneWidget);

      // 3. Matching Album rendered with subtitle "Album • $artist"
      expect(find.text('Kiss'), findsOneWidget);
      expect(find.textContaining('Album •'), findsOneWidget);

      // 4. Verify tapping an album fires onSelectAlbum
      await tester.tap(find.text('Kiss'));
      expect(selectedAlbum, isNotNull);
      expect(selectedAlbum!['id'], equals('alb_kiss'));

      // 5. Verify NO "Artist" entities or section is rendered
      expect(find.textContaining('Artist •'), findsNothing);
    });
  });
}
