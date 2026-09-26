import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';
import 'api_client.dart';
import 'auth_manager.dart';

class HistoryManager {
  static const String boxName = 'history_box';
  static final ValueNotifier<List<Song>> historyNotifier = ValueNotifier<List<Song>>([]);

  static Box get _box => Hive.box(boxName);

  static Future<void> init() async {
    await Hive.openBox(boxName);
    _refreshList();

    // Background sync with cloud history if authenticated
    if (AuthManager.isLoggedIn) {
      _syncWithBackend();
    }
  }

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
    // Most recent first: stored with key as negative timestamp or sorted by stored order
    historyNotifier.value = list.reversed.toList();
  }

  static List<Song> getHistory() => historyNotifier.value;
  static List<Song> getRecentSongs() => historyNotifier.value;

  static Future<void> clear() => clearHistory();

  static Future<void> addSong(Song song) async {
    try {
      // Remove any existing occurrence to avoid duplicates
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

      // Keep max 100 items in history
      if (_box.length >= 100) {
        final firstKey = _box.keys.first;
        await _box.delete(firstKey);
      }

      // Store with auto-increment or timestamp key
      final key = 'h_${DateTime.now().millisecondsSinceEpoch}';
      await _box.put(key, song.toMap());
      _refreshList();
    } catch (_) {}
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

  static Future<void> _syncWithBackend() async {
    try {
      final remoteHistory = await ApiClient.fetchListenHistory();
      if (remoteHistory.isNotEmpty) {
        for (final song in remoteHistory.take(25)) {
          bool alreadyExists = false;
          for (final key in _box.keys) {
            final data = _box.get(key);
            if (data != null && data is Map && data['id'] == song.id) {
              alreadyExists = true;
              break;
            }
          }
          if (!alreadyExists) {
            final key = 'h_${DateTime.now().millisecondsSinceEpoch}_${song.id}';
            await _box.put(key, song.toMap());
          }
        }
        _refreshList();
      }
    } catch (_) {}
  }
}
