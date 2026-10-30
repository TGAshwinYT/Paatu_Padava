import '../models/song.dart';

/// Decides whether a YouTube result is a real, single "song" or something that
/// should never appear in search / autoplay: hour-long jukeboxes, non-stop mixes,
/// full-album uploads, live streams, 24/7 radios and teasers.
///
/// Why: these files are 30-120+ MB, cannot be fetched fast enough to play
/// without stalling (-> auto-skip), have no useful seek bar and pollute radio.
///
/// Pure Dart (no Flutter / network) so it is trivially unit-testable.
class TrackQualityFilter {
  TrackQualityFilter._();

  /// Hard cap: anything longer is not treated as a song (10 min).
  static const int maxSongDurationSec = 600;

  /// Teasers / promos / ringtones shorter than this are dropped.
  static const int minSongDurationSec = 45;

  /// "Mix-like" title words only count once the video is at least this long,
  /// so a real 4-minute song named "Nonstop" or "Mashup" is not removed.
  static const int mixKeywordMinSec = 420;

  static final RegExp _mixKeywords = RegExp(
    r'(juke\s?box|non[\s\-]?stop|mega\s?mix|\bmashups?\b|\bmedley\b|full\s+album|all\s+songs|'
    r'songs?\s+collection|hits?\s+collection|back\s+to\s+back|\bbest\s+of\b|\btop\s+\d+\b|'
    r'\b\d+\s+(songs|hits|tracks)\b|\bmix\b|\bplaylist\b)',
    caseSensitive: false,
  );

  /// Words that mean "this is a stream / very long loop", rejected when long or of unknown length.
  static final RegExp _streamKeywords = RegExp(
    r'(\b\d+\s*(hours?|hrs?)\b|\b24\s*/\s*7\b|live\s*stream|\blivestream\b|\bnon[\s\-]?stop\s+radio\b)',
    caseSensitive: false,
  );

  /// Returns a short reason when the item must be dropped, or null when it is fine.
  static String? rejectReason({
    required String title,
    required int durationSec,
    bool allowUnknownDuration = false,
  }) {
    if (durationSec <= 0) {
      if (allowUnknownDuration) return null;
      return 'unknown duration (live stream / premiere)';
    }
    if (durationSec > maxSongDurationSec) {
      return 'longer than ${maxSongDurationSec ~/ 60} min';
    }
    if (durationSec < minSongDurationSec) {
      return 'shorter than ${minSongDurationSec}s (teaser/clip)';
    }
    if (_streamKeywords.hasMatch(title)) {
      return 'stream / hours-long marker in title';
    }
    if (durationSec >= mixKeywordMinSec && _mixKeywords.hasMatch(title)) {
      return 'mix / compilation marker in title';
    }
    return null;
  }

  static bool shouldKeep({
    required String title,
    required int durationSec,
    bool allowUnknownDuration = false,
  }) =>
      rejectReason(
        title: title,
        durationSec: durationSec,
        allowUnknownDuration: allowUnknownDuration,
      ) ==
      null;

  /// Filters a list of songs. Only YouTube-sourced items are judged; JioSaavn /
  /// local / Audius tracks are always real songs and pass through untouched.
  static List<Song> filterSongs(Iterable<Song> songs, {bool allowUnknownDuration = true}) {
    return songs.where((s) {
      if (s.source != 'youtube') return true;
      return shouldKeep(
        title: s.title,
        durationSec: s.duration,
        allowUnknownDuration: allowUnknownDuration,
      );
    }).toList();
  }
}
