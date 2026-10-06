import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/ui/widgets/fluid_mesh_gradient.dart';
import 'package:paatu_padava_mobile/ui/widgets/swipeable_song_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSong = Song(
    id: 'visual_01',
    title: 'Aalaporaan Thamizhan',
    artist: 'A.R. Rahman, Kailash Kher',
    album: 'Mersal',
    duration: 348,
    coverUrl: 'https://example.com/mersal.jpg',
  );

  group('FluidMeshGradient Widget Tests', () {
    testWidgets('FluidMeshGradient renders child within ambient container', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FluidMeshGradient(
              imageUrl: testSong.coverUrl,
              blurSigma: 60.0,
              opacity: 0.5,
              animate: false,
              child: const Center(
                child: Text('Player Overlay', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Player Overlay'), findsOneWidget);
      expect(find.byType(FluidMeshGradient), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('SwipeableSongTile Gesture & Direction Tests', () {
    testWidgets('SwipeableSongTile renders title, artist, and index correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableSongTile(
              song: testSong,
              queue: [testSong],
              index: 0,
            ),
          ),
        ),
      );

      expect(find.text('Aalaporaan Thamizhan'), findsOneWidget);
      expect(find.text('A.R. Rahman, Kailash Kher'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('DismissDirection is startToEnd when onRemove is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableSongTile(
              song: testSong,
              queue: [testSong],
            ),
          ),
        ),
      );

      final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
      expect(dismissible.direction, equals(DismissDirection.startToEnd));
    });

    testWidgets('DismissDirection is horizontal when onRemove is provided', (tester) async {
      bool removeCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableSongTile(
              song: testSong,
              queue: [testSong],
              onRemove: () => removeCalled = true,
              removeTooltip: 'Delete Track',
            ),
          ),
        ),
      );

      final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
      expect(dismissible.direction, equals(DismissDirection.horizontal));
      expect(removeCalled, isFalse);
    });

    testWidgets('SwipeableSongTile popup menu presents Add to Queue and Play Next options', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableSongTile(
              song: testSong,
              queue: [testSong],
            ),
          ),
        ),
      );

      final popupBtn = find.byType(PopupMenuButton<String>);
      expect(popupBtn, findsOneWidget);
      await tester.tap(popupBtn);
      await tester.pumpAndSettle();

      expect(find.text('Play Next'), findsOneWidget);
      expect(find.text('Add to Queue'), findsOneWidget);
      expect(find.text('Start Song Radio'), findsOneWidget);
      expect(find.text('Add to Playlist'), findsOneWidget);
    });
  });
}
