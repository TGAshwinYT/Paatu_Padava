import '../domain/models/clustered_track_result.dart';
import '../models/song.dart';

/// Decides whether a YouTube or streaming result is a real single song,
/// a fan mix/mashup/BGM, or something that should be dropped immediately:
/// non-music reviews, public reactions, interviews, press meets, teasers, and streams.
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

  /// Non-music video junk: movie reviews, audience reactions, interviews, trailers, teasers, shorts.
  static final RegExp _junkRegex = RegExp(
    r'\b(review|public\s*review|reaction|interview|press\s*meet|trailer|teaser|'
    r'making\s*of|speech|shorts|whatsapp\s*status|lyric\s*video\s*status|sneak\s*peek|glimpse)\b',
    caseSensitive: false,
  );

  /// Fanbase mixes, slowed+reverb, mashups, instrumental BGMs.
  static final RegExp _fanMixRegex = RegExp(
    r'\b(mashup|lo[\s\-]?fi|slowed|reverb|8d|unplugged|cover|bgm|theme|remix|dj|acoustic|reprise|instrumental)\b',
    caseSensitive: false,
  );

  /// Evaluates and classifies a track candidate based on title, duration, and origin source.
  static ContentClassification classifyTrack({
    required String title,
    required int durationSec,
    String? source,
    String? artist,
  }) {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return ContentClassification.rejectedJunk;

    // JioSaavn / curated platforms are always music
    if (source == 'saavn' || source == 'jiosaavn') {
      if (_fanMixRegex.hasMatch(cleanTitle)) {
        return ContentClassification.fanMixOrVersion;
      }
      return ContentClassification.officialTrack;
    }

    // 1. YouTube Non-Music Junk Filter
    if (_junkRegex.hasMatch(cleanTitle)) {
      return ContentClassification.rejectedJunk;
    }

    // 2. Teaser / Promo duration lower bound (< 45s)
    if (durationSec > 0 && durationSec < minSongDurationSec) {
      return ContentClassification.rejectedJunk;
    }

    // 3. Streams or multi-hour loops
    if (_streamKeywords.hasMatch(cleanTitle)) {
      return ContentClassification.rejectedJunk;
    }

    // 4. Over 12 minutes (720s) for a single song
    if (durationSec > 720) {
      return ContentClassification.rejectedJunk;
    }

    // 5. Fanbase mix or BGM check
    if (_fanMixRegex.hasMatch(cleanTitle)) {
      return ContentClassification.fanMixOrVersion;
    }

    return ContentClassification.officialTrack;
  }

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
    if (_junkRegex.hasMatch(title)) {
      return 'non-music junk (review/reaction/teaser)';
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
