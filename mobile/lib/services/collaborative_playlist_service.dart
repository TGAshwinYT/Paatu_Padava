import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/track_entity.dart';
import '../models/song.dart';
import 'playlist_manager.dart';
import 'supabase_service.dart';
import 'app_logger.dart';

/// Real-time Collaborative Playlist Coordinator.
/// Manages invite code generation, join flows, and live Supabase Realtime
/// subscriptions for instant multi-user playlist synchronization.
class CollaborativePlaylistService {
  static final Random _random = Random.secure();

  /// Generates a human-readable 6-character alphanumeric invite code (e.g. "PP-9K2M")
  static String generateInviteCode() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // excludes ambiguous chars 0, 1, I, O
    final randStr = String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
    );
    return 'PP-$randStr';
  }

  /// Enables collaboration on an existing playlist, generating a sharable invite code
  static Future<UserPlaylist?> enableCollaboration(String playlistId) async {
    final playlist = PlaylistManager.getPlaylist(playlistId);
    if (playlist == null) return null;

    final code = playlist.inviteCode ?? generateInviteCode();
    final updated = playlist.copyWith(
      isCollaborative: true,
      inviteCode: code,
    );

    // Save locally
    await PlaylistManager.savePlaylistDirectly(updated);

    // Update in Supabase cloud
    final client = SupabaseService.client;
    final supaUser = SupabaseService.currentUser;
    if (client != null && supaUser != null && !supaUser.isAnonymous) {
      try {
        await client.from('playlists').update({
          'is_public': true,
          'is_collaborative': true,
          'invite_code': code,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', playlistId).eq('user_id', supaUser.id);
      } catch (e) {
        debugPrint('[CollaborativePlaylistService] enableCollaboration cloud update notice: $e');
      }
    }

    return updated;
  }

  /// Disables collaboration on a playlist
  static Future<UserPlaylist?> disableCollaboration(String playlistId) async {
    final playlist = PlaylistManager.getPlaylist(playlistId);
    if (playlist == null) return null;

    final updated = playlist.copyWith(
      isCollaborative: false,
    );

    // Save locally
    await PlaylistManager.savePlaylistDirectly(updated);

    // Update in Supabase cloud
    final client = SupabaseService.client;
    final supaUser = SupabaseService.currentUser;
    if (client != null && supaUser != null && !supaUser.isAnonymous) {
      try {
        await client.from('playlists').update({
          'is_collaborative': false,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', playlistId).eq('user_id', supaUser.id);
      } catch (e) {
        debugPrint('[CollaborativePlaylistService] disableCollaboration cloud notice: $e');
      }
    }

    return updated;
  }

  /// Joins a collaborative playlist using an invite code and pulls its tracks
  static Future<UserPlaylist> joinPlaylistByCode(String rawCode) async {
    final cleanCode = rawCode.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      throw Exception('Please enter a valid invite code');
    }

    final client = SupabaseService.client;
    if (client == null) {
      throw Exception('Cloud sync is offline. Sign in to join collaborative playlists.');
    }

    // 1. Query playlist by invite_code with joined tracks (with resilient fallback for added_by column)
    List<dynamic> rows;
    try {
      rows = await client
          .from('playlists')
          .select('id, user_id, title, cover_url, is_collaborative, invite_code, created_at, playlist_tracks(id, track_id, title, artist, artwork_url, stream_url, source_type, position, added_by)')
          .eq('invite_code', cleanCode)
          .limit(1);
    } catch (e) {
      AppLogger.log('CollaborativePlaylistService', 'Column added_by select fallback: $e');
      rows = await client
          .from('playlists')
          .select('id, user_id, title, cover_url, is_collaborative, invite_code, created_at, playlist_tracks(id, track_id, title, artist, artwork_url, stream_url, source_type, position)')
          .eq('invite_code', cleanCode)
          .limit(1);
    }

    if (rows.isEmpty) {
      throw Exception('No collaborative playlist found for code "$cleanCode"');
    }

    final row = rows.first;
    final plId = row['id']?.toString() ?? '';
    final plTitle = TrackEntity.sanitize(row['title'], fallback: 'Shared Playlist');
    final createdAtStr = row['created_at']?.toString();
    final createdAtMs = createdAtStr != null
        ? (DateTime.tryParse(createdAtStr)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch)
        : DateTime.now().millisecondsSinceEpoch;

    final List<dynamic> rawTracks = row['playlist_tracks'] as List<dynamic>? ?? [];
    rawTracks.sort((a, b) => ((a['position'] ?? 0) as num).compareTo((b['position'] ?? 0) as num));

    final List<Song> tracks = rawTracks.map((t) {
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

    final playlist = UserPlaylist(
      id: plId,
      title: plTitle,
      createdAt: createdAtMs,
      tracks: tracks,
      isCollaborative: true,
      inviteCode: cleanCode,
      ownerId: row['user_id']?.toString(),
    );

    // Save into local Hive cache
    await PlaylistManager.savePlaylistDirectly(playlist);

    return playlist;
  }

  /// Subscribes to Supabase Realtime Postgres Changes for a collaborative playlist.
  /// Fires [onTracksUpdated] immediately when any collaborator adds, deletes, or reorders tracks.
  /// Fires [onConnectionStatusChanged] when channel connects, disconnects, or reconnects.
  static RealtimeChannel? subscribeToPlaylist({
    required String playlistId,
    required void Function(List<Song> updatedTracks) onTracksUpdated,
    void Function(bool isConnected)? onConnectionStatusChanged,
  }) {
    final client = SupabaseService.client;
    if (client == null) return null;

    try {
      final channel = client.channel('collab:$playlistId');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'playlist_tracks',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'playlist_id',
          value: playlistId,
        ),
        callback: (payload) async {
          debugPrint('[CollaborativePlaylistService] Realtime update event received on playlist $playlistId');
          await _fetchAndBroadcastTracks(client, playlistId, onTracksUpdated);
        },
      );

      channel.subscribe((status, [error]) async {
        debugPrint('[CollaborativePlaylistService] Subscription status for $playlistId: $status (error: $error)');
        final isSubscribed = status == RealtimeSubscribeStatus.subscribed;
        onConnectionStatusChanged?.call(isSubscribed);

        if (isSubscribed) {
          // Reconcile on initial connect or after reconnecting from network drop
          await _fetchAndBroadcastTracks(client, playlistId, onTracksUpdated);
        }
      });

      return channel;
    } catch (e) {
      debugPrint('[CollaborativePlaylistService] Subscription error: $e');
      return null;
    }
  }

  /// Refetches tracks from Supabase, updates local Hive cache, and notifies listeners.
  static Future<void> _fetchAndBroadcastTracks(
    SupabaseClient client,
    String playlistId,
    void Function(List<Song> updatedTracks) onTracksUpdated,
  ) async {
    try {
      List<dynamic> trackRows;
      try {
        trackRows = await client
            .from('playlist_tracks')
            .select('id, track_id, title, artist, artwork_url, stream_url, source_type, position, added_by')
            .eq('playlist_id', playlistId)
            .order('position', ascending: true);
      } catch (e) {
        AppLogger.log('CollaborativePlaylistService', 'playlist_tracks added_by select fallback: $e');
        trackRows = await client
            .from('playlist_tracks')
            .select('id, track_id, title, artist, artwork_url, stream_url, source_type, position')
            .eq('playlist_id', playlistId)
            .order('position', ascending: true);
      }

      final updatedSongs = trackRows.map((t) {
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

      // Update local playlist
      final local = PlaylistManager.getPlaylist(playlistId);
      if (local != null) {
        final newLocal = local.copyWith(tracks: updatedSongs);
        await PlaylistManager.savePlaylistDirectly(newLocal);
      }

      onTracksUpdated(updatedSongs);
    } catch (e) {
      debugPrint('[CollaborativePlaylistService] Refresh tracks error: $e');
    }
  }

  /// Unsubscribes from Realtime channel safely
  static void unsubscribe(RealtimeChannel? channel) {
    if (channel == null) return;
    try {
      SupabaseService.client?.removeChannel(channel);
    } catch (e) {
      AppLogger.log('CollaborativePlaylistService', 'Channel unsubscribe notice: $e');
    }
  }
}
