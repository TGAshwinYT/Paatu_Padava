import 'dart:async';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';
import '../models/song.dart';
import '../core/dsa/bk_tree.dart';
import 'saavn_client.dart';
import 'settings_manager.dart';
import 'app_logger.dart';

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
    'Mersal',
    'Aalaporaan Thamizhan',
    'Neethanae',
    'Mersal Arasan',
    'Maacho',
    'Sarkar',
    'Bigil',
    'Kaththi',
    'Theri',
    'Thuppakki',
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

  static final BkTree<String> _bkTree = BkTree<String>();
  static bool _bkTreeInitialized = false;

  static void _ensureInitialized() {
    if (!_bkTreeInitialized) {
      _bkTree.insertAll(_candidateDictionary);
      _bkTreeInitialized = true;
    }
  }

  /// Direct accessor for candidate dictionary terms
  static Set<String> get candidateDictionary {
    _ensureInitialized();
    return _candidateDictionary;
  }

  /// Evaluates whether [song] matches [query] across title, artist, and album.
  /// Includes full-phrase substring matching and 1-character typo tolerance (Levenshtein distance <= 1).
  static bool matchesSong(Song song, String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return false;

    final tLower = song.title.toLowerCase();
    final aLower = song.artist.toLowerCase();
    final albLower = song.album.toLowerCase();

    // 1. Instant full substring containment
    if (tLower.contains(lower) || aLower.contains(lower) || albLower.contains(lower)) {
      return true;
    }

    // 2. Tokenized & typo-tolerant matching (Levenshtein <= 1)
    final queryWords = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (queryWords.isEmpty) return false;

    final fullText = '$tLower $aLower $albLower';
    final songTokens = fullText.split(RegExp(r'[^a-zA-Z0-9]+')).where((t) => t.isNotEmpty).toList();

    return queryWords.every((qw) {
      if (songTokens.any((t) => t.contains(qw))) return true;
      if (qw.length >= 3) {
        final maxDist = qw.length >= 6 ? 2 : 1;
        return songTokens.any((t) =>
            (t.length - qw.length).abs() <= maxDist &&
            BkTree.levenshteinDistance(t, qw, maxDistance: maxDist) <= maxDist);
      }
      return false;
    });
  }

  /// Direct accessor for the underlying BK-Tree for diagnostic/testing purposes
  static BkTree<String> get bkTree {
    _ensureInitialized();
    return _bkTree;
  }

  /// Dynamically register candidate terms (from search history, favorites, or loaded songs)
  static void registerCandidates(Iterable<String> terms) {
    _ensureInitialized();
    for (final term in terms) {
      final sanitized = Song.sanitize(term).trim();
      if (sanitized.length >= 3) {
        if (_candidateDictionary.add(sanitized)) {
          _bkTree.insert(sanitized);
        }
      }
    }
  }

  /// Register songs into the dictionary for instantaneous local typo matching
  static void registerSongs(Iterable<Song> songs) {
    for (final song in songs) {
      registerCandidates([song.title, song.artist, song.album]);
    }
  }

  /// Evaluate if query contains a typo and locate the best match using O(log N) BK-Tree metric space search
  static FuzzyCorrectionResult? findCorrection(String query) {
    final cleanQuery = Song.sanitize(query).trim();
    if (cleanQuery.length < 3) return null;

    final lowerQuery = cleanQuery.toLowerCase();

    // Avoid correcting category queries or generic discovery terms (e.g. "Top Tamil Hits")
    final genericDiscoveryPattern = RegExp(
      r'^(?:top|best|latest|trending|new)?\s*(?:tamil|telugu|hindi|english|malayalam|kannada)?\s*(?:hits?|songs?|tracks?|melodies|vibes?)?$',
      caseSensitive: false,
    );
    if (genericDiscoveryPattern.hasMatch(cleanQuery)) {
      return null;
    }
    _ensureInitialized();

    // If exact case-insensitive match already exists, no typo correction is needed
    if (_candidateDictionary.any((c) => c.toLowerCase() == lowerQuery)) {
      return null;
    }

    try {
      // 1. Fast O(log N) metric space search using Burkhard-Keller Tree (max edit distance <= 2)
      final bkMatches = _bkTree.search(cleanQuery, maxDistance: 2, limit: 5);

      if (bkMatches.isNotEmpty) {
        final best = bkMatches.first;
        final tokenScore = tokenSetRatio(cleanQuery, best.term);
        final weightScore = weightedRatio(cleanQuery, best.term);
        final similarityPct = (best.similarity * 100).toInt();
        final combinedScore = (similarityPct + tokenScore + weightScore) ~/ 3;

        if (combinedScore >= 65 && best.term.toLowerCase() != lowerQuery) {
          return FuzzyCorrectionResult(
            original: cleanQuery,
            corrected: Song.sanitize(best.term),
            score: combinedScore,
          );
        }
      }

      // 2. Token-set fallback for multi-word permutations if edit distance > 2
      if (cleanQuery.contains(' ')) {
        final List<ExtractedResult<String>> matches = extractTop<String>(
          query: cleanQuery,
          choices: _candidateDictionary.toList(),
          limit: 3,
          cutoff: 70,
        );

        if (matches.isNotEmpty) {
          final best = matches.first;
          final tokenScore = tokenSetRatio(cleanQuery, best.choice);
          final weightScore = weightedRatio(cleanQuery, best.choice);
          final combinedScore = (best.score + tokenScore + weightScore) ~/ 3;

          final queryTokens = lowerQuery.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
          final choiceTokens = best.choice.toLowerCase().split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
          final extraTokens = choiceTokens.difference(queryTokens);

          if (combinedScore >= 70 && best.choice.toLowerCase() != lowerQuery && extraTokens.length <= 1) {
            return FuzzyCorrectionResult(
              original: cleanQuery,
              corrected: Song.sanitize(best.choice),
              score: combinedScore,
            );
          }
        }
      }
    } catch (e) {
      AppLogger.log('FuzzySearchService', 'Fuzzy correction notice: $e');
    }

    return null;
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
