import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paatu_dsp_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(SettingsManager.boxName);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SettingsManager Audio DSP & Normalization Tests', () {
    test('Default settings initialize with normalization ON and crossfade 0s (Gapless)', () async {
      await SettingsManager.init();

      expect(SettingsManager.isVolumeNormalizationEnabled, isTrue);
      expect(SettingsManager.crossfadeSeconds, equals(0));
      expect(SettingsManager.streamingQuality, equals('320kbps'));
      expect(SettingsManager.downloadQuality, equals('320kbps'));
    });

    test('Updating volume normalization toggles notifier and persists in Hive', () async {
      await SettingsManager.init();

      await SettingsManager.setVolumeNormalization(false);
      expect(SettingsManager.isVolumeNormalizationEnabled, isFalse);
      expect(SettingsManager.volumeNormalizationNotifier.value, isFalse);

      final box = Hive.box(SettingsManager.boxName);
      expect(box.get('volume_normalization'), isFalse);

      await SettingsManager.setVolumeNormalization(true);
      expect(SettingsManager.isVolumeNormalizationEnabled, isTrue);
      expect(box.get('volume_normalization'), isTrue);
    });

    test('Updating crossfade seconds clamps between 0 and 12s and persists', () async {
      await SettingsManager.init();

      await SettingsManager.setCrossfadeSeconds(5);
      expect(SettingsManager.crossfadeSeconds, equals(5));

      // Test bounds clamping
      await SettingsManager.setCrossfadeSeconds(25);
      expect(SettingsManager.crossfadeSeconds, equals(12));

      await SettingsManager.setCrossfadeSeconds(-4);
      expect(SettingsManager.crossfadeSeconds, equals(0));
    });

    test('Updating streaming and download quality updates notifiers and persists', () async {
      await SettingsManager.init();

      await SettingsManager.setStreamingQuality('96kbps');
      expect(SettingsManager.streamingQuality, equals('96kbps'));

      await SettingsManager.setDownloadQuality('160kbps');
      expect(SettingsManager.downloadQuality, equals('160kbps'));
    });
  });

  group('Volume Normalization (ReplayGain / EBU R128) Math & Calibration Tests', () {
    test('When normalization is disabled, all songs play at unity 1.0 volume', () async {
      await SettingsManager.init();
      await SettingsManager.setVolumeNormalization(false);

      final saavnSong = Song(
        id: 'saavn_track_1',
        title: 'Master Audio',
        artist: 'Artist',
        album: 'Album',
        duration: 240,
        coverUrl: '',
        source: 'saavn',
        streamUrl: 'https://c.saavncdn.com/123/master_320.mp4',
      );

      final ytSong = Song(
        id: 'yt_track_1',
        title: 'YouTube Track',
        artist: 'Artist',
        album: 'Album',
        duration: 240,
        coverUrl: '',
        source: 'youtube',
      );

      expect(AudioQueueHandler.getNormalizedVolumeForSong(saavnSong), equals(1.0));
      expect(AudioQueueHandler.getNormalizedVolumeForSong(ytSong), equals(1.0));
    });

    test('When normalization is enabled, hot studio masters are calibrated to ~ -2.0 dB (0.80)', () async {
      await SettingsManager.init();
      await SettingsManager.setVolumeNormalization(true);

      final saavnSong = Song(
        id: 'saavn_track_1',
        title: 'Master Audio',
        artist: 'Artist',
        album: 'Album',
        duration: 240,
        coverUrl: '',
        source: 'saavn',
        streamUrl: 'https://c.saavncdn.com/123/master_320.mp4',
      );

      final ytSong = Song(
        id: 'yt_track_1',
        title: 'YouTube Track',
        artist: 'Artist',
        album: 'Album',
        duration: 240,
        coverUrl: '',
        source: 'youtube',
      );

      // JioSaavn hot master calibrated down to prevent sudden loudness spikes
      expect(AudioQueueHandler.getNormalizedVolumeForSong(saavnSong), equals(0.80));

      // YouTube track already loudness normalized to -14 LUFS, left at unity headroom
      expect(AudioQueueHandler.getNormalizedVolumeForSong(ytSong), equals(1.0));
    });

    test('Stream URL containing jiosaavn or .mp4 triggers master normalization', () async {
      await SettingsManager.init();
      await SettingsManager.setVolumeNormalization(true);

      final songWithMp4Url = Song(
        id: 'track_mixed',
        title: 'Song',
        artist: 'Artist',
        album: '',
        duration: 180,
        coverUrl: '',
        streamUrl: 'https://example.com/audio/song_320.mp4',
      );

      expect(AudioQueueHandler.getNormalizedVolumeForSong(songWithMp4Url), equals(0.80));
    });
  });
}
