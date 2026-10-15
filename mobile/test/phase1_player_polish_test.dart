import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/youtube_client.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/equalizer_curve_canvas.dart';
import 'package:paatu_padava_mobile/ui/widgets/swipeable_song_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paatu_phase1_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(SettingsManager.boxName);
    await Hive.openBox(FavoritesManager.boxName);
    await FavoritesManager.init();
    await SettingsManager.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Equalizer Expanded Presets & DSP Hardware Controls Tests', () {
    test('SettingsManager includes all expanded presets (Acoustic, Vocal Booster, Deep, etc.)', () {
      expect(SettingsManager.presets.containsKey('flat'), isTrue);
      expect(SettingsManager.presets.containsKey('bass_boost'), isTrue);
      expect(SettingsManager.presets.containsKey('bass_treble'), isTrue);
      expect(SettingsManager.presets.containsKey('acoustic'), isTrue);
      expect(SettingsManager.presets.containsKey('electronic'), isTrue);
      expect(SettingsManager.presets.containsKey('rock'), isTrue);
      expect(SettingsManager.presets.containsKey('pop'), isTrue);
      expect(SettingsManager.presets.containsKey('classical'), isTrue);
      expect(SettingsManager.presets.containsKey('hip_hop'), isTrue);
      expect(SettingsManager.presets.containsKey('vocal_booster'), isTrue);
      expect(SettingsManager.presets.containsKey('deep'), isTrue);

      // Verify band count for each preset is 5
      for (final preset in SettingsManager.presets.values) {
        expect(preset.length, equals(5));
      }
    });

    test('Selecting preset updates eqPresetNotifier and eqBandsNotifier', () async {
      await SettingsManager.setEqPreset('acoustic');
      expect(SettingsManager.eqPreset, equals('acoustic'));
      expect(SettingsManager.eqBands, equals(SettingsManager.presets['acoustic']));

      await SettingsManager.setEqPreset('vocal_booster');
      expect(SettingsManager.eqPreset, equals('vocal_booster'));
      expect(SettingsManager.eqBands, equals(SettingsManager.presets['vocal_booster']));
    });

    test('Saving, applying, and deleting custom EQ presets persists in Hive', () async {
      final customBands = [4.0, 2.0, 0.0, 2.0, 4.0];
      await SettingsManager.saveCustomEqPreset('MyCustomCurve', customBands);

      expect(SettingsManager.customEqPresets.containsKey('MyCustomCurve'), isTrue);
      expect(SettingsManager.customEqPresets['MyCustomCurve'], equals(customBands));
      expect(SettingsManager.eqPreset, equals('custom_MyCustomCurve'));

      // Re-apply flat, then re-apply custom
      await SettingsManager.setEqPreset('flat');
      expect(SettingsManager.eqPreset, equals('flat'));

      await SettingsManager.applyCustomEqPreset('MyCustomCurve');
      expect(SettingsManager.eqPreset, equals('custom_MyCustomCurve'));
      expect(SettingsManager.eqBands, equals(customBands));

      // Delete custom preset
      await SettingsManager.deleteCustomEqPreset('MyCustomCurve');
      expect(SettingsManager.customEqPresets.containsKey('MyCustomCurve'), isFalse);
      expect(SettingsManager.eqPreset, equals('flat'));
    });

    test('BassBoost and Virtualizer settings clamp between 0.0 and 1.0 and persist', () async {
      await SettingsManager.setBassBoost(0.75);
      expect(SettingsManager.bassBoost, equals(0.75));

      await SettingsManager.setVirtualizer(0.60);
      expect(SettingsManager.virtualizer, equals(0.60));

      // Test clamping
      await SettingsManager.setBassBoost(1.5);
      expect(SettingsManager.bassBoost, equals(1.0));

      await SettingsManager.setVirtualizer(-0.5);
      expect(SettingsManager.virtualizer, equals(0.0));
    });
  });

  group('EqualizerCurveCanvas Widget Tests', () {
    testWidgets('Renders EqualizerCurveCanvas with 5 frequency bands smoothly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EqualizerCurveCanvas(
              bands: [5.0, 2.5, 0.0, 3.0, 5.0],
              height: 100,
            ),
          ),
        ),
      );

      expect(find.byType(EqualizerCurveCanvas), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('Swipe-to-Like & SwipeableSongTile Tests', () {
    testWidgets('SwipeableSongTile renders with DismissDirection.horizontal', (tester) async {
      final testSong = Song(
        id: 'test_song_1',
        title: 'Test Track',
        artist: 'Test Artist',
        album: 'Test Album',
        duration: 200,
        coverUrl: '',
        source: 'saavn',
      );

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

      final dismissibleFinder = find.byType(Dismissible);
      expect(dismissibleFinder, findsOneWidget);
      final dismissible = tester.widget<Dismissible>(dismissibleFinder);
      expect(dismissible.direction, equals(DismissDirection.horizontal));
    });

    test('FavoritesManager toggleFavorite correctly toggles state and persists', () async {
      final song = Song(
        id: 'fav_song_1',
        title: 'Favorited Track',
        artist: 'Artist',
        album: 'Album',
        duration: 180,
        coverUrl: '',
      );

      expect(FavoritesManager.isFavorite(song.id), isFalse);

      final added = await FavoritesManager.toggleFavorite(song);
      expect(added, isTrue);
      expect(FavoritesManager.isFavorite(song.id), isTrue);

      final removed = await FavoritesManager.toggleFavorite(song);
      expect(removed, isFalse);
      expect(FavoritesManager.isFavorite(song.id), isFalse);
    });
  });

  group('YouTubeClient Video Resolution Tests', () {
    test('resolveVideoIdForSong resolves 11-char YouTube song IDs directly', () async {
      final ytSong = Song(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        album: 'Whenever You Need Somebody',
        duration: 213,
        coverUrl: '',
        source: 'youtube',
      );

      final videoId = await YouTubeClient.resolveVideoIdForSong(ytSong);
      expect(videoId, equals('dQw4w9WgXcQ'));
    });

    test('resolveVideoIdForSong extracts ID from embedded YouTube URLs in id', () async {
      final ytUrlSong = Song(
        id: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Track',
        artist: 'Artist',
        album: 'Album',
        duration: 213,
        coverUrl: '',
        source: 'youtube',
      );

      final videoId = await YouTubeClient.resolveVideoIdForSong(ytUrlSong);
      expect(videoId, equals('dQw4w9WgXcQ'));
    });

    test('resolveVideoIdForSong falls back to YouTube version in versions list', () async {
      final saavnSongWithYtVersion = Song(
        id: 'saavn_track_99',
        title: 'Song With Video Version',
        artist: 'Artist',
        album: 'Album',
        duration: 213,
        coverUrl: '',
        source: 'saavn',
        versions: [
          Song(
            id: 'dQw4w9WgXcQ',
            title: 'Song With Video Version',
            artist: 'Artist',
            album: 'Album',
            duration: 213,
            coverUrl: '',
            source: 'youtube',
          ),
        ],
      );

      final videoId = await YouTubeClient.resolveVideoIdForSong(saavnSongWithYtVersion);
      expect(videoId, equals('dQw4w9WgXcQ'));
    });
  });
}
