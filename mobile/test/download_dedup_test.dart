import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/models/user_playlist.dart';
import 'package:paatu_padava_mobile/services/download_dedup_helper.dart';
import 'package:paatu_padava_mobile/services/download_manager.dart';

Song _makeSong({
  required String id,
  required String title,
  required String artist,
  int duration = 210,
  String? localFilePath,
  int? downloadedAt,
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    album: 'Test Album',
    coverUrl: '',
    duration: duration,
    localFilePath: localFilePath,
    isDownloaded: localFilePath != null,
    downloadedAt: downloadedAt,
  );
}

void main() {
  group('DownloadDedupHelper', () {
    test('findMatch matches re-imported song with different ID and movie tag', () {
      final downloaded = [
        _makeSong(
          id: 'saavn_123',
          title: 'Arabic Kuthu (From "Beast")',
          artist: 'Anirudh Ravichander, Jonita Gandhi',
          duration: 280,
          localFilePath: '/tmp/saavn_123.m4a',
        ),
      ];

      final match = DownloadDedupHelper.findMatch(
        downloadedSongs: downloaded,
        title: 'Arabic Kuthu',
        artist: 'Anirudh Ravichander',
        durationSeconds: 279,
      );

      expect(match, isNotNull);
      expect(match!.id, 'saavn_123');
    });

    test('findMatch rejects songs with different artist or >15s duration difference', () {
      final downloaded = [
        _makeSong(
          id: 'saavn_123',
          title: 'Why This Kolaveri Di',
          artist: 'Dhanush, Anirudh Ravichander',
          duration: 260,
        ),
      ];

      expect(
        DownloadDedupHelper.findMatch(
          downloadedSongs: downloaded,
          title: 'Why This Kolaveri Di',
          artist: 'Completely Different Artist',
          durationSeconds: 260,
        ),
        isNull,
      );

      expect(
        DownloadDedupHelper.findMatch(
          downloadedSongs: downloaded,
          title: 'Why This Kolaveri Di',
          artist: 'Dhanush',
          durationSeconds: 180,
        ),
        isNull,
      );
    });

    test('findDuplicateGroups clusters same-song variants across providers', () {
      final songs = [
        _makeSong(
          id: 'yt_999',
          title: 'Naa Ready',
          artist: 'Anirudh Ravichander, Vijay',
          duration: 248,
          downloadedAt: 2000,
        ),
        _makeSong(
          id: 'saavn_111',
          title: 'Naa Ready (From "Leo")',
          artist: 'Vijay, Anirudh Ravichander',
          duration: 249,
          downloadedAt: 1000,
        ),
        _makeSong(
          id: 'saavn_222',
          title: 'Hukum',
          artist: 'Anirudh Ravichander',
          duration: 205,
          downloadedAt: 1500,
        ),
      ];

      final groups = DownloadDedupHelper.findDuplicateGroups(songs);
      expect(groups.length, 1);
      expect(groups.first.map((s) => s.id).toList(), ['yt_999', 'saavn_111']);
    });

    test('findOrphanedPlaylistDownloads protects songs used in other playlists or favorites', () {
      final dlShared = _makeSong(
        id: 'saavn_shared',
        title: 'Kaavaalaa',
        artist: 'Anirudh Ravichander, Shilpa Rao',
        duration: 190,
      );
      final dlFav = _makeSong(
        id: 'saavn_fav',
        title: 'Hukum',
        artist: 'Anirudh Ravichander',
        duration: 205,
      );
      final dlOrphan = _makeSong(
        id: 'saavn_orphan',
        title: 'Only In Deleted Playlist',
        artist: 'Some Artist',
        duration: 200,
      );

      final deletedPl = UserPlaylist(
        id: 'pl_deleted',
        title: 'Old Playlist',
        createdAt: 1,
        tracks: [
          _makeSong(
            id: 'yt_shared_reimport',
            title: 'Kaavaalaa (From "Jailer")',
            artist: 'Shilpa Rao',
            duration: 191,
          ),
          dlFav,
          dlOrphan,
        ],
      );

      final otherPl = UserPlaylist(
        id: 'pl_other',
        title: 'Keep Playlist',
        createdAt: 2,
        tracks: [dlShared],
      );

      final orphaned = DownloadDedupHelper.findOrphanedPlaylistDownloads(
        playlist: deletedPl,
        allPlaylists: [deletedPl, otherPl],
        favoriteSongs: [dlFav],
        downloadedSongs: [dlShared, dlFav, dlOrphan],
      );

      expect(orphaned.map((s) => s.id).toList(), ['saavn_orphan']);
    });
  });

  group('DownloadManager deduplication with Hive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pp_dedup_test_');
      Hive.init(tempDir.path);
      final box = await Hive.openBox(DownloadManager.boxName);
      await box.clear();
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('isSongDownloaded and deduplicateExistingDownloads recognize and clean duplicates', () async {
      final file1 = File('${tempDir.path}/saavn_1.m4a')..writeAsBytesSync([1, 2, 3, 4]);
      final file2 = File('${tempDir.path}/yt_2.m4a')..writeAsBytesSync([1, 2, 3, 4]);

      final box = Hive.box(DownloadManager.boxName);
      await box.put(
        'saavn_1',
        _makeSong(
          id: 'saavn_1',
          title: 'Vathi Coming (From "Master")',
          artist: 'Anirudh Ravichander, Gana Balachandar',
          duration: 230,
          localFilePath: file1.path,
          downloadedAt: 1000,
        ).toMap(),
      );
      await box.put(
        'yt_2',
        _makeSong(
          id: 'yt_2',
          title: 'Vathi Coming',
          artist: 'Anirudh Ravichander',
          duration: 231,
          localFilePath: file2.path,
          downloadedAt: 2000,
        ).toMap(),
      );

      final reimported = _makeSong(
        id: 'yt_new_import_id',
        title: 'Vathi Coming',
        artist: 'Anirudh Ravichander',
        duration: 230,
      );

      expect(DownloadManager.isSongDownloaded(reimported), isTrue);
      expect(DownloadManager.areAllDownloaded([reimported]), isTrue);
      expect(DownloadManager.getDownloadedCount([reimported]), 1);

      final removed = await DownloadManager.deduplicateExistingDownloads();
      expect(removed, 1);
      expect(DownloadManager.getDownloadedSongs().length, 1);
      expect(DownloadManager.getDownloadedSongs().first.id, 'yt_2');
      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isTrue);
    });
  });
}
