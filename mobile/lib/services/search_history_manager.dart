import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SearchHistoryManager {
  static const String boxName = 'search_history';
  static final ValueNotifier<List<String>> historyNotifier = ValueNotifier<List<String>>([]);

  static Future<void> init() async {
    await Hive.openBox(boxName);
    _refreshList();
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

  static Future<void> removeQuery(String query) async {
    final clean = query.trim().toLowerCase();
    final current = List<String>.from(historyNotifier.value);
    current.removeWhere((item) => item.trim().toLowerCase() == clean);
    await _box.put('recent_searches', current);
    historyNotifier.value = current;
  }

  static Future<void> clearAll() async {
    await _box.put('recent_searches', <String>[]);
    historyNotifier.value = [];
  }
}
