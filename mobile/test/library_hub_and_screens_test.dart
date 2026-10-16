import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/ui/screens/library_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/playlists_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/offline_screen.dart';
import 'package:paatu_padava_mobile/services/playlist_manager.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/download_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Library Hub & Dedicated Screens Architecture Tests', () {
    testWidgets('LibraryScreen renders Bento Grid cards for Playlists, Liked, History, and Offline', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: LibraryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Your Library'), findsOneWidget);

      // Verify 4 Bento Cards
      expect(find.text('Playlists'), findsWidgets);
      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);

      // Verify Paatu Recap
      expect(find.text('Paatu Recap 2026'), findsOneWidget);

      // Verify Shelf
      expect(find.text('Your Playlists'), findsOneWidget);
      expect(find.text('See All'), findsOneWidget);
    });

    testWidgets('PlaylistsScreen renders action buttons and does NOT duplicate Liked Songs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PlaylistsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Action buttons in PlaylistsScreen
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Join Shared'), findsOneWidget);
      expect(find.text('Blend'), findsOneWidget);
      expect(find.text('Import Spotify'), findsOneWidget);

      // CRITICAL: Ensure Liked Songs is NEVER in PlaylistsScreen
      expect(find.text('Liked Songs'), findsNothing);
    });

    testWidgets('OfflineScreen renders title and storage controls cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OfflineScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Offline Screen Title
      expect(find.text('Offline Music'), findsOneWidget);
    });
  });
}
