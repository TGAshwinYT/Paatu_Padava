import '../services/youtube/youtube_title_cleaner.dart';
import '../services/artist_sanitizer.dart';
import '../services/spotify_track_key.dart';

/// Decides query planning and cross-source track canonicalization across search providers.
class SearchQueryPlanner {
  SearchQueryPlanner._();

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

  /// Cleans titles removing YouTube video baggage, bracketed film tags, and promotional markers
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

  /// Generates a canonical fingerprint: lowercase(clean_title) + '|' + primary_artist
  /// Prevents the same song from JioSaavn and YouTube Music from appearing as duplicates.
  static String generateCanonicalFingerprint(String title, String artist) {
    final cleaned = cleanTitle(title);
    final normTitle = SpotifyTrackKey.norm(cleaned);

    var decodedArtist = ArtistSanitizer.decodeHtml(artist);
    // Strip YouTube Topic channel marker "- Topic"
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

    // JioSaavn needs explicit language prepended if not already in query to prevent Hindi leaks
    final saavnQuery = (explicitLanguage != null && !lower.contains(explicitLanguage.toLowerCase()))
        ? '${explicitLanguage.trim()} $clean'
        : clean;

    // YouTube Music InnerTube performs best with raw clean query without synthetic language noise
    final ytQuery = clean;

    return {
      'saavn': saavnQuery,
      'youtube': ytQuery,
    };
  }
}
