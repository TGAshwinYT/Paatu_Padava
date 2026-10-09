import 'package:html_unescape/html_unescape.dart';

/// App-wide genuine musical artist validator and channel sanitizer.
/// Purges record labels, television/YouTube channels, production banners,
/// and non-musician actors across search, artist recommendations, and queue playback.
class ArtistSanitizer {
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Known Record Labels & Music Corporations
  static const Set<String> _recordLabels = {
    't-series',
    'tseries',
    'sony music',
    'sonymusic',
    'saregama',
    'think music',
    'thinkmusic',
    'think indie',
    'thinkindie',
    'zee music',
    'zeemusic',
    'lahari music',
    'lahari',
    'aditya music',
    'tips official',
    'tips',
    'venus',
    'eros now',
    'eros',
    'times music',
    'divo',
    'trend music',
    'trendmusic',
    'speed audio',
    'satyam audio',
    'satyam audios',
    'universal music',
    'muzik247',
    'eastman',
    'gemini music',
    'mass music',
    'speed records',
    'ananda audio',
    'svf music',
    'sathya movies',
    'music company',
    'record label',
    'records',
  };

  /// Channels, Media Houses & Film Production Banners
  static const Set<String> _mediaAndProductionBanners = {
    'vevo',
    'topic',
    '- topic',
    'channel',
    'entertainment',
    'official',
    'media',
    'productions',
    'films',
    'movies',
    'television',
    'tv',
    'behindwoods',
    'galatta',
    'black sheep',
    'madras central',
    'chuchu',
    'chuchutv',
    'lyca',
    'sun pictures',
    'red giant',
    'studio green',
    'ags entertainment',
    'viacom18',
    'zee studios',
    'hombale films',
    'mythri movie makers',
    'geetha arts',
    'dvv entertainment',
    'sun tv',
    'star vijay',
    'kalaignar tv',
    'zee tamil',
  };

  /// Generic Non-Artist Audio Tags
  static const Set<String> _nonArtistGenericTags = {
    'gospel',
    'rhymes',
    'nursery',
    'lullaby',
    'devotional',
    'dialogue',
    'comedy',
    'scenes',
    'trailer',
    'teaser',
    'soundtrack',
    'karaoke',
    'instrumental cover',
    'ringtone',
    'bgm',
    'status',
  };

  /// Non-Musician Actors / Comedians (Pure cast members who do not sing or compose)
  static const Set<String> _nonMusicianActors = {
    'rajinikanth',
    'thalapathy vijay',
    'ajith',
    'ajith kumar',
    'suriya',
    'surya',
    'karthi',
    'vijay sethupathi',
    'vadivelu',
    'prakash raj',
    'nasser',
    'radha ravi',
    'brahmanandam',
    'goundamani',
    'senthil',
    'manivannan',
    'ms bhaskar',
    'kota srinivasa rao',
    'ashish vidyarthi',
    'sayaji shinde',
    'mansoor ali khan',
    'anandaraj',
    'ponvannan',
    'delhi ganesh',
    'vijayan',
    'raghuvaran',
  };

  /// Validates whether a candidate map or name represents a genuine musical artist.
  static bool isGenuineArtist(dynamic candidate) {
    if (candidate == null) return false;

    String rawName = '';
    String role = '';

    if (candidate is Map) {
      rawName = (candidate['name'] ?? candidate['title'] ?? '').toString();
      role = (candidate['role'] ?? candidate['extra'] ?? candidate['subtitle'] ?? '').toString().toLowerCase().trim();
    } else {
      rawName = candidate.toString();
    }

    rawName = _unescape.convert(rawName).toLowerCase().trim();
    if (rawName.isEmpty || rawName == 'unknown artist' || rawName == 'various artists') {
      return false;
    }

    // 1. Check Record Label match
    for (final label in _recordLabels) {
      if (rawName == label || rawName.contains(label)) return false;
    }

    // 2. Check Media and Channel match
    for (final media in _mediaAndProductionBanners) {
      if (rawName == media || rawName.contains(media)) return false;
    }

    // 3. Check Generic non-artist keywords
    for (final tag in _nonArtistGenericTags) {
      if (rawName == tag || rawName.contains(tag)) return false;
    }

    // 4. Check Non-musician actors
    for (final actor in _nonMusicianActors) {
      if (rawName == actor || rawName.contains(actor)) return false;
    }

    // 5. Role validation if present
    if (role.isNotEmpty) {
      final isActor = role.contains('actor') || role.contains('starring') || role.contains('cast');
      final isMusician = role.contains('music') ||
          role.contains('singer') ||
          role.contains('composer') ||
          role.contains('director') ||
          role.contains('lyricist') ||
          role.contains('vocalist') ||
          role.contains('artist');
      if (isActor && !isMusician) {
        return false;
      }
    }

    return true;
  }

  /// Checks if a string is a known record label or channel name
  static bool isRecordLabelOrChannel(String name) {
    final lower = name.toLowerCase().trim();
    for (final label in _recordLabels) {
      if (lower == label || lower.contains(label)) return true;
    }
    for (final media in _mediaAndProductionBanners) {
      if (lower == media || lower.contains(media)) return true;
    }
    return false;
  }

  /// Sanitizes YouTube video artist attribution.
  /// If the channel author is a record label or VEVO channel (e.g. "SonyMusicSouthVEVO"),
  /// extracts genuine musical artists from delimiters in the video title,
  /// or falls back to "Soundtrack / Film Cast".
  static String extractArtistFromVideo(String videoTitle, String videoAuthor) {
    final unescapedTitle = _unescape.convert(videoTitle).trim();

    // 0. Detect leading @handle (e.g. "@SaiAbhyankkar - Pavazha Malli")
    final handleMatch = RegExp(r'^@([a-zA-Z0-9_.]+)').firstMatch(unescapedTitle);
    if (handleMatch != null) {
      final rawHandle = handleMatch.group(1)!;
      // Convert PascalCase / snake_case: "SaiAbhyankkar" -> "Sai Abhyankkar"
      final formatted = rawHandle
          .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m.group(1)} ${m.group(2)}')
          .replaceAll(RegExp(r'[_.]'), ' ')
          .trim();
      if (formatted.isNotEmpty && !isRecordLabelOrChannel(formatted)) {
        return formatted;
      }
    }

    final cleanAuthor = videoAuthor.trim();
    if (cleanAuthor.isNotEmpty && !isRecordLabelOrChannel(cleanAuthor)) {
      return cleanAuthor;
    }

    // Author is a label/channel: parse title for artist indicators
    // Common patterns: "Song Name | Movie | Singer / Composer"
    final pipeParts = unescapedTitle.split('|').map((s) => s.trim()).toList();
    for (var i = pipeParts.length - 1; i >= 1; i--) {
      final candidate = pipeParts[i].replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '').trim();
      if (candidate.isNotEmpty && isGenuineArtist(candidate)) {
        return candidate;
      }
    }

    // Pattern: "Song Name - Singer / Composer"
    final dashParts = unescapedTitle.split(' - ').map((s) => s.trim()).toList();
    for (var i = dashParts.length - 1; i >= 1; i--) {
      final candidate = dashParts[i].replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '').trim();
      if (candidate.isNotEmpty && isGenuineArtist(candidate)) {
        return candidate;
      }
    }

    return 'Original Soundtrack';
  }
}
