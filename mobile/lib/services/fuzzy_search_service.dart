import 'dart:async';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';
import '../models/song.dart';
import '../core/dsa/bk_tree.dart';
import '../core/dsa/lru_cache.dart';
import '../core/dsa/symspell.dart';
import '../core/dsa/trigram_index.dart';
import 'saavn_client.dart';
import '../logic/lyrics/indic_romanizer.dart';
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
  static const Set<String> _coreDictionary = {
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
    'Naa Ready', 'Badass', 'Hukum', 'Arabic Kuthu', 'Vaseegara',
    'Why This Kolaveri Di', 'Rowdy Baby', 'Kaavaalaa', 'Chinna Chinna Aasai',
    'Munbe Vaa', 'Nenjukkul Peidhidum', 'Enjoy Enjaami', 'Ordinary Person',
    'Bloody Sweet', 'Chellamma', 'Vaathi Coming', 'Kutty Story',
    'Master the Blaster', 'Dippam Dappam',
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

  static final Set<String> _candidateDictionary = Set<String>.from(_coreDictionary);
  static const int maxDynamicCandidates = 100;
  static final List<String> _dynamicHistory = [];
  static final LruCache<String, FuzzyCorrectionResult?> _correctionCache =
      LruCache<String, FuzzyCorrectionResult?>(capacity: 100);

  static final BkTree<String> _bkTree = BkTree<String>();
  static final SymSpell _symSpell = SymSpell(maxEditDistance: 2);
  static final TrigramIndex<String> _trigramIndex = TrigramIndex<String>();
  static final Map<String, String> _normalizedToOriginal = {};
  static final Set<String> _lowercaseCandidateSet = <String>{};
  static bool _bkTreeInitialized = false;

  static String _normKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s,._\-!?/\\&|:;()\[\]{}"]+'), '');

  static void _rebuildAll() {
    _candidateDictionary
      ..clear()
      ..addAll(_coreDictionary)
      ..addAll(_dynamicHistory);

    _lowercaseCandidateSet.clear();
    _normalizedToOriginal.clear();
    _bkTree.clear();
    _symSpell.clear();
    _trigramIndex.clear();

    _bkTree.insertAll(_candidateDictionary);
    for (final term in _candidateDictionary) {
      _lowercaseCandidateSet.add(term.toLowerCase().trim());
      _normalizedToOriginal[_normKey(term)] = term;
      _symSpell.insert(term);
      _trigramIndex.insert(term, payload: term);
    }
    _correctionCache.clear();
  }

  static void _ensureInitialized() {
    if (!_bkTreeInitialized) {
      _rebuildAll();
      _bkTreeInitialized = true;
    }
  }

  /// High-performance O(1) membership check against the candidate dictionary
  static bool containsCandidate(String term) {
    _ensureInitialized();
    return _lowercaseCandidateSet.contains(term.toLowerCase().trim());
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

    bool matchesWordStart(String text, String prefix) {
      if (text.startsWith(prefix)) return true;
      final tokens = text.split(RegExp(r'[\s,._\-!?/\\&|:;()[\]{}"]+'));
      for (final t in tokens) {
        if (t.startsWith(prefix)) return true;
      }
      return false;
    }

    // 1. Short queries (< 3 chars): strictly require word-start prefix match to prevent noisy substring collisions
    if (lower.length < 3) {
      return matchesWordStart(tLower, lower) || matchesWordStart(aLower, lower) || matchesWordStart(albLower, lower);
    }

    // 2. Full substring containment (for queries >= 3 chars)
    if (tLower.contains(lower) || aLower.contains(lower) || albLower.contains(lower)) {
      return true;
    }

    // 2. Tokenized & typo-tolerant matching (Levenshtein <= 1)
    final queryWords = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (queryWords.isEmpty) return false;

    final fullText = '$tLower $aLower $albLower';
    final songTokens = fullText.split(RegExp(r'[\s,._\-!?/\\&|:;()\[\]{}"]+')).where((t) => t.isNotEmpty).toList();

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

  /// Dynamically register candidate terms with strict capacity bounding (max 100 dynamic entries)
  static void registerCandidates(Iterable<String> terms) {
    _ensureInitialized();

    // Enforce strict upper bound on dynamic dictionary size (max 100 dynamic entries).
    // Perform bulk pruning and single rebuild BEFORE insertion loop, never on every iteration.
    final candidateList = terms.toList();
    if (_dynamicHistory.isNotEmpty && (_dynamicHistory.length + candidateList.length >= maxDynamicCandidates)) {
      final excess = (_dynamicHistory.length + candidateList.length) - maxDynamicCandidates + 25;
      final pruneCount = excess.clamp(1, _dynamicHistory.length);
      _dynamicHistory.removeRange(0, pruneCount);
      _rebuildAll();
    }

    bool addedAny = false;
    for (final term in candidateList) {
      if (_dynamicHistory.length >= maxDynamicCandidates) break;
      final sanitized = Song.sanitize(term).trim();
      if (sanitized.length < 3 || sanitized.length > 35) continue;
      final lower = sanitized.toLowerCase();
      if (_lowercaseCandidateSet.contains(lower)) continue;

      if (_candidateDictionary.add(sanitized)) {
        _dynamicHistory.add(sanitized);
        _lowercaseCandidateSet.add(lower);
        _normalizedToOriginal[_normKey(sanitized)] = sanitized;
        _bkTree.insert(sanitized);
        _symSpell.insert(sanitized);
        _trigramIndex.insert(sanitized, payload: sanitized);
        if (IndicRomanizer.hasIndicScript(sanitized)) {
          final roman = IndicRomanizer.romanize(sanitized).trim();
          final rLower = roman.toLowerCase();
          if (roman.length >= 3 && _candidateDictionary.add(roman)) {
            _dynamicHistory.add(roman);
            _lowercaseCandidateSet.add(rLower);
            _normalizedToOriginal[_normKey(roman)] = roman;
            _bkTree.insert(roman);
            _symSpell.insert(roman);
            _trigramIndex.insert(roman, payload: sanitized);
          }
        }
        addedAny = true;
      }
    }
    if (addedAny) {
      _correctionCache.clear();
    }
  }

  /// Register verified song titles and primary artists from library into the dictionary (capped to 100)
  static void registerSongs(Iterable<Song> songs) {
    final terms = <String>[];
    for (final song in songs.take(100)) {
      if (song.title.isNotEmpty && song.title.length <= 35) {
        terms.add(song.title);
      }
      if (song.primaryArtist.isNotEmpty && song.primaryArtist.length <= 30) {
        terms.add(song.primaryArtist);
      }
    }
    if (terms.isNotEmpty) registerCandidates(terms);
  }

  /// Evaluate if query contains a typo and locate the best match using O(log N) BK-Tree metric space search
  static FuzzyCorrectionResult? findCorrection(String query) {
    final cleanQuery = Song.sanitize(query).trim();
    if (cleanQuery.length <= 3) return null;

    final lowerQuery = cleanQuery.toLowerCase();

    // Check O(1) LRU correction cache
    if (_correctionCache.containsKey(lowerQuery)) {
      return _correctionCache.get(lowerQuery);
    }

    // Avoid correcting category queries or generic discovery terms (e.g. "Top Tamil Hits")
    final genericDiscoveryPattern = RegExp(
      r'^(?:top|best|latest|trending|new)?\s*(?:tamil|telugu|hindi|english|malayalam|kannada)?\s*(?:hits?|songs?|tracks?|melodies|vibes?)?$',
      caseSensitive: false,
    );
    if (genericDiscoveryPattern.hasMatch(cleanQuery)) {
      _correctionCache.put(lowerQuery, null);
      return null;
    }
    _ensureInitialized();

    // If exact case-insensitive match already exists, no typo correction is needed
    if (_lowercaseCandidateSet.contains(lowerQuery)) {
      _correctionCache.put(lowerQuery, null);
      return null;
    }

    FuzzyCorrectionResult? result;
    try {
      // 0a. Ultra-fast O(1) SymSpell typo lookup (< 0.2ms)
      final symSpellMatches = _symSpell.lookup(cleanQuery, maxDistance: 2, limit: 3);
      if (symSpellMatches.isNotEmpty) {
        final best = symSpellMatches.first;
        final resolved = _normalizedToOriginal[best.term] ?? best.term;
        if (best.distance > 0 && resolved.toLowerCase() != lowerQuery) {
          final tokenScore = tokenSetRatio(cleanQuery, resolved);
          final weightScore = weightedRatio(cleanQuery, resolved);
          final combinedScore = (((1.0 - (best.distance / cleanQuery.length)) * 100).toInt() + tokenScore + weightScore) ~/ 3;
          if (combinedScore >= 65) {
            result = FuzzyCorrectionResult(
              original: cleanQuery,
              corrected: resolved,
              score: combinedScore,
            );
          }
        }
      }

      // 0b. Tri-Gram Tanglish phonetic transliteration lookup (< 1.5ms)
      if (result == null) {
        final triMatches = _trigramIndex.search(cleanQuery, threshold: 0.50, limit: 3);
        if (triMatches.isNotEmpty) {
          final best = triMatches.first;
          final resolved = best.payload ?? _normalizedToOriginal[_normKey(best.term)] ?? best.term;
          if (resolved.toLowerCase() != lowerQuery && best.similarity >= 0.55) {
            result = FuzzyCorrectionResult(
              original: cleanQuery,
              corrected: resolved,
              score: (best.similarity * 100).toInt(),
            );
          }
        }
      }

      // 1. Fast O(log N) metric space search using Burkhard-Keller Tree (max edit distance <= 2)
      if (result == null) {
        final bkMatches = _bkTree.search(cleanQuery, maxDistance: 2, limit: 5);
        if (bkMatches.isNotEmpty) {
          final best = bkMatches.first;
          final resolved = _normalizedToOriginal[_normKey(best.term)] ?? best.term;
          final tokenScore = tokenSetRatio(cleanQuery, resolved);
          final weightScore = weightedRatio(cleanQuery, resolved);
          final similarityPct = (best.similarity * 100).toInt();
          final combinedScore = (similarityPct + tokenScore + weightScore) ~/ 3;

          if (combinedScore >= 65 && resolved.toLowerCase() != lowerQuery) {
            result = FuzzyCorrectionResult(
              original: cleanQuery,
              corrected: resolved,
              score: combinedScore,
            );
          }
        }
      }

      // 2. Token-set fallback for multi-word permutations if edit distance > 2
      if (result == null && cleanQuery.contains(' ')) {
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
            result = FuzzyCorrectionResult(
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

    _correctionCache.put(lowerQuery, result);
    return result;
  }

  /// Execute fallback search using fuzzy corrected query if primary search produced 0 results
  static Future<List<Song>> executeFallbackSearch(
    String originalQuery, {
    String? language,
  }) async {
    final correction = findCorrection(originalQuery);
    if (correction == null) return [];

    final effectiveLang = (language != null && language.isNotEmpty && language.toLowerCase() != 'all') ? language : null;
    return await SaavnClient.search(correction.corrected, limit: 20, language: effectiveLang);
  }
}
