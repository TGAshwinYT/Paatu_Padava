import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import '../models/user_playlist.dart';
import 'auth_manager.dart';
import 'playlist_blend_helper.dart';
import 'sync_manager.dart';

import 'package:paatu_padava_mobile/services/app_logger.dart';

export '../models/user_playlist.dart';

enum PlaylistScope { guest, account }

class PlaylistManager {
  static const String guestBoxName = 'guest_playlists';
  static const String boxName = guestBoxName;
  static const String legacyBoxName = 'playlists_box';
  static const String _metaBoxName = 'playlist_import_meta';
  static String accountBoxName(String userId) => 'account_playlists_$userId';

  static final ValueNotifier<List<UserPlaylist>> guestPlaylistsNotifier = ValueNotifier<List<UserPlaylist>>([]);
  static final ValueNotifier<List<UserPlaylist>> accountPlaylistsNotifier = ValueNotifier<List<UserPlaylist>>([]);
  static final ValueNotifier<List<UserPlaylist>> playlistsNotifier = ValueNotifier<List<UserPlaylist>>([]);

  static String? _activeUserId;

  static Box get _guestBox => Hive.box(guestBoxName);
  static Box? get _accountBox =>
      (_activeUserId != null && Hive.isBoxOpen(accountBoxName(_activeUserId!)))
          ? Hive.box(accountBoxName(_activeUserId!))
          : null;

  static Future<void> init() async {
    if (!Hive.isBoxOpen(guestBoxName)) {
      await Hive.openBox(guestBoxName);
    }
    if (!Hive.isBoxOpen(_metaBoxName)) {
      await Hive.openBox(_metaBoxName);
    }

    // One-time legacy migration from 'playlists_box'
    if (await Hive.boxExists(legacyBoxName)) {
      try {
        final legacyBox = Hive.isBoxOpen(legacyBoxName)
            ? Hive.box(legacyBoxName)
            : await Hive.openBox(legacyBoxName);
        if (AuthManager.isLoggedIn && AuthManager.currentUser?.id != null) {
          final uid = AuthManager.currentUser!.id;
          _activeUserId = uid;
          final accName = accountBoxName(uid);
          final accBox = Hive.isBoxOpen(accName) ? Hive.box(accName) : await Hive.openBox(accName);
          for (final key in legacyBox.keys) {
            final data = legacyBox.get(key);
            if (data is Map && !accBox.containsKey(key)) {
              await accBox.put(key, Map<dynamic, dynamic>.from(data));
            }
          }
        } else {
          for (final key in legacyBox.keys) {
            final data = legacyBox.get(key);
            if (data is Map && !_guestBox.containsKey(key)) {
              await _guestBox.put(key, Map<dynamic, dynamic>.from(data));
            }
          }
        }
        await legacyBox.close();
        await Hive.deleteBoxFromDisk(legacyBoxName);
      } catch (e) {
        AppLogger.debug('PlaylistManager', 'Legacy migration notice: $e');
      }
    }

    _refreshList();
  }

  /// Opens account-scoped Hive box on authentication and migrates any lingering legacy box
  static Future<void> onUserAuthenticated(String userId) async {
    if (userId.isEmpty || userId == 'guest') return;
    _activeUserId = userId;
    final accName = accountBoxName(userId);
    if (!Hive.isBoxOpen(accName)) {
      await Hive.openBox(accName);
    }
    if (await Hive.boxExists(legacyBoxName)) {
      try {
        final legacyBox = Hive.isBoxOpen(legacyBoxName)
            ? Hive.box(legacyBoxName)
            : await Hive.openBox(legacyBoxName);
        final accBox = Hive.box(accName);
        for (final key in legacyBox.keys) {
          final data = legacyBox.get(key);
          if (data is Map && !accBox.containsKey(key)) {
            await accBox.put(key, Map<dynamic, dynamic>.from(data));
          }
        }
        await legacyBox.close();
        await Hive.deleteBoxFromDisk(legacyBoxName);
      } catch (e) {
        AppLogger.debug('PlaylistManager', 'Account legacy migration notice: $e');
      }
    }
    _refreshList();
  }

  /// Purges all account playlists from memory & local Hive cache on logout
  static Future<void> clearAccountPlaylistsOnLogout(String? userId) async {
    final targetUserId = userId ?? _activeUserId;
    _activeUserId = null;
    accountPlaylistsNotifier.value = [];

    if (targetUserId != null && targetUserId.isNotEmpty && targetUserId != 'guest') {
      final accName = accountBoxName(targetUserId);
      try {
        if (Hive.isBoxOpen(accName)) {
          await Hive.box(accName).clear();
          await Hive.box(accName).close();
        }
        if (await Hive.boxExists(accName)) {
          await Hive.deleteBoxFromDisk(accName);
        }
      } catch (e) {
        AppLogger.debug('PlaylistManager', 'Logout account cache clear notice: $e');
      }
    }
    _refreshList();
  }

  static List<UserPlaylist> _readBoxPlaylists(Box? box) {
    if (box == null || !box.isOpen) return [];
    final List<UserPlaylist> list = [];
    for (final key in box.keys) {
      final data = box.get(key);
      if (data != null && data is Map) {
        list.add(UserPlaylist.fromMap(data));
      }
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static void _refreshList() {
    final guestList = Hive.isBoxOpen(guestBoxName) ? _readBoxPlaylists(_guestBox) : <UserPlaylist>[];
    final accountList = AuthManager.isLoggedIn ? _readBoxPlaylists(_accountBox) : <UserPlaylist>[];

    guestPlaylistsNotifier.value = guestList;
    accountPlaylistsNotifier.value = accountList;
    playlistsNotifier.value = AuthManager.isLoggedIn ? [...accountList, ...guestList] : [...guestList];
  }

  static void refreshList() => _refreshList();

  static List<UserPlaylist> getPlaylists() => playlistsNotifier.value;
  static List<UserPlaylist> getGuestPlaylists() => guestPlaylistsNotifier.value;
  static List<UserPlaylist> getAccountPlaylists() => accountPlaylistsNotifier.value;

  static bool isGuestPlaylist(String playlistId) {
    if (Hive.isBoxOpen(guestBoxName) && _guestBox.containsKey(playlistId)) {
      return true;
    }
    return guestPlaylistsNotifier.value.any((p) => p.id == playlistId);
  }

  static UserPlaylist? getPlaylist(String id) {
    final accBox = _accountBox;
    if (accBox != null && accBox.containsKey(id)) {
      final data = accBox.get(id);
      if (data is Map) return UserPlaylist.fromMap(data);
    }
    if (Hive.isBoxOpen(guestBoxName) && _guestBox.containsKey(id)) {
      final data = _guestBox.get(id);
      if (data is Map) return UserPlaylist.fromMap(data);
    }
    return null;
  }

  /// Directly saves a playlist into the specified scope's Hive box
  static Future<void> savePlaylistDirectly(
    UserPlaylist playlist, {
    PlaylistScope? scope,
  }) async {
    final targetScope = scope ??
        (isGuestPlaylist(playlist.id)
            ? PlaylistScope.guest
            : (AuthManager.isLoggedIn ? PlaylistScope.account : PlaylistScope.guest));

    if (targetScope == PlaylistScope.account && _accountBox != null) {
      await _accountBox!.put(playlist.id, playlist.toMap());
    } else {
      if (!Hive.isBoxOpen(guestBoxName)) await Hive.openBox(guestBoxName);
      await _guestBox.put(playlist.id, playlist.toMap());
    }
    _refreshList();
  }

  /// Replaces all cached account playlists with reconciled cloud + pending-local state
  static Future<void> replaceAccountPlaylists(List<UserPlaylist> playlists) async {
    final accBox = _accountBox;
    if (accBox == null) return;
    await accBox.clear();
    for (final pl in playlists) {
      await accBox.put(pl.id, pl.toMap());
    }
    _refreshList();
  }

  static List<String> _getHandledGuestIds(String userId) {
    if (!Hive.isBoxOpen(_metaBoxName)) return [];
    final raw = Hive.box(_metaBoxName).get('handled_$userId');
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  static Future<void> _markGuestIdsHandled(String userId, List<String> ids) async {
    if (!Hive.isBoxOpen(_metaBoxName)) await Hive.openBox(_metaBoxName);
    final existing = _getHandledGuestIds(userId).toSet()..addAll(ids);
    await Hive.box(_metaBoxName).put('handled_$userId', existing.toList());
  }

  /// Returns true if device has guest playlists not yet approved/declined for [userId]
  static bool hasUnhandledGuestPlaylists(String userId) {
    final guests = getGuestPlaylists();
    if (guests.isEmpty) return false;
    final handled = _getHandledGuestIds(userId).toSet();
    return guests.any((g) => !handled.contains(g.id));
  }

  static Future<void> markGuestImportDeclined(String userId) async {
    final ids = getGuestPlaylists().map((g) => g.id).toList();
    await _markGuestIdsHandled(userId, ids);
  }

  /// Copies guest playlists into account_playlists_<userId> with fresh UUIDs and marks them handled.
  static Future<List<UserPlaylist>> importGuestPlaylistsToAccount(String userId) async {
    await onUserAuthenticated(userId);
    final guests = getGuestPlaylists();
    final handled = _getHandledGuestIds(userId).toSet();
    final toImport = guests.where((g) => !handled.contains(g.id)).toList();
    final List<UserPlaylist> imported = [];

    for (final guest in toImport) {
      final accountCopy = guest.copyWith(
        id: const Uuid().v4(),
        ownerId: userId,
      );
      await savePlaylistDirectly(accountCopy, scope: PlaylistScope.account);
      imported.add(accountCopy);
    }

    await _markGuestIdsHandled(userId, guests.map((g) => g.id).toList());
    return imported;
  }

  static void _updateCoverInBox(Box? box, String songId, String newCover) {
    if (box == null || !box.isOpen) return;
    for (final key in box.keys) {
      final data = box.get(key);
      if (data is! Map) continue;
      final pl = UserPlaylist.fromMap(data);
      bool plChanged = false;
      final updatedTracks = pl.tracks.map((t) {
        if (t.id == songId && t.coverUrl != newCover) {
          plChanged = true;
          return t.copyWith(coverUrl: newCover);
        }
        return t;
      }).toList();
      if (plChanged) {
        box.put(pl.id, pl.copyWith(tracks: updatedTracks).toMap());
      }
    }
  }

  /// Updates a track's cover URL across local playlists if it had a playlist mosaic or missing cover
  static void updateTrackCover(String songId, String newCover) {
    if (songId.isEmpty || newCover.isEmpty) return;
    try {
      if (Hive.isBoxOpen(guestBoxName)) {
        _updateCoverInBox(_guestBox, songId, newCover);
      }
      if (_accountBox != null) {
        _updateCoverInBox(_accountBox, songId, newCover);
      }
      _refreshList();
    } catch (e) {
      AppLogger.debug('PlaylistManager', 'Handled exception: $e');
    }
  }

  /// Directly deletes a playlist from the appropriate Hive cache
  static Future<void> deletePlaylistDirectly(
    String playlistId, {
    PlaylistScope? scope,
  }) async {
    final targetScope = scope ??
        (isGuestPlaylist(playlistId) ? PlaylistScope.guest : PlaylistScope.account);
    if (targetScope == PlaylistScope.guest) {
      if (Hive.isBoxOpen(guestBoxName)) await _guestBox.delete(playlistId);
    } else if (_accountBox != null) {
      await _accountBox!.delete(playlistId);
    }
    _refreshList();
  }

  /// Creates a new playlist strictly in Guest (local) or Account (cloud-synced) storage
  static Future<UserPlaylist> createPlaylist(
    String title, {
    List<Song>? initialTracks,
    PlaylistScope? scope,
  }) async {
    final effectiveScope = scope ??
        (AuthManager.isLoggedIn ? PlaylistScope.account : PlaylistScope.guest);
    if (effectiveScope == PlaylistScope.guest) {
      final cleanTitle = title.trim().isEmpty ? 'My Playlist' : title.trim();
      final existing = getGuestPlaylists().where(
        (p) => p.title.toLowerCase() == cleanTitle.toLowerCase(),
      ).firstOrNull;
      if (existing != null) return existing;

      final playlist = UserPlaylist(
        id: const Uuid().v4(),
        title: cleanTitle,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        tracks: initialTracks ?? [],
      );
      await savePlaylistDirectly(playlist, scope: PlaylistScope.guest);
      return playlist;
    }
    return await SyncManager.createPlaylist(title, initialTracks: initialTracks);
  }

  /// Adds a song to a playlist, keeping Guest edits strictly local
  static Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    if (isGuestPlaylist(playlistId)) {
      final pl = getPlaylist(playlistId);
      if (pl == null) return false;
      if (pl.tracks.any((t) => t.id == song.id)) return true;
      pl.tracks.add(song);
      await savePlaylistDirectly(pl, scope: PlaylistScope.guest);
      return true;
    }
    return await SyncManager.addSongToPlaylist(playlistId, song);
  }

  /// Removes a song from a playlist, keeping Guest edits strictly local
  static Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    if (isGuestPlaylist(playlistId)) {
      final pl = getPlaylist(playlistId);
      if (pl == null) return;
      pl.tracks.removeWhere((t) => t.id == songId);
      await savePlaylistDirectly(pl, scope: PlaylistScope.guest);
      return;
    }
    await SyncManager.removeSongFromPlaylist(playlistId, songId);
  }

  /// Deletes a playlist, keeping Guest deletions strictly local
  static Future<void> deletePlaylist(String playlistId) async {
    if (isGuestPlaylist(playlistId)) {
      await deletePlaylistDirectly(playlistId, scope: PlaylistScope.guest);
      return;
    }
    await SyncManager.deletePlaylist(playlistId);
  }

  /// Renames a playlist, keeping Guest renames strictly local
  static Future<void> renamePlaylist(String playlistId, String newTitle) async {
    if (isGuestPlaylist(playlistId)) {
      final pl = getPlaylist(playlistId);
      if (pl == null) return;
      pl.title = newTitle.trim().isEmpty ? 'Untitled Playlist' : newTitle.trim();
      await savePlaylistDirectly(pl, scope: PlaylistScope.guest);
      return;
    }
    await SyncManager.renamePlaylist(playlistId, newTitle);
  }

  /// Creates a Spotify-style Blend playlist merging user tracks with a partner's tracks.
  static Future<UserPlaylist> createBlendPlaylist({
    required String partnerName,
    required List<Song> userTracks,
    required List<Song> partnerTracks,
    int? customTasteMatch,
  }) =>
      PlaylistBlendHelper.createBlendPlaylist(
        partnerName: partnerName,
        userTracks: userTracks,
        partnerTracks: partnerTracks,
        customTasteMatch: customTasteMatch,
      );
}
