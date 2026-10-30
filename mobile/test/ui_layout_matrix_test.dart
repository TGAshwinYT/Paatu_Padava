// UI LAYOUT MATRIX
//
// Renders every registered screen on 4 device sizes x 2 text scales and FAILS
// if Flutter reports a layout problem (RenderFlex overflow, unbounded height,
// etc). This is the automated version of "run the app and look for the yellow
// and black stripes".
//
// HOW TO ADD A NEW SCREEN
//   1. Add a ScreenCase to `registeredScreens` below.
//   2. If the screen needs fixtures/Hive/plugins that you can't set up yet, add
//      its file name to `exemptScreenFiles` WITH a reason, and open a TODO.
//   The guard test at the bottom fails if you do neither.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';
import 'package:paatu_padava_mobile/ui/screens/appearance_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/audio_quality_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/downloads_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/history_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/home_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/library_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/liked_songs_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/offline_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/party_sync_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/playlists_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/storage_settings_screen.dart';

import 'helpers/layout_harness.dart';

class ScreenCase {
  final String name;
  final String file; // file name inside lib/ui/screens/
  final Widget Function() build;
  const ScreenCase(this.name, this.file, this.build);
}

final List<ScreenCase> registeredScreens = [
  ScreenCase('LibraryScreen', 'library_screen.dart', () => const LibraryScreen()),
  ScreenCase('PlaylistsScreen', 'playlists_screen.dart', () => const PlaylistsScreen()),
  ScreenCase('OfflineScreen', 'offline_screen.dart', () => const OfflineScreen()),
  ScreenCase('HistoryScreen', 'history_screen.dart', () => const HistoryScreen()),
  ScreenCase('LikedSongsScreen', 'liked_songs_screen.dart', () => const LikedSongsScreen()),
  ScreenCase('SettingsScreen', 'settings_screen.dart', () => const SettingsScreen()),
  ScreenCase('AudioQualitySettingsScreen', 'audio_quality_settings_screen.dart',
      () => const AudioQualitySettingsScreen()),
  ScreenCase('DownloadsSettingsScreen', 'downloads_settings_screen.dart',
      () => const DownloadsSettingsScreen()),
  ScreenCase('AppearanceSettingsScreen', 'appearance_settings_screen.dart',
      () => const AppearanceSettingsScreen()),
  ScreenCase('PartySyncSettingsScreen', 'party_sync_settings_screen.dart',
      () => const PartySyncSettingsScreen()),
  ScreenCase('HomeSettingsScreen', 'home_settings_screen.dart', () => const HomeSettingsScreen()),
  ScreenCase('StorageSettingsScreen', 'storage_settings_screen.dart',
      () => const StorageSettingsScreen()),
];

/// Screens that exist today but are NOT yet covered. Each needs fixtures
/// (a Song/Album/Artist argument, a live audio handler, platform plugins...).
/// Burn this list down over time; never add to it without a reason.
const Map<String, String> exemptScreenFiles = {
  'main_navigation.dart': 'needs AudioService + Supabase; covered by integration_test/app_smoke_test.dart',
  'home_screen.dart': 'needs home feed provider fixtures',
  'search_screen.dart': 'needs search service fixtures',
  'full_player_screen.dart': 'needs a playing audio handler; TODO: fake PaatuAudioHandler',
  'lyrics_screen.dart': 'needs lyrics client + player state',
  'album_screen.dart': 'needs album argument fixture',
  'artist_screen.dart': 'needs artist argument fixture',
  'playlist_screen.dart': 'needs playlist argument fixture',
  'remote_playlist_screen.dart': 'needs remote playlist argument fixture and mock network client',
  'equalizer_settings_screen.dart': 'uses native equalizer platform channel',
  'listening_recap_screen.dart': 'needs recap data fixture',
  'listening_session_screen.dart': 'needs session fixture',
  'onboarding_screen.dart': 'needs auth/settings flow',
  'onboarding_artists_screen.dart': 'needs artist list fixture',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('layout_matrix_hive_');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen(SettingsManager.boxName)) {
      await Hive.openBox(SettingsManager.boxName);
    }
    await SettingsManager.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  for (final screen in registeredScreens) {
    group('Layout: ${screen.name}', () {
      for (final device in kDevices) {
        for (final scale in kTextScales) {
          testWidgets('$device @ text x$scale has no layout errors', (tester) async {
            final report = await pumpAndCollectLayoutErrors(
              tester,
              screen.build(),
              device: device,
              textScale: scale,
            );

            // Sanity: something actually rendered (guards against a screen that
            // threw in build and silently showed nothing).
            expect(find.byType(Scaffold), findsWidgets,
                reason: '${screen.name} did not render a Scaffold.');

            if (report.otherErrors.isNotEmpty) {
              // Not a layout failure, but worth seeing in the log.
              // ignore: avoid_print
              print('[${screen.name}] non-layout errors: ${report.otherErrors.toSet()}');
            }

            expect(
              report.layoutErrors,
              isEmpty,
              reason: '${screen.name} on $device at text x$scale:\n'
                  '${report.layoutErrors.toSet().join('\n')}',
            );
          });
        }
      }
    });
  }

  group('Guard: every screen file is covered or explicitly exempt', () {
    test('no un-tracked screens in lib/ui/screens', () {
      final dir = Directory('lib/ui/screens');
      expect(dir.existsSync(), isTrue,
          reason: 'Run `flutter test` from the mobile/ directory.');

      final files = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('_screen.dart'))
          .toSet();

      final covered = registeredScreens.map((s) => s.file).toSet();
      final exempt = exemptScreenFiles.keys.toSet();
      final untracked = files.difference(covered).difference(exempt);

      expect(
        untracked,
        isEmpty,
        reason: 'New screen file(s) with no layout test: $untracked\n'
            'Add a ScreenCase in test/ui_layout_matrix_test.dart '
            '(or add to exemptScreenFiles with a reason).',
      );
    });
  });
}
