import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'auth_manager.dart';

class UserPlaylist {
  final String id;
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
      id: map['id']?.toString() ?? '',
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
    syncWithBackend();
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

  static List<UserPlaylist> getPlaylists() => playlistsNotifier.value;

  static UserPlaylist? getPlaylist(String id) {
    final data = _box.get(id);
    if (data != null && data is Map) {
      return UserPlaylist.fromMap(data);
    }
    return null;
  }

  static Future<UserPlaylist> createPlaylist(String title, {List<Song>? initialTracks}) async {
    final cleanTitle = title.trim().isEmpty ? 'My Playlist' : title.trim();
    final id = 'pl_${DateTime.now().millisecondsSinceEpoch}_${playlistsNotifier.value.length + 1}';
    final playlist = UserPlaylist(
      id: id,
      title: cleanTitle,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      tracks: initialTracks != null ? List<Song>.from(initialTracks) : [],
    );

    await _box.put(id, playlist.toMap());
    _refreshList();

    // Cloud sync if authenticated
    if (AuthManager.isLoggedIn) {
      _syncCreateToBackend(playlist);
    }

    return playlist;
  }

  static Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    final playlist = getPlaylist(playlistId);
    if (playlist == null) return false;

    // Check duplicate
    if (playlist.tracks.any((t) => t.id == song.id)) return true;

    playlist.tracks.add(song);
    await _box.put(playlistId, playlist.toMap());
    _refreshList();

    if (AuthManager.isLoggedIn) {
      _syncAddTrackToBackend(playlistId, song);
    }

    return true;
  }

  static Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final playlist = getPlaylist(playlistId);
    if (playlist == null) return;

    playlist.tracks.removeWhere((t) => t.id == songId);
    await _box.put(playlistId, playlist.toMap());
    _refreshList();
  }

  static Future<void> deletePlaylist(String playlistId) async {
    await _box.delete(playlistId);
    _refreshList();

    if (AuthManager.isLoggedIn) {
      try {
        final token = AuthManager.token;
        if (token != null) {
          final uri = Uri.parse('${AuthManager.baseUrl}/api/playlists/$playlistId');
          http.delete(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 4));
        }
      } catch (_) {}
    }
  }

  static Future<void> syncWithBackend() async {
    if (!AuthManager.isLoggedIn) return;
    final token = AuthManager.token;
    if (token == null) return;

    try {
      final uri = Uri.parse('${AuthManager.baseUrl}/api/playlists');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is List) {
          for (final item in data) {
            if (item is Map) {
              final id = item['id']?.toString() ?? '';
              final title = item['title']?.toString() ?? 'Playlist';
              if (id.isNotEmpty && !_box.containsKey(id)) {
                final pl = UserPlaylist(
                  id: id,
                  title: title,
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                  tracks: [],
                );
                await _box.put(id, pl.toMap());
              }
            }
          }
          _refreshList();
        }
      }
    } catch (_) {}
  }

  static void _syncCreateToBackend(UserPlaylist playlist) async {
    try {
      final token = AuthManager.token;
      if (token == null) return;
      final uri = Uri.parse('${AuthManager.baseUrl}/api/playlists');
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'title': playlist.title}),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  static void _syncAddTrackToBackend(String playlistId, Song song) async {
    try {
      final token = AuthManager.token;
      if (token == null) return;
      final uri = Uri.parse('${AuthManager.baseUrl}/api/playlists/$playlistId/tracks');
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'yt_video_id': song.id,
          'title': song.title,
          'artist': song.artist,
          'cover_url': song.coverUrl,
          'duration': song.duration,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }
}
