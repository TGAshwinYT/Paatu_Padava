import 'package:html_unescape/html_unescape.dart';

/// App-wide genuine musical artist validator and channel sanitizer.
/// Purges record labels, television/YouTube channels, production banners,
/// and non-musician actors across search, artist recommendations, and queue playback.
class ArtistSanitizer {
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Decodes HTML entities (&amp;, &quot;, &#039;, &apos;, &lt;, &gt;) safely
  static String decodeHtml(String text) {
    if (text.isEmpty) return text;
    var decoded = _unescape.convert(text);
    decoded = decoded
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return decoded.trim();
  }

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
    'sithara entertainments',
    'vels film international',
    'sun tv',
    'star vijay',
    'kalaignar tv',
    'zee tamil',
    'divo movies',
    'sony music south',
    'saregama tamil',
    't-series tamil',
    'think music india',
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

  /// Non-Musician Actors / Comedians / Film Stars (Pure cast members who should not override composers/singers)
  static const Set<String> _nonMusicianActors = {
    'rajinikanth',
    'thalapathy vijay',
    'vijay',
    'ajith',
    'ajith kumar',
    'suriya',
    'surya',
    'karthi',
    'vikram',
    'chiyaan vikram',
    'vijay sethupathi',
    'sivakarthikeyan',
    'jayam ravi',
    'arya',
    'jiiva',
    'vishal',
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
    'yogi babu',
    'soori',
    'santhanam',
    'vivek',
    'nayanthara',
    'samantha',
    'samantha ruth prabhu',
    'trisha',
    'trisha krishnan',
    'keerthy suresh',
    'rashmika mandanna',
    'pooja hegde',
    'ram charan',
    'jr ntr',
    'prabhas',
    'allu arjun',
    'mahesh babu',
    'pawan kalyan',
    'yash',
    'darshan',
    'mammootty',
    'mohanlal',
    'fahadh faasil',
    'tovino thomas',
    'dulquer salmaan',
    'nivin pauly',
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

  /// Checks if a string represents multiple collaborating artists or a composite duo/trio.
  /// Examples: "Arijit Singh & Chinmayi Sripada", "Anirudh feat. Jonita", "Dhanush, Dhee"
  static bool isCompositeOrMultiArtist(String rawName) {
    final clean = decodeHtml(rawName);
    if (clean.isEmpty) return false;

    // Check for collaboration indicators
    final compositePattern = RegExp(
      r'(\s+(&|and|\+|x|vs\.?|with)\s+|[,/|]|\b(feat\.?|ft\.?|featuring|duet)\b)',
      caseSensitive: false,
    );
    return compositePattern.hasMatch(clean);
  }

  /// Canonical artist alias mapping for South/Indian music industry
  static const Map<String, String> _canonicalArtistMap = {
    'chinmayi sripada': 'Chinmayi',
    'chinmayi sumit': 'Chinmayi',
    'chinmayee': 'Chinmayi',
    'reetha anthony daasan': 'Anthony Daasan',
    'gnana anthony daasan': 'Anthony Daasan',
    'anthony dasan': 'Anthony Daasan',
    'antony daasan': 'Anthony Daasan',
    'antony dasan': 'Anthony Daasan',
    'a.r. rahman': 'A.R. Rahman',
    'ar rahman': 'A.R. Rahman',
    'a r rahman': 'A.R. Rahman',
    'a. r. rahman': 'A.R. Rahman',
    'rahman': 'A.R. Rahman',
    'anirudh ravichander': 'Anirudh Ravichander',
    'anirudh': 'Anirudh Ravichander',
    'yuvan shankar raja': 'Yuvan Shankar Raja',
    'yuvan': 'Yuvan Shankar Raja',
    'u1': 'Yuvan Shankar Raja',
    'harris jayaraj': 'Harris Jayaraj',
    'harris jeyaraj': 'Harris Jayaraj',
    'hiphop tamizha': 'Hiphop Tamizha',
    'hip hop tamizha': 'Hiphop Tamizha',
    'hiphop thamizha': 'Hiphop Tamizha',
    'g.v. prakash kumar': 'G.V. Prakash Kumar',
    'gv prakash kumar': 'G.V. Prakash Kumar',
    'g.v. prakash': 'G.V. Prakash Kumar',
    'gv prakash': 'G.V. Prakash Kumar',
    'santhosh narayanan': 'Santhosh Narayanan',
    'santosh narayanan': 'Santhosh Narayanan',
    'ilaiyaraaja': 'Ilaiyaraaja',
    'ilayaraja': 'Ilaiyaraaja',
    'ilaiyaraja': 'Ilaiyaraaja',
    'd. imman': 'D. Imman',
    'd imman': 'D. Imman',
    'imman': 'D. Imman',
    'sid sriram': 'Sid Sriram',
    'shreya ghoshal': 'Shreya Ghoshal',
    'shreya ghosal': 'Shreya Ghoshal',
    'vijay antony': 'Vijay Antony',
    'haricharan seshadri': 'Haricharan',
    's.p. balasubrahmanyam': 'S.P. Balasubrahmanyam',
    'sp balasubrahmanyam': 'S.P. Balasubrahmanyam',
    's. p. balasubrahmanyam': 'S.P. Balasubrahmanyam',
    'spb': 'S.P. Balasubrahmanyam',
    'k.s. chithra': 'K.S. Chithra',
    'ks chithra': 'K.S. Chithra',
    'k. s. chithra': 'K.S. Chithra',
    'chithra': 'K.S. Chithra',
    'k.j. yesudas': 'K.J. Yesudas',
    'kj yesudas': 'K.J. Yesudas',
    'k. j. yesudas': 'K.J. Yesudas',
    'yesudas': 'K.J. Yesudas',
    'swetha mohan': 'Swetha Mohan',
    'shweta mohan': 'Swetha Mohan',
    'pradeep kumar': 'Pradeep Kumar',
    'sean roldan': 'Sean Roldan',
    'andrea jeremiah': 'Andrea Jeremiah',
    'jonita gandhi': 'Jonita Gandhi',
    'bombay jayashri': 'Bombay Jayashri',
    'bombay jayashree': 'Bombay Jayashri',
    'harish raghavendra': 'Harish Raghavendra',
    'kaushik krish': 'Kaushik Krish',
    'anuradha sriram': 'Anuradha Sriram',
    'saindhavi': 'Saindhavi',
    'saindhavi g.v. prakash': 'Saindhavi',
    'saindhavi prakash': 'Saindhavi',
  };

  /// Common non-distinctive surnames/words that should not trigger false deduplication matches
  static const Set<String> _commonGenericNameWords = {
    'kumar',
    'singh',
    'sharma',
    'khan',
    'music',
    'raja',
    'iyer',
    'nair',
    'reddy',
    'das',
    'dasan',
  };

  /// Resolves an artist name to its canonical display name if known,
  /// or returns trimmed unescaped name.
  static String canonicalArtistName(String rawName) {
    final unescaped = _unescape.convert(rawName).trim();
    if (unescaped.isEmpty) return unescaped;
    final lower = unescaped.toLowerCase();
    return _canonicalArtistMap[lower] ?? unescaped;
  }

  /// Determines if two artist names refer to the same artist or a duplicate variant.
  /// Handles canonical aliases, honorific variations, and distinctive surname overlap.
  static bool areSameOrVariantArtists(String a, String b) {
    final cleanA = _unescape.convert(a).trim();
    final cleanB = _unescape.convert(b).trim();
    if (cleanA.isEmpty || cleanB.isEmpty) return false;

    // 1. Exact case-insensitive match
    if (cleanA.toLowerCase() == cleanB.toLowerCase()) return true;

    // 2. Canonical mapping match
    final canonA = canonicalArtistName(cleanA).toLowerCase();
    final canonB = canonicalArtistName(cleanB).toLowerCase();
    if (canonA == canonB) return true;

    // 3. Normalized alphanumeric string comparison (e.g. "A.R. Rahman" vs "AR Rahman")
    final alphaA = cleanA.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final alphaB = cleanB.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (alphaA.isNotEmpty && alphaA == alphaB) return true;

    // 4. Distinctive token containment check
    // If one is fully contained in the other and the contained portion is a distinctive artist name
    final lowerA = cleanA.toLowerCase();
    final lowerB = cleanB.toLowerCase();
    final shorter = lowerA.length <= lowerB.length ? lowerA : lowerB;
    final longer = lowerA.length <= lowerB.length ? lowerB : lowerA;

    // If shorter is a known canonical name or has distinctive multi-word tokens (>= 2 words)
    final shorterTokens = shorter.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (shorterTokens.length >= 2) {
      // Check if all tokens of shorter appear in order or together in longer
      final cleanShorterTokens = shorterTokens.where((t) => !_commonGenericNameWords.contains(t)).toList();
      if (cleanShorterTokens.length >= 2 && longer.contains(shorter)) {
        return true;
      }
    } else if (shorterTokens.length == 1) {
      final singleToken = shorterTokens.first;
      // Single distinctive name of length >= 6 (e.g. "chinmayi", "haricharan", "ilaiyaraaja", "anirudh")
      if (singleToken.length >= 6 && !_commonGenericNameWords.contains(singleToken)) {
        final longerTokens = longer.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (longerTokens.contains(singleToken)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Extracts the primary genuine musician (composer or playback singer)
  /// from a composite artist credit string (e.g. "Anirudh Ravichander, Thalapathy Vijay" -> "Anirudh Ravichander")
  static String extractPrimaryGenuineArtist(String artistString) {
    final unescaped = decodeHtml(artistString);
    if (unescaped.isEmpty) return 'Unknown Artist';

    final parts = unescaped.split(RegExp(r'[,&/|]|\bfeat\.?\b|\bft\.?\b|\bwith\b', caseSensitive: false));
    for (final part in parts) {
      final clean = part.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '').trim();
      if (clean.isNotEmpty && isGenuineArtist(clean)) {
        return clean;
      }
    }

    final first = parts.isNotEmpty ? parts.first.trim() : unescaped;
    return first.isNotEmpty ? first : 'Unknown Artist';
  }

  /// Extracts ALL genuine individual artists from a composite artist credit string,
  /// splitting by common collaboration delimiters (",", "&", "/", "|", "+", "feat.", "ft.", "with", "and").
  /// Returns a deduplicated list of clean genuine artist names preserving original casing.
  /// Example: "Anirudh Ravichander, Sai Abhyankkar" -> ["Anirudh Ravichander", "Sai Abhyankkar"]
  static List<String> extractAllGenuineArtists(String artistString) {
    final unescaped = decodeHtml(artistString);
    if (unescaped.isEmpty) return const [];

    final parts = unescaped.split(RegExp(
      r'[,&/|+]|\b(?:feat|ft|featuring|with|and)(?:\.|\b)',
      caseSensitive: false,
    ));

    final result = <String>[];
    final seen = <String>{};

    for (final part in parts) {
      var clean = part.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '').trim();
      clean = clean.replaceAll(RegExp(r'^[.\s,:|/\-]+'), '');
      clean = clean.replaceAll(RegExp(r'[\s,:|/\-]+$'), '').trim();

      if (clean.isNotEmpty && isGenuineArtist(clean)) {
        final lower = clean.toLowerCase();
        if (seen.add(lower)) {
          result.add(clean);
        }
      }
    }

    // Fallback: if no split part passed isGenuineArtist (e.g. newly debuted indie artist),
    // include parts that are not known record labels or production houses
    if (result.isEmpty) {
      for (final part in parts) {
        var clean = part.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '').trim();
        clean = clean.replaceAll(RegExp(r'^[.\s,:|/\-]+'), '');
        clean = clean.replaceAll(RegExp(r'[\s,:|/\-]+$'), '').trim();

        if (clean.isNotEmpty && !isRecordLabelOrChannel(clean)) {
          final lower = clean.toLowerCase();
          if (seen.add(lower)) {
            result.add(clean);
          }
        }
      }
    }

    if (result.isEmpty && unescaped.isNotEmpty) {
      result.add(unescaped);
    }

    return result;
  }
}

