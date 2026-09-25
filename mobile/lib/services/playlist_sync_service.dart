import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import 'playlist_manager.dart';
import 'supabase_service.dart';
import 'sync_manager.dart';

class PlaylistSyncService {
  static const Uuid _uuid = Uuid();

  /// Triggered on app launch or post-login: performs bidirectional sync
  /// between Supabase cloud tables and local Hive offline cache.
  static Future<void> syncOnLaunch() async {
    await SyncManager.syncAll();
  }


  /// Pushes a complete playlist and its tracks to Supabase
  static Future<void> _pushPlaylistToCloud(UserPlaylist pl, String userId) async {
    final c = SupabaseService.client;
    if (c == null) return;

    try {
      await c.from('user_playlists').upsert({
        'id': pl.id,
        'user_id': userId,
        'title': pl.title,
        'thumbnail_url': pl.coverUrl,
      });

      if (pl.tracks.isNotEmpty) {
        final trackRows = pl.tracks.map((song) => {
          'playlist_id': pl.id,
          'track_id': song.id,
          'title': song.title,
          'artist': song.artist,
          'artwork_url': song.coverUrl,
          'stream_url': song.streamUrl,
          'source_type': song.source,
        }).toList();

        await c.from('playlist_tracks').upsert(
          trackRows,
          onConflict: 'playlist_id, track_id',
        );
      }
    } catch (e) {
      debugPrint('[PlaylistSyncService] _pushPlaylistToCloud error: $e');
    }
  }

  /// Creates a playlist with instant local caching and asynchronous Supabase cloud commit
  static Future<UserPlaylist> createPlaylist(String title, {List<Song>? initialTracks}) async {
    final cleanTitle = title.trim().isEmpty ? 'My Playlist' : title.trim();
    final id = _uuid.v4();
    final tracks = initialTracks != null ? List<Song>.from(initialTracks) : <Song>[];

    final playlist = UserPlaylist(
      id: id,
      title: cleanTitle,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      tracks: tracks,
    );

    // 1. Commit locally to Hive for instant offline availability
    await PlaylistManager.savePlaylistDirectly(playlist);

    // 2. Commit to Supabase cloud if user is authenticated
    final supaUser = SupabaseService.currentUser;
    if (supaUser != null) {
      _pushPlaylistToCloud(playlist, supaUser.id);
    }

    return playlist;
  }

  /// Adds a song to a playlist, immediately persisting locally and updating Supabase cloud
  static Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    final pl = PlaylistManager.getPlaylist(playlistId);
    if (pl == null) return false;

    // Prevent duplicates within the playlist
    if (pl.tracks.any((t) => t.id == song.id)) {
      return false;
    }

    pl.tracks.add(song);

    // 1. Update local cache
    await PlaylistManager.savePlaylistDirectly(pl);

    // 2. Update Supabase table `playlist_tracks`
    final supaUser = SupabaseService.currentUser;
    if (supaUser != null) {
      final c = SupabaseService.client;
      if (c != null) {
        try {
          await c.from('playlist_tracks').upsert({
            'playlist_id': playlistId,
            'track_id': song.id,
            'title': song.title,
            'artist': song.artist,
            'artwork_url': song.coverUrl,
            'stream_url': song.streamUrl,
            'source_type': song.source,
          });

          // Update playlist thumbnail if this was the first track
          if (pl.tracks.length == 1) {
            await c.from('user_playlists').update({
              'thumbnail_url': song.coverUrl,
            }).eq('id', playlistId);
          }
        } catch (e) {
          debugPrint('[PlaylistSyncService] addSong cloud error: $e');
        }
      }
    }

    return true;
  }

  /// Removes a song from a playlist, persisting locally and removing from Supabase
  static Future<bool> removeSongFromPlaylist(String playlistId, String songId) async {
    final pl = PlaylistManager.getPlaylist(playlistId);
    if (pl == null) return false;

    pl.tracks.removeWhere((t) => t.id == songId);

    // 1. Update local cache
    await PlaylistManager.savePlaylistDirectly(pl);

    // 2. Delete from Supabase table `playlist_tracks`
    final supaUser = SupabaseService.currentUser;
    if (supaUser != null) {
      final c = SupabaseService.client;
      if (c != null) {
        try {
          await c
              .from('playlist_tracks')
              .delete()
              .eq('playlist_id', playlistId)
              .eq('track_id', songId);
        } catch (e) {
          debugPrint('[PlaylistSyncService] removeSong cloud error: $e');
        }
      }
    }

    return true;
  }

  /// Deletes a playlist permanently from local storage and Supabase cloud
  static Future<bool> deletePlaylist(String playlistId) async {
    // 1. Delete from local cache
    await PlaylistManager.deletePlaylistDirectly(playlistId);

    // 2. Delete from Supabase table `user_playlists` (cascades to playlist_tracks)
    final supaUser = SupabaseService.currentUser;
    if (supaUser != null) {
      final c = SupabaseService.client;
      if (c != null) {
        try {
          await c.from('user_playlists').delete().eq('id', playlistId);
        } catch (e) {
          debugPrint('[PlaylistSyncService] deletePlaylist cloud error: $e');
        }
      }
    }

    return true;
  }

  /// Renames a playlist in local storage and Supabase cloud
  static Future<bool> renamePlaylist(String playlistId, String newTitle) async {
    final clean = newTitle.trim();
    if (clean.isEmpty) return false;

    final pl = PlaylistManager.getPlaylist(playlistId);
    if (pl == null) return false;

    pl.title = clean;

    // 1. Update local cache
    await PlaylistManager.savePlaylistDirectly(pl);

    // 2. Update Supabase table `user_playlists`
    final supaUser = SupabaseService.currentUser;
    if (supaUser != null) {
      final c = SupabaseService.client;
      if (c != null) {
        try {
          await c.from('user_playlists').update({'title': clean}).eq('id', playlistId);
        } catch (e) {
          debugPrint('[PlaylistSyncService] renamePlaylist cloud error: $e');
        }
      }
    }

    return true;
  }
}
