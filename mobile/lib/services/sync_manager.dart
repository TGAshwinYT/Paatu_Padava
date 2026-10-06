import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/track_entity.dart';
import '../models/song.dart';
import 'auth_manager.dart';
import 'favorites_manager.dart';
import 'history_manager.dart';
import 'playlist_manager.dart';
import 'supabase_service.dart';
import 'error_handler.dart';
import 'app_logger.dart';

enum SyncStatus { idle, syncing, synced, offline, error }

/// Unified Cloud Sync Manager for Paatu Paadava
/// Consolidates all cloud library operations into a single architectural component:
/// - Single joined query (eliminates N+1 fetch) for fast, scalable synchronization.
/// - Defense-in-depth user-scoped mutations (.eq('user_id', ...) & row id).
/// - Reactive sync status notifier (SyncStatus.syncing, synced, offline, error) for UI visibility.
class SyncManager {
  static const Uuid _uuid = Uuid();
  static bool _isSyncing = false;

  static final ValueNotifier<SyncStatus> syncStatusNotifier =
      ValueNotifier<SyncStatus>(SyncStatus.idle);
  static final ValueNotifier<String?> syncErrorNotifier =
      ValueNotifier<String?>(null);

  static bool get isSyncing => _isSyncing;
  static SyncStatus get status => syncStatusNotifier.value;

  /// High-efficiency library synchronization:
  /// Performs a single joined query to fetch playlists and all associated tracks at once.
  static Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;
    syncStatusNotifier.value = SyncStatus.syncing;
    syncErrorNotifier.value = null;

    try {
      final supaUser = SupabaseService.currentUser;
      if (supaUser == null) {
        debugPrint('[SyncManager] No authenticated Supabase session. State is offline.');
        syncStatusNotifier.value = SyncStatus.offline;
        _isSyncing = false;
        return;
      }

      final client = SupabaseService.client;
      if (client == null) {
        syncStatusNotifier.value = SyncStatus.offline;
        _isSyncing = false;
        return;
      }

      debugPrint('[SyncManager] Syncing library via joined query for user ${supaUser.id}...');

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
        }
      } catch (e) {
        debugPrint('[SyncManager] Favorite artists sync notice: $e');
      }

      // ================= 2. Scalable Joined Playlists & Tracks Query ================= //
      // Single joined query: selects playlists and embeds playlist_tracks(*) in one network request!
      List<dynamic> remotePlaylists = [];
      try {
        remotePlaylists = await client
            .from('playlists')
            .select('id, user_id, title, cover_url, is_collaborative, invite_code, created_at, playlist_tracks(id, track_id, title, artist, artwork_url, stream_url, source_type, added_at, position, added_by)')
            .eq('user_id', supaUser.id)
            .order('created_at', ascending: false);
      } catch (e) {
        AppLogger.log('SyncManager', 'Playlists added_by select fallback: $e');
        // Fallback for older schema without added_by column
        remotePlaylists = await client
            .from('playlists')
            .select('id, user_id, title, cover_url, is_collaborative, invite_code, created_at, playlist_tracks(id, track_id, title, artist, artwork_url, stream_url, source_type, added_at, position)')
            .eq('user_id', supaUser.id)
            .order('created_at', ascending: false);
      }

      final Map<String, UserPlaylist> reconciledMap = {};

      for (final pl in remotePlaylists) {
        final plId = pl['id']?.toString() ?? '';
        final plTitle = TrackEntity.sanitize(pl['title'], fallback: 'Untitled Playlist');
        final createdAtStr = pl['created_at']?.toString();
        final createdAtMs = createdAtStr != null
            ? (DateTime.tryParse(createdAtStr)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch)
            : DateTime.now().millisecondsSinceEpoch;

        // Tracks are directly populated from the joined relation (no N+1 query loop!)
        final List<dynamic> tracksData = pl['playlist_tracks'] as List<dynamic>? ?? [];
        tracksData.sort((a, b) => ((a['position'] ?? 0) as num).compareTo((b['position'] ?? 0) as num));

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
            addedBy: t['added_by']?.toString(),
          );
        }).toList();

        reconciledMap[plId] = UserPlaylist(
          id: plId,
          title: plTitle,
          createdAt: createdAtMs,
          tracks: tracks,
          isCollaborative: pl['is_collaborative'] == true,
          inviteCode: pl['invite_code']?.toString(),
          ownerId: pl['user_id']?.toString(),
        );
      }

      // 3. Check local offline-created playlists and push up to Supabase
      final localPlaylists = PlaylistManager.getPlaylists();
      for (final local in localPlaylists) {
        if (!reconciledMap.containsKey(local.id)) {
          await pushPlaylistToCloud(local, supaUser.id);
          reconciledMap[local.id] = local;
        }
      }

      // 4. Commit unified state down into local Hive cache
      for (final pl in reconciledMap.values) {
        await PlaylistManager.savePlaylistDirectly(pl);
      }

      PlaylistManager.refreshList();

      // ================= 3. Sync Liked Songs / Favorites ================= //
      try {
        await FavoritesManager.syncWithCloud();
      } catch (e) {
        debugPrint('[SyncManager] Favorites sync notice: $e');
      }

      // ================= 4. Sync Listening History ================= //
      try {
        await HistoryManager.syncCloudHistory();
      } catch (e) {
        debugPrint('[SyncManager] History sync notice: $e');
      }

      syncStatusNotifier.value = SyncStatus.synced;
      debugPrint('[SyncManager] Joined sync finished: ${reconciledMap.length} playlists, favorites, and history synchronized.');
    } catch (e) {
      debugPrint('[SyncManager] Sync failed: $e');
      syncErrorNotifier.value = ErrorHandler.resolve(e).userMessage;
      syncStatusNotifier.value = SyncStatus.error;
    } finally {
      _isSyncing = false;
    }
  }

  // ================= Direct User-Scoped Mutations ================= //

  /// Creates a playlist with instant local persistence and asynchronous Supabase cloud sync
  /// Idempotently reuses existing playlist if title already exists, preventing duplicates
  static Future<UserPlaylist> createPlaylist(String title, {List<Song>? initialTracks}) async {
    final cleanTitle = title.trim().isEmpty ? 'My Playlist' : title.trim();

    // Idempotency check: Does a playlist with this title already exist?
    final existingList = PlaylistManager.getPlaylists();
    UserPlaylist? existing;
    for (final p in existingList) {
      if (p.title.trim().toLowerCase() == cleanTitle.toLowerCase()) {
        existing = p;
        break;
      }
    }

    if (existing != null) {
      // If playlist already exists, append new tracks without creating a duplicate!
      if (initialTracks != null && initialTracks.isNotEmpty) {
        for (final track in initialTracks) {
          if (!existing.tracks.any((t) => t.id == track.id)) {
            existing.tracks.add(track);
          }
        }
        await PlaylistManager.savePlaylistDirectly(existing);

        final supaUser = SupabaseService.currentUser;
        if (supaUser != null) {
          await pushPlaylistToCloud(existing, supaUser.id);
        }
      }
      return existing;
    }

    final id = _uuid.v4();
    final tracks = initialTracks != null ? List<Song>.from(initialTracks) : <Song>[];

    final playlist = UserPlaylist(
      id: id,
      title: cleanTitle,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      tracks: tracks,
    );

    // 1. Commit locally to Hive for zero-latency offline access
    await PlaylistManager.savePlaylistDirectly(playlist);

    // 2. Commit to Supabase if authenticated
    final supaUser = SupabaseService.currentUser;
    if (supaUser != null) {
      await pushPlaylistToCloud(playlist, supaUser.id);
    }

    return playlist;
  }

  /// Adds a song to a playlist, persisting locally and writing to Supabase.
  /// Prevents concurrent duplicates and records user attribution.
  static Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    final pl = PlaylistManager.getPlaylist(playlistId);
    if (pl == null) return false;

    // 1. Local duplicate prevention
    if (pl.tracks.any((t) => t.id == song.id)) {
      return false; // Prevent duplicates within the playlist
    }

    final client = SupabaseService.client;
    final supaUser = SupabaseService.currentUser;

    // 2. Concurrent remote duplicate check for collaborative playlists
    if (pl.isCollaborative && client != null) {
      try {
        final remoteCheck = await client
            .from('playlist_tracks')
            .select('id')
            .eq('playlist_id', playlistId)
            .eq('track_id', song.id)
            .limit(1);
        if (remoteCheck.isNotEmpty) {
          debugPrint('[SyncManager] Duplicate track detected in remote playlist, skipping add.');
          return false;
        }
      } catch (e) {
        debugPrint('[SyncManager] Remote duplicate check notice: $e');
      }
    }

    final localUser = AuthManager.currentUser;
    final addedByName = song.addedBy ??
        (localUser != null && localUser.username.isNotEmpty ? localUser.username : null) ??
        (localUser != null && localUser.email.isNotEmpty ? localUser.email.split('@').first : null) ??
        'Collaborator';

    final trackToAdd = song.copyWith(addedBy: addedByName);
    final newPosition = pl.tracks.length;
    pl.tracks.add(trackToAdd);
    await PlaylistManager.savePlaylistDirectly(pl);

    if (supaUser != null && client != null) {
      try {
        // Try inserting with added_by column
        await client.from('playlist_tracks').upsert({
          'id': _uuid.v4(),
          'playlist_id': playlistId,
          'track_id': song.id,
          'title': TrackEntity.sanitize(song.title),
          'artist': TrackEntity.sanitize(song.artist),
          'artwork_url': song.coverUrl,
          'stream_url': song.streamUrl,
          'source_type': song.source,
          'position': newPosition,
          'added_by': addedByName,
        }, onConflict: 'playlist_id, track_id');

        if (pl.tracks.length == 1) {
          await client
              .from('playlists')
              .update({'cover_url': song.coverUrl})
              .eq('id', playlistId)
              .eq('user_id', supaUser.id);
        }
      } catch (e) {
        // Fallback for database schema without added_by column
        try {
          await client.from('playlist_tracks').upsert({
            'id': _uuid.v4(),
            'playlist_id': playlistId,
            'track_id': song.id,
            'title': TrackEntity.sanitize(song.title),
            'artist': TrackEntity.sanitize(song.artist),
            'artwork_url': song.coverUrl,
            'stream_url': song.streamUrl,
            'source_type': song.source,
            'position': newPosition,
          }, onConflict: 'playlist_id, track_id');
        } catch (err) {
          debugPrint('[SyncManager] Remote track insert notice: $err');
        }
      }
    }
    return true;
  }

  /// Removes a song from a playlist, updating local Hive and Supabase
  static Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final pl = PlaylistManager.getPlaylist(playlistId);
    if (pl == null) return;

    pl.tracks.removeWhere((t) => t.id == songId);
    await PlaylistManager.savePlaylistDirectly(pl);

    final client = SupabaseService.client;
    if (client != null) {
      try {
        await client
            .from('playlist_tracks')
            .delete()
            .eq('playlist_id', playlistId)
            .eq('track_id', songId);
      } catch (e) {
        debugPrint('[SyncManager] Remote track delete notice: $e');
      }
    }
  }

  /// Renames a playlist with user-scoped defense in depth
  static Future<void> renamePlaylist(String playlistId, String newTitle) async {
    final pl = PlaylistManager.getPlaylist(playlistId);
    if (pl == null) return;

    pl.title = newTitle.trim().isEmpty ? 'Untitled Playlist' : newTitle.trim();
    await PlaylistManager.savePlaylistDirectly(pl);

    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser != null && client != null) {
      try {
        await client
            .from('playlists')
            .update({'title': pl.title})
            .eq('id', playlistId)
            .eq('user_id', supaUser.id);
      } catch (e) {
        debugPrint('[SyncManager] Remote rename notice: $e');
      }
    }
  }

  /// Deletes a playlist with user-scoped defense in depth and cascading cloud deletion
  static Future<void> deletePlaylist(String playlistId) async {
    await PlaylistManager.deletePlaylistDirectly(playlistId);

    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser != null && client != null) {
      try {
        await client
            .from('playlists')
            .delete()
            .eq('id', playlistId)
            .eq('user_id', supaUser.id);
      } catch (e) {
        debugPrint('[SyncManager] Remote delete notice: $e');
      }
    }
  }

  /// Pushes a local playlist and all its tracks up to Supabase
  /// Enforces ON CONFLICT (user_id, title) to update existing instead of creating duplicate
  static Future<void> pushPlaylistToCloud(UserPlaylist pl, String userId) async {
    final client = SupabaseService.client;
    if (client == null) return;

    try {
      await client.from('playlists').upsert({
        'id': pl.id,
        'user_id': userId,
        'title': pl.title,
        'cover_url': pl.coverUrl,
      }, onConflict: 'user_id, title');

      if (pl.tracks.isNotEmpty) {
        final trackRows = pl.tracks.asMap().entries.map((entry) {
          final idx = entry.key;
          final song = entry.value;
          return {
            'id': _uuid.v4(),
            'playlist_id': pl.id,
            'track_id': song.id,
            'title': TrackEntity.sanitize(song.title),
            'artist': TrackEntity.sanitize(song.artist),
            'artwork_url': song.coverUrl,
            'stream_url': song.streamUrl,
            'source_type': song.source,
            'position': idx,
          };
        }).toList();

        await client.from('playlist_tracks').upsert(
          trackRows,
          onConflict: 'playlist_id, track_id',
        );
      }
    } catch (e) {
      debugPrint('[SyncManager] pushPlaylistToCloud notice: $e');
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

      if (rows.isNotEmpty) {
        await client.from('user_favorite_artists').upsert(
          rows,
          onConflict: 'user_id, artist_name',
        );
      }
    } catch (e) {
      debugPrint('[SyncManager] mirrorFavoriteArtists notice: $e');
    }
  }
}
