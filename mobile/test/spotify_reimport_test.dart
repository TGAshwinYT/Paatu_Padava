import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/spotify_import_links.dart';
import 'package:paatu_padava_mobile/services/spotify_import_service.dart';
import 'package:paatu_padava_mobile/services/spotify_track_key.dart';

SpotifyTrackItem sp(String title, String artist) =>
    SpotifyTrackItem(title: title, artist: artist, durationSeconds: 200);

Song song(String id, String title, String artist) =>
    Song(id: id, title: title, artist: artist, album: '', coverUrl: '', duration: 200);

void main() {
  group('SpotifyTrackKey', () {
    test('same song across Spotify / Saavn / YouTube naming is recognised', () {
      expect(
        SpotifyTrackKey.sameTrack(
          titleA: 'Vaama Vaama',
          artistsA: 'Thaman S, Dhanush, Adhitya',
          titleB: 'Vaama Vaama',
          artistsB: 'Dhanush, Thaman S',
        ),
        isTrue,
      );
    });

    test('different artist with the same title is NOT treated as a duplicate', () {
      expect(
        SpotifyTrackKey.sameTrack(titleA: 'Kadhal', artistsA: 'Anirudh', titleB: 'Kadhal', artistsB: 'Sid Sriram'),
        isFalse,
      );
    });

    test('Tamil script titles are compared correctly', () {
      expect(
        SpotifyTrackKey.sameTrack(titleA: 'இதயாயா', artistsA: 'தமன்', titleB: 'இதயாயா!', artistsB: 'தமன்'),
        isTrue,
      );
    });

    test('keyFor is stable for the same Spotify item', () {
      expect(SpotifyTrackKey.keyFor('Idhayaa', 'Thaman S, Vishal Mishra'),
          SpotifyTrackKey.keyFor('Idhayaa', 'Thaman S, Vishal Mishra'));
    });
  });

  group('SpotifyImportService re-import', () {
    test('tracks already in the playlist are matched against text, not ids', () {
      final inList = [song('yt123', 'Vaama Vaama (From "Idhayam Murali")', 'Thaman S, Dhanush')];
      expect(SpotifyImportService.isTrackInSongs(sp('Vaama Vaama', 'Thaman S'), inList), isTrue);
      expect(SpotifyImportService.isTrackInSongs(sp('Kattazhagi', 'Thaman S'), inList), isFalse);
    });

    test('all tracks already imported -> nothing is matched, nothing is added', () async {
      final meta = SpotifyPlaylistMetadata(
        title: 'Idhayam Murali',
        totalTracks: 2,
        tracks: [sp('Vaama Vaama', 'Thaman S'), sp('Kattazhagi', 'Thaman S')],
      );
      final progress = <String>[];
      final result = await SpotifyImportService.importPlaylistWithProgress(
        metadata: meta,
        isAlreadyImported: (_) => true, // everything exists -> no network is touched
        onProgress: (c, t, p, status, matched) => progress.add(status),
      );
      expect(result.importedSongs, isEmpty);
      expect(result.alreadyPresentCount, 2);
      expect(result.handledKeys.length, 2);
      expect(result.skippedTracks, isEmpty);
      expect(progress.every((s) => !s.contains('Skipped')), isTrue);
    });
  });

  group('SpotifyImportLinks', () {
    late Directory dir;
    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('spotify_links_');
      Hive.init(dir.path);
    });
    tearDownAll(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('save / get / remove round-trip', () async {
      expect(await SpotifyImportLinks.get('playlist:abc'), isNull);
      await SpotifyImportLinks.save(const SpotifyImportLink(
        spotifyKey: 'playlist:abc',
        playlistId: 'local-1',
        importedKeys: {'a|b', 'c|d'},
        updatedAt: 1,
      ));
      final got = await SpotifyImportLinks.get('playlist:abc');
      expect(got?.playlistId, 'local-1');
      expect(got?.importedKeys, {'a|b', 'c|d'});
      await SpotifyImportLinks.remove('playlist:abc');
      expect(await SpotifyImportLinks.get('playlist:abc'), isNull);
    });
  });
}
