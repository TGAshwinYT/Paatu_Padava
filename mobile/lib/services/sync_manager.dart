import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/track_entity.dart';
import '../models/song.dart';
import 'auth_manager.dart';
import 'playlist_manager.dart';
import 'supabase_service.dart';

/// Clean Architecture Cloud Sync Manager
/// Connects Supabase tables (user_playlists, playlist_tracks, user_favorite_artists).
/// Enforces bidirectional synchronization: pulls remote library on login/launch,
/// and mirrors local writes to Supabase honoring PostgreSQL Row Level Security.
class SyncManager {
  static const Uuid _uuid = Uuid();
  static bool _isSyncing = false;

  static bool get isSyncing => _isSyncing;

  /// Pulls remote user library from Supabase and reconciles with local Hive offline storage.
  /// Triggered on app initialization and after successful authentication events.
  static Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final supaUser = SupabaseService.currentUser;
      if (supaUser == null) {
        debugPrint('[SyncManager] No authenticated Supabase session. Skipping cloud sync.');
        _isSyncing = false;
        return;
      }

      final client = SupabaseService.client;
      if (client == null) {
        _isSyncing = false;
        return;
      }

      debugPrint('[SyncManager] Starting bidirectional library synchronization for user ${supaUser.id}...');

      // ================= 1. Sync User Favorite Artists ================= //
      try {
        final List<dynamic> remoteArtists = await client
            .from('user_favorite_artists')
            .select('artist_name, artist_image_url')
            .eq('user_id', supaUser.id);

        final List<String> remoteArtistNames = remoteArtists
            .map((a) => a['artist_name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();

        if (remoteArtistNames.isNotEmpty) {
          final localArtists = AuthManager.currentUser?.favoriteArtists ?? [];
          final combined = {...localArtists, ...remoteArtistNames}.toList();
          await AuthManager.updateArtistPreferences(combined);
          debugPrint('[SyncManager] Synced ${combined.length} favorite artists with Supabase');
        }
      } catch (e) {
        debugPrint('[SyncManager] Error syncing favorite artists: $e');
      }

      // ================= 2. Sync Cloud Playlists & Tracks ================= //
      try {
        final List<dynamic> remotePlaylists = await client
            .from('user_playlists')
            .select('id, title, thumbnail_url, created_at')
            .eq('user_id', supaUser.id)
            .order('created_at', ascending: false);

        final Map<String, UserPlaylist> reconciledMap = {};

        for (final pl in remotePlaylists) {
          final plId = pl['id']?.toString() ?? '';
          final plTitle = TrackEntity.sanitize(pl['title'], fallback: 'Untitled Playlist');
          final createdAtStr = pl['created_at']?.toString();
          final createdAtMs = createdAtStr != null
              ? (DateTime.tryParse(createdAtStr)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch)
              : DateTime.now().millisecondsSinceEpoch;

          // Fetch all tracks belonging to this remote playlist
          final List<dynamic> tracksData = await client
              .from('playlist_tracks')
              .select('track_id, title, artist, artwork_url, stream_url, source_type, added_at')
              .eq('playlist_id', plId)
              .order('added_at', ascending: true);

          final List<Song> tracks = tracksData.map((t) {
            return Song(
              id: t['track_id']?.toString() ?? '',
              title: TrackEntity.sanitize(t['title'], fallback: 'Unknown Track'),
              artist: TrackEntity.sanitize(t['artist'], fallback: 'Various Artists'),
              album: '',
              duration: 0,
              coverUrl: t['artwork_url']?.toString() ?? '',
              streamUrl: t['stream_url']?.toString(),
              source: t['source_type']?.toString() ?? 'saavn',
            );
          }).toList();

          reconciledMap[plId] = UserPlaylist(
            id: plId,
            title: plTitle,
            createdAt: createdAtMs,
            tracks: tracks,
          );
        }

        // Check local playlists created offline: mirror them to Supabase
        final localPlaylists = PlaylistManager.getPlaylists();
        for (final local in localPlaylists) {
          if (!reconciledMap.containsKey(local.id)) {
            await pushPlaylistToCloud(local, supaUser.id);
            reconciledMap[local.id] = local;
          }
        }

        // Commit unified library state into local Hive cache
        for (final pl in reconciledMap.values) {
          await PlaylistManager.savePlaylistDirectly(pl);
        }

        PlaylistManager.refreshList();
        debugPrint('[SyncManager] Synced ${reconciledMap.length} playlists with Supabase');
      } catch (e) {
        debugPrint('[SyncManager] Error syncing playlists: $e');
      }
    } catch (e) {
      debugPrint('[SyncManager] General sync failure: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ================= Local -> Cloud Mutation Mirrors ================= //

  /// Mirror new playlist creation to Supabase
  static Future<void> mirrorPlaylistCreated(UserPlaylist playlist) async {
    final supaUser = SupabaseService.currentUser;
    if (supaUser == null) return;
    await pushPlaylistToCloud(playlist, supaUser.id);
  }

  /// Mirror playlist title update to Supabase
  static Future<void> mirrorPlaylistRenamed(String playlistId, String newTitle) async {
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser == null || client == null) return;

    try {
      await client
          .from('user_playlists')
          .update({'title': newTitle})
          .eq('id', playlistId)
          .eq('user_id', supaUser.id);
    } catch (e) {
      debugPrint('[SyncManager] Remote rename failed: $e');
    }
  }

  /// Mirror playlist deletion to Supabase
  static Future<void> mirrorPlaylistDeleted(String playlistId) async {
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser == null || client == null) return;

    try {
      await client
          .from('user_playlists')
          .delete()
          .eq('id', playlistId)
          .eq('user_id', supaUser.id);
    } catch (e) {
      debugPrint('[SyncManager] Remote delete failed: $e');
    }
  }

  /// Mirror track addition to Supabase
  static Future<void> mirrorTrackAdded(String playlistId, Song song) async {
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser == null || client == null) return;

    try {
      await client.from('playlist_tracks').insert({
        'id': _uuid.v4(),
        'playlist_id': playlistId,
        'track_id': song.id,
        'title': TrackEntity.sanitize(song.title),
        'artist': TrackEntity.sanitize(song.artist),
        'artwork_url': song.coverUrl,
        'stream_url': song.streamUrl,
        'source_type': song.source,
      });

      // Update thumbnail of playlist if it's the first track
      await client
          .from('user_playlists')
          .update({'thumbnail_url': song.coverUrl})
          .eq('id', playlistId)
          .eq('user_id', supaUser.id);
    } catch (e) {
      debugPrint('[SyncManager] Remote track insert failed: $e');
    }
  }

  /// Mirror track removal from Supabase
  static Future<void> mirrorTrackRemoved(String playlistId, String trackId) async {
    final client = SupabaseService.client;
    if (client == null) return;

    try {
      await client
          .from('playlist_tracks')
          .delete()
          .eq('playlist_id', playlistId)
          .eq('track_id', trackId);
    } catch (e) {
      debugPrint('[SyncManager] Remote track deletion failed: $e');
    }
  }

  /// Mirror user favorite artists selection directly into Supabase
  static Future<void> mirrorFavoriteArtists(List<Map<String, String>> artists) async {
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser == null || client == null || artists.isEmpty) return;

    try {
      final rows = artists.map((a) => {
        'user_id': supaUser.id,
        'artist_name': TrackEntity.sanitize(a['name'] ?? ''),
        'artist_image_url': a['image'] ?? '',
      }).where((r) => (r['artist_name'] as String).isNotEmpty).toList();

      await client.from('user_favorite_artists').upsert(
        rows,
        onConflict: 'user_id, artist_name',
      );
      debugPrint('[SyncManager] Mirrored ${rows.length} favorite artists to Supabase');
    } catch (e) {
      debugPrint('[SyncManager] Remote artist upsert failed: $e');
    }
  }

  /// Helper to push a complete local playlist entity to Supabase cloud
  static Future<void> pushPlaylistToCloud(UserPlaylist pl, String userId) async {
    final client = SupabaseService.client;
    if (client == null) return;

    try {
      await client.from('user_playlists').upsert({
        'id': pl.id,
        'user_id': userId,
        'title': pl.title,
        'thumbnail_url': pl.coverUrl,
      });

      if (pl.tracks.isNotEmpty) {
        final trackRows = pl.tracks.map((t) => {
          'id': _uuid.v4(),
          'playlist_id': pl.id,
          'track_id': t.id,
          'title': TrackEntity.sanitize(t.title),
          'artist': TrackEntity.sanitize(t.artist),
          'artwork_url': t.coverUrl,
          'stream_url': t.streamUrl,
          'source_type': t.source,
        }).toList();

        await client.from('playlist_tracks').upsert(trackRows);
      }
    } catch (e) {
      debugPrint('[SyncManager] Push playlist to cloud failed: $e');
    }
  }
}
