import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/track_entity.dart';
import '../models/song.dart';
import 'supabase_service.dart';

/// Unified Favorites Manager for Paatu Paadava.
/// Supports zero-latency local Hive operations with bi-directional Supabase cloud sync (`liked_songs`).
class FavoritesManager {
  static const String boxName = 'favorite_songs';
  static final ValueNotifier<List<Song>> favoritesNotifier = ValueNotifier<List<Song>>([]);
  static const Uuid _uuid = Uuid();
  static bool _isSyncing = false;

  static Future<void> init() async {
    await Hive.openBox(boxName);
    _refreshList();
  }

  static Box get _box => Hive.box(boxName);

  static void _refreshList() {
    final List<Song> list = [];
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data != null && data is Map) {
        try {
          list.add(Song.fromMap(data));
        } catch (_) {}
      }
    }
    favoritesNotifier.value = list;
  }

  static bool isFavorite(String songId) {
    return _box.containsKey(songId);
  }

  static Future<bool> toggleFavorite(Song song) async {
    if (isFavorite(song.id)) {
      await _box.delete(song.id);
      _refreshList();
      _deleteFavoriteFromCloud(song.id);
      return false;
    } else {
      await _box.put(song.id, song.toMap());
      _refreshList();
      _pushFavoriteToCloud(song);
      return true;
    }
  }

  static List<Song> getFavorites() {
    return List.from(favoritesNotifier.value);
  }

  /// Asynchronously push a favorite addition to Supabase
  static void _pushFavoriteToCloud(Song song) {
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser == null || client == null) return;

    Future(() async {
      try {
        await client.from('liked_songs').upsert({
          'id': _uuid.v4(),
          'user_id': supaUser.id,
          'yt_video_id': song.id,
          'title': TrackEntity.sanitize(song.title),
          'artist': TrackEntity.sanitize(song.artist),
          'cover_url': song.coverUrl,
          'audio_url': song.streamUrl,
          'language': song.language ?? '',
        }, onConflict: 'user_id,yt_video_id');
      } catch (e) {
        debugPrint('[FavoritesManager] Cloud favorite push notice: $e');
      }
    });
  }

  /// Asynchronously delete a favorite from Supabase
  static void _deleteFavoriteFromCloud(String songId) {
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser == null || client == null) return;

    Future(() async {
      try {
        await client
            .from('liked_songs')
            .delete()
            .eq('user_id', supaUser.id)
            .eq('yt_video_id', songId);
      } catch (e) {
        debugPrint('[FavoritesManager] Cloud favorite delete notice: $e');
      }
    });
  }

  /// Bi-directional synchronization with Supabase `liked_songs`:
  /// - Downloads remote favorites not present in local Hive.
  /// - Uploads local favorites created while offline to Supabase.
  static Future<void> syncWithCloud() async {
    if (_isSyncing) return;
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser == null || client == null) return;

    _isSyncing = true;
    try {
      // 1. Fetch remote favorites
      final List<dynamic> remoteData = await client
          .from('liked_songs')
          .select('id, yt_video_id, title, artist, cover_url, audio_url, language')
          .eq('user_id', supaUser.id);

      final Set<String> remoteTrackIds = {};

      for (final item in remoteData) {
        final trackId = item['yt_video_id']?.toString() ?? '';
        if (trackId.isEmpty) continue;
        remoteTrackIds.add(trackId);

        if (!_box.containsKey(trackId)) {
          final song = Song(
            id: trackId,
            title: TrackEntity.sanitize(item['title'], fallback: 'Unknown Song'),
            artist: TrackEntity.sanitize(item['artist'], fallback: 'Various Artists'),
            album: '',
            duration: 0,
            coverUrl: item['cover_url']?.toString() ?? '',
            streamUrl: item['audio_url']?.toString(),
            language: item['language']?.toString(),
          );
          await _box.put(trackId, song.toMap());
        }
      }

      // 2. Upload any local offline favorites to remote
      final List<Song> localFavorites = getFavorites();
      for (final local in localFavorites) {
        if (!remoteTrackIds.contains(local.id)) {
          try {
            await client.from('liked_songs').upsert({
              'id': _uuid.v4(),
              'user_id': supaUser.id,
              'yt_video_id': local.id,
              'title': TrackEntity.sanitize(local.title),
              'artist': TrackEntity.sanitize(local.artist),
              'cover_url': local.coverUrl,
              'audio_url': local.streamUrl,
              'language': local.language ?? '',
            }, onConflict: 'user_id,yt_video_id');
          } catch (e) {
            debugPrint('[FavoritesManager] Local favorite cloud sync notice: $e');
          }
        }
      }

      _refreshList();
      debugPrint('[FavoritesManager] Synced ${remoteTrackIds.length} remote and ${localFavorites.length} local favorites.');
    } catch (e) {
      debugPrint('[FavoritesManager] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Clears local favorites cache (e.g. on logout or fresh guest login)
  static Future<void> clearLocal() async {
    try {
      await _box.clear();
      favoritesNotifier.value = [];
    } catch (_) {}
  }
}
