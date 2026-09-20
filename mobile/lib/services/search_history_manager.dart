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
    historyNotifier.value = raw.map((e) => e.toString()).toList();
  }

  static Future<void> addQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    final current = List<String>.from(historyNotifier.value);
    current.removeWhere((item) => item.toLowerCase() == clean.toLowerCase());
    current.insert(0, clean);

    if (current.length > 20) {
      current.removeRange(20, current.length);
    }

    await _box.put('recent_searches', current);
    historyNotifier.value = current;
  }

  static Future<void> removeQuery(String query) async {
    final current = List<String>.from(historyNotifier.value);
    current.removeWhere((item) => item == query);
    await _box.put('recent_searches', current);
    historyNotifier.value = current;
  }

  static Future<void> clearAll() async {
    await _box.put('recent_searches', <String>[]);
    historyNotifier.value = [];
  }
}
