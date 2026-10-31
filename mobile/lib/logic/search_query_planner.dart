import '../models/song.dart';
import '../domain/models/clustered_track_result.dart';
import '../services/youtube/youtube_title_cleaner.dart';
import '../services/artist_sanitizer.dart';
import '../services/spotify_track_key.dart';

/// Explicit type of search intent detected from user input.
enum QueryIntentType {
  song,
  collectionOrMovie,
  artist,
  mixOrBgm,
}

/// Analysis metadata for a search query.
class QueryIntentAnalysis {
  final String rawQuery;
  final String cleanQuery;
  final QueryIntentType intentType;
  final String? explicitLanguage;
  final bool isExplicitMixRequest;

  const QueryIntentAnalysis({
    required this.rawQuery,
    required this.cleanQuery,
    required this.intentType,
    this.explicitLanguage,
    this.isExplicitMixRequest = false,
  });
}

/// Decides query planning, intent detection, and cross-source track canonicalization across search providers.
class SearchQueryPlanner {
  SearchQueryPlanner._();

  static final RegExp _mixIntentRegex = RegExp(
    r'\b(mashup|bgm|ost|theme|slowed|reverb|remix|lo[\s\-]?fi|cover|acoustic|instrumental|unplugged)\b',
    caseSensitive: false,
  );

  static final RegExp _collectionIntentRegex = RegExp(
    r'\b(soundtrack|movie|album|songs|all\s*songs|jukebox|discography)\b',
    caseSensitive: false,
  );

  static final RegExp _artistIntentRegex = RegExp(
    r'\b(hits|best\s*of|collection|all\s*hits)\b',
    caseSensitive: false,
  );

  /// Recent searches, trending-artist chips and typed text: searched EXACTLY as written.
  static String forExactQuery(String query) => query.trim();

  /// Browse-category tiles ("Workout", "Party"): add the user's preferred
  /// language only when the query does not already name a language.
  static String forCategory(
    String query, {
    required String preferredLanguage,
    String? explicitLanguage,
  }) {
    final clean = query.trim();
    final pref = preferredLanguage.trim();
    if (pref.isEmpty) return clean;
    if (explicitLanguage != null) return clean;
    if (clean.toLowerCase().contains(pref.toLowerCase())) return clean;
    return '$pref $clean';
  }

  /// Parses search query to detect intended search category (Song, Movie/Album, Artist, Mix/BGM).
  static QueryIntentAnalysis analyzeQuery(String query, {String? explicitLanguage}) {
    final clean = query.trim();
    final lower = clean.toLowerCase();

    final isMix = _mixIntentRegex.hasMatch(lower);
    if (isMix) {
      return QueryIntentAnalysis(
        rawQuery: query,
        cleanQuery: clean,
        intentType: QueryIntentType.mixOrBgm,
        explicitLanguage: explicitLanguage,
        isExplicitMixRequest: true,
      );
    }

    if (_collectionIntentRegex.hasMatch(lower)) {
      return QueryIntentAnalysis(
        rawQuery: query,
        cleanQuery: clean,
        intentType: QueryIntentType.collectionOrMovie,
        explicitLanguage: explicitLanguage,
      );
    }

    if (_artistIntentRegex.hasMatch(lower)) {
      return QueryIntentAnalysis(
        rawQuery: query,
        cleanQuery: clean,
        intentType: QueryIntentType.artist,
        explicitLanguage: explicitLanguage,
      );
    }

    return QueryIntentAnalysis(
      rawQuery: query,
      cleanQuery: clean,
      intentType: QueryIntentType.song,
      explicitLanguage: explicitLanguage,
      isExplicitMixRequest: false,
    );
  }

  /// Cleans titles removing YouTube video baggage, bracketed film tags, and promotional markers.
  static String cleanTitle(String title) {
    var cleaned = YouTubeTitleCleaner.cleanTitle(title);
    cleaned = cleaned
        .replaceAll(RegExp(r'\((?:from|soundtrack|ost)[^)]*\)', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\[(?:from|soundtrack|ost)[^\]]*\]', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b(?:from|soundtrack|ost)\s+["\w\s]+$', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b(video|audio|lyric|lyrical|full)?\s*songs?\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isNotEmpty ? cleaned : title.trim();
  }

  /// Extracts the canonical core title by stripping fan mix/version tags for grouping.
  static String extractNormalizedCoreTitle(String title) {
    var core = cleanTitle(title);
    core = core
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ')
        .replaceAll(RegExp(r'\s+(?:x|vs)\s+.*?\b(?:mashup|remix|mix|edit|flip|version)\b.*$', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s*[-|–]\s*(lo[\s\-]?fi|slowed|reverb|8d|mashup|bgm|remix|acoustic|cover|unplugged|theme|flip|version|edit|mix).*$', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b(lo[\s\-]?fi|slowed|reverb|8d|mashup|bgm|remix|acoustic|cover|unplugged|theme|flip|version|edit|mix)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    return core.isNotEmpty ? core : title.trim().toLowerCase();
  }

  /// Computes a 0.0 to 1.0 confidence score for Smart Crown Top Result promotion.
  static double calculateRelevanceScore({
    required String query,
    required Song song,
    required ContentClassification classification,
    bool isExplicitMixRequest = false,
  }) {
    final qNorm = SpotifyTrackKey.norm(query);
    final tNorm = SpotifyTrackKey.norm(song.title);
    final aNorm = SpotifyTrackKey.norm(song.artist);

    if (qNorm.isEmpty || tNorm.isEmpty) return 0.0;

    double score = 0.50;

    // Exact title match
    if (qNorm == tNorm) {
      score += 0.35;
    } else if (tNorm.contains(qNorm) || qNorm.contains(tNorm)) {
      score += 0.25;
    } else {
      final qTokens = qNorm.split(' ').where((t) => t.length > 2).toSet();
      final tTokens = tNorm.split(' ').where((t) => t.length > 2).toSet();
      if (qTokens.isNotEmpty && qTokens.intersection(tTokens).length == qTokens.length) {
        score += 0.20;
      }
    }

    // Artist overlap
    if (aNorm.isNotEmpty && qNorm.contains(aNorm)) {
      score += 0.15;
    }

    // Source authority
    if (song.source == 'saavn' || song.source == 'jiosaavn') {
      score += 0.10; // Studio audio quality guarantee
    }

    // Classification alignment
    if (classification == ContentClassification.officialTrack) {
      score += 0.05;
    } else if (classification == ContentClassification.fanMixOrVersion) {
      if (!isExplicitMixRequest) {
        score -= 0.20; // Penalize fan mixes for standard song searches
      } else {
        score += 0.15; // User specifically asked for BGM/Mix
      }
    } else {
      score = 0.0;
    }

    return score.clamp(0.0, 1.0);
  }

  /// Generates a canonical fingerprint: lowercase(clean_title) + '|' + primary_artist
  static String generateCanonicalFingerprint(String title, String artist) {
    final cleaned = cleanTitle(title);
    final normTitle = SpotifyTrackKey.norm(cleaned);

    var decodedArtist = ArtistSanitizer.decodeHtml(artist);
    decodedArtist = decodedArtist.replaceAll(RegExp(r'\s*-\s*topic\b', caseSensitive: false), '').trim();

    final firstArtist = decodedArtist
        .split(RegExp(r'[,&/|]|\bfeat\.?\b|\bft\.?\b|\bwith\b', caseSensitive: false))
        .map(SpotifyTrackKey.norm)
        .firstWhere((a) => a.isNotEmpty, orElse: () => '');

    return '$normTitle|$firstArtist';
  }

  /// True when two tracks across sources represent the exact same recording.
  static bool isSameSong({
    required String titleA,
    required String artistsA,
    required String titleB,
    required String artistsB,
  }) {
    final fpA = generateCanonicalFingerprint(titleA, artistsA);
    final fpB = generateCanonicalFingerprint(titleB, artistsB);
    if (fpA.isNotEmpty && fpA == fpB) return true;

    return SpotifyTrackKey.sameTrack(
      titleA: cleanTitle(titleA),
      artistsA: artistsA,
      titleB: cleanTitle(titleB),
      artistsB: artistsB,
    );
  }

  /// Plans targeted queries for concurrent multi-source fetching (JioSaavn and YouTube Music)
  static Map<String, String> planMultiSourceQueries(
    String cleanQuery, {
    String? explicitLanguage,
  }) {
    final clean = cleanQuery.trim();
    final lower = clean.toLowerCase();

    final saavnQuery = (explicitLanguage != null && !lower.contains(explicitLanguage.toLowerCase()))
        ? '${explicitLanguage.trim()} $clean'
        : clean;

    return {
      'saavn': saavnQuery,
      'youtube': clean,
    };
  }
}
