import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/track_entity.dart';
import '../models/song.dart';
import 'app_logger.dart';
import 'queue_cooldown_manager.dart';

/// Manages user-defined blocked/blacklisted songs and artists ("Don't play this").
/// Prevents blacklisted items from appearing in Autoplay, Radio, Home Feed, and Queue.
/// Enabled by default per user preferences.
class BlacklistManager {
  static const String boxName = 'blacklist_box';
  static const String _enabledKey = 'blacklist_enabled';
  static const String _songsKey = 'blacklisted_songs';
  static const String _artistsKey = 'blacklisted_artists';

  static final ValueNotifier<bool> isEnabledNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<List<Song>> blacklistedSongsNotifier = ValueNotifier<List<Song>>([]);
  static final ValueNotifier<List<String>> blacklistedArtistsNotifier = ValueNotifier<List<String>>([]);

  static final Map<String, Song> _songsMap = {};
  static final Set<String> _songIdSet = {};
  static final Set<String> _artistKeySet = {};
  static final List<String> _artistList = [];

  static Box get _box => Hive.box(boxName);

  static bool get isEnabled => isEnabledNotifier.value;

  /// Initializes local Hive storage and hydrates in-memory caches
  static Future<void> init() async {
    await Hive.openBox(boxName);

    isEnabledNotifier.value = _box.get(_enabledKey, defaultValue: true) as bool;

    final rawSongs = _box.get(_songsKey);
    _songsMap.clear();
    _songIdSet.clear();
    if (rawSongs is Map) {
      for (final entry in rawSongs.entries) {
        try {
          if (entry.value is Map) {
            final song = Song.fromMap(Map<String, dynamic>.from(entry.value as Map));
            _songsMap[song.id] = song;
            _songIdSet.add(song.id);
            if (song.canonicalBaseKey.isNotEmpty) {
              _songIdSet.add(song.canonicalBaseKey);
            }
          }
        } catch (e) {
          AppLogger.log('BlacklistManager', 'Error deserializing blacklisted song: $e');
        }
      }
    }
    blacklistedSongsNotifier.value = List.unmodifiable(_songsMap.values.toList());

    final rawArtists = _box.get(_artistsKey);
    _artistKeySet.clear();
    _artistList.clear();
    if (rawArtists is List) {
      for (final a in rawArtists) {
        if (a is String && a.trim().isNotEmpty) {
          final clean = a.trim();
          _artistList.add(clean);
          _artistKeySet.add(QueueCooldownManager.normalizeArtistKey(clean));
        }
      }
    }
    blacklistedArtistsNotifier.value = List.unmodifiable(_artistList);
  }

  /// Checks if a song is blacklisted (either song directly or primary artist)
  static bool isBlacklisted(Song song) {
    if (!isEnabled) return false;
    if (_songIdSet.contains(song.id)) return true;
    if (song.canonicalBaseKey.isNotEmpty && _songIdSet.contains(song.canonicalBaseKey)) return true;
    return isArtistBlacklisted(song.primaryArtist);
  }

  /// Checks if a TrackEntity is blacklisted
  static bool isTrackBlacklisted(TrackEntity track) {
    if (!isEnabled) return false;
    if (_songIdSet.contains(track.id)) return true;
    return isArtistBlacklisted(track.artist);
  }

  /// Checks if an artist is blacklisted
  static bool isArtistBlacklisted(String artistName) {
    if (!isEnabled) return false;
    if (artistName.trim().isEmpty) return false;
    final key = QueueCooldownManager.normalizeArtistKey(artistName);
    return _artistKeySet.contains(key);
  }

  /// Blacklists a song and prevents it from playing
  static Future<void> blacklistSong(Song song) async {
    _songsMap[song.id] = song;
    _songIdSet.add(song.id);
    if (song.canonicalBaseKey.isNotEmpty) {
      _songIdSet.add(song.canonicalBaseKey);
    }
    blacklistedSongsNotifier.value = List.unmodifiable(_songsMap.values.toList());

    final serialized = <String, dynamic>{
      for (final s in _songsMap.values) s.id: s.toMap(),
    };
    await _box.put(_songsKey, serialized);
    AppLogger.log('BlacklistManager', 'Blacklisted song "${song.title}" (${song.id})');
  }

  /// Unblacklists a song by ID
  static Future<void> unblacklistSong(String songId) async {
    final removed = _songsMap.remove(songId);
    _songIdSet.remove(songId);
    if (removed != null && removed.canonicalBaseKey.isNotEmpty) {
      _songIdSet.remove(removed.canonicalBaseKey);
    }
    blacklistedSongsNotifier.value = List.unmodifiable(_songsMap.values.toList());

    final serialized = <String, dynamic>{
      for (final s in _songsMap.values) s.id: s.toMap(),
    };
    await _box.put(_songsKey, serialized);
    AppLogger.log('BlacklistManager', 'Unblacklisted song $songId');
  }

  /// Blacklists an artist and prevents all songs by them from playing
  static Future<void> blacklistArtist(String artistName) async {
    final clean = artistName.trim();
    if (clean.isEmpty) return;
    final key = QueueCooldownManager.normalizeArtistKey(clean);
    if (!_artistKeySet.contains(key)) {
      _artistKeySet.add(key);
      _artistList.add(clean);
      blacklistedArtistsNotifier.value = List.unmodifiable(_artistList);
      await _box.put(_artistsKey, _artistList);
      AppLogger.log('BlacklistManager', 'Blacklisted artist "$clean"');
    }
  }

  /// Unblacklists an artist
  static Future<void> unblacklistArtist(String artistName) async {
    final key = QueueCooldownManager.normalizeArtistKey(artistName);
    _artistKeySet.remove(key);
    _artistList.removeWhere((a) => QueueCooldownManager.normalizeArtistKey(a) == key);
    blacklistedArtistsNotifier.value = List.unmodifiable(_artistList);
    await _box.put(_artistsKey, _artistList);
    AppLogger.log('BlacklistManager', 'Unblacklisted artist "$artistName"');
  }

  /// Toggles blacklist filtering on or off
  static Future<void> setEnabled(bool enabled) async {
    isEnabledNotifier.value = enabled;
    await _box.put(_enabledKey, enabled);
  }

  /// Clears all blacklist data (useful for testing or full reset)
  static Future<void> clear() async {
    _songsMap.clear();
    _songIdSet.clear();
    _artistKeySet.clear();
    _artistList.clear();
    blacklistedSongsNotifier.value = [];
    blacklistedArtistsNotifier.value = [];
    await _box.delete(_songsKey);
    await _box.delete(_artistsKey);
  }
}
