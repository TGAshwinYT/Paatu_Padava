import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/playlist_manager.dart';
import 'package:paatu_padava_mobile/services/sync_manager.dart';

void main() {
  group('TrackEntity & Sanitation Tests', () {
    test('deduplicationKey normalizes title and artist across casing and whitespace', () {
      final entity1 = TrackEntity(
        id: '1',
        title: '  Vennilave Vennilave  ',
        artist: 'Hariharan, Sadhana Sargam',
        coverUrl: 'https://example.com/cover1.jpg',
        source: 'saavn',
      );

      final entity2 = TrackEntity(
        id: '2',
        title: 'vennilave vennilave',
        artist: '  HARIHARAN, SADHANA SARGAM  ',
        coverUrl: 'https://example.com/cover2.jpg',
        source: 'youtube',
      );

      expect(entity1.deduplicationKey, equals(entity2.deduplicationKey));
      expect(entity1.deduplicationKey, equals('vennilave vennilave_hariharan, sadhana sargam'));
    });

    test('deduplicationKey distinguishes different tracks', () {
      final entity1 = TrackEntity(
        id: '1',
        title: 'Kandukondain Kandukondain',
        artist: 'A.R. Rahman',
        coverUrl: 'https://example.com/cover1.jpg',
        source: 'saavn',
      );

      final entity2 = TrackEntity(
        id: '2',
        title: 'Enna Solla Pogirai',
        artist: 'A.R. Rahman',
        coverUrl: 'https://example.com/cover2.jpg',
        source: 'saavn',
      );

      expect(entity1.deduplicationKey, isNot(equals(entity2.deduplicationKey)));
    });

    test('sanitize unescapes HTML entities properly', () {
      expect(
        TrackEntity.sanitize('Rock &amp; Roll &#039;N&#039; &quot;Tamil&quot;'),
        equals('Rock & Roll \'N\' "Tamil"'),
      );
    });

    test('sanitize returns fallback for null or empty string', () {
      expect(TrackEntity.sanitize(null, fallback: 'Fallback Title'), equals('Fallback Title'));
      expect(TrackEntity.sanitize('   ', fallback: 'Fallback Title'), equals('Fallback Title'));
    });
  });

  group('Sync Reconciliation & UserPlaylist Serialization', () {
    test('UserPlaylist serialization round-trip maintains integrity', () {
      final song = Song(
        id: 's_001',
        title: 'Aalaporan Thamizhan',
        artist: 'A.R. Rahman, Kailash Kher',
        album: 'Mersal',
        duration: 348,
        coverUrl: 'https://example.com/mersal.jpg',
        streamUrl: 'https://example.com/stream.mp4',
        source: 'saavn',
      );

      final playlist = UserPlaylist(
        id: 'pl_001',
        title: 'AR Rahman Hits',
        createdAt: 1700000000000,
        tracks: [song],
      );

      final map = playlist.toMap();
      expect(map['id'], equals('pl_001'));
      expect(map['title'], equals('AR Rahman Hits'));
      expect((map['tracks'] as List).length, equals(1));

      final restored = UserPlaylist.fromMap(map);
      expect(restored.id, equals(playlist.id));
      expect(restored.title, equals(playlist.title));
      expect(restored.createdAt, equals(playlist.createdAt));
      expect(restored.tracks.length, equals(1));
      expect(restored.tracks.first.id, equals('s_001'));
      expect(restored.coverUrl, equals('https://example.com/mersal.jpg'));
    });

    test('SyncStatusNotifier correctly updates and exposes states', () {
      SyncManager.syncStatusNotifier.value = SyncStatus.idle;
      expect(SyncManager.status, equals(SyncStatus.idle));

      SyncManager.syncStatusNotifier.value = SyncStatus.syncing;
      expect(SyncManager.status, equals(SyncStatus.syncing));

      SyncManager.syncStatusNotifier.value = SyncStatus.synced;
      expect(SyncManager.status, equals(SyncStatus.synced));

      SyncManager.syncStatusNotifier.value = SyncStatus.offline;
      expect(SyncManager.status, equals(SyncStatus.offline));

      SyncManager.syncStatusNotifier.value = SyncStatus.error;
      expect(SyncManager.status, equals(SyncStatus.error));
    });
  });

  group('Playlist De-Duplication & Idempotency Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('paatu_playlist_test_');
      Hive.init(tempDir.path);
      await Hive.openBox(PlaylistManager.boxName);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Creating a playlist with an existing title reuses existing playlist instead of duplicating', () async {
      final songA = Song(id: 's_01', title: 'Song 1', artist: 'Artist 1', album: '', duration: 180, coverUrl: '');
      final pl1 = await SyncManager.createPlaylist('My Playlist', initialTracks: [songA]);

      expect(PlaylistManager.getPlaylists().length, equals(1));
      expect(pl1.title, equals('My Playlist'));

      // Attempt to create "My Playlist" again (even with casing/whitespace variance)
      final songB = Song(id: 's_02', title: 'Song 2', artist: 'Artist 2', album: '', duration: 200, coverUrl: '');
      final pl2 = await SyncManager.createPlaylist('  my playlist  ', initialTracks: [songB]);

      // Verifies no duplicate playlist was created!
      expect(PlaylistManager.getPlaylists().length, equals(1));
      expect(pl2.id, equals(pl1.id));
      expect(pl2.tracks.length, equals(2));
      expect(pl2.tracks.map((t) => t.id), containsAll(['s_01', 's_02']));
    });

    test('Adding duplicate song to playlist is cleanly rejected', () async {
      final song = Song(id: 's_dup', title: 'Song Dup', artist: 'Artist', album: '', duration: 180, coverUrl: '');
      final pl = await SyncManager.createPlaylist('Favorites Collection', initialTracks: [song]);

      final addedAgain = await SyncManager.addSongToPlaylist(pl.id, song);
      expect(addedAgain, isFalse);
      expect(pl.tracks.length, equals(1));
    });

    test('Collaborative track attribution preserves addedBy and role permissions', () async {
      final song = Song(
        id: 's_collab_1',
        title: 'Master The Blaster',
        artist: 'Anirudh',
        album: 'Master',
        coverUrl: '',
        addedBy: 'Ashwin',
      );

      final playlist = UserPlaylist(
        id: 'collab_pl_1',
        title: 'Squad Jams',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        tracks: [song],
        isCollaborative: true,
        inviteCode: 'PP-9K2M',
        ownerId: 'user_123',
      );

      // Verify serialization preserves addedBy and collab fields
      final map = playlist.toMap();
      expect(map['is_collaborative'], isTrue);
      expect(map['invite_code'], equals('PP-9K2M'));
      expect(map['owner_id'], equals('user_123'));
      expect(map['tracks'][0]['addedBy'], equals('Ashwin'));

      final restored = UserPlaylist.fromMap(map);
      expect(restored.isCollaborative, isTrue);
      expect(restored.inviteCode, equals('PP-9K2M'));
      expect(restored.tracks.first.addedBy, equals('Ashwin'));

      // Test adding song with explicit attribution via addSongToPlaylist
      await PlaylistManager.savePlaylistDirectly(restored);
      final song2 = Song(
        id: 's_collab_2',
        title: 'Vaathi Coming',
        artist: 'Anirudh',
        album: 'Master',
        coverUrl: '',
        addedBy: 'GuestEditor',
      );
      final added = await SyncManager.addSongToPlaylist('collab_pl_1', song2);
      expect(added, isTrue);

      final updated = PlaylistManager.getPlaylist('collab_pl_1');
      expect(updated?.tracks.length, equals(2));
      expect(updated?.tracks[1].addedBy, equals('GuestEditor'));
    });
  });
}
