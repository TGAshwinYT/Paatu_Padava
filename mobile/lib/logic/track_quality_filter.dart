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

  /// Non-music spoken dialogue, punch dialogues, movie scenes, comedy tracks, ringtones.
  static final RegExp _dialogueRegex = RegExp(
    r'\b(dialogues?|punch\s*dialogues?|mass\s*dialogues?|movie\s*scenes?|'
    r'comedy\s*scenes?|audio\s*scenes?|scenes?|ringtones?|bgm\s*ringtones?)\b',
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

  /// Devotional, temple chants, mantras, slokas, suprabhatam, and religious prayer tracks.
  static final RegExp _devotionalRegex = RegExp(
    r'\b(devotional|bakthi|bhakti|suprabh?atam|slokam|shlokam|bhajans?|a+rathi|a+rti|'
    r'mantra|gayatri|chalisa|stotram?|sahasranamam|namavali|keerthana(?:lu)?|kavacham|ashtakam|'
    r'aaradhana|srinivasa(?:ne)?|venkateswara|perumale|thirumalaiyil|govinda|ayyappan?|'
    r'vinayagar|murugan|mariamman|amman|shiva\s+stotram|om\s+namah|hare\s+rama|hanuman\s+chalisa|'
    r'veeramanidasan|bombay\s+sisters|mahanadhi\s+shobana|k\.\s*veeramani|pithukuli\s+murugadas)\b',
    caseSensitive: false,
  );

  /// Checks whether a track is a devotional/religious chant track.
  static bool isDevotionalTrack({
    required String title,
    String? album,
    String? artist,
  }) {
    final text = '$title ${album ?? ""} ${artist ?? ""}'.toLowerCase();
    return _devotionalRegex.hasMatch(text);
  }

  /// Convenience helper for Song entity.
  static bool isDevotionalSong(Song song) {
    return isDevotionalTrack(
      title: song.title,
      album: song.album,
      artist: song.artist,
    );
  }

  /// Evaluates and classifies a track candidate based on title, duration, and origin source.
  static ContentClassification classifyTrack({
    required String title,
    required int durationSec,
    String? source,
    String? artist,
    String? query,
  }) {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return ContentClassification.rejectedJunk;

    final qLower = (query ?? '').toLowerCase().trim();
    final queryExplicitlyRequestsDialogue = qLower.contains('dialogue') ||
        qLower.contains('scene') ||
        qLower.contains('ringtone');

    if (!queryExplicitlyRequestsDialogue && _dialogueRegex.hasMatch(cleanTitle)) {
      return ContentClassification.rejectedJunk;
    }

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
    String? query,
  }) {
    final qLower = (query ?? '').toLowerCase().trim();
    final queryExplicitlyRequestsDialogue = qLower.contains('dialogue') ||
        qLower.contains('scene') ||
        qLower.contains('ringtone');

    if (!queryExplicitlyRequestsDialogue && _dialogueRegex.hasMatch(title)) {
      return 'non-music spoken dialogue/scene';
    }
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
    String? query,
  }) =>
      rejectReason(
        title: title,
        durationSec: durationSec,
        allowUnknownDuration: allowUnknownDuration,
        query: query,
      ) ==
      null;

  /// Filters a list of songs. Spoken dialogue is filtered globally unless explicitly searched.
  static List<Song> filterSongs(
    Iterable<Song> songs, {
    bool allowUnknownDuration = true,
    String? query,
  }) {
    final qLower = (query ?? '').toLowerCase().trim();
    final queryExplicitlyRequestsDialogue = qLower.contains('dialogue') ||
        qLower.contains('scene') ||
        qLower.contains('ringtone');

    return songs.where((s) {
      if (!queryExplicitlyRequestsDialogue && _dialogueRegex.hasMatch(s.title)) {
        return false;
      }
      if (s.source != 'youtube') return true;
      return shouldKeep(
        title: s.title,
        durationSec: s.duration,
        allowUnknownDuration: allowUnknownDuration,
        query: query,
      );
    }).toList();
  }
}
