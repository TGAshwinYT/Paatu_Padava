import '../settings_manager.dart';
import 'search_models.dart';

class _SearchCacheEntry {
  final SearchResults results;
  final DateTime createdAt;
  _SearchCacheEntry(this.results) : createdAt = DateTime.now();
  bool get isExpired => DateTime.now().difference(createdAt).inMinutes > 15;
}

class SearchCache {
  static const int _maxEntries = 60;
  static final Map<String, _SearchCacheEntry> _cache = {};
  static final List<String> _lruOrder = [];

  static SearchResults? get(String query, {String? language}) {
    final prefLangs = SettingsManager.preferredLanguages.join(',');
    final key = '${query.trim().toLowerCase()}__${(language == null || language.isEmpty || language.toLowerCase() == "all") ? "all" : language.toLowerCase()}__$prefLangs';
    final entry = _cache[key];
    if (entry != null) {
      if (entry.isExpired) {
        _cache.remove(key);
        _lruOrder.remove(key);
        return null;
      }
      _lruOrder.remove(key);
      _lruOrder.add(key);
      return entry.results;
    }
    return null;
  }

  static void put(String query, SearchResults results, {String? language}) {
    if (results.isEmpty || results.hasError) return;
    if (results.songs.isEmpty && results.saavnSongs.isEmpty && results.ytSongs.isEmpty) return;

    final prefLangs = SettingsManager.preferredLanguages.join(',');
    final key = '${query.trim().toLowerCase()}__${(language == null || language.isEmpty || language.toLowerCase() == "all") ? "all" : language.toLowerCase()}__$prefLangs';
    if (_cache.containsKey(key)) {
      _lruOrder.remove(key);
    } else if (_lruOrder.length >= _maxEntries) {
      final oldest = _lruOrder.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[key] = _SearchCacheEntry(results);
    _lruOrder.add(key);
  }

  static void clear() {
    _cache.clear();
    _lruOrder.clear();
  }
}
