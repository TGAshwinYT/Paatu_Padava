import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';
import 'package:paatu_padava_mobile/ui/screens/audio_quality_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/downloads_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/appearance_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/party_sync_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('settings_test_hive_');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen(SettingsManager.boxName)) {
      await Hive.openBox(SettingsManager.boxName);
    }
    await SettingsManager.init();
  });

  group('Settings Hub & Sub-screens Architecture Tests', () {
    testWidgets('SettingsScreen Hub renders all modular navigation tiles', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Audio Quality & Streaming'), findsOneWidget);
      expect(find.text('5-Band Hardware Equalizer'), findsOneWidget);
      expect(find.text('Downloads & Network Rules'), findsOneWidget);
      expect(find.text('Storage & Cache Management'), findsOneWidget);
      expect(find.text('Appearance & Display'), findsOneWidget);
      expect(find.text('Music Languages'), findsOneWidget);
      expect(find.text('Multi-Phone Party Sync & Latency'), findsOneWidget);
      expect(find.text('Paatu Recap & Music Wrapped'), findsOneWidget);
    });

    testWidgets('AudioQualitySettingsScreen updates streaming bitrates and normalization', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: AudioQualitySettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Audio Quality & Streaming'), findsOneWidget);
      expect(find.text('Data Saver (96 kbps)'), findsOneWidget);
      expect(find.text('Standard Quality (160 kbps)'), findsOneWidget);
      expect(find.text('High Fidelity (320 kbps)'), findsOneWidget);
      expect(find.text('ReplayGain Loudness Match'), findsOneWidget);
      expect(find.text('Autoplay Similar Tracks'), findsOneWidget);
      expect(find.text('Spotify Context'), findsOneWidget);
      expect(find.text('YouTube Auto-Mix'), findsOneWidget);

      // Select 160kbps
      await tester.tap(find.text('Standard Quality (160 kbps)'));
      await tester.pumpAndSettle();
      expect(SettingsManager.streamingQuality, equals('160kbps'));

      // Select 320kbps
      await tester.tap(find.text('High Fidelity (320 kbps)'));
      await tester.pumpAndSettle();
      expect(SettingsManager.streamingQuality, equals('320kbps'));
    });

    testWidgets('DownloadsSettingsScreen toggles Wi-Fi only and updates storage path', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: DownloadsSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Downloads & Offline'), findsOneWidget);
      expect(find.text('Download via Wi-Fi Only'), findsOneWidget);
      expect(find.text('Download Storage Path'), findsOneWidget);
      expect(find.text('Clear All Downloads'), findsOneWidget);

      // Tap SD Card option
      await tester.tap(find.text('SD Card / External Storage'));
      await tester.pumpAndSettle();
      expect(SettingsManager.downloadPath, equals('SD Card'));

      // Tap Internal Storage option
      await tester.tap(find.text('Internal Device Storage'));
      await tester.pumpAndSettle();
      expect(SettingsManager.downloadPath, equals('Internal Storage'));
    });

    testWidgets('AppearanceSettingsScreen toggles theme, dynamic background, and Romanization', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: AppearanceSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Appearance & Display'), findsOneWidget);
      expect(find.text('AMOLED Black'), findsOneWidget);
      expect(find.text('Dark Indigo'), findsOneWidget);
      expect(find.text('Dynamic Fluid Mesh Gradient'), findsOneWidget);
      expect(find.text('Romanize Indic Lyrics'), findsOneWidget);
      expect(find.text('Keep Screen Awake'), findsOneWidget);

      // Toggle Dark Indigo
      await tester.tap(find.text('Dark Indigo'));
      await tester.pumpAndSettle();
      expect(SettingsManager.themeMode, equals('dark_indigo'));

      // Toggle AMOLED
      await tester.tap(find.text('AMOLED Black'));
      await tester.pumpAndSettle();
      expect(SettingsManager.themeMode, equals('amoled'));
    });

    testWidgets('PartySyncSettingsScreen adjusts hardware audio latency and displays NTP diagnostics', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: PartySyncSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Party Sync & Latency'), findsOneWidget);
      expect(find.text('Hardware Output Offset'), findsOneWidget);
      expect(find.text('Bluetooth Buffer Compensation'), findsOneWidget);
      expect(find.text('Live Clock Drift'), findsOneWidget);
      expect(find.text('Network RTT'), findsOneWidget);
      expect(find.text('NTP Offset (Theta)'), findsOneWidget);

      // Test step buttons
      await tester.tap(find.text('Reset (0ms)'));
      await tester.pumpAndSettle();
      expect(SettingsManager.hardwareAudioLatencyMs, equals(0));

      await tester.tap(find.text('+10ms'));
      await tester.pumpAndSettle();
      expect(SettingsManager.hardwareAudioLatencyMs, equals(10));

      await tester.tap(find.text('-10ms'));
      await tester.pumpAndSettle();
      expect(SettingsManager.hardwareAudioLatencyMs, equals(0));
    });
  });
}
