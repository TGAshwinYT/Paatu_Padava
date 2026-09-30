import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/playlist_manager.dart';
import 'package:paatu_padava_mobile/services/player_handler.dart';
import 'package:paatu_padava_mobile/services/collaborative_playlist_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paatu_collab_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(PlaylistManager.boxName);
    await Hive.openBox(FavoritesManager.boxName);
    await Hive.openBox(HistoryManager.boxName);
    await Hive.openBox(HistoryManager.pendingBoxName);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('UserPlaylist Collaborative Serialization Tests', () {
    test('toMap and fromMap preserve isCollaborative and inviteCode', () {
      final playlist = UserPlaylist(
        id: 'test_pl_1',
        title: 'Road Trip Vibes',
        createdAt: 1727710000000,
        tracks: [
          Song(id: 't1', title: 'Hukum', artist: 'Anirudh', album: 'Jailer', coverUrl: '', source: 'saavn'),
        ],
        isCollaborative: true,
        inviteCode: 'PP-7G9B',
        ownerId: 'user_xyz_123',
      );

      final map = playlist.toMap();
      expect(map['is_collaborative'], isTrue);
      expect(map['invite_code'], equals('PP-7G9B'));
      expect(map['owner_id'], equals('user_xyz_123'));

      final restored = UserPlaylist.fromMap(map);
      expect(restored.id, equals('test_pl_1'));
      expect(restored.title, equals('Road Trip Vibes'));
      expect(restored.isCollaborative, isTrue);
      expect(restored.inviteCode, equals('PP-7G9B'));
      expect(restored.ownerId, equals('user_xyz_123'));
      expect(restored.tracks.length, equals(1));
    });

    test('copyWith updates collaborative properties properly', () {
      final playlist = UserPlaylist(
        id: 'test_pl_2',
        title: 'Party Mix',
        createdAt: 1727710000000,
        tracks: [],
      );

      expect(playlist.isCollaborative, isFalse);
      expect(playlist.inviteCode, isNull);

      final collab = playlist.copyWith(
        isCollaborative: true,
        inviteCode: 'PP-3K8N',
      );

      expect(collab.isCollaborative, isTrue);
      expect(collab.inviteCode, equals('PP-3K8N'));
      expect(collab.title, equals('Party Mix'));
    });
  });

  group('CollaborativePlaylistService Tests', () {
    test('generateInviteCode produces valid PP- prefix and length', () {
      final code1 = CollaborativePlaylistService.generateInviteCode();
      final code2 = CollaborativePlaylistService.generateInviteCode();

      expect(code1.startsWith('PP-'), isTrue);
      expect(code1.length, equals(7)); // PP- + 4 chars
      expect(code1, isNot(equals(code2)));
    });

    test('enableCollaboration and disableCollaboration update local Hive playlist', () async {
      final original = UserPlaylist(
        id: 'local_collab_test',
        title: 'College Jam',
        createdAt: 1727710000000,
        tracks: [],
      );
      await PlaylistManager.savePlaylistDirectly(original);

      // Enable collaboration
      final enabled = await CollaborativePlaylistService.enableCollaboration('local_collab_test');
      expect(enabled, isNotNull);
      expect(enabled!.isCollaborative, isTrue);
      expect(enabled.inviteCode, isNotNull);
      expect(enabled.inviteCode!.startsWith('PP-'), isTrue);

      final inHive = PlaylistManager.getPlaylist('local_collab_test');
      expect(inHive!.isCollaborative, isTrue);
      expect(inHive.inviteCode, equals(enabled.inviteCode));

      // Disable collaboration
      final disabled = await CollaborativePlaylistService.disableCollaboration('local_collab_test');
      expect(disabled, isNotNull);
      expect(disabled!.isCollaborative, isFalse);

      final inHiveAfter = PlaylistManager.getPlaylist('local_collab_test');
      expect(inHiveAfter!.isCollaborative, isFalse);
    });
  });

  group('Android Auto MediaBrowserService Hierarchy Tests', () {
    test('MEDIA_ROOT_ID returns Liked, Recent, and Playlists categories', () async {
      final handler = PaatuAudioHandler();

      final roots = await handler.getChildren(AudioService.MEDIA_ROOT_ID);
      expect(roots.length, equals(3));
      expect(roots[0].id, equals('root_liked'));
      expect(roots[0].title, equals('Liked Songs'));
      expect(roots[0].playable, isFalse);

      expect(roots[1].id, equals('root_history'));
      expect(roots[1].title, equals('Recently Played'));
      expect(roots[1].playable, isFalse);

      expect(roots[2].id, equals('root_playlists'));
      expect(roots[2].title, equals('Playlists'));
      expect(roots[2].playable, isFalse);
    });

    test('getChildren root_liked returns playable favorites from FavoritesManager', () async {
      final handler = PaatuAudioHandler();
      final song = Song(
        id: 'fav_song_1',
        title: 'Kanmani Anbodu',
        artist: 'Ilaiyaraaja, Kamal Haasan',
        album: 'Gunaa',
        duration: 310,
        coverUrl: 'https://example.com/gunaa.jpg',
        source: 'saavn',
      );
      await FavoritesManager.toggleFavorite(song);

      final likedChildren = await handler.getChildren('root_liked');
      expect(likedChildren.isNotEmpty, isTrue);
      expect(likedChildren.first.id, equals('fav_song_1'));
      expect(likedChildren.first.playable, isTrue);
    });

    test('getChildren root_history returns playable tracks from HistoryManager', () async {
      final handler = PaatuAudioHandler();
      final song = Song(
        id: 'hist_song_1',
        title: 'New York Nagaram',
        artist: 'A.R. Rahman',
        album: 'Sillunu Oru Kaadhal',
        duration: 360,
        coverUrl: 'https://example.com/sok.jpg',
        source: 'saavn',
      );
      await HistoryManager.recordPlay(song);

      final histChildren = await handler.getChildren('root_history');
      expect(histChildren.isNotEmpty, isTrue);
      expect(histChildren.first.id, equals('hist_song_1'));
      expect(histChildren.first.playable, isTrue);
    });

    test('getChildren root_playlists returns browsable user playlists and specific playlist tracks', () async {
      final handler = PaatuAudioHandler();
      final testPl = UserPlaylist(
        id: 'auto_pl_1',
        title: 'Car Roadtrip',
        createdAt: 1727710000000,
        tracks: [
          Song(id: 'c1', title: 'Marakkuma Nenjam', artist: 'A.R. Rahman', album: 'VTK', coverUrl: '', source: 'saavn'),
        ],
      );
      await PlaylistManager.savePlaylistDirectly(testPl);

      final plCategories = await handler.getChildren('root_playlists');
      expect(plCategories.isNotEmpty, isTrue);
      expect(plCategories.any((p) => p.id == 'pl_auto_pl_1'), isTrue);

      final plTracks = await handler.getChildren('pl_auto_pl_1');
      expect(plTracks.length, equals(1));
      expect(plTracks.first.id, equals('c1'));
      expect(plTracks.first.playable, isTrue);
    });
  });
}
