import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/history_entry.dart';
import '../domain/models/listening_session.dart';
import '../domain/models/track_entity.dart';
import '../models/song.dart';
import 'api_client.dart';
import 'auth_manager.dart';
import 'playlist_manager.dart';
import 'supabase_service.dart';
import 'app_logger.dart';

/// Unified Listening History Manager for Paatu Paadava matching Spotify and YouTube Music specifications.
/// Manages timestamped [HistoryEntry] storage, 24-hour deduplication hoisting,
/// LRU capacity limits (capped at 200 items), continuous [ListeningSession] clustering,
/// and bi-directional Supabase cloud synchronization.
class HistoryManager {
  static const String boxName = 'history_box';
  static const String pendingBoxName = 'pending_history_box';
  static const String sessionsBoxName = 'history_sessions_box';
  static const int maxHistoryLimit = 100;

  /// Reactive notifiers for UI binding
  static final ValueNotifier<List<HistoryEntry>> historyEntriesNotifier = ValueNotifier<List<HistoryEntry>>([]);
  static final ValueNotifier<List<Song>> historyNotifier = ValueNotifier<List<Song>>([]);
  static final ValueNotifier<List<ListeningSession>> historySessionsNotifier = ValueNotifier<List<ListeningSession>>([]);
  static bool _isSyncing = false;

  static Box get _box => Hive.box(boxName);
  static Box? get _pendingBox => Hive.isBoxOpen(pendingBoxName) ? Hive.box(pendingBoxName) : null;
  static Box get _sessionsBox => Hive.box(sessionsBoxName);

  /// Initializes local Hive storage and refreshes in-memory history
  static Future<void> init() async {
    await Hive.openBox(boxName);
    await Hive.openBox(pendingBoxName);
    await Hive.openBox(sessionsBoxName);
    _refreshList();
    _refreshSessions();

    // Background sync with cloud history if authenticated
    if (AuthManager.isLoggedIn) {
      syncCloudHistory();
    }
  }

  /// Internal reload and cache synchronization
  static void _refreshList() {
    final List<HistoryEntry> entries = [];
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

  /// Internal session reload and automatic continuous session grouping
  static void _refreshSessions() {
    if (!Hive.isBoxOpen(sessionsBoxName)) return;
    final List<ListeningSession> sessions = [];
    for (final key in _sessionsBox.keys) {
      final data = _sessionsBox.get(key);
      if (data != null && data is Map) {
        try {
          final session = ListeningSession.fromJson(Map<String, dynamic>.from(data));
          if (session.tracks.isNotEmpty) {
            sessions.add(session);
          }
        } catch (e) {
          AppLogger.log('HistoryManager', 'Corrupt session ignored: $e');
        }
      }
    }

    // If no explicit sessions saved yet but we have history entries, backfill/cluster from history!
    if (sessions.isEmpty && historyEntriesNotifier.value.isNotEmpty) {
      final clustered = clusterEntriesIntoSessions(historyEntriesNotifier.value);
      for (final s in clustered) {
        _sessionsBox.put(s.id, s.toJson());
        sessions.add(s);
      }
    }

    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    historySessionsNotifier.value = List.unmodifiable(sessions);
  }

  /// Clusters a list of [HistoryEntry] items into continuous [ListeningSession] objects
  /// using a 35-minute temporal proximity window between sequential plays.
  static List<ListeningSession> clusterEntriesIntoSessions(List<HistoryEntry> entries) {
    if (entries.isEmpty) return [];

    // Chronological sort: oldest plays to newest plays
    final sorted = List<HistoryEntry>.from(entries)
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));

    final List<ListeningSession> sessions = [];
    List<TrackEntity> currentCluster = [sorted.first.track];
    DateTime sessionStart = sorted.first.playedAt;
    DateTime lastPlayTime = sorted.first.playedAt;

    for (int i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      final gapMinutes = current.playedAt.difference(lastPlayTime).inMinutes.abs();

      // If gap is within 35 minutes, it is part of the continuous playback session
      if (gapMinutes <= 35) {
        currentCluster.add(current.track);
        lastPlayTime = current.playedAt;
      } else {
        sessions.add(ListeningSession.fromTracks(
          id: 'session_${sessionStart.millisecondsSinceEpoch}',
          tracks: List.from(currentCluster),
          startedAt: sessionStart,
          endedAt: lastPlayTime,
        ));
        currentCluster = [current.track];
        sessionStart = current.playedAt;
        lastPlayTime = current.playedAt;
      }
    }

    if (currentCluster.isNotEmpty) {
      sessions.add(ListeningSession.fromTracks(
        id: 'session_${sessionStart.millisecondsSinceEpoch}',
        tracks: List.from(currentCluster),
        startedAt: sessionStart,
        endedAt: lastPlayTime,
      ));
    }

    // Newest sessions first
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  /// Accessors for history
  static List<HistoryEntry> getHistoryEntries() => historyEntriesNotifier.value;
  static List<Song> getHistory() => historyNotifier.value;
  static List<Song> getRecentSongs() => historyNotifier.value;
  static List<ListeningSession> getListeningSessions() => historySessionsNotifier.value;

  /// Retrieves a specific continuous listening session by its unique ID
  static ListeningSession? getSessionById(String id) {
    try {
      return historySessionsNotifier.value.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Converts a continuous [ListeningSession] into a user-owned custom playlist
  static Future<UserPlaylist> saveSessionAsPlaylist(ListeningSession session, {String? customTitle}) async {
    final title = (customTitle != null && customTitle.trim().isNotEmpty) ? customTitle.trim() : session.title;
    return await PlaylistManager.createPlaylist(title, initialTracks: session.songs);
  }

  static Future<void> clear() => clearHistory();

  /// Adds a [TrackEntity] to playback history with Spotify/YouTube Music deduplication hoisting:
  /// 1. Checks if a [HistoryEntry] with `entry.track.id == track.id` exists within the last 24 hours.
  /// 2. If present, removes the prior entry.
  /// 3. Inserts the new [HistoryEntry(track: track, playedAt: DateTime.now())] at index 0.
  /// 4. Enforces a 100-item ceiling using LRU eviction.
  /// 5. Persists to Hive (preserving play_count and timestamps) and synchronizes with cloud services.
  static Future<void> addToHistory(TrackEntity track) async {
    try {
      final now = DateTime.now();
      final currentList = List<HistoryEntry>.from(historyEntriesNotifier.value);

      // Check if entry already exists within the last 24 hours
      final existingIndex = currentList.indexWhere((e) =>
          e.track.id == track.id && now.difference(e.playedAt).inHours < 24);

      if (existingIndex != -1) {
        currentList.removeAt(existingIndex);
      } else {
        // Also remove older entries of same track to avoid duplicates
        currentList.removeWhere((e) => e.track.id == track.id);
      }

      // Insert new entry at index 0 (hoisting)
      final newEntry = HistoryEntry(track: track, playedAt: now);
      currentList.insert(0, newEntry);

      // LRU eviction: Cap at 100 items max
      if (currentList.length > maxHistoryLimit) {
        currentList.removeRange(maxHistoryLimit, currentList.length);
      }

      historyEntriesNotifier.value = List.unmodifiable(currentList);
      historyNotifier.value = List.unmodifiable(currentList.map((e) => e.track.toSong()).toList());

      // Persist to local Hive storage if open
      if (Hive.isBoxOpen(boxName)) {
        int playCount = 1;
        List<int> timestamps = [];
        final keysToDelete = <dynamic>[];
        for (final key in _box.keys) {
          final data = _box.get(key);
          if (data != null && data is Map) {
            final id = data['track']?['id'] ?? data['id'];
            if (id == track.id) {
              keysToDelete.add(key);
              if (data['play_count'] is num) {
                playCount = (data['play_count'] as num).toInt() + 1;
              } else {
                playCount = 2;
              }
              if (data['timestamps'] is List) {
                timestamps = (data['timestamps'] as List).map((e) => (e as num).toInt()).toList();
              }
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

        final nowMs = now.millisecondsSinceEpoch;
        timestamps.add(nowMs);

        final entryMap = Map<String, dynamic>.from(track.toMap());
        entryMap['id'] = track.id;
        entryMap['track'] = track.toMap();
        entryMap['playedAt'] = now.toIso8601String();
        entryMap['played_at'] = nowMs;
        entryMap['play_count'] = playCount;
        entryMap['timestamps'] = timestamps;

        final key = 'h_${nowMs}_${track.id}';
        await _box.put(key, entryMap);

        // Update continuous playback sessions in _sessionsBox
        if (Hive.isBoxOpen(sessionsBoxName)) {
          ListeningSession? activeSession;
          if (historySessionsNotifier.value.isNotEmpty) {
            final latest = historySessionsNotifier.value.first;
            // If song played within 35 minutes of latest session's last song
            if (now.difference(latest.endedAt).inMinutes.abs() <= 35) {
              activeSession = latest;
            }
          }

          if (activeSession != null) {
            final updatedTracks = List<TrackEntity>.from(activeSession.tracks)..add(track);
            final updatedSession = ListeningSession(
              id: activeSession.id,
              title: ListeningSession.generateTitle(updatedTracks, activeSession.startedAt),
              startedAt: activeSession.startedAt,
              endedAt: now,
              tracks: updatedTracks,
            );
            await _sessionsBox.put(updatedSession.id, updatedSession.toJson());
          } else {
            final newSession = ListeningSession.fromTracks(
              id: 'session_${now.millisecondsSinceEpoch}',
              tracks: [track],
              startedAt: now,
              endedAt: now,
            );
            await _sessionsBox.put(newSession.id, newSession.toJson());
          }
          _refreshSessions();
        }
      }

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
          final entryMap = Map<String, dynamic>.from(track.toMap());
          entryMap['id'] = songId;
          entryMap['track'] = track.toMap();
          entryMap['playedAt'] = DateTime.fromMillisecondsSinceEpoch(epochMs).toIso8601String();
          entryMap['played_at'] = epochMs;
          entryMap['play_count'] = 1;
          entryMap['timestamps'] = [epochMs];
          await _box.put(key, entryMap);
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

      // Also clean up from continuous sessions
      if (Hive.isBoxOpen(sessionsBoxName)) {
        for (final key in _sessionsBox.keys) {
          final data = _sessionsBox.get(key);
          if (data != null && data is Map) {
            final session = ListeningSession.fromJson(Map<String, dynamic>.from(data));
            final updatedTracks = session.tracks.where((t) => t.id != songId).toList();
            if (updatedTracks.isEmpty) {
              await _sessionsBox.delete(key);
            } else if (updatedTracks.length != session.tracks.length) {
              final updatedSession = ListeningSession(
                id: session.id,
                title: ListeningSession.generateTitle(updatedTracks, session.startedAt),
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                tracks: updatedTracks,
              );
              await _sessionsBox.put(key, updatedSession.toJson());
            }
          }
        }
        _refreshSessions();
      }
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'HistoryManager.removeSong');
    }
  }

  /// Clears all history entries and continuous listening sessions
  static Future<void> clearHistory() async {
    try {
      await _box.clear();
      if (Hive.isBoxOpen(sessionsBoxName)) {
        await _sessionsBox.clear();
      }
      historyEntriesNotifier.value = [];
      historyNotifier.value = [];
      historySessionsNotifier.value = [];
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'HistoryManager.clearHistory');
    }
  }
}
