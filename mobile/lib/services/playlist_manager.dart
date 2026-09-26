import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import 'sync_manager.dart';

class UserPlaylist {
  String id;
  String title;
  final int createdAt;
  List<Song> tracks;

  UserPlaylist({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.tracks,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'created_at': createdAt,
    'tracks': tracks.map((t) => t.toMap()).toList(),
  };

  factory UserPlaylist.fromMap(Map<dynamic, dynamic> map) {
    final rawTracks = map['tracks'] as List<dynamic>? ?? [];
    return UserPlaylist(
      id: map['id']?.toString() ?? const Uuid().v4(),
      title: map['title']?.toString() ?? 'Untitled Playlist',
      createdAt: int.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
      tracks: rawTracks.map((t) => Song.fromMap(t as Map<dynamic, dynamic>)).toList(),
    );
  }

  String get coverUrl => tracks.isNotEmpty ? tracks.first.coverUrl : '';
}

class PlaylistManager {
  static const String boxName = 'playlists_box';
  static final ValueNotifier<List<UserPlaylist>> playlistsNotifier = ValueNotifier<List<UserPlaylist>>([]);

  static Box get _box => Hive.box(boxName);

  static Future<void> init() async {
    await Hive.openBox(boxName);
    _refreshList();
    // Unified Supabase cloud playlist sync on app launch
    SyncManager.syncAll();
  }

  static void _refreshList() {
    final List<UserPlaylist> list = [];
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data != null && data is Map) {
        list.add(UserPlaylist.fromMap(data));
      }
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    playlistsNotifier.value = list;
  }

  static void refreshList() => _refreshList();

  static List<UserPlaylist> getPlaylists() => playlistsNotifier.value;

  static UserPlaylist? getPlaylist(String id) {
    final data = _box.get(id);
    if (data != null && data is Map) {
      return UserPlaylist.fromMap(data);
    }
    return null;
  }

  /// Directly saves a playlist in local Hive cache
  static Future<void> savePlaylistDirectly(UserPlaylist playlist) async {
    await _box.put(playlist.id, playlist.toMap());
    _refreshList();
  }

  /// Directly deletes a playlist from local Hive cache
  static Future<void> deletePlaylistDirectly(String playlistId) async {
    await _box.delete(playlistId);
    _refreshList();
  }

  /// Creates a new playlist with immediate local persistence and Supabase cloud sync
  static Future<UserPlaylist> createPlaylist(String title, {List<Song>? initialTracks}) async {
    return await SyncManager.createPlaylist(title, initialTracks: initialTracks);
  }

  /// Adds a song to a playlist with immediate local persistence and Supabase cloud sync
  static Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    return await SyncManager.addSongToPlaylist(playlistId, song);
  }

  /// Removes a song from a playlist with immediate local persistence and Supabase cloud sync
  static Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    await SyncManager.removeSongFromPlaylist(playlistId, songId);
  }

  /// Deletes a playlist with immediate local removal and Supabase cloud cascade deletion
  static Future<void> deletePlaylist(String playlistId) async {
    await SyncManager.deletePlaylist(playlistId);
  }

  /// Renames a playlist in local storage and Supabase cloud
  static Future<void> renamePlaylist(String playlistId, String newTitle) async {
    await SyncManager.renamePlaylist(playlistId, newTitle);
  }
}
