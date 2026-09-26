import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/track_entity.dart';
import '../models/song.dart';
import 'api_client.dart';
import 'auth_manager.dart';
import 'supabase_service.dart';

/// Unified Listening History Manager for Paatu Paadava.
/// Coordinates instant local Hive caching with Supabase `user_history` cloud persistence,
/// retry queuing, and bi-directional restoration on fresh installs.
class HistoryManager {
  static const String boxName = 'history_box';
  static const String pendingBoxName = 'pending_history_box';
  static final ValueNotifier<List<Song>> historyNotifier = ValueNotifier<List<Song>>([]);
  static bool _isSyncing = false;

  static Box get _box => Hive.box(boxName);
  static Box? get _pendingBox => Hive.isBoxOpen(pendingBoxName) ? Hive.box(pendingBoxName) : null;

  static Future<void> init() async {
    await Hive.openBox(boxName);
    await Hive.openBox(pendingBoxName);
    _refreshList();

    // Background sync with cloud history if authenticated
    if (AuthManager.isLoggedIn) {
      syncCloudHistory();
    }
  }

  static void _refreshList() {
    final List<MapEntry<int, Song>> entries = [];
    int fallbackIndex = 0;
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data != null && data is Map) {
        try {
          final timestamp = (data['played_at'] is num)
              ? (data['played_at'] as num).toInt()
              : fallbackIndex++;
          entries.add(MapEntry(timestamp, Song.fromMap(data)));
        } catch (_) {}
      }
    }
    // Highest timestamp (most recent play) first
    entries.sort((a, b) => b.key.compareTo(a.key));
    historyNotifier.value = entries.map((e) => e.value).toList();
  }

  static List<Song> getHistory() => historyNotifier.value;
  static List<Song> getRecentSongs() => historyNotifier.value;

  static Future<void> clear() => clearHistory();

  /// Coordinated single write entry point for track play events:
  /// 1. Updates local Hive cache with deduplication and 100-item ceiling.
  /// 2. Asynchronously writes to Supabase `user_history` with error capture and pending retry queue.
  static Future<void> recordPlay(Song song) async {
    try {
      // 1. Remove existing duplicate key
      String? existingKey;
      for (final key in _box.keys) {
        final data = _box.get(key);
        if (data != null && data is Map && data['id'] == song.id) {
          existingKey = key.toString();
          break;
        }
      }
      if (existingKey != null) {
        await _box.delete(existingKey);
      }

      // Enforce 100 max history items in local cache
      if (_box.length >= 100) {
        final firstKey = _box.keys.first;
        await _box.delete(firstKey);
      }

      // Store new timestamped entry with explicit played_at epoch ms
      final now = DateTime.now().millisecondsSinceEpoch;
      final key = 'h_${now}_${song.id}';
      final songMap = Map<String, dynamic>.from(song.toMap());
      songMap['played_at'] = now;
      await _box.put(key, songMap);
      _refreshList();

      // 2. Coordinated Cloud Persistence
      final supaUser = SupabaseService.currentUser;
      if (supaUser != null && !supaUser.isAnonymous) {
        _persistPlayToCloud(supaUser.id, song);
      }
    } catch (e) {
      debugPrint('[HistoryManager] Local recordPlay notice: $e');
    }
  }

  /// Backward-compatibility alias
  static Future<void> addSong(Song song) => recordPlay(song);

  /// Asynchronously persists play event to Supabase, queuing for retry if network is unavailable
  static void _persistPlayToCloud(String userId, Song song) {
    Future(() async {
      try {
        await SupabaseService.recordUserHistory(userId, song);
      } catch (e) {
        debugPrint('[HistoryManager] Cloud history write failed, queuing for retry: $e');
        try {
          await _pendingBox?.put(song.id, song.toMap());
        } catch (_) {}
      }

      // Feed backend ML recommendation engine
      try {
        await ApiClient.addListenHistory(song);
      } catch (_) {}
    });
  }

  /// Bi-directional history synchronization:
  /// - Flushes any pending un-synced plays to Supabase.
  /// - Pulls recent listen history from Supabase `user_history` so history survives reinstalls.
  static Future<void> syncCloudHistory() async {
    if (_isSyncing) return;
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser == null || client == null) return;

    _isSyncing = true;
    try {
      // 1. Flush pending offline plays
      if (_pendingBox != null && _pendingBox!.isNotEmpty) {
        final pendingKeys = List.from(_pendingBox!.keys);
        for (final k in pendingKeys) {
          final data = _pendingBox!.get(k);
          if (data is Map) {
            try {
              final song = Song.fromMap(data);
              await SupabaseService.recordUserHistory(supaUser.id, song);
              await _pendingBox!.delete(k);
            } catch (_) {
              break; // Stop flushing if network fails again
            }
          }
        }
      }

      // 2. Pull remote history
      final List<dynamic> remoteRows = await client
          .from('user_history')
          .select('song_id, title, artist, cover_url, source, played_at')
          .eq('user_id', supaUser.id)
          .order('played_at', ascending: false)
          .limit(50);

      final Set<String> localIds = {
        for (final s in historyNotifier.value) s.id
      };

      for (final row in remoteRows.reversed) {
        final songId = row['song_id']?.toString() ?? '';
        if (songId.isNotEmpty && !localIds.contains(songId)) {
          final song = Song(
            id: songId,
            title: TrackEntity.sanitize(row['title'], fallback: 'Unknown Song'),
            artist: TrackEntity.sanitize(row['artist'], fallback: 'Various Artists'),
            album: '',
            duration: 0,
            coverUrl: row['cover_url']?.toString() ?? '',
            source: row['source']?.toString() ?? 'saavn',
          );
          final playedAtStr = row['played_at']?.toString();
          final epochMs = playedAtStr != null
              ? (DateTime.tryParse(playedAtStr)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch)
              : DateTime.now().millisecondsSinceEpoch;
          final key = 'h_${epochMs}_$songId';
          final map = Map<String, dynamic>.from(song.toMap());
          map['played_at'] = epochMs;
          await _box.put(key, map);
          localIds.add(songId);
        }
      }

      _refreshList();
    } catch (e) {
      debugPrint('[HistoryManager] syncCloudHistory error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  static Future<void> removeSong(String songId) async {
    try {
      for (final key in _box.keys) {
        final data = _box.get(key);
        if (data != null && data is Map && data['id'] == songId) {
          await _box.delete(key);
          break;
        }
      }
      _refreshList();
    } catch (_) {}
  }

  static Future<void> clearHistory() async {
    try {
      await _box.clear();
      historyNotifier.value = [];
    } catch (_) {}
  }
}
