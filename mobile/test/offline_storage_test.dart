import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/cache_manager.dart';
import 'package:paatu_padava_mobile/services/download_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageBreakdown & Format Math Tests', () {
    test('StorageBreakdown.formatBytes converts bytes to human-readable strings', () {
      expect(StorageBreakdown.formatBytes(0), equals('0.0 MB'));
      expect(StorageBreakdown.formatBytes(-50), equals('0.0 MB'));
      expect(StorageBreakdown.formatBytes(1024 * 1024), equals('1.0 MB'));
      expect(StorageBreakdown.formatBytes(45 * 1024 * 1024), equals('45.0 MB'));
      expect(StorageBreakdown.formatBytes(1024 * 1024 * 1024), equals('1.00 GB'));
      expect(StorageBreakdown.formatBytes((2.5 * 1024 * 1024 * 1024).toInt()), equals('2.50 GB'));
    });

    test('StorageBreakdown getters format individual partitions accurately', () {
      const breakdown = StorageBreakdown(
        offlineAudioBytes: 150 * 1024 * 1024,
        offlineSongCount: 15,
        tempCacheBytes: 30 * 1024 * 1024,
        imageCacheBytes: 12 * 1024 * 1024,
        hiveDatabaseBytes: 2 * 1024 * 1024,
        totalAppBytes: 194 * 1024 * 1024,
      );

      expect(breakdown.offlineAudioFormatted, equals('150.0 MB'));
      expect(breakdown.tempCacheFormatted, equals('30.0 MB'));
      expect(breakdown.imageCacheFormatted, equals('12.0 MB'));
      expect(breakdown.hiveDatabaseFormatted, equals('2.0 MB'));
      expect(breakdown.totalAppFormatted, equals('194.0 MB'));
      expect(breakdown.offlineSongCount, equals(15));
    });
  });

  group('DownloadManager Batch & Concurrency Queue Tests', () {
    late Directory tempDir;
    late File mockAudioFile1;
    late File mockAudioFile2;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('paatu_download_test_');
      Hive.init(tempDir.path);
      await Hive.openBox(DownloadManager.boxName);

      // Create dummy audio files on disk
      final audioDir = Directory('${tempDir.path}/offline_audio')..createSync(recursive: true);
      mockAudioFile1 = File('${audioDir.path}/song_1.mp3')..writeAsBytesSync(List.filled(1024 * 1024 * 3, 0)); // 3 MB
      mockAudioFile2 = File('${audioDir.path}/song_2.mp3')..writeAsBytesSync(List.filled(1024 * 1024 * 5, 0)); // 5 MB
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      DownloadManager.activeDownloads.value = {};
    });

    test('areAllDownloaded returns true only when every song is in offline storage and file exists', () async {
      final song1 = Song(
        id: 's_01',
        title: 'Song 1',
        artist: 'Artist',
        album: '',
        duration: 200,
        coverUrl: '',
        localFilePath: mockAudioFile1.path,
        isDownloaded: true,
      );
      final song2 = Song(
        id: 's_02',
        title: 'Song 2',
        artist: 'Artist',
        album: '',
        duration: 180,
        coverUrl: '',
        localFilePath: mockAudioFile2.path,
        isDownloaded: true,
      );
      final song3 = Song(
        id: 's_03',
        title: 'Song 3',
        artist: 'Artist',
        album: '',
        duration: 210,
        coverUrl: '',
      );

      final box = Hive.box(DownloadManager.boxName);
      await box.put('s_01', song1.toMap());

      expect(DownloadManager.isDownloaded('s_01'), isTrue);
      expect(DownloadManager.isDownloaded('s_02'), isFalse);

      // List with song1 and song2: song2 not yet downloaded -> false
      expect(DownloadManager.areAllDownloaded([song1, song2]), isFalse);
      expect(DownloadManager.getDownloadedCount([song1, song2, song3]), equals(1));

      // Now save song2
      await box.put('s_02', song2.toMap());
      expect(DownloadManager.areAllDownloaded([song1, song2]), isTrue);
      expect(DownloadManager.getDownloadedCount([song1, song2, song3]), equals(2));
    });

    test('getBatchDownloadProgress accounts for downloaded and active in-flight progress', () async {
      final song1 = Song(
        id: 'p_01',
        title: 'Track 1',
        artist: 'Artist',
        album: '',
        duration: 180,
        coverUrl: '',
        localFilePath: mockAudioFile1.path,
      );
      final song2 = Song(id: 'p_02', title: 'Track 2', artist: 'Artist', album: '', duration: 180, coverUrl: '');
      final song3 = Song(id: 'p_03', title: 'Track 3', artist: 'Artist', album: '', duration: 180, coverUrl: '');
      final song4 = Song(id: 'p_04', title: 'Track 4', artist: 'Artist', album: '', duration: 180, coverUrl: '');

      final songs = [song1, song2, song3, song4];

      // Initially 0.0
      expect(DownloadManager.getBatchDownloadProgress(songs), equals(0.0));

      // Mark song1 as downloaded (1 / 4 = 0.25)
      final box = Hive.box(DownloadManager.boxName);
      await box.put('p_01', song1.toMap());
      expect(DownloadManager.getBatchDownloadProgress(songs), equals(0.25));

      // Set song2 actively downloading at 50% (1.5 / 4 = 0.375)
      DownloadManager.activeDownloads.value = {'p_02': 0.5};
      expect(DownloadManager.getBatchDownloadProgress(songs), equals(0.375));

      // Both downloaded (song1 and song2), song3 at 100%, song4 at 0% (3.0 / 4 = 0.75)
      await box.put('p_02', song2.toMap());
      DownloadManager.activeDownloads.value = {'p_03': 1.0};
      expect(DownloadManager.getBatchDownloadProgress(songs), equals(0.75));
    });

    test('cancelDownload removes item from active downloads', () {
      DownloadManager.activeDownloads.value = {'test_01': 0.45, 'test_02': 0.80};
      expect(DownloadManager.activeDownloads.value.containsKey('test_01'), isTrue);

      DownloadManager.cancelDownload('test_01');
      expect(DownloadManager.activeDownloads.value.containsKey('test_01'), isFalse);
      expect(DownloadManager.activeDownloads.value.containsKey('test_02'), isTrue);
    });

    test('deleteAllDownloads clears Hive box and downloadedSongsNotifier', () async {
      final song = Song(
        id: 'del_01',
        title: 'Delete Me',
        artist: 'Artist',
        album: '',
        duration: 180,
        coverUrl: '',
        localFilePath: mockAudioFile1.path,
      );

      final box = Hive.box(DownloadManager.boxName);
      await box.put('del_01', song.toMap());
      DownloadManager.downloadedSongsNotifier.value = DownloadManager.getDownloadedSongs();

      expect(DownloadManager.getDownloadedSongs().length, equals(1));

      await DownloadManager.deleteAllDownloads();

      expect(DownloadManager.getDownloadedSongs().isEmpty, isTrue);
      expect(DownloadManager.downloadedSongsNotifier.value.isEmpty, isTrue);
      expect(box.isEmpty, isTrue);
    });
  });
}
