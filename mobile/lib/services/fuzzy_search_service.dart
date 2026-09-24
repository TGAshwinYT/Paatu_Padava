import 'dart:async';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';
import '../models/song.dart';
import 'saavn_client.dart';
import 'settings_manager.dart';

class FuzzyCorrectionResult {
  final String original;
  final String corrected;
  final int score;

  const FuzzyCorrectionResult({
    required this.original,
    required this.corrected,
    required this.score,
  });
}

class FuzzySearchService {
  static final Set<String> _candidateDictionary = {
    // Top Regional & Tamil Artists
    'Anirudh Ravichander',
    'A.R. Rahman',
    'Harris Jayaraj',
    'Yuvan Shankar Raja',
    'Ilaiyaraaja',
    'Santhosh Narayanan',
    'Sid Sriram',
    'D. Imman',
    'G.V. Prakash Kumar',
    'Sean Roldan',
    'Hiphop Tamizha',
    'Shreya Ghoshal',
    'S.P. Balasubrahmanyam',
    'K.J. Yesudas',
    'Pradeep Kumar',
    'Dhanush',
    'Karthik',
    'Hariharan',
    'Vijay Antony',
    'Shweta Mohan',
    'Jonita Gandhi',
    'Andrea Jeremiah',

    // Popular Tamil Tracks & Movie Hits
    'Naa Ready',
    'Badass',
    'Hukum',
    'Arabic Kuthu',
    'Vaseegara',
    'Why This Kolaveri Di',
    'Rowdy Baby',
    'Kaavaalaa',
    'Chinna Chinna Aasai',
    'Munbe Vaa',
    'Nenjukkul Peidhidum',
    'Enjoy Enjaami',
    'Ordinary Person',
    'Bloody Sweet',
    'Chellamma',
    'Vaathi Coming',
    'Kutty Story',
    'Master the Blaster',
    'Dippam Dappam',
    'Megham Karukatha',
    'Two Two Two',
    'Kanave Kanave',
    'Porkanda Singam',
    'Pathala Pathala',
    'Vikram Title Track',
    'Once Upon a Time',
    'Marakkuma Nenjam',
    'Mallipoo',
    'Chola Chola',
    'Aga Naga',
    'Ponni Nadhi',
    'Kadhaippoma',
    'Bae',
    'Jimikki Ponnu',
    'Ranjithame',
    'Thee Thalapathy',
    'Soul of Varisu',
    'Leo',
    'Jailer',
    'Vikram',
    'Master',
    'Varisu',
    'Ponniyin Selvan',
    'Thunivu',
    'Beast',
    'Doctor',
    'Don',
    'Petta',
    'Kabali',
    'Enthiran',
  };

  /// Dynamically register candidate terms (from search history, favorites, or loaded songs)
  static void registerCandidates(Iterable<String> terms) {
    for (final term in terms) {
      final sanitized = Song.sanitize(term).trim();
      if (sanitized.length >= 3) {
        _candidateDictionary.add(sanitized);
      }
    }
  }

  /// Register songs into the dictionary for instantaneous local typo matching
  static void registerSongs(Iterable<Song> songs) {
    for (final song in songs) {
      registerCandidates([song.title, song.artist, song.album]);
    }
  }

  /// Evaluate if query contains a typo and locate the best match (> 70 score)
  static FuzzyCorrectionResult? findCorrection(String query) {
    final cleanQuery = Song.sanitize(query).trim();
    if (cleanQuery.length < 3) return null;

    final lowerQuery = cleanQuery.toLowerCase();

    // If exact case-insensitive match already exists, no typo correction is needed
    if (_candidateDictionary.any((c) => c.toLowerCase() == lowerQuery)) {
      return null;
    }

    try {
      final List<ExtractedResult<String>> matches = extractTop<String>(
        query: cleanQuery,
        choices: _candidateDictionary.toList(),
        limit: 3,
        cutoff: 70,
      );

      if (matches.isNotEmpty) {
        final best = matches.first;
        // Verify tokenSetRatio as well for robust token reordering tolerance
        final tokenScore = tokenSetRatio(cleanQuery, best.choice);
        final weightScore = weightedRatio(cleanQuery, best.choice);
        final combinedScore = (best.score + tokenScore + weightScore) ~/ 3;

        if (combinedScore >= 70 && best.choice.toLowerCase() != lowerQuery) {
          return FuzzyCorrectionResult(
            original: cleanQuery,
            corrected: Song.sanitize(best.choice),
            score: combinedScore,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  /// Re-ranks song search results based on fuzzy token similarity
  static List<Song> reRankSongs(String query, List<Song> songs) {
    if (songs.length <= 1 || query.trim().isEmpty) return songs;

    final cleanQuery = Song.sanitize(query).trim();
    final List<MapEntry<Song, int>> scored = [];

    for (final song in songs) {
      final target = '${song.title} ${song.artist}';
      final score = tokenSetRatio(cleanQuery, target);
      scored.add(MapEntry(song, score));
    }

    // Sort descending by similarity score
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  /// Execute fallback search using fuzzy corrected query if primary search produced 0 results
  static Future<List<Song>> executeFallbackSearch(
    String originalQuery, {
    String? language,
  }) async {
    final correction = findCorrection(originalQuery);
    if (correction == null) return [];

    final prefLang = language ?? SettingsManager.preferredLanguages.firstOrNull ?? 'tamil';
    return await SaavnClient.search(correction.corrected, limit: 20, language: prefLang);
  }
}
