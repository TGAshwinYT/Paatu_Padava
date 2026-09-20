import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';

class FavoritesManager {
  static const String boxName = 'favorite_songs';
  static final ValueNotifier<List<Song>> favoritesNotifier = ValueNotifier<List<Song>>([]);

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
        list.add(Song.fromMap(data));
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
      return false;
    } else {
      await _box.put(song.id, song.toMap());
      _refreshList();
      return true;
    }
  }

  static List<Song> getFavorites() {
    return List.from(favoritesNotifier.value);
  }
}
