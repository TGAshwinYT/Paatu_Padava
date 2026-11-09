import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/home_feed_models.dart';
import '../models/song.dart';
import 'app_logger.dart';

/// Spotify-Style Bounded MRU/LRU Recently Played Containers Manager.
/// Tracks up to 6 recently played containers (Albums, Playlists, Daily Mixes, Liked Songs).
/// Dynamically grows from 1 to 6 items, hoists existing containers to [0][0],
/// and evicts the oldest [3][2] container upon capacity overflow.
class RecentContainersManager {
  static const String boxName = 'recent_containers_box';
  static const int maxCapacity = 6;

  static final ValueNotifier<List<HomeQuickTile>> containersNotifier =
      ValueNotifier<List<HomeQuickTile>>([]);

  static Future<void> init() async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      _loadFromBox();
    } catch (e) {
      AppLogger.log('RecentContainersManager', 'Hive init notice: $e');
    }
  }

  static void _loadFromBox() {
    try {
      if (!Hive.isBoxOpen(boxName)) return;
      final box = Hive.box(boxName);
      final rawList = box.get('recent_containers');
      if (rawList is List) {
        final List<HomeQuickTile> loaded = [];
        for (final item in rawList) {
          if (item is Map) {
            try {
              loaded.add(HomeQuickTile.fromMap(Map<String, dynamic>.from(item)));
            } catch (_) {}
          }
        }
        containersNotifier.value = loaded.take(maxCapacity).toList();
      }
    } catch (e) {
      AppLogger.log('RecentContainersManager', 'Load notice: $e');
    }
  }

  static Future<void> _persist() async {
    try {
      if (!Hive.isBoxOpen(boxName)) return;
      final box = Hive.box(boxName);
      final list = containersNotifier.value.map((t) => t.toMap()).toList();
      await box.put('recent_containers', list);
    } catch (e) {
      AppLogger.log('RecentContainersManager', 'Persist notice: $e');
    }
  }

  /// Records a container when user plays a track from an Album, Playlist, Mix, or Liked Songs.
  /// Hoists to [0][0] if already present, or inserts at [0][0] and evicts [3][2] if full.
  static Future<void> recordContainer({
    required String id,
    required String title,
    String? subtitle,
    required String coverUrl,
    required String type,
    List<Color> gradient = const [Color(0xFF4C1D95), Color(0xFF7C3AED)],
    List<Song> tracks = const [],
  }) async {
    final current = List<HomeQuickTile>.from(containersNotifier.value);

    // Remove if already exists (to hoist to top [0][0])
    current.removeWhere((tile) => tile.id == id);

    // Create the tile
    final newTile = HomeQuickTile(
      id: id,
      title: title,
      subtitle: subtitle,
      coverUrl: coverUrl,
      gradient: gradient,
      tracks: tracks,
      type: type,
    );

    // Insert at [0][0]
    current.insert(0, newTile);

    // Enforce maxCapacity 6: drop [3][2] (the 6th item) if capacity exceeded
    if (current.length > maxCapacity) {
      current.removeRange(maxCapacity, current.length);
    }

    containersNotifier.value = List.unmodifiable(current);
    await _persist();
  }

  /// Clears all recent containers (e.g. for testing or user profile reset)
  static Future<void> clearAll() async {
    containersNotifier.value = const [];
    try {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).delete('recent_containers');
      }
    } catch (_) {}
  }
}
