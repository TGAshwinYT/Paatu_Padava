import 'dart:collection';
import '../models/song.dart';
import 'app_logger.dart';

/// Manages a rolling 75-track anti-fatigue cooldown buffer.
/// Enforces Spotify & Apple Music industry standards: prevents played songs
/// from repeating in autoplay, smart shuffle, or radio until at least 75 unique
/// songs have elapsed.
class QueueCooldownManager {
  static const int maxCooldownCapacity = 75;

  // Ring buffer of keys maintaining order of playback
  static final Queue<String> _historyRing = Queue<String>();

  // Fast O(1) set for immediate containment checks
  static final Set<String> _cooldownKeys = <String>{};

  // Ring buffer of clean artist names maintaining order of playback
  static final Queue<String> _artistHistoryRing = Queue<String>();

  /// Records a track as recently played, adding it to the cooldown window.
  /// Evicts the oldest track once capacity reaches 75.
  static void recordPlayed(Song song) {
    final titleKey = song.cleanTitleKey;
    if (titleKey.isEmpty) return;

    // Remove if already in ring to refresh its position to most recent
    if (_cooldownKeys.contains(titleKey)) {
      _historyRing.remove(titleKey);
    }

    _historyRing.addLast(titleKey);
    _cooldownKeys.add(titleKey);

    // Evict oldest tracks exceeding 75
    while (_historyRing.length > maxCooldownCapacity) {
      final oldest = _historyRing.removeFirst();
      // Only remove from set if not present multiple times
      if (!_historyRing.contains(oldest)) {
        _cooldownKeys.remove(oldest);
      }
    }

    // Record primary artist for artist dispersion cooldown (last 4 tracks window)
    final artist = song.primaryArtist.toLowerCase().trim();
    if (artist.isNotEmpty && artist != 'various artists') {
      _artistHistoryRing.addLast(artist);
      while (_artistHistoryRing.length > maxCooldownCapacity) {
        _artistHistoryRing.removeFirst();
      }
    }

    AppLogger.log(
      'QueueCooldownManager',
      'Recorded "$titleKey" (artist: "$artist") to cooldown buffer. Active cooling count: ${_historyRing.length}/$maxCooldownCapacity',
    );
  }

  /// Checks if a song or its core composition title is currently within the 75-track cooldown window.
  static bool isCoolingDown(Song song) {
    final key = song.cleanTitleKey;
    if (key.isEmpty) return false;
    return isCoolingDownKey(key);
  }

  /// Direct key check for clean composition title
  static bool isCoolingDownKey(String cleanTitleKey) {
    final norm = cleanTitleKey.toLowerCase().trim();
    return _cooldownKeys.contains(norm);
  }

  /// Checks if a candidate's primary artist has appeared in the last [window] played tracks (default 4).
  /// Spotify / Apple Music standard: prevents repetitive single-artist runs in auto-generated queues.
  static bool isArtistCoolingDown(String primaryArtist, {int window = 4}) {
    final norm = primaryArtist.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
    if (norm.isEmpty || norm == 'various artists') return false;
    final recent = _artistHistoryRing.toList().reversed.take(window);
    return recent.contains(norm);
  }

  /// Returns the most recent played primary artists (up to [window], newest first)
  static List<String> getRecentArtists({int window = 4}) {
    return _artistHistoryRing.toList().reversed.take(window).toList();
  }

  /// Filters out any candidates currently cooling down.
  /// If all candidates are cooling down (pool starvation), falls back to returning candidates to prevent dead silence.
  static List<Song> filterEligible(Iterable<Song> candidates) {
    final eligible = candidates.where((s) => !isCoolingDown(s)).toList();
    if (eligible.isNotEmpty) {
      return eligible;
    }
    // Pool exhaustion fallback: return all candidates so music never stops
    return candidates.toList();
  }

  /// Current number of tracks in cooldown buffer
  static int get activeCooldownCount => _historyRing.length;

  /// Clears the cooldown history (used for unit testing or explicit queue reset)
  static void clear() {
    _historyRing.clear();
    _cooldownKeys.clear();
    _artistHistoryRing.clear();
  }
}
