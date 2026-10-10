import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import '../models/song.dart';
import '../domain/models/app_error.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';
import 'settings_manager.dart';
import 'fuzzy_search_service.dart';
import 'error_handler.dart';
import '../data/repositories/song_repository.dart';

class QueryIntent {
  final String rawQuery;
  final String cleanQuery;
  final String? detectedScript;
  final String? explicitLanguage;
  final String transliteratedQuery;
  final bool isRemixIntent;
  final String? didYouMeanSuggestion;

  const QueryIntent({
    required this.rawQuery,
    required this.cleanQuery,
    this.detectedScript,
    this.explicitLanguage,
    required this.transliteratedQuery,
    this.isRemixIntent = false,
    this.didYouMeanSuggestion,
  });

  String? get detectedLanguage => detectedScript;
  String? get explicitLanguageOverride => explicitLanguage?.toLowerCase();
}

class SearchResults {
  final List<Song> songs;
  final List<Song> ytSongs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> artists;
  final Map<String, dynamic>? topResult;
  final String? didYouMean;
  final AppError? error;

  SearchResults({
    this.songs = const [],
    this.ytSongs = const [],
    this.albums = const [],
    this.artists = const [],
    this.topResult,
    this.didYouMean,
    this.error,
  });

  bool get isEmpty => songs.isEmpty && ytSongs.isEmpty && albums.isEmpty && artists.isEmpty;
  bool get hasError => error != null;
}

class SearchCache {
  static const int _maxEntries = 60;
  static final Map<String, SearchResults> _cache = {};
  static final List<String> _lruOrder = [];

  static SearchResults? get(String query, {String? language}) {
    final key = '${query.trim().toLowerCase()}__${language?.toLowerCase() ?? ""}';
    if (_cache.containsKey(key)) {
      _lruOrder.remove(key);
      _lruOrder.add(key);
      return _cache[key];
    }
    return null;
  }

  static void put(String query, SearchResults results, {String? language}) {
    if (results.isEmpty || results.hasError) return;
    final key = '${query.trim().toLowerCase()}__${language?.toLowerCase() ?? ""}';
    if (_cache.containsKey(key)) {
      _lruOrder.remove(key);
    } else if (_lruOrder.length >= _maxEntries) {
      final oldest = _lruOrder.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[key] = results;
    _lruOrder.add(key);
  }

  static void clear() {
    _cache.clear();
    _lruOrder.clear();
  }
}

class SearchService {
  static const List<String> _knownLanguages = [
    'tamil',
    'telugu',
    'hindi',
    'english',
    'malayalam',
    'kannada',
    'punjabi',
    'marathi',
    'bengali',
  ];

  // Common Tanglish & South Indian phonetic transliterations
  static const Map<String, String> _tanglishIndex = {
    'mesaya muruku': 'Meesaya Murukku',
    'meesaya muruku': 'Meesaya Murukku',
    'mesaya murukku': 'Meesaya Murukku',
    'oorum blood': 'Oorum Blood',
    'oorum raththam': 'Oorum Blood',
    'puthu mazha': 'Puthu Mazha',
    'pudhu mazha': 'Puthu Mazha',
    'pudhumazha': 'Puthu Mazha',
    'puthumazha': 'Puthu Mazha',
    'vaathi coming': 'Vaathi Coming',
    'vathi coming': 'Vaathi Coming',
    'rowdy bby': 'Rowdy Baby',
    'rowdy baby': 'Rowdy Baby',
    'alaporan tamizhan': 'Aalaporaan Thamizhan',
    'aalaporan': 'Aalaporaan Thamizhan',
    'arabic kuthu': 'Arabic Kuthu',
    'arabik kuthu': 'Arabic Kuthu',
  };

  /// Expands common South Indian, Tanglish, and phonetically variant queries
  static String expandPhoneticQuery(String query) {
    var text = query.trim().toLowerCase();
    if (text.isEmpty) return query;

    if (_tanglishIndex.containsKey(text)) {
      return _tanglishIndex[text]!;
    }

    // Common phonetic swaps
    text = text.replaceAll('aniruth', 'anirudh')
               .replaceAll('ar rehman', 'ar rahman')
               .replaceAll('rehman', 'rahman')
               .replaceAll('yuvan shanker', 'yuvan shankar')
               .replaceAll('ilayaraja', 'ilaiyaraaja')
               .replaceAll('ilayaraaja', 'ilaiyaraaja')
               .replaceAll('hukkum', 'hukum')
               .replaceAll('hukm', 'hukum')
               .replaceAll('nerupuda', 'neruppu da')
               .replaceAll('kadaippoma', 'kadhaippoma')
               .replaceAll('vaseegara', 'vaseegara')
               .replaceAll('waseegara', 'vaseegara')
               .replaceAll('mesaya muruku', 'meesaya murukku')
               .replaceAll('oorum blood', 'oorum blood');

    return text;
  }

  /// Strictly filters out single-song releases and fake albums
  static List<Map<String, dynamic>> filterGenuineAlbums(List<Map<String, dynamic>> rawAlbums) {
    final valid = <Map<String, dynamic>>[];
    for (final alb in rawAlbums) {
      final songCount = int.tryParse(alb['song_count']?.toString() ?? '0') ?? 0;
      final title = (alb['title'] ?? '').toString().toLowerCase();
      if (songCount == 1 || title.contains('single')) {
        continue;
      }
      valid.add({
        ...alb,
        'type': 'Album',
        'is_single': false,
      });
    }
    return valid;
  }

  /// Understands user query: detects script, explicit language override, and Tanglish transliteration.
  static QueryIntent understandQuery(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return QueryIntent(rawQuery: '', cleanQuery: '', transliteratedQuery: '');
    }

    // 1. Script detection
    String? detectedScript;
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(trimmed)) {
      detectedScript = 'tamil';
    } else if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(trimmed)) {
      detectedScript = 'telugu';
    } else if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(trimmed)) {
      detectedScript = 'malayalam';
    } else if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(trimmed)) {
      detectedScript = 'kannada';
    } else if (RegExp(r'[\u0900-\u097F]').hasMatch(trimmed)) {
      detectedScript = 'hindi';
    } else {
      detectedScript = 'latin';
    }

    // 2. Explicit language override detection
    String clean = trimmed;
    String? explicitLang;
    final lower = trimmed.toLowerCase();

    for (final lang in _knownLanguages) {
      final langPattern = RegExp('\\b$lang\\b', caseSensitive: false);
      if (langPattern.hasMatch(lower)) {
        explicitLang = lang[0].toUpperCase() + lang.substring(1);
        clean = clean.replaceAll(langPattern, '').replaceAll(RegExp(r'\s+'), ' ').trim();
        break;
      }
    }

    if (clean.isEmpty) clean = trimmed;

    // 3. Tanglish transliteration check
    final cleanLower = clean.toLowerCase();
    String transliterated = clean;
    String? didYouMean;

    if (_tanglishIndex.containsKey(cleanLower)) {
      transliterated = _tanglishIndex[cleanLower]!;
      didYouMean = transliterated;
    } else {
      // Check partial Tanglish phrases
      for (final entry in _tanglishIndex.entries) {
        if (cleanLower.contains(entry.key)) {
          transliterated = cleanLower.replaceAll(entry.key, entry.value);
          didYouMean = transliterated;
          break;
        }
      }
    }

    if (didYouMean == null) {
      final phoneticExpanded = expandPhoneticQuery(cleanLower);
      if (phoneticExpanded.toLowerCase() != cleanLower) {
        transliterated = phoneticExpanded;
        didYouMean = phoneticExpanded;
      }
    }

    if (didYouMean == null && cleanLower != transliterated.toLowerCase()) {
      didYouMean = transliterated;
    }

    final isRemix = lower.contains('remix') || lower.contains('lofi') || lower.contains('slowed');

    return QueryIntent(
      rawQuery: trimmed,
      cleanQuery: clean,
      detectedScript: detectedScript,
      explicitLanguage: explicitLang,
      transliteratedQuery: transliterated,
      isRemixIntent: isRemix,
      didYouMeanSuggestion: didYouMean,
    );
  }


  /// Computes composite relevance score combining text similarity, artist match,
  /// language prior boost, version penalty, and source quality.
  static double scoreSong(
    Song song,
    QueryIntent intent, {
    required List<String> preferredLanguages,
  }) {
    double score = 0.0;
    final qLower = intent.cleanQuery.toLowerCase();
    final transLower = intent.transliteratedQuery.toLowerCase();
    final titleNorm = song.normalizedTitle;
    final artistNorm = song.primaryArtist;

    // 1. Text Similarity (0.0 to 0.50)
    final ratioTitle = weightedRatio(qLower, titleNorm) / 100.0;
    final ratioTrans = weightedRatio(transLower, titleNorm) / 100.0;
    final textMatch = ratioTitle > ratioTrans ? ratioTitle : ratioTrans;
    score += textMatch * 0.50;

    // Direct containment bonus
    if (titleNorm.contains(qLower) || qLower.contains(titleNorm)) {
      score += 0.15;
    }

    // 2. Artist Match (0.0 to 0.20)
    final artistRatio = weightedRatio(qLower, artistNorm) / 100.0;
    if (artistRatio >= 0.75 || artistNorm.contains(qLower)) {
      score += 0.20;
    }

    // 3. Language Prior Boost (Never a filter!)
    // If query has explicit language override, respect it as top priority
    final primaryLang = (intent.explicitLanguage ??
            (preferredLanguages.isNotEmpty ? preferredLanguages.first : 'Tamil'))
        .toLowerCase();
    final secondaryLang = preferredLanguages.length > 1
        ? preferredLanguages[1].toLowerCase()
        : null;

    final songLang = song.language?.toLowerCase() ?? '';
    if (songLang == primaryLang || song.title.toLowerCase().contains(primaryLang)) {
      score += 0.35; // Strongest boost for 1st preferred language
    } else if (secondaryLang != null && (songLang == secondaryLang || song.title.toLowerCase().contains(secondaryLang))) {
      score += 0.15; // Weaker boost for 2nd preferred language
    }

    // 4. Version Penalty
    final isVersion = song.versionTag == 'Remix' || song.versionTag == 'Lofi' || song.versionTag == 'Live';
    if (isVersion && !intent.isRemixIntent) {
      score -= 0.15; // Version penalty unless explicitly requested
    } else if (isVersion && intent.isRemixIntent) {
      score += 0.15;
    }

    // 5. Source Quality & Official Album Art
    if (song.source == 'saavn') {
      score += 0.08;
    }
    if (song.hasOfficialAlbumArt) {
      score += 0.05;
    }

    return score;
  }

  /// High-precision progressive search across JioSaavn & YouTube Music.
  /// Applies script detection, Tanglish transliteration, canonical grouping,
  /// composite scoring, and Top Result confidence thresholding.
  static Future<SearchResults> searchUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
  }) async {
    final intent = understandQuery(rawQuery);
    if (intent.cleanQuery.isEmpty) return SearchResults();

    final prefLangs = SettingsManager.preferredLanguages;
    final effectiveLang = intent.explicitLanguage ??
        (language ?? (prefLangs.isNotEmpty ? prefLangs.first : 'Tamil'));

    // Check fast LRU in-memory cache first (0ms)
    final cached = SearchCache.get(rawQuery, language: effectiveLang);
    if (cached != null) {
      return cached;
    }

    try {
      // 1. Parallel retrieval with timeouts: Query JioSaavn first
      final saavnFuture = SaavnClient.search(
        intent.cleanQuery,
        limit: limit,
        language: effectiveLang,
      ).timeout(const Duration(seconds: 5));

      final transliteratedSaavnFuture = (intent.transliteratedQuery != intent.cleanQuery)
          ? SaavnClient.search(
              intent.transliteratedQuery,
              limit: limit,
              language: effectiveLang,
            ).timeout(const Duration(seconds: 5), onTimeout: () => <Song>[])
          : Future.value(<Song>[]);

      // Lazily retrieve albums and artists in parallel
      final albumsFuture = SaavnClient.searchAlbums(intent.cleanQuery, limit: 12)
          .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
      final artistsFuture = SaavnClient.searchArtists(intent.cleanQuery, limit: 12)
          .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
      final ytFuture = YouTubeClient.search(intent.cleanQuery, limit: limit)
          .timeout(const Duration(seconds: 6), onTimeout: () => <Song>[]);

      final initialResults = await Future.wait([
        saavnFuture,
        transliteratedSaavnFuture,
        albumsFuture,
        artistsFuture,
        ytFuture,
      ]);

      final rawSaavn = initialResults[0] as List<Song>;
      final transSaavn = initialResults[1] as List<Song>;
      final rawAlbums = initialResults[2] as List<Map<String, dynamic>>;
      final artists = initialResults[3] as List<Map<String, dynamic>>;
      final rawYt = initialResults[4] as List<Song>;

      final List<Song> combinedSaavn = [];
      combinedSaavn.addAll(rawSaavn);
      for (final s in transSaavn) {
        if (!combinedSaavn.any((x) => x.id == s.id)) {
          combinedSaavn.add(s);
        }
      }

      // Group versions into canonical songs
      final canonicalSaavn = SongRepository.groupCanonicalSongs(
        combinedSaavn,
        preferredLanguage: effectiveLang,
      );

      // Score candidates
      final scoredSaavn = canonicalSaavn.map((s) {
        final score = scoreSong(s, intent, preferredLanguages: prefLangs);
        return MapEntry(score, s);
      }).toList();

      scoredSaavn.sort((a, b) => b.key.compareTo(a.key));
      final rankedSaavn = scoredSaavn.map((e) => e.value).toList();

      // Process parallel YouTube songs
      final groupedYt = SongRepository.groupCanonicalSongs(rawYt, preferredLanguage: effectiveLang);
      final ytSongs = SongRepository.deduplicateSongs(groupedYt);

      // Filter and label multi-track genuine albums strictly
      final labeledAlbums = filterGenuineAlbums(rawAlbums);

      // Set confidence bar for Top Result (>= 0.70 threshold)
      Map<String, dynamic>? topResult;
      String? didYouMean;

      if (scoredSaavn.isNotEmpty && scoredSaavn.first.key >= 0.70) {
        final top = scoredSaavn.first.value;
        topResult = {
          'type': 'song',
          'id': top.id,
          'title': top.title,
          'artist': top.artist,
          'cover_url': top.coverUrl,
          'duration': top.duration,
          'source': top.source,
          'score': scoredSaavn.first.key,
          'versions': top.versions.map((v) => v.toMap()).toList(),
        };
      } else {
        // Did not clear confidence bar: offer "Did you mean..." instead of a false positive
        final correction = FuzzySearchService.findCorrection(intent.cleanQuery);
        if (correction != null && correction.corrected.toLowerCase() != intent.cleanQuery.toLowerCase()) {
          didYouMean = correction.corrected;
        } else if (intent.transliteratedQuery != intent.cleanQuery) {
          didYouMean = intent.transliteratedQuery;
        }
      }

      // Register with fuzzy index
      FuzzySearchService.registerSongs(rankedSaavn);

      final searchBundle = SearchResults(
        songs: rankedSaavn,
        ytSongs: ytSongs,
        albums: labeledAlbums,
        artists: artists,
        topResult: topResult,
        didYouMean: didYouMean,
      );

      // Save to fast in-memory LRU cache
      SearchCache.put(rawQuery, searchBundle, language: effectiveLang);

      return searchBundle;
    } catch (e, stack) {
      debugPrint('[SearchService] Search error: $e');
      final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'SearchService.searchUnified');
      return SearchResults(error: appErr);
    }
  }
}
