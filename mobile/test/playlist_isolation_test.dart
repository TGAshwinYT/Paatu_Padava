import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/auth_manager.dart';
import 'package:paatu_padava_mobile/services/playlist_manager.dart';

Song _makeSong(String id, String title) => Song(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      duration: 200,
      coverUrl: 'https://example.com/cover.jpg',
      source: 'saavn',
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('paatu_playlist_iso_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(AuthManager.boxName);
    await PlaylistManager.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    AuthManager.authNotifier.value = AuthUser.guest();
    AuthManager.pendingGuestImportCountNotifier.value = 0;
  });

  test('Declining guest import on login keeps guest playlists local and account bucket empty', () async {
    AuthManager.authNotifier.value = AuthUser.guest();
    final guestPl = await PlaylistManager.createPlaylist(
      'Road Trip Mix',
      initialTracks: [_makeSong('s1', 'Track 1')],
      scope: PlaylistScope.guest,
    );
    expect(PlaylistManager.getGuestPlaylists().length, 1);

    // Simulate user authentication
    const userId = 'user-123';
    AuthManager.authNotifier.value = AuthUser(
      id: userId,
      username: 'Tester',
      email: 'test@example.com',
      isGuest: false,
    );
    await PlaylistManager.onUserAuthenticated(userId);
    expect(PlaylistManager.hasUnhandledGuestPlaylists(userId), isTrue);

    // Decline import
    await PlaylistManager.markGuestImportDeclined(userId);
    expect(PlaylistManager.hasUnhandledGuestPlaylists(userId), isFalse);
    expect(PlaylistManager.getGuestPlaylists().map((p) => p.id), contains(guestPl.id));
    expect(PlaylistManager.getAccountPlaylists(), isEmpty);
  });

  test('Logged-in state exposes both buckets and guest edits stay strictly local', () async {
    final guestPl = await PlaylistManager.createPlaylist(
      'Offline Vibes',
      scope: PlaylistScope.guest,
    );

    const userId = 'user-456';
    AuthManager.authNotifier.value = AuthUser(
      id: userId,
      username: 'Tester',
      email: 'test@example.com',
      isGuest: false,
    );
    await PlaylistManager.onUserAuthenticated(userId);

    final accountPl = UserPlaylist(
      id: 'acc-pl-1',
      title: 'Cloud Favorites',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      tracks: [],
      ownerId: userId,
    );
    await PlaylistManager.savePlaylistDirectly(accountPl, scope: PlaylistScope.account);

    expect(PlaylistManager.getAccountPlaylists().length, 1);
    expect(PlaylistManager.getGuestPlaylists().length, 1);
    expect(PlaylistManager.getPlaylists().length, 2);

    // Edit guest playlist while logged in
    await PlaylistManager.addSongToPlaylist(guestPl.id, _makeSong('s2', 'Guest Track'));
    await PlaylistManager.renamePlaylist(guestPl.id, 'Offline Vibes Updated');

    final updatedGuest = PlaylistManager.getGuestPlaylists().first;
    expect(updatedGuest.title, 'Offline Vibes Updated');
    expect(updatedGuest.tracks.length, 1);
    expect(PlaylistManager.getAccountPlaylists().first.tracks, isEmpty);
  });

  test('Logout clears account playlists from memory & disk while preserving guest playlists', () async {
    await PlaylistManager.createPlaylist('Guest Keep', scope: PlaylistScope.guest);

    const userId = 'user-789';
    AuthManager.authNotifier.value = AuthUser(
      id: userId,
      username: 'Tester',
      email: 'test@example.com',
      isGuest: false,
    );
    await PlaylistManager.onUserAuthenticated(userId);
    await PlaylistManager.savePlaylistDirectly(
      UserPlaylist(
        id: 'acc-secret-1',
        title: 'Private Cloud',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        tracks: [],
        ownerId: userId,
      ),
      scope: PlaylistScope.account,
    );
    expect(PlaylistManager.getAccountPlaylists().length, 1);

    // Logout
    AuthManager.authNotifier.value = AuthUser.guest();
    await PlaylistManager.clearAccountPlaylistsOnLogout(userId);

    expect(PlaylistManager.getAccountPlaylists(), isEmpty);
    expect(PlaylistManager.getPlaylists().length, 1);
    expect(PlaylistManager.getPlaylists().first.title, 'Guest Keep');
    expect(await Hive.boxExists(PlaylistManager.accountBoxName(userId)), isFalse);
  });

  test('Approving guest import copies playlists with new IDs into account bucket', () async {
    final guestPl = await PlaylistManager.createPlaylist(
      'Travel Jams',
      initialTracks: [_makeSong('s9', 'Highway Song')],
      scope: PlaylistScope.guest,
    );

    const userId = 'user-999';
    AuthManager.authNotifier.value = AuthUser(
      id: userId,
      username: 'Tester',
      email: 'test@example.com',
      isGuest: false,
    );

    final imported = await PlaylistManager.importGuestPlaylistsToAccount(userId);
    expect(imported.length, 1);
    expect(imported.first.id, isNot(equals(guestPl.id)));
    expect(imported.first.title, 'Travel Jams');
    expect(imported.first.tracks.length, 1);
    expect(PlaylistManager.getAccountPlaylists().length, 1);
    expect(PlaylistManager.hasUnhandledGuestPlaylists(userId), isFalse);
  });
}
