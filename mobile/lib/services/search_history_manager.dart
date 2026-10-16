import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';

class SearchHistoryManager {
  static const String boxName = 'search_history';
  static final ValueNotifier<List<String>> historyNotifier = ValueNotifier<List<String>>([]);
  static final ValueNotifier<List<Song>> recentSongsNotifier = ValueNotifier<List<Song>>([]);

  static Future<void> init() async {
    await Hive.openBox(boxName);
    _refreshList();
    _refreshSongsList();
  }

  static Box get _box => Hive.box(boxName);

  static void _refreshList() {
    final List<dynamic> raw = _box.get('recent_searches', defaultValue: []) as List<dynamic>;
    final List<String> list = [];
    final Set<String> seen = {};

    for (final item in raw) {
      final str = item.toString().trim();
      final lower = str.toLowerCase();
      if (str.isNotEmpty && !seen.contains(lower)) {
        seen.add(lower);
        list.add(str);
      }
    }

    if (list.length > 12) {
      list.removeRange(12, list.length);
    }
    historyNotifier.value = list;
  }

  static void _refreshSongsList() {
    final List<dynamic> raw = _box.get('recent_searched_songs', defaultValue: []) as List<dynamic>;
    final List<Song> list = [];
    final Set<String> seenIds = {};

    for (final item in raw) {
      try {
        if (item is Map) {
          final song = Song.fromMap(item);
          if (song.id.isNotEmpty && !seenIds.contains(song.id)) {
            seenIds.add(song.id);
            list.add(song);
          }
        }
      } catch (e) {
        // Skip corrupted entries safely
      }
    }

    if (list.length > 20) {
      list.removeRange(20, list.length);
    }
    recentSongsNotifier.value = list;
  }

  /// Adds a search term to history with strict deduplication, case-insensitivity,
  /// and a maximum cap of 12 recent searches.
  static Future<void> addQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    final current = List<String>.from(historyNotifier.value);
    // Case-insensitive removal of existing duplicates
    current.removeWhere((item) => item.trim().toLowerCase() == clean.toLowerCase());
    current.insert(0, clean);

    // Enforce max cap of 12 recent searches
    if (current.length > 12) {
      current.removeRange(12, current.length);
    }

    await _box.put('recent_searches', current);
    historyNotifier.value = current;
  }

  /// Adds a clicked song to search history with strict deduplication by ID,
  /// moving it to the top and enforcing a 20-song cap (like Spotify & Apple Music).
  static Future<void> addSong(Song song) async {
    if (song.id.isEmpty) return;

    final current = List<Song>.from(recentSongsNotifier.value);
    current.removeWhere((s) => s.id == song.id);
    current.insert(0, song);

    if (current.length > 20) {
      current.removeRange(20, current.length);
    }

    recentSongsNotifier.value = current;
    final serialized = current.map((s) => s.toMap()).toList();
    await _box.put('recent_searched_songs', serialized);
  }

  static Future<void> removeSong(String songId) async {
    final current = List<Song>.from(recentSongsNotifier.value);
    current.removeWhere((s) => s.id == songId);
    recentSongsNotifier.value = current;
    final serialized = current.map((s) => s.toMap()).toList();
    await _box.put('recent_searched_songs', serialized);
  }

  static Future<void> removeQuery(String query) async {
    final clean = query.trim().toLowerCase();
    final current = List<String>.from(historyNotifier.value);
    current.removeWhere((item) => item.trim().toLowerCase() == clean);
    await _box.put('recent_searches', current);
    historyNotifier.value = current;
  }

  static Future<void> clearSongs() async {
    recentSongsNotifier.value = [];
    await _box.put('recent_searched_songs', <Map<String, dynamic>>[]);
  }

  static Future<void> clearAll() async {
    await _box.put('recent_searches', <String>[]);
    await _box.put('recent_searched_songs', <Map<String, dynamic>>[]);
    historyNotifier.value = [];
    recentSongsNotifier.value = [];
  }
}
