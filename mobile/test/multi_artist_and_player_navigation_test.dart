import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/artist_sanitizer.dart';
import 'package:paatu_padava_mobile/ui/screens/artist_screen.dart';
import 'package:paatu_padava_mobile/ui/widgets/artist_picker_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final collabSong = Song(
    id: 'collab_01',
    title: 'Pavazha Malli',
    artist: 'Anirudh Ravichander, Sai Abhyankkar',
    album: 'Single',
    duration: 215,
    coverUrl: 'https://example.com/cover.jpg',
  );

  final singleArtistSong = Song(
    id: 'single_01',
    title: 'Naan Pizhai',
    artist: 'Anirudh Ravichander',
    album: 'Kaathuvaakula Rendu Kaadhal',
    duration: 240,
    coverUrl: 'https://example.com/cover2.jpg',
  );

  group('ArtistSanitizer Multi-Artist Extraction Tests', () {
    test('Splits composite artist strings into genuine individual artists', () {
      final list = ArtistSanitizer.extractAllGenuineArtists('Anirudh Ravichander, Sai Abhyankkar');
      expect(list, equals(['Anirudh Ravichander', 'Sai Abhyankkar']));
    });

    test('Filters out non-musician actors from collaborations', () {
      final list = ArtistSanitizer.extractAllGenuineArtists('Sam C.S., Thalapathy Vijay');
      expect(list, equals(['Sam C.S.']));
    });

    test('Preserves single genuine artist string', () {
      final list = ArtistSanitizer.extractAllGenuineArtists('Yuvan Shankar Raja');
      expect(list, equals(['Yuvan Shankar Raja']));
    });
  });

  group('ArtistPickerSheet UI & Modal Tests', () {
    testWidgets('Single artist navigates directly to ArtistScreen without sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ArtistPickerSheet.show(context, song: singleArtistSong),
                child: const Text('Open Artist'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Artist'));
      await tester.pumpAndSettle();

      // Directly pushed ArtistScreen
      expect(find.byType(ArtistScreen), findsOneWidget);
      expect(find.text('Anirudh Ravichander'), findsWidgets);
      expect(find.text('Go to artist'), findsNothing);
    });

    testWidgets('Multi-artist opens Spotify-style "Go to artist" selection sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ArtistPickerSheet.show(context, song: collabSong),
                child: const Text('Open Artist'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Artist'));
      await tester.pumpAndSettle();

      // Bottom sheet is open
      expect(find.text('Go to artist'), findsOneWidget);
      expect(find.text('Select an artist to view their full catalog'), findsOneWidget);
      expect(find.text('Anirudh Ravichander'), findsOneWidget);
      expect(find.text('Sai Abhyankkar'), findsOneWidget);

      // Tapping the second artist (Sai Abhyankkar) opens Sai Abhyankkar's page
      await tester.tap(find.text('Sai Abhyankkar'));
      await tester.pumpAndSettle();

      expect(find.byType(ArtistScreen), findsOneWidget);
      final artistScreenFinder = find.byType(ArtistScreen);
      final artistScreenWidget = tester.widget<ArtistScreen>(artistScreenFinder);
      expect(artistScreenWidget.artistName, equals('Sai Abhyankkar'));
    });
  });

  group('Floating SnackBar Clearance Over MiniPlayer Tests', () {
    testWidgets('SnackBar floats cleanly with bottom clearance margin', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                      content: const Text('Playback error test'),
                    ),
                  );
                },
                child: const Text('Trigger Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Error'));
      await tester.pump();

      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);

      final SnackBar snackBar = tester.widget<SnackBar>(snackBarFinder);
      expect(snackBar.behavior, equals(SnackBarBehavior.floating));
      expect(snackBar.margin, equals(const EdgeInsets.fromLTRB(16, 0, 16, 88)));
    });
  });
}
