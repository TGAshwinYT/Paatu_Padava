import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/history_entry.dart';
import '../domain/models/track_entity.dart';
import '../models/song.dart';
import 'api_client.dart';
import 'auth_manager.dart';
import 'supabase_service.dart';
import 'app_logger.dart';

/// Unified Listening History Manager for Paatu Paadava matching Spotify and YouTube Music specifications.
/// Manages timestamped [HistoryEntry] storage, 24-hour deduplication hoisting,
/// LRU capacity limits (capped at 200 items), and bi-directional Supabase cloud synchronization.
class HistoryManager {
  static const String boxName = 'history_box';
  static const String pendingBoxName = 'pending_history_box';
  static const int maxHistoryLimit = 200;

  /// Reactive notifiers for UI binding
  static final ValueNotifier<List<HistoryEntry>> historyEntriesNotifier = ValueNotifier<List<HistoryEntry>>([]);
  static final ValueNotifier<List<Song>> historyNotifier = ValueNotifier<List<Song>>([]);
  static bool _isSyncing = false;

  static Box get _box => Hive.box(boxName);
  static Box? get _pendingBox => Hive.isBoxOpen(pendingBoxName) ? Hive.box(pendingBoxName) : null;

  /// Initializes local Hive storage and refreshes in-memory history
  static Future<void> init() async {
    await Hive.openBox(boxName);
    await Hive.openBox(pendingBoxName);
    _refreshList();

    // Background sync with cloud history if authenticated
    if (AuthManager.isLoggedIn) {
      syncCloudHistory();
    }
  }

  /// Internal reload and cache synchronization
  static void _refreshList() {
    final List<HistoryEntry> entries = [];
    int fallbackIndex = 0;
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data != null && data is Map) {
        try {
          final entry = HistoryEntry.fromJson(Map<String, dynamic>.from(data));
          entries.add(entry);
        } catch (e) {
          AppLogger.log('HistoryManager', 'Corrupt history entry ignored: $e');
        }
      }
    }

    // Sort newest plays first (descending timestamp)
    entries.sort((a, b) => b.playedAt.compareTo(a.playedAt));

    // Deduplicate identical track IDs within 24 hours and enforce LRU cap
    final List<HistoryEntry> deduped = [];
    for (final entry in entries) {
      final hasRecentDuplicate = deduped.any((e) =>
          e.track.id == entry.track.id &&
          e.playedAt.difference(entry.playedAt).inHours.abs() < 24);
      if (!hasRecentDuplicate) {
        deduped.add(entry);
      }
    }

    if (deduped.length > maxHistoryLimit) {
      deduped.removeRange(maxHistoryLimit, deduped.length);
    }

    historyEntriesNotifier.value = List.unmodifiable(deduped);
    historyNotifier.value = List.unmodifiable(deduped.map((e) => e.track.toSong()).toList());
  }

  /// Accessors for history
  static List<HistoryEntry> getHistoryEntries() => historyEntriesNotifier.value;
  static List<Song> getHistory() => historyNotifier.value;
  static List<Song> getRecentSongs() => historyNotifier.value;

  static Future<void> clear() => clearHistory();

  /// Adds a [TrackEntity] to playback history with Spotify/YouTube Music deduplication hoisting:
  /// 1. Checks if a [HistoryEntry] with `entry.track.id == track.id` exists within the last 24 hours.
  /// 2. If present, removes the prior entry.
  /// 3. Inserts the new [HistoryEntry(track: track, playedAt: DateTime.now())] at index 0.
  /// 4. Enforces a 200-item ceiling using LRU eviction.
  /// 5. Persists to Hive and synchronizes with cloud services.
  static Future<void> addToHistory(TrackEntity track) async {
    try {
      final now = DateTime.now();
      final currentList = List<HistoryEntry>.from(historyEntriesNotifier.value);

      // Check if entry already exists within the last 24 hours
      final existingIndex = currentList.indexWhere((e) =>
          e.track.id == track.id && now.difference(e.playedAt).inHours < 24);

      if (existingIndex != -1) {
        currentList.removeAt(existingIndex);
      }

      // Insert new entry at index 0 (hoisting)
      final newEntry = HistoryEntry(track: track, playedAt: now);
      currentList.insert(0, newEntry);

      // LRU eviction: Cap at 200 items max
      if (currentList.length > maxHistoryLimit) {
        currentList.removeRange(maxHistoryLimit, currentList.length);
      }

      historyEntriesNotifier.value = List.unmodifiable(currentList);
      historyNotifier.value = List.unmodifiable(currentList.map((e) => e.track.toSong()).toList());

      // Persist to local Hive storage: clean out existing key for same track
      final keysToDelete = <dynamic>[];
      for (final key in _box.keys) {
        final data = _box.get(key);
        if (data != null && data is Map) {
          final id = data['track']?['id'] ?? data['id'];
          if (id == track.id) {
            keysToDelete.add(key);
          }
        }
      }
      for (final k in keysToDelete) {
        await _box.delete(k);
      }

      while (_box.length >= maxHistoryLimit) {
        final oldestKey = _box.keys.first;
        await _box.delete(oldestKey);
      }

      final key = 'h_${now.millisecondsSinceEpoch}_${track.id}';
      await _box.put(key, newEntry.toJson());

      // Coordinated Cloud Persistence Path
      final song = track.toSong();
      final supaUser = SupabaseService.currentUser;
      if (supaUser != null && !supaUser.isAnonymous) {
        _persistPlayToCloud(supaUser.id, song);
      } else {
        _persistPlayToBackendOnly(song);
      }
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'HistoryManager.addToHistory');
      debugPrint('[HistoryManager] addToHistory error: $e');
    }
  }

  /// Compatibility bridge for Song instances
  static Future<void> recordPlay(Song song) async {
    await addToHistory(TrackEntity.fromSong(song));
  }

  /// Exposes raw history entries with play counts, timestamps, and song metadata for analytics
  static List<Map<String, dynamic>> getRawHistoryEntries() {
    final List<Map<String, dynamic>> raw = [];
    if (!Hive.isBoxOpen(boxName)) return raw;
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data != null && data is Map) {
        raw.add(Map<String, dynamic>.from(data));
      }
    }
    return raw;
  }

  /// Asynchronously persists play event to Supabase, queuing for retry if network is unavailable
  static void _persistPlayToCloud(String userId, Song song) {
    Future(() async {
      try {
        await SupabaseService.recordUserHistory(userId, song);
      } catch (e) {
        debugPrint('[HistoryManager] Cloud history write failed, queuing for retry: $e');
        try {
          await _pendingBox?.put(song.id, song.toMap());
        } catch (err) {
          AppLogger.log('HistoryManager', 'Pending box write failed: $err');
        }
      }
    });
  }

  /// Fallback single write path when Supabase is unauthenticated/guest
  static void _persistPlayToBackendOnly(Song song) {
    Future(() async {
      try {
        await ApiClient.addListenHistory(song);
      } catch (e) {
        AppLogger.log('HistoryManager', 'Backend listen history fallback: $e');
      }
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
            } catch (err) {
              AppLogger.log('HistoryManager', 'Pending history flush paused: $err');
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
          final track = TrackEntity(
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
          final entry = HistoryEntry(track: track, playedAt: DateTime.fromMillisecondsSinceEpoch(epochMs));
          await _box.put(key, entry.toJson());
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

  /// Removes a song from history by ID
  static Future<void> removeSong(String songId) async {
    try {
      final currentList = List<HistoryEntry>.from(historyEntriesNotifier.value);
      currentList.removeWhere((e) => e.track.id == songId);
      historyEntriesNotifier.value = List.unmodifiable(currentList);
      historyNotifier.value = List.unmodifiable(currentList.map((e) => e.track.toSong()).toList());

      final keysToDelete = <dynamic>[];
      for (final key in _box.keys) {
        final data = _box.get(key);
        if (data != null && data is Map) {
          final id = data['track']?['id'] ?? data['id'];
          if (id == songId) {
            keysToDelete.add(key);
          }
        }
      }
      for (final k in keysToDelete) {
        await _box.delete(k);
      }
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'HistoryManager.removeSong');
    }
  }

  /// Clears all history entries
  static Future<void> clearHistory() async {
    try {
      await _box.clear();
      historyEntriesNotifier.value = [];
      historyNotifier.value = [];
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'HistoryManager.clearHistory');
    }
  }
}
