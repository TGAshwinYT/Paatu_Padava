import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import 'supabase_service.dart';
import 'sync_manager.dart';
import 'collaborative_playlist_service.dart';

class UserPlaylist {
  String id;
  String title;
  final int createdAt;
  List<Song> tracks;
  bool isCollaborative;
  String? inviteCode;
  String? ownerId;
  bool isBlend;
  String? blendPartnerName;
  int? tasteMatchScore;

  UserPlaylist({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.tracks,
    this.isCollaborative = false,
    this.inviteCode,
    this.ownerId,
    this.isBlend = false,
    this.blendPartnerName,
    this.tasteMatchScore,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'created_at': createdAt,
    'tracks': tracks.map((t) => t.toMap()).toList(),
    'is_collaborative': isCollaborative,
    'invite_code': inviteCode,
    'owner_id': ownerId,
    'is_blend': isBlend,
    'blend_partner_name': blendPartnerName,
    'taste_match_score': tasteMatchScore,
  };

  factory UserPlaylist.fromMap(Map<dynamic, dynamic> map) {
    final rawTracks = map['tracks'] as List<dynamic>? ?? [];
    return UserPlaylist(
      id: map['id']?.toString() ?? const Uuid().v4(),
      title: map['title']?.toString() ?? 'Untitled Playlist',
      createdAt: int.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
      tracks: rawTracks.map((t) => Song.fromMap(t as Map<dynamic, dynamic>)).toList(),
      isCollaborative: map['is_collaborative'] == true,
      inviteCode: map['invite_code']?.toString(),
      ownerId: map['owner_id']?.toString(),
      isBlend: map['is_blend'] == true,
      blendPartnerName: map['blend_partner_name']?.toString(),
      tasteMatchScore: (map['taste_match_score'] as num?)?.toInt(),
    );
  }

  UserPlaylist copyWith({
    String? id,
    String? title,
    int? createdAt,
    List<Song>? tracks,
    bool? isCollaborative,
    String? inviteCode,
    String? ownerId,
    bool? isBlend,
    String? blendPartnerName,
    int? tasteMatchScore,
  }) {
    return UserPlaylist(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      tracks: tracks ?? this.tracks,
      isCollaborative: isCollaborative ?? this.isCollaborative,
      inviteCode: inviteCode ?? this.inviteCode,
      ownerId: ownerId ?? this.ownerId,
      isBlend: isBlend ?? this.isBlend,
      blendPartnerName: blendPartnerName ?? this.blendPartnerName,
      tasteMatchScore: tasteMatchScore ?? this.tasteMatchScore,
    );
  }

  /// Whether current logged-in user owns this playlist
  bool get isOwner {
    final supaId = SupabaseService.currentUser?.id;
    if (ownerId == null || supaId == null) return true;
    return ownerId == supaId;
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

  /// Creates a Spotify-style Blend playlist merging user tracks with a partner's tracks.
  /// Automatically interleaves tracks, tags 'addedBy', calculates taste match %,
  /// and enables collaboration mode.
  static Future<UserPlaylist> createBlendPlaylist({
    required String partnerName,
    required List<Song> userTracks,
    required List<Song> partnerTracks,
    int? customTasteMatch,
  }) async {
    // 1. Calculate realistic taste match score if not explicitly supplied
    int matchScore = customTasteMatch ?? 0;
    if (matchScore <= 0) {
      final userArtists = userTracks.map((s) => s.artist.toLowerCase()).toSet();
      final partnerArtists = partnerTracks.map((s) => s.artist.toLowerCase()).toSet();
      final intersection = userArtists.intersection(partnerArtists);
      if (userArtists.isEmpty && partnerArtists.isEmpty) {
        matchScore = 86;
      } else {
        final totalUnique = userArtists.union(partnerArtists).length;
        final base = totalUnique > 0 ? ((intersection.length / totalUnique) * 100).round() : 75;
        matchScore = (base + 66).clamp(68, 98);
      }
    }

    // 2. Interleave tracks alternating between User and Partner
    final mergedTracks = <Song>[];
    final maxLen = max(userTracks.length, partnerTracks.length);
    for (int i = 0; i < maxLen; i++) {
      if (i < userTracks.length) {
        final song = userTracks[i];
        mergedTracks.add(song.copyWith(addedBy: 'You'));
      }
      if (i < partnerTracks.length) {
        final song = partnerTracks[i];
        mergedTracks.add(song.copyWith(addedBy: partnerName));
      }
    }

    final id = const Uuid().v4();
    final blend = UserPlaylist(
      id: id,
      title: '$partnerName + You',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      tracks: mergedTracks,
      isCollaborative: true,
      inviteCode: CollaborativePlaylistService.generateInviteCode(),
      isBlend: true,
      blendPartnerName: partnerName,
      tasteMatchScore: matchScore,
    );

    await savePlaylistDirectly(blend);
    return blend;
  }
}
