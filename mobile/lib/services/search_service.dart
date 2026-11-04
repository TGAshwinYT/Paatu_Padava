import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../domain/models/app_error.dart';
import '../domain/models/track_entity.dart';
import '../core/dsa/bk_tree.dart';
import '../core/dsa/trigram_index.dart';
// import '../core/dsa/symspell.dart';
import 'lyrics_search_service.dart';
import 'semantic_search_service.dart';
// import '../core/dsa/minhash.dart';
import '../core/dsa/prefix_trie.dart';
import '../logic/search_query_planner.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';
import 'settings_manager.dart';
import 'history_manager.dart';
import 'favorites_manager.dart';
import 'fuzzy_search_service.dart';
import 'error_handler.dart';
import 'app_logger.dart';
import 'artist_sanitizer.dart';
import 'api_client.dart';
import 'catalog_database.dart';
import 'user_preference_matrix.dart';
import '../data/repositories/song_repository.dart';
import '../core/dsa/lru_cache.dart';
import '../domain/models/clustered_track_result.dart';
import '../logic/track_quality_filter.dart';
import '../logic/lyrics/indic_romanizer.dart';





class QueryIntent {
  final String rawQuery;
  final String cleanQuery;
  final String coreSubject;
  final String? detectedScript;
  final String? explicitLanguage;
  final String transliteratedQuery;
  final bool isRemixIntent;
  final String? didYouMeanSuggestion;
  final String? universalPhoneticVariant;

  const QueryIntent({
    required this.rawQuery,
    required this.cleanQuery,
    this.coreSubject = '',
    this.detectedScript,
    this.explicitLanguage,
    required this.transliteratedQuery,
    this.isRemixIntent = false,
    this.didYouMeanSuggestion,
    this.universalPhoneticVariant,
  });

  String get effectiveCoreQuery => coreSubject.isNotEmpty ? coreSubject : cleanQuery;
  String? get detectedLanguage => detectedScript;
  String? get explicitLanguageOverride => explicitLanguage?.toLowerCase();

  QueryIntent copyWith({
    String? rawQuery,
    String? cleanQuery,
    String? coreSubject,
    String? detectedScript,
    String? explicitLanguage,
    String? transliteratedQuery,
    bool? isRemixIntent,
    String? didYouMeanSuggestion,
    String? universalPhoneticVariant,
  }) {
    return QueryIntent(
      rawQuery: rawQuery ?? this.rawQuery,
      cleanQuery: cleanQuery ?? this.cleanQuery,
      coreSubject: coreSubject ?? this.coreSubject,
      detectedScript: detectedScript ?? this.detectedScript,
      explicitLanguage: explicitLanguage,
      transliteratedQuery: transliteratedQuery ?? this.transliteratedQuery,
      isRemixIntent: isRemixIntent ?? this.isRemixIntent,
      didYouMeanSuggestion: didYouMeanSuggestion ?? this.didYouMeanSuggestion,
      universalPhoneticVariant: universalPhoneticVariant ?? this.universalPhoneticVariant,
    );
  }
}

class SearchResults {
  final List<Song> songs;
  final List<Song> ytSongs;
  final List<Song> saavnSongs;
  final List<Song> audiusSongs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> playlists;
  final Map<String, dynamic>? topResult;
  final String? didYouMean;
  final AppError? error;
  final bool isFinal;
  final bool isCached;

  SearchResults({
    this.songs = const [],
    this.ytSongs = const [],
    this.saavnSongs = const [],
    this.audiusSongs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.topResult,
    this.didYouMean,
    this.error,
    this.isFinal = false,
    this.isCached = false,
  });

  bool get isEmpty =>
      songs.isEmpty &&
      ytSongs.isEmpty &&
      saavnSongs.isEmpty &&
      audiusSongs.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty;
  bool get hasError => error != null;
}

/// Bundle containing text completions, matching songs, and matching albums for active typing.
class SearchTypeaheadBundle {
  final List<String> completions;
  final List<Song> songs;
  final List<Map<String, dynamic>> albums;

  const SearchTypeaheadBundle({
    this.completions = const [],
    this.songs = const [],
    this.albums = const [],
  });

  bool get isEmpty => completions.isEmpty && songs.isEmpty && albums.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

class _SearchCacheEntry {
  final SearchResults results;
  final DateTime createdAt;
  _SearchCacheEntry(this.results) : createdAt = DateTime.now();
  bool get isExpired => DateTime.now().difference(createdAt).inMinutes > 15;
}

class SearchCache {
  static const int _maxEntries = 60;
  static final Map<String, _SearchCacheEntry> _cache = {};
  static final List<String> _lruOrder = [];

  static SearchResults? get(String query, {String? language}) {
    final prefLangs = SettingsManager.preferredLanguages.join(',');
    final key = '${query.trim().toLowerCase()}__${(language == null || language.isEmpty || language.toLowerCase() == "all") ? "all" : language.toLowerCase()}__$prefLangs';
    final entry = _cache[key];
    if (entry != null) {
      if (entry.isExpired) {
        _cache.remove(key);
        _lruOrder.remove(key);
        return null;
      }
      _lruOrder.remove(key);
      _lruOrder.add(key);
      return entry.results;
    }
    return null;
  }

  static void put(String query, SearchResults results, {String? language}) {
    if (results.isEmpty || results.hasError) return;
    if (results.songs.isEmpty && results.saavnSongs.isEmpty && results.ytSongs.isEmpty) return;

    final prefLangs = SettingsManager.preferredLanguages.join(',');
    final key = '${query.trim().toLowerCase()}__${(language == null || language.isEmpty || language.toLowerCase() == "all") ? "all" : language.toLowerCase()}__$prefLangs';
    if (_cache.containsKey(key)) {
      _lruOrder.remove(key);
    } else if (_lruOrder.length >= _maxEntries) {
      final oldest = _lruOrder.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[key] = _SearchCacheEntry(results);
    _lruOrder.add(key);
  }

  static void clear() {
    _cache.clear();
    _lruOrder.clear();
  }
}

/// Precomputed immutable context for O(1) user affinity lookups during multi-song ranking.
/// Completely eliminates O(N * (F + H)) linear scans across favorites and history.
class UserAffinityContext {
  final Set<String> favoriteIds;
  final Set<String> favoriteArtists;
  final Set<String> favoriteAlbums;
  final Map<String, int> historyArtistPlayCounts;
  final Map<String, int> historyAlbumPlayCounts;
  final Set<String> historySongIds;

  const UserAffinityContext({
    required this.favoriteIds,
    required this.favoriteArtists,
    required this.favoriteAlbums,
    required this.historyArtistPlayCounts,
    required this.historyAlbumPlayCounts,
    required this.historySongIds,
  });

  factory UserAffinityContext.fromSongs({List<Song>? favorites, List<Song>? history}) {
    final favs = favorites ?? (FavoritesManager.favoritesNotifier.value);
    final hist = history ?? (HistoryManager.historyNotifier.value);

    final favIds = <String>{};
    final favArtists = <String>{};
    final favAlbums = <String>{};

    for (final f in favs) {
      favIds.add(f.id);
      final art = f.primaryArtist.toLowerCase().trim();
      if (art.isNotEmpty) {
        favArtists.add(art);
        favArtists.add(SongRepository.normalizeArtist(f.artist).toLowerCase().trim());
      }
      final alb = f.album.toLowerCase().trim();
      if (alb.isNotEmpty && alb != 'studio album' && alb != 'single' && alb != 'unknown') {
        favAlbums.add(alb);
      }
    }

    final histSongIds = <String>{};
    final histArtistCounts = <String, int>{};
    final histAlbumCounts = <String, int>{};

    for (final h in hist) {
      histSongIds.add(h.id);
      final art = h.primaryArtist.toLowerCase().trim();
      if (art.isNotEmpty) {
        histArtistCounts[art] = (histArtistCounts[art] ?? 0) + 1;
        final norm = SongRepository.normalizeArtist(h.artist).toLowerCase().trim();
        if (norm != art) histArtistCounts[norm] = (histArtistCounts[norm] ?? 0) + 1;
      }
      final alb = h.album.toLowerCase().trim();
      if (alb.isNotEmpty && alb != 'studio album' && alb != 'single' && alb != 'unknown') {
        histAlbumCounts[alb] = (histAlbumCounts[alb] ?? 0) + 2;
      }
    }

    return UserAffinityContext(
      favoriteIds: favIds,
      favoriteArtists: favArtists,
      favoriteAlbums: favAlbums,
      historyArtistPlayCounts: histArtistCounts,
      historyAlbumPlayCounts: histAlbumCounts,
      historySongIds: histSongIds,
    );
  }

  double computeAffinity(Song song) {
    if (favoriteIds.contains(song.id)) return 1.0;

    final candArtist = song.primaryArtist.toLowerCase().trim();
    final candAlbum = song.album.toLowerCase().trim();

    if (candArtist.isNotEmpty && favoriteArtists.contains(candArtist)) return 1.0;
    if (candAlbum.isNotEmpty && favoriteAlbums.contains(candAlbum)) return 0.95;

    if (historySongIds.contains(song.id)) return 0.90;

    int playCount = 0;
    if (candArtist.isNotEmpty) {
      playCount += historyArtistPlayCounts[candArtist] ?? 0;
    }
    if (candAlbum.isNotEmpty) {
      playCount += historyAlbumPlayCounts[candAlbum] ?? 0;
    }

    if (playCount >= 5) return 1.0;
    if (playCount >= 3) return 0.75;
    if (playCount == 2) return 0.50;
    if (playCount == 1) return 0.25;

    return 0.0;
  }
}

class SearchService {
  static final RegExp _dialogueRegex = RegExp(
    r'\b(dialogues?|punch\s*dialogues?|mass\s*dialogues?|movie\s*scenes?|comedy\s*scenes?|audio\s*scenes?|dialogue\s*mix|scenes?|ringtones?|bgm\s*ringtones?)\b',
    caseSensitive: false,
  );
  static final RegExp _arabicScriptRegex = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]',
  );
  static final RegExp _knownIndianArtistsRegex = RegExp(
    r'\b(anirudh|rahman|yuvan|harris|santhosh|hiphop|ilaiyaraaja|sid\s*sriram|pradeep|spb|jen\s*martin|hesham|dhanush|karthik|shreya|jonita|chinmayi|vijay|ajith|surya|rajini|kamal|nani|keerthy)\b',
    caseSensitive: false,
  );

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

    // 0. Automatic Indic Script Transliteration (Tamil, Hindi, Telugu, Malayalam, Kannada)
    if (IndicRomanizer.hasIndicScript(text)) {
      final roman = IndicRomanizer.romanize(text).trim();
      if (roman.isNotEmpty) return roman;
    }

    if (_tanglishIndex.containsKey(text)) {
      return _tanglishIndex[text]!;
    }

    // Common phonetic swaps (eliminating no-ops and expanding multi-variant aliases)
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
               .replaceAll('waseegara', 'vaseegara')
               .replaceAll('vasikara', 'vaseegara')
               .replaceAll('mesaya muruku', 'meesaya murukku')
               .replaceAll('oorum raththam', 'oorum blood')
               .replaceAll('oorum ratham', 'oorum blood');

    return text;
  }

  /// Generates multi-language universal phonetic variants for Romanized search queries.
  /// Handles common Romanized vowel substitutions (a <-> e, ee <-> i, oo <-> u, ai <-> ay, au <-> ou),
  /// consonant normalizations (w <-> v), and geminate consonant collapses across all languages.
  static List<String> generateUniversalPhoneticVariants(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.length < 3) return const [];

    final variants = <String>{};

    // 1. Check BK-Tree / Fuzzy dictionary for closest known entry within edit distance <= 1
    final correction = FuzzySearchService.findCorrection(clean);
    if (correction != null && correction.corrected.toLowerCase() != clean) {
      variants.add(correction.corrected.toLowerCase());
    }

    // 2. Vowel substitutions (universal across Romanized Indian languages & English typos)
    // a <-> e (e.g. "marsal" <-> "mersal", "chennai" <-> "channai")
    if (clean.contains('ar') || clean.contains('er')) {
      variants.add(clean.replaceAll('ar', 'er'));
      variants.add(clean.replaceAll('er', 'ar'));
    }
    if (clean.contains('al') || clean.contains('el')) {
      variants.add(clean.replaceAll('al', 'el'));
      variants.add(clean.replaceAll('el', 'al'));
    }
    if (clean.contains('a') && !clean.contains('e')) {
      variants.add(clean.replaceFirst('a', 'e'));
    } else if (clean.contains('e') && !clean.contains('a')) {
      variants.add(clean.replaceFirst('e', 'a'));
    }

    // ee <-> i, i <-> ee (e.g. "neethanae" <-> "nithanae", "veer" <-> "vir")
    if (clean.contains('ee')) {
      variants.add(clean.replaceAll('ee', 'i'));
    } else if (clean.contains('i')) {
      variants.add(clean.replaceAll('i', 'ee'));
    }

    // oo <-> u, u <-> oo (e.g. "soorya" <-> "surya", "dhoom" <-> "dhum")
    if (clean.contains('oo')) {
      variants.add(clean.replaceAll('oo', 'u'));
    } else if (clean.contains('u')) {
      variants.add(clean.replaceAll('u', 'oo'));
    }

    // ai <-> ay, ei <-> ai (e.g. "ilaiyaraaja" <-> "ilayaraja")
    if (clean.contains('ai')) {
      variants.add(clean.replaceAll('ai', 'ay'));
    } else if (clean.contains('ay')) {
      variants.add(clean.replaceAll('ay', 'ai'));
    }

    // w <-> v (e.g. "waseegara" <-> "vaseegara")
    if (clean.contains('w')) {
      variants.add(clean.replaceAll('w', 'v'));
    }

    // Geminate collapse (e.g. "neruppu" -> "nerupu", "kutty" -> "kuty")
    final collapsed = clean.replaceAllMapped(RegExp(r'([b-df-hj-np-tv-z])\1'), (m) => m[1]!);
    if (collapsed != clean) {
      variants.add(collapsed);
    }

    // Dental / retroflex aspirates (e.g. "aniruth" -> "anirudh")
    if (clean.endsWith('uth')) {
      variants.add('${clean.substring(0, clean.length - 3)}udh');
    }

    // Indic Script romanization variant
    if (IndicRomanizer.hasIndicScript(clean)) {
      final roman = IndicRomanizer.romanize(clean).trim().toLowerCase();
      if (roman.isNotEmpty && roman != clean) variants.add(roman);
    }

    // South Indian allophone folding (zh <-> l, th <-> dh, ph <-> f)
    if (clean.contains('zh')) variants.add(clean.replaceAll('zh', 'l'));
    if (clean.contains('th')) variants.add(clean.replaceAll('th', 'dh'));
    if (clean.contains('dh')) variants.add(clean.replaceAll('dh', 'th'));
    if (clean.contains('ph')) variants.add(clean.replaceAll('ph', 'f'));
    if (clean.contains('f')) variants.add(clean.replaceAll('f', 'ph'));

    // Geminate consonant expansion (intervocalic medial positions ONLY, e.g. "nerupu" -> "neruppu", "kutty" -> "kuty")
    // Consonant doubling in South Asian phonetics never occurs word-initially (never "kk-", "pp-", "tt-").
    for (final ch in const ['k', 'p', 't', 'l', 'm', 'n', 'r']) {
      final medialRegex = RegExp('([aeiou])$ch([aeiou])');
      if (medialRegex.hasMatch(clean) && !clean.contains('$ch$ch')) {
        variants.add(clean.replaceAllMapped(medialRegex, (m) => '${m[1]}$ch$ch${m[2]}'));
      }
    }

    variants.remove(clean);
    return variants.toList();
  }

  /// Stage 1: Instant Debounced Typeahead (< 150ms).
  static final LruCache<String, List<String>> _typeaheadLruCache =
      LruCache<String, List<String>>(capacity: 100, defaultTtl: const Duration(minutes: 15));

  static final LruCache<String, SearchTypeaheadBundle> _typeaheadBundleCache =
      LruCache<String, SearchTypeaheadBundle>(capacity: 60, defaultTtl: const Duration(minutes: 5));

  /// Bounded cache for paginated YouTube federated searches to prevent cost growing with scrolling
  static final LruCache<String, List<Song>> _pagedYouTubeCache =
      LruCache<String, List<Song>>(capacity: 30, defaultTtl: const Duration(minutes: 10));

  /// Clears the typeahead LRU cache upon library mutations (favorites, downloads, history).
  static void clearTypeaheadCache() {
    _typeaheadLruCache.clear();
    _typeaheadBundleCache.clear();
  }

  /// Fetches rich autocomplete bundle: text completions, top online songs, and top online albums.
  static Future<SearchTypeaheadBundle> getTypeaheadBundle(
    String query, {
    PrefixTrie<String>? localTrie,
    int limit = 6,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const SearchTypeaheadBundle();

    final cacheKey = clean.toLowerCase();
    final cached = _typeaheadBundleCache.get(cacheKey);
    if (cached != null) return cached;

    final ytFuture = YouTubeClient.getSearchSuggestions(clean)
        .timeout(const Duration(milliseconds: 600), onTimeout: () => <String>[])
        .catchError((_) => <String>[]);
    final saavnFuture = SaavnClient.getAutocompleteData(clean)
        .timeout(const Duration(milliseconds: 2500), onTimeout: () => <String, dynamic>{})
        .catchError((_) => <String, dynamic>{});

    final res = await Future.wait([ytFuture, saavnFuture]);
    final ytCompletions = res[0] as List<String>;
    final saavnData = res[1] as Map<String, dynamic>;

    final completions = <String>[];
    final seen = <String>{};

    void addComp(String s) {
      final t = s.trim();
      if (t.isNotEmpty && !YouTubeClient.isJunkSuggestion(t) && seen.add(t.toLowerCase())) {
        completions.add(t);
      }
    }

    if (localTrie != null) {
      for (final m in localTrie.findByPrefix(clean, limit: 3)) {
        addComp(m.term);
      }
    }

    final saavnComps = (saavnData['completions'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    for (final s in saavnComps) {
      if (completions.length >= limit) break;
      addComp(s);
    }

    for (final s in ytCompletions) {
      if (completions.length >= limit) break;
      addComp(s);
    }

    var songs = (saavnData['songs'] as List<dynamic>?)?.cast<Song>() ?? <Song>[];
    var albums = (saavnData['albums'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];

    if (songs.isEmpty) {
      final cachedSearch = SearchCache.get(clean);
      if (cachedSearch != null && cachedSearch.songs.isNotEmpty) {
        songs = cachedSearch.songs;
      }
    }
    if (albums.isEmpty) {
      final cachedSearch = SearchCache.get(clean);
      if (cachedSearch != null && cachedSearch.albums.isNotEmpty) {
        albums = cachedSearch.albums;
      }
    }

    final bundle = SearchTypeaheadBundle(
      completions: completions,
      songs: songs.take(3).toList(),
      albums: albums.take(2).toList(),
    );

    _typeaheadBundleCache.put(cacheKey, bundle);
    return bundle;
  }

  /// Pre-warms the primary search query in the background on debounced typing pauses (300ms).
  static void prewarmQuery(
    String query, {
    String? language,
    void Function(List<Song> songs, List<Map<String, dynamic>> albums)? onPrewarmed,
  }) {
    final clean = query.trim();
    if (clean.length < 2) return;
    final cached = SearchCache.get(clean, language: language);
    if (cached != null) {
      if (cached.songs.isNotEmpty || cached.albums.isNotEmpty) {
        onPrewarmed?.call(cached.songs.take(3).toList(), cached.albums.take(2).toList());
      }
      return;
    }

    SaavnClient.search(clean, limit: 25, language: language).then((songs) {
      if (songs.isNotEmpty) {
        final existing = SearchCache.get(clean, language: language);
        final extractedAlbums = <Map<String, dynamic>>[];
        final seen = <String>{};
        for (final s in songs.take(6)) {
          final alb = s.album.trim();
          final albLower = alb.toLowerCase();
          if (alb.isNotEmpty &&
              albLower != 'single' &&
              albLower != 'unknown' &&
              albLower != 'various artists' &&
              albLower != 'studio album' &&
              seen.add(albLower)) {
            extractedAlbums.add({
              'id': alb.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase(),
              'title': alb,
              'artist': s.artist,
              'image': s.coverUrl,
              'type': 'Album',
              'is_movie': true,
              'source': s.source,
            });
          }
        }
        if (existing == null) {
          SearchCache.put(
            clean,
            SearchResults(
              songs: songs,
              saavnSongs: songs,
              albums: extractedAlbums,
              isFinal: false,
            ),
            language: language,
          );
        }
        onPrewarmed?.call(songs.take(3).toList(), extractedAlbums.take(2).toList());
      }
    }).catchError((_) {});
  }

  /// Queries local PrefixTrie in < 1ms, then merges lightweight autocomplete suggestions
  /// progressively from YouTube and JioSaavn as each arrives without blocking.
  /// Enforces a partitioned quota so local library items never crowd out discovery suggestions.
  /// Bounded by in-memory LRU cache to eliminate redundant network roundtrips.
  static Future<List<String>> getTypeaheadSuggestions(
    String query, {
    PrefixTrie<String>? localTrie,
    int limit = 10,
    bool skipRemote = false,
    void Function(List<String> partial)? onPartialResults,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    final cacheKey = '${clean.toLowerCase()}|lim=$limit|sr=$skipRemote';
    final cached = _typeaheadLruCache.get(cacheKey);
    if (cached != null) {
      onPartialResults?.call(cached);
      return cached;
    }

    final List<String> suggestions = [];
    final Set<String> seenLower = {};

    void addSuggestion(String s) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) return;
      final lower = trimmed.toLowerCase();
      if (seenLower.add(lower)) {
        suggestions.add(trimmed);
      }
    }

    final List<String> deferredLocal = [];

    // 1. Instant local Prefix Trie matches (0ms local latency)
    // Budget local items so remote discovery suggestions are never crowded out.
    if (localTrie != null) {
      final localMatches = localTrie.findByPrefix(clean, limit: limit + 2);
      final maxLocalInitial = skipRemote ? limit : (limit <= 5 ? 2 : (limit * 0.4).ceil());
      for (final m in localMatches) {
        if (suggestions.length < maxLocalInitial) {
          addSuggestion(m.term);
        } else {
          deferredLocal.add(m.term);
        }
      }
      if (suggestions.isNotEmpty) {
        onPartialResults?.call(List<String>.from(suggestions));
      }
    }

    if (skipRemote) {
      return suggestions.take(limit).toList();
    }

    // 2. Progressive non-blocking remote suggestions:
    // Fire Google and JioSaavn concurrently. As EACH one returns, merge suggestions immediately!
    int remoteAddedCount = 0;
    final ytFuture = YouTubeClient.getSearchSuggestions(clean)
        .timeout(const Duration(milliseconds: 600), onTimeout: () => <String>[])
        .catchError((_) => <String>[]);
    final saavnFuture = SaavnClient.getSearchSuggestions(clean)
        .timeout(const Duration(milliseconds: 600), onTimeout: () => <String>[])
        .catchError((_) => <String>[]);

    final f1 = ytFuture.then((ytList) {
      if (ytList.isNotEmpty) {
        bool addedAny = false;
        for (final s in ytList) {
          if (suggestions.length >= limit) break;
          final lenBefore = suggestions.length;
          addSuggestion(s);
          if (suggestions.length > lenBefore) {
            addedAny = true;
            remoteAddedCount++;
          }
        }
        if (addedAny) onPartialResults?.call(List<String>.from(suggestions));
      }
    });

    final f2 = saavnFuture.then((saavnList) {
      if (saavnList.isNotEmpty) {
        bool addedAny = false;
        for (final s in saavnList) {
          if (suggestions.length >= limit) break;
          final lenBefore = suggestions.length;
          addSuggestion(s);
          if (suggestions.length > lenBefore) {
            addedAny = true;
            remoteAddedCount++;
          }
        }
        if (addedAny) onPartialResults?.call(List<String>.from(suggestions));
      }
    });

    try {
      await Future.wait([f1, f2]);
    } catch (e) {
      debugPrint('[SearchService] getTypeaheadSuggestions notice: $e');
    }

    // Backfill with deferred local suggestions if remote returned fewer than quota
    if (suggestions.length < limit && deferredLocal.isNotEmpty) {
      for (final def in deferredLocal) {
        if (suggestions.length >= limit) break;
        addSuggestion(def);
      }
    }

    final result = suggestions.take(limit).toList();

    // Cache in LRU only if remote suggestions succeeded or if remote was skipped.
    // Do NOT cache degraded timeout-only results so subsequent queries can retry.
    if (remoteAddedCount > 0 || skipRemote) {
      _typeaheadLruCache.put(cacheKey, result);
    }

    return result;
  }

  /// Strictly filters out single-song releases, fake albums, and unrelated compilations
  /// Returns true if an album title or song.album matches a film entity query
  /// (e.g. "Hi Nanna" matches "Samayama (From \"Hi Nanna\")", "Odiyamma (From \"Hi Nanna\") - Tamil",
  /// or "Mersal" matches "Mersal", "Mersal (Original Motion Picture Soundtrack)").
  static bool isAlbumOrMovieEntityMatch(String title, String query) {
    final t = title.toLowerCase().trim();
    final q = query.toLowerCase().trim();
    if (q.isEmpty || t.isEmpty) return false;
    if (t == q) return true;

    final baseT = t.contains(' - ') ? t.split(' - ').first.trim() : t;
    if (baseT == q) return true;
    if (q.length >= 3 && (t.startsWith(q) || baseT.startsWith(q))) return true;

    // Check "(From <movie>)", "(From \"<movie>\")", "[From <movie>]", "From <movie>"
    final fromMovieRegex = RegExp(
      r'[\(\[\-]\s*(?:from|ost|movie|soundtrack)\s*[\":\s]*' + RegExp.escape(q),
      caseSensitive: false,
    );
    if (fromMovieRegex.hasMatch(t)) return true;

    // Direct containment with word boundaries for queries >= 3 chars
    if (q.length >= 3) {
      final qWordRegex = RegExp(r'\b' + RegExp.escape(q) + r'\b', caseSensitive: false);
      if (qWordRegex.hasMatch(t)) return true;
    }

    return false;
  }

  static List<Map<String, dynamic>> filterGenuineAlbums(
    List<Map<String, dynamic>> rawAlbums, {
    String? query,
  }) {
    final valid = <Map<String, dynamic>>[];
    final cleanQuery = (query ?? '').trim().toLowerCase();
    final queryTokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();

    for (final alb in rawAlbums) {
      final songCount = int.tryParse(alb['song_count']?.toString() ?? '0') ?? 0;
      final title = (alb['title'] ?? '').toString().toLowerCase();
      final artist = (alb['artist'] ?? '').toString().toLowerCase();

      // If album title directly matches or starts with the query (e.g. "Hi Nanna", "Hi", "Mersal"),
      // preserve it as a genuine movie entity even if song_count is reported as 1 or single!
      final cleanBaseTitle = title.split(' - ').first.replaceAll(RegExp(r'\s*\((From|OST|Original).*\)', caseSensitive: false), '').trim();
      final isDirectEntityMatch = cleanQuery.length >= 2 &&
          (isAlbumOrMovieEntityMatch(title, cleanQuery) || cleanBaseTitle == cleanQuery || title.startsWith(cleanQuery));

      if (!isDirectEntityMatch && (songCount <= 1 || title.contains('single') || title.contains('teaser'))) {
        continue;
      }

      // Filter out completely unrelated albums for specific queries
      if (cleanQuery.length >= 2 && queryTokens.isNotEmpty) {
        final titleTokens = title.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
        final artistTokens = artist.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
        final isRelevant = isDirectEntityMatch ||
            title.contains(cleanQuery) ||
            cleanQuery.contains(title) ||
            artist.contains(cleanQuery) ||
            titleTokens.intersection(queryTokens).isNotEmpty ||
            artistTokens.intersection(queryTokens).isNotEmpty;
        if (!isRelevant) {
          continue;
        }
      }

      valid.add({
        ...alb,
        'type': 'Album',
        'is_single': false,
      });
    }

    // Sort: Exact title match first, then multi-track soundtrack albums, then song count
    // Only sort if a query is provided to preserve original upstream order for untargeted requests
    if (cleanQuery.isNotEmpty) {
      valid.sort((a, b) {
        final tA = (a['title'] ?? '').toString().toLowerCase().trim();
        final tB = (b['title'] ?? '').toString().toLowerCase().trim();
        final matchA = isAlbumOrMovieEntityMatch(tA, cleanQuery);
        final matchB = isAlbumOrMovieEntityMatch(tB, cleanQuery);
        if (matchA != matchB) return matchA ? -1 : 1;

        final eqA = tA == cleanQuery || (tA.contains(' - ') && tA.split(' - ').first.trim() == cleanQuery);
        final eqB = tB == cleanQuery || (tB.contains(' - ') && tB.split(' - ').first.trim() == cleanQuery);
        if (eqA != eqB) return eqA ? -1 : 1;

        final scA = int.tryParse(a['song_count']?.toString() ?? '0') ?? 0;
        final scB = int.tryParse(b['song_count']?.toString() ?? '0') ?? 0;
        if ((scA > 1) != (scB > 1)) {
          return (scB > 1) ? 1 : -1;
        }
        return scB.compareTo(scA);
      });
    }
    return valid;
  }

  /// Filters playlists to ensure query relevance and language alignment.
  /// Prevents cross-language noise (e.g. Kannada/Marathi playlists for 'Hi Nanna') from leaking in.
  static List<Map<String, dynamic>> filterPlaylistsByRelevanceAndLanguage(
    List<Map<String, dynamic>> rawPlaylists, {
    required String query,
    String? language,
  }) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty) return rawPlaylists;

    final queryTokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
    final prefLang = (language ?? (SettingsManager.preferredLanguages.isNotEmpty ? SettingsManager.preferredLanguages.first : 'tamil')).toLowerCase().trim();
    final foreignLangRegex = RegExp(r'\b(kannada|marathi|bhojpuri|punjabi|haryanvi|bengali|gujarati)\b', caseSensitive: false);

    final filtered = <Map<String, dynamic>>[];
    for (final p in rawPlaylists) {
      final title = (p['title'] ?? p['name'] ?? '').toString().toLowerCase().trim();
      if (title.isEmpty) continue;

      // 1. Language mismatch check on playlist title & metadata
      final playlistLang = (p['language'] ?? p['more_info']?['language'] ?? '').toString().toLowerCase().trim();
      if (foreignLangRegex.hasMatch(playlistLang) || foreignLangRegex.hasMatch(title)) {
        if (!cleanQuery.contains('kannada') && !cleanQuery.contains('marathi') && !cleanQuery.contains('punjabi') && !title.contains(prefLang)) {
          continue;
        }
      }

      // 2. Query relevance check using strict word / token boundaries
      if (queryTokens.length >= 2) {
        final matchesPhrase = title.contains(cleanQuery) || cleanQuery.contains(title);
        // Ensure all query tokens match as WHOLE WORDS, not arbitrary internal substrings
        final matchesAllTokensAsWords = queryTokens.every((token) =>
            RegExp(r'\b' + RegExp.escape(token) + r'\b', caseSensitive: false).hasMatch(title));
        if (!matchesPhrase && !matchesAllTokensAsWords) {
          continue;
        }
      } else if (queryTokens.isNotEmpty) {
        final token = queryTokens.first;
        if (!RegExp(r'\b' + RegExp.escape(token) + r'\b', caseSensitive: false).hasMatch(title)) {
          continue;
        }
      }

      // 3. Drop empty or single-track YouTube playlists that fail when opened
      if (p['source'] == 'youtube') {
        final count = int.tryParse(p['song_count']?.toString() ?? '0') ?? 0;
        if (count < 2) continue;
      }

      filtered.add(p);
    }
    return filtered;
  }

  /// Synthesizes dynamic 'Movie Soundtrack' auto-playlists directly from album metadata
  static List<Map<String, dynamic>> generateAutoPlaylistsFromAlbums(
    List<Map<String, dynamic>> albums, {
    int maxCount = 4,
  }) {
    final List<Map<String, dynamic>> autoPlaylists = [];
    for (final album in albums.take(maxCount)) {
      final title = (album['title'] ?? album['name'] ?? '').toString().trim();
      final id = album['id']?.toString() ?? '';
      final img = album['image']?.toString() ?? album['cover_url']?.toString() ?? '';
      final artist = album['artist']?.toString() ?? album['composer']?.toString() ?? '';
      final songCount = album['song_count'] ?? 0;
      if (title.isNotEmpty) {
        autoPlaylists.add({
          'id': id.isNotEmpty ? id : 'pl_${title.toLowerCase().replaceAll(' ', '_')}',
          'title': '$title (All Songs)',
          'subtitle': songCount > 0 ? '$songCount Tracks • Movie Playlist' : 'Movie Playlist',
          'image': img,
          'artist': artist,
          'song_count': songCount,
          'source': id.startsWith('mov_') || id.startsWith('jailer') || id.startsWith('leo') ? 'catalog' : 'auto_album',
          'type': 'playlist',
        });
      }
    }
    return autoPlaylists;
  }

  /// Deduplicates and merges playlist collections across providers
  static List<Map<String, dynamic>> mergePlaylists(
    List<Map<String, dynamic>> primary,
    List<Map<String, dynamic>> secondary,
  ) {
    final List<Map<String, dynamic>> merged = [];
    final Set<String> seen = {};

    for (final p in primary) {
      final key = (p['title'] ?? '').toString().toLowerCase().trim();
      if (key.isNotEmpty && seen.add(key)) {
        merged.add(p);
      }
    }

    for (final p in secondary) {
      final key = (p['title'] ?? '').toString().toLowerCase().trim();
      if (key.isNotEmpty && seen.add(key)) {
        merged.add(p);
      }
    }

    return merged;
  }

  /// Searches playlists across JioSaavn, YouTube, and dynamic album-based playlists
  static Future<List<Map<String, dynamic>>> searchPlaylists(
    String query, {
    String? language,
    int limit = 20,
  }) async {
    final intent = understandQuery(query);
    final effectiveLang = intent.explicitLanguage ??
        (language != null && language.isNotEmpty && language.toLowerCase() != 'all' ? language : null);
    final saavnQuery = SearchQueryPlanner.formatProviderQuery(intent.cleanQuery, explicitLanguage: effectiveLang);

    final saavnFuture = SaavnClient.searchPlaylists(saavnQuery, limit: limit, language: effectiveLang)
        .timeout(const Duration(seconds: 4), onTimeout: () => <Map<String, dynamic>>[]);
    final ytFuture = YouTubeClient.searchPlaylists(intent.cleanQuery, limit: limit)
        .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
    final albumsFuture = SaavnClient.searchAlbums(saavnQuery, limit: 4)
        .timeout(const Duration(seconds: 3), onTimeout: () => <Map<String, dynamic>>[]);

    final results = await Future.wait([saavnFuture, ytFuture, albumsFuture]);
    final saavnPlaylists = results[0];
    final ytPlaylists = results[1];
    final albums = results[2];

    final autoPlaylists = generateAutoPlaylistsFromAlbums(albums);

    final List<Map<String, dynamic>> merged = [];
    final Set<String> seenTitles = {};

    for (final p in autoPlaylists) {
      final key = (p['title'] ?? '').toString().toLowerCase();
      if (seenTitles.add(key)) merged.add(p);
    }

    final rawMerged = <Map<String, dynamic>>[];
    int sIdx = 0;
    int yIdx = 0;
    while (sIdx < saavnPlaylists.length || yIdx < ytPlaylists.length) {
      if (sIdx < saavnPlaylists.length) {
        final p = saavnPlaylists[sIdx++];
        final key = (p['title'] ?? '').toString().toLowerCase();
        if (key.isNotEmpty && seenTitles.add(key)) rawMerged.add(p);
      }
      if (yIdx < ytPlaylists.length) {
        final p = ytPlaylists[yIdx++];
        final key = (p['title'] ?? '').toString().toLowerCase();
        if (key.isNotEmpty && seenTitles.add(key)) rawMerged.add(p);
      }
    }

    final filteredPlaylists = filterPlaylistsByRelevanceAndLanguage(
      rawMerged,
      query: query,
      language: effectiveLang,
    );
    merged.addAll(filteredPlaylists);
    return merged;
  }

  /// Direct URL / Entity detection: Instant resolution for pasted YouTube URLs or Playlist links
  static Future<Map<String, dynamic>?> resolveDirectUrlOrEntity(String clean) async {
    final ytVideoId = YouTubeClient.extractVideoId(clean);
    final ytPlaylistId = YouTubeClient.extractPlaylistId(clean);

    final isExplicitPlaylist = ytPlaylistId != null &&
        (clean.contains('list=') || RegExp(r'^(?:PL|UU|LL|FL|RD)[a-zA-Z0-9_-]{16,}$').hasMatch(clean) || clean.startsWith('OLAK5uy_'));

    if ((ytVideoId != null && (clean.contains('youtu') || clean.contains('http'))) || isExplicitPlaylist) {
      if (isExplicitPlaylist) {
        final playlistTracks = await YouTubeClient.getPlaylistTracks(ytPlaylistId, limit: 40);
        if (playlistTracks.isNotEmpty) {
          return {
            'type': 'playlist',
            'id': ytPlaylistId,
            'title': 'YouTube Playlist',
            'subtitle': '${playlistTracks.length} tracks (Client Resolved)',
            'image': playlistTracks.first.coverUrl,
            'tracks': playlistTracks,
          };
        }
      } else if (ytVideoId != null) {
        final track = await YouTubeClient.resolveTrackFromUrl(clean);
        if (track != null) {
          return {
            'type': 'song',
            'id': track.id,
            'title': track.title,
            'subtitle': track.artist,
            'image': track.coverUrl,
            'tracks': [track],
          };
        }
      }
    }
    return null;
  }

  /// Tab search: Songs only with progressive pagination and semantic ranking
  static Future<List<Song>> searchSongsTab(String query, {String? language, int limit = 25, int page = 1}) async {
    try {
      final songs = await SaavnClient.search(query, limit: limit, page: page, language: language)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
      for (final s in songs) {
        if (s.lyrics != null && s.lyrics!.isNotEmpty) {
          LyricsSearchService.instance.indexLyrics(s, s.lyrics!);
        }
      }

      final lyricHits = LyricsSearchService.instance.searchLyrics(query);
      final List<Song> enrichedSongs = [];
      for (final s in songs) {
        final hit = lyricHits.cast<LyricSearchResult?>().firstWhere(
          (h) => h?.songId == s.id,
          orElse: () => null,
        );
        if (hit != null) {
          enrichedSongs.add(s.copyWith(matchedLyricSnippet: hit.matchingSnippet));
        } else {
          enrichedSongs.add(s);
        }
      }

      for (final hit in lyricHits) {
        if (!enrichedSongs.any((s) => s.id == hit.songId)) {
          final matched = LyricsSearchService.instance.getSong(hit.songId);
          if (matched != null) {
            enrichedSongs.insert(0, matched.copyWith(matchedLyricSnippet: hit.matchingSnippet));
          }
        }
      }

      final grouped = SongRepository.groupCanonicalSongs(enrichedSongs, preferredLanguage: language);
      final deduped = SongRepository.deduplicateSongs(grouped);
      return SemanticSearchService.instance.rankBySemanticIntent(deduped, query);
    } catch (e, stack) {
      AppLogger.log('SearchService', 'searchSongsTab error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchSongsTab query="$query"');
      return <Song>[];
    }
  }

  /// Multi-source paginated song search (JioSaavn + YouTube Music + Canonical Deduplication)
  /// Used for infinite-scrolling pages (Page 2, 3...) to guarantee source parity.
  static Future<List<Song>> searchSongsPaged(
    String query, {
    int page = 1,
    int limit = 20,
    String? language,
  }) async {
    try {
      final intent = understandQuery(query);
      final effectiveLang = intent.explicitLanguage ?? language;

      final saavnFuture = SaavnClient.search(query, limit: limit, page: page, language: effectiveLang)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);

      final ytQuery = SearchQueryPlanner.formatProviderQuery(query, explicitLanguage: effectiveLang);
      final ytOffset = (page - 1) * limit;
      final Future<List<Song>> ytFuture = () async {
        final cached = _pagedYouTubeCache.get(ytQuery);
        if (cached != null) {
          if (ytOffset >= cached.length) return <Song>[];
          return cached.skip(ytOffset).take(limit).toList();
        }
        // Fetch bounded YouTube pool once (max 25 items) and cache for subsequent pages
        final pool = await YouTubeClient.search(ytQuery, limit: 25)
            .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
        if (pool.isNotEmpty) {
          _pagedYouTubeCache.put(ytQuery, pool);
        }
        if (ytOffset >= pool.length) return <Song>[];
        return pool.skip(ytOffset).take(limit).toList();
      }();

      final results = await Future.wait([saavnFuture, ytFuture]);
      final saavnSongs = results[0];
      final ytSongs = results[1];

      return deduplicateAndRankUnified(
        saavnSongs: saavnSongs,
        ytSongs: ytSongs,
        intent: intent,
        preferredLanguages: effectiveLang != null ? [effectiveLang] : null,
      );
    } catch (e, stack) {
      AppLogger.log('SearchService', 'searchSongsPaged error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchSongsPaged query="$query", page=$page');
      return <Song>[];
    }
  }

  /// Tab search: Albums only
  static Future<List<Map<String, dynamic>>> searchAlbumsTab(String query, {int limit = 25}) async {
    try {
      final albumsFuture = SaavnClient.searchAlbums(query, limit: limit)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Map<String, dynamic>>[]);
      final songsFuture = SaavnClient.search(query, limit: 15)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
      final catMoviesFuture = CatalogDatabase.searchMovies(query, limit: limit);
      final res = await Future.wait([albumsFuture, songsFuture, catMoviesFuture]);
      final directAlbums = res[0] as List<Map<String, dynamic>>;
      final songs = res[1] as List<Song>;
      final catMovies = res[2] as List<Map<String, dynamic>>;

      final List<Map<String, dynamic>> correlatedAlbums = [];
      final Set<String> seenAlbumNames = {};

      for (final m in catMovies) {
        final title = (m['title'] ?? '').toString().trim();
        if (title.isNotEmpty && seenAlbumNames.add(title.toLowerCase())) {
          correlatedAlbums.add(m);
        }
      }

      for (final song in songs) {
        final albName = song.album.trim();
        final albId = song.albumId?.trim() ?? '';
        if (albName.isNotEmpty && albName.toLowerCase() != 'unknown album') {
          final key = albName.toLowerCase();
          if (seenAlbumNames.add(key)) {
            correlatedAlbums.add({
              'id': albId.isNotEmpty ? albId : 'alb_${song.id}',
              'title': albName,
              'image': song.coverUrl,
              'year': '',
              'artist': song.artist,
            });
          }
        }
      }

      for (final alb in directAlbums) {
        final title = (alb['title'] ?? alb['name'] ?? '').toString().trim();
        if (title.isNotEmpty && seenAlbumNames.add(title.toLowerCase())) {
          correlatedAlbums.add(alb);
        }
      }

      return filterGenuineAlbums(correlatedAlbums, query: query);
    } catch (e, stack) {
      AppLogger.log('SearchService', 'searchAlbumsTab error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchAlbumsTab query="$query"');
      return <Map<String, dynamic>>[];
    }
  }

  /// Tab search: Artists only
  static Future<List<Map<String, dynamic>>> searchArtistsTab(String query, {String? language, int limit = 25}) async {
    try {
      final artistsFuture = SaavnClient.searchArtists(query, limit: limit, language: language)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Map<String, dynamic>>[]);
      final songsFuture = SaavnClient.search(query, limit: 15, language: language)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
      final catArtistsFuture = CatalogDatabase.searchArtists(query, limit: limit);
      final res = await Future.wait([artistsFuture, songsFuture, catArtistsFuture]);
      final directArtists = res[0] as List<Map<String, dynamic>>;
      final songs = res[1] as List<Song>;
      final catArtists = res[2] as List<Map<String, dynamic>>;

      final List<Map<String, dynamic>> correlatedArtists = [];
      final Set<String> seenArtistNames = {};

      for (final ca in catArtists) {
        final name = (ca['name'] ?? '').toString().trim();
        if (name.isNotEmpty && seenArtistNames.add(name.toLowerCase())) {
          correlatedArtists.add(ca);
        }
      }

      for (final song in songs) {
        final genuine = ArtistSanitizer.extractAllGenuineArtists(song.artist);
        for (final artName in genuine) {
          if (artName.isNotEmpty && artName.toLowerCase() != 'various artists') {
            final key = artName.toLowerCase();
            if (seenArtistNames.add(key)) {
              correlatedArtists.add({
                'id': 'art_${song.id}_${key.replaceAll(' ', '_')}',
                'name': artName,
                'title': artName,
                'image': song.coverUrl,
                'role': 'Singer / Music Director',
              });
            }
          }
        }
      }

      for (final art in directArtists) {
        final name = (art['name'] ?? art['title'] ?? '').toString().trim();
        if (name.isNotEmpty && seenArtistNames.add(name.toLowerCase())) {
          correlatedArtists.add(art);
        }
      }

      return filterArtistsByLanguage(
        correlatedArtists,
        language: language,
        query: query,
      );
    } catch (e, stack) {
      AppLogger.log('SearchService', 'searchArtistsTab error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchArtistsTab query="$query"');
      return <Map<String, dynamic>>[];
    }
  }

  /// Tab search: YouTube Music tracks
  static Future<List<Song>> searchYtMusicTab(String query, {String? language, int limit = 25}) async {
    try {
      final intent = understandQuery(query);
      final targetLang = intent.explicitLanguage ?? language;
      final ytQuery = (targetLang != null && !query.toLowerCase().contains(targetLang.toLowerCase()))
          ? '$targetLang $query'
          : query;
      var yt = await YouTubeClient.search(ytQuery, limit: limit)
          .timeout(const Duration(seconds: 6), onTimeout: () => <Song>[]);
      if (yt.isEmpty) {
        final saavn = await SaavnClient.search(query, limit: limit, language: language);
        yt = saavn.map((s) => s.copyWith(source: 'youtube')).toList();
      }
      final filteredYt = targetLang != null
          ? SongRepository.filterByLanguage(yt, targetLang)
          : yt;
      final groupedYt = SongRepository.groupCanonicalSongs(filteredYt, preferredLanguage: targetLang);
      return SongRepository.deduplicateSongs(groupedYt);
    } catch (e, stack) {
      AppLogger.log('SearchService', 'searchYtMusicTab error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchYtMusicTab query="$query"');
      return <Song>[];
    }
  }

  /// Tab search: Audius tracks (deprecated/removed)
  static Future<List<Song>> searchAudiusTab(String query, {int limit = 25}) async {
    return const <Song>[];
  }

  /// Records a search click event for telemetry and ranking feedback loop
  static Future<void> recordSearchClick(Song song) async {
    try {
      await ApiClient.recordSearchClick(song);
    } catch (e) {
      AppLogger.log('SearchService', 'recordSearchClick error: $e', level: LogLevel.warn);
    }
  }

  /// Strictly filters search artists by language, purging Bollywood/Hindi leaks,
  /// English pop stars (e.g. Justin Bieber) from regional queries, and placeholder images.
  static List<Map<String, dynamic>> filterArtistsByLanguage(
    List<Map<String, dynamic>> artists, {
    String? language,
    required String query,
  }) {
    final filtered = <Map<String, dynamic>>[];
    final cleanLang = (language != null && language.isNotEmpty && language.toLowerCase() != 'all')
        ? language.toLowerCase().trim()
        : null;
    final qLower = query.toLowerCase().trim();

    for (final item in artists) {
      final name = (item['name'] ?? item['title'] ?? '').toString().trim();
      final norm = SongRepository.normalizeArtist(name);
      if (norm.isEmpty) continue;

      // Filter out accidental spam or false substring hits
      if (!ArtistSanitizer.isGenuineArtist(name)) continue;

      // Language alignment check when a specific language is requested
      if (cleanLang != null) {
        final artistLang = (item['language'] ?? item['more_info']?['language'] ?? '').toString().toLowerCase().trim();
        final isDirectNameMatch = name.toLowerCase() == qLower || name.toLowerCase().contains(qLower);
        if (!isDirectNameMatch && artistLang.isNotEmpty && artistLang != cleanLang) {
          continue;
        }
      }

      final img = item['image']?.toString();
      final hasRealImage = !ArtistSanitizer.isPlaceholderImage(img) || SongRepository.isArtistVerified(name);

      filtered.add({
        ...item,
        'image': hasRealImage ? (img ?? '') : '',
      });
    }
    return filtered;
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
      detectedScript = 'devanagari';
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
        // Special case: Movie titles like "Hindi Medium" or "English Vinglish" where the language name is an integral part of the title
        final isTitleEntity = lower == 'hindi medium' || lower.startsWith('hindi medium ') || lower.endsWith(' hindi medium') ||
            lower == 'english vinglish' || lower.startsWith('english vinglish ') || lower.endsWith(' english vinglish');
        if (isTitleEntity) {
          explicitLang = null;
          clean = trimmed;
          break;
        }

        final stripped = clean.replaceAll(langPattern, '').replaceAll(RegExp(r'\s+'), ' ').trim();
        explicitLang = lang[0].toUpperCase() + lang.substring(1);
        clean = stripped.isEmpty ? trimmed : stripped;
        break;
      }
    }

    if (clean.isEmpty) clean = trimmed;

    // Detect native-script language keywords (e.g. मराठी -> Marathi, தமிழ் -> Tamil)
    if (explicitLang == null) {
      if (clean.contains('मराठी')) {
        explicitLang = 'Marathi';
      } else if (clean.contains('हिंदी') || clean.contains('हिन्दी')) {
        explicitLang = 'Hindi';
      } else if (clean.contains('தமிழ்')) {
        explicitLang = 'Tamil';
      } else if (clean.contains('తెలుగు')) {
        explicitLang = 'Telugu';
      } else if (clean.contains('മലയാളം')) {
        explicitLang = 'Malayalam';
      } else if (clean.contains('ಕನ್ನಡ')) {
        explicitLang = 'Kannada';
      }
    }

    // 3. Script detection & Transliteration check
    final cleanLower = clean.toLowerCase();
    String transliterated = clean;
    String? didYouMean;

    // A. Native Indic script handling (Tamil, Hindi, Telugu, Malayalam, Kannada, etc.)
    if (IndicRomanizer.hasIndicScript(clean)) {
      final roman = IndicRomanizer.romanize(clean).trim();
      if (roman.isNotEmpty && roman.toLowerCase() != cleanLower) {
        transliterated = roman;
        // Do NOT set didYouMean = roman; native Indic script is an authentic, intentional query, not a misspelling!
      }
      if (explicitLang == null) {
        final detected = IndicRomanizer.detectScript(clean);
        // Devanagari is a multi-language script family (Hindi, Marathi, etc.), not a single language
        if (detected != 'latin' && detected != 'devanagari') {
          final lang = IndicRomanizer.scriptToLanguage(detected);
          explicitLang = lang[0].toUpperCase() + lang.substring(1);
        }
      }
    } else if (_tanglishIndex.containsKey(cleanLower)) {
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

    if (didYouMean == null && !IndicRomanizer.hasIndicScript(clean)) {
      final typoOrTanglish = FuzzySearchService.findCorrection(cleanLower);
      if (typoOrTanglish != null && typoOrTanglish.corrected.toLowerCase() != cleanLower) {
        transliterated = typoOrTanglish.corrected;
        didYouMean = typoOrTanglish.corrected;
      }
    }

    if (didYouMean == null) {
      final phoneticExpanded = expandPhoneticQuery(cleanLower);
      if (phoneticExpanded.toLowerCase() != cleanLower) {
        transliterated = phoneticExpanded;
        if (!IndicRomanizer.hasIndicScript(clean)) {
          didYouMean = phoneticExpanded;
        }
      }
    }

    // Universal multi-language phonetic fallback
    String? universalPhonetic;
    final phoneticVariants = generateUniversalPhoneticVariants(cleanLower);
    if (phoneticVariants.isNotEmpty) {
      universalPhonetic = phoneticVariants.firstWhere(
        (v) => FuzzySearchService.containsCandidate(v),
        orElse: () => '',
      );
      if (universalPhonetic.isEmpty) {
        universalPhonetic = null;
      }
    }

    if (transliterated.toLowerCase() == cleanLower && universalPhonetic != null) {
      transliterated = universalPhonetic;
    }

    if (didYouMean == null && cleanLower != transliterated.toLowerCase() && !IndicRomanizer.hasIndicScript(clean)) {
      didYouMean = transliterated;
    }

    final isRemix = lower.contains('remix') || lower.contains('lofi') || lower.contains('slowed');
    final core = SearchQueryPlanner.extractCoreSubject(clean);

    return QueryIntent(
      rawQuery: trimmed,
      cleanQuery: clean,
      coreSubject: core,
      detectedScript: detectedScript,
      explicitLanguage: explicitLang,
      transliteratedQuery: transliterated,
      isRemixIntent: isRemix,
      didYouMeanSuggestion: didYouMean,
      universalPhoneticVariant: universalPhonetic,
    );
  }


  /// Stage 4: Multi-Factor Relevance Scoring Component 1: StringSimilarity (Weight 0.45)
  /// Evaluates exact match, token containment, and Levenshtein metric distance via BkTree
  /// to handle Tanglish and Romanized South Indian spelling variations.
  static double calculateStringSimilarity(Song song, QueryIntent intent) {
    final qLower = intent.cleanQuery.toLowerCase();
    final transLower = intent.transliteratedQuery.toLowerCase();
    final titleNorm = song.normalizedTitle;
    final cleanTitle = SearchQueryPlanner.cleanTitle(song.title).toLowerCase();

    if (qLower.isEmpty) return 0.0;
    if (cleanTitle == qLower || titleNorm == qLower || transLower == cleanTitle || transLower == titleNorm) {
      return 1.0;
    }
    if (cleanTitle.startsWith(qLower) || titleNorm.startsWith(qLower) || cleanTitle.startsWith(transLower)) {
      return 0.95;
    }

    double similarity = 0.0;

    // Levenshtein typo-tolerance using BkTree: strictly Distance = 0 for <= 3 chars
    if (qLower.length > 3) {
      final int distClean = BkTree.levenshteinDistance(qLower, cleanTitle);
      final int maxLenClean = math.max(qLower.length, cleanTitle.length);
      final double levClean = maxLenClean == 0 ? 1.0 : (1.0 - (distClean / maxLenClean)).clamp(0.0, 1.0);

      final int distNorm = BkTree.levenshteinDistance(qLower, titleNorm);
      final int maxLenNorm = math.max(qLower.length, titleNorm.length);
      final double levNorm = maxLenNorm == 0 ? 1.0 : (1.0 - (distNorm / maxLenNorm)).clamp(0.0, 1.0);

      final int distTrans = BkTree.levenshteinDistance(transLower, titleNorm);
      final int maxLenTrans = math.max(transLower.length, titleNorm.length);
      final double levTrans = maxLenTrans == 0 ? 1.0 : (1.0 - (distTrans / maxLenTrans)).clamp(0.0, 1.0);

      similarity = math.max(levClean, math.max(levNorm, levTrans));

      // Tri-Gram Jaccard similarity for Tanglish phonetic transliteration
      final double jaccardScore = TrigramIndex.jaccard(qLower, cleanTitle);
      if (jaccardScore > 0.50) {
        similarity = math.max(similarity, jaccardScore * 0.95);
      }
    }

    bool matchesToken(String text, String token) {
      if (token.isEmpty || text.isEmpty) return false;
      if (token.length <= 3) {
        int idx = text.indexOf(token);
        while (idx != -1) {
          final isStartWord = idx == 0 || !((text.codeUnitAt(idx - 1) >= 48 && text.codeUnitAt(idx - 1) <= 57) || (text.codeUnitAt(idx - 1) >= 65 && text.codeUnitAt(idx - 1) <= 90) || (text.codeUnitAt(idx - 1) >= 97 && text.codeUnitAt(idx - 1) <= 122));
          final end = idx + token.length;
          final isEndWord = end == text.length || !((text.codeUnitAt(end) >= 48 && text.codeUnitAt(end) <= 57) || (text.codeUnitAt(end) >= 65 && text.codeUnitAt(end) <= 90) || (text.codeUnitAt(end) >= 97 && text.codeUnitAt(end) <= 122));
          if (isStartWord && isEndWord) return true;
          idx = text.indexOf(token, idx + 1);
        }
        return false;
      }
      return text.contains(token);
    }

    // Word token containment (e.g. query "hukum" inside "Hukum - Thalaivar Alappara")
    if (matchesToken(cleanTitle, qLower) || matchesToken(titleNorm, qLower) || matchesToken(titleNorm, transLower)) {
      final tokenBoost = 0.80 + (0.15 * (qLower.length / math.max(1, titleNorm.length)));
      similarity = math.max(similarity, tokenBoost);
    }

    // Artist token match: for <= 3 chars, strictly exact match only (disable partial contains)
    final artistLower = song.primaryArtist.toLowerCase();
    final coreLower = intent.effectiveCoreQuery.toLowerCase();
    if (qLower.length > 3) {
      if (artistLower.isNotEmpty &&
          (artistLower == qLower || matchesToken(artistLower, qLower) || matchesToken(artistLower, coreLower))) {
        similarity = math.max(similarity, 0.85);
      }
    } else {
      if (artistLower.isNotEmpty && (artistLower == qLower || artistLower == coreLower)) {
        similarity = math.max(similarity, 0.85);
      }
    }

    // Album token match bonus (e.g. searching movie/album "mersal" finds songs like "Neethanae", or searching "Hi" finds songs from album "Hi")
    final albumLower = song.album.toLowerCase();
    if (albumLower.isNotEmpty) {
      final exactAlbum = albumLower == qLower || albumLower == transLower ||
          albumLower == coreLower || (albumLower.contains(' - ') && albumLower.split(' - ').first.trim() == qLower);
      if (exactAlbum) {
        similarity = math.max(similarity, 0.98);
      } else if (qLower.length > 3) {
        if (matchesToken(albumLower, qLower) || matchesToken(albumLower, transLower) ||
            (qLower.length >= 4 && qLower.contains(albumLower)) ||
            (qLower.length >= 4 && BkTree.levenshteinDistance(albumLower, qLower, maxDistance: 1) <= 1)) {
          similarity = math.max(similarity, 0.90);
        }
      } else if (matchesToken(albumLower, qLower)) {
        similarity = math.max(similarity, 0.90);
      }
    }
    return similarity.clamp(0.0, 1.0);
  }

  /// Stage 4: Multi-Factor Relevance Scoring Component 2: SourcePopularity (Weight 0.35)
  /// Weights 320kbps JioSaavn studio catalog, YouTube Music Official Topic/VEVO badges,
  /// verified square album artwork, and song duration sanity (90s - 360s).
  static double calculateSourcePopularity(Song song) {
    double score = 0.0;

    // 1. Studio release authority / verified audio stream quality
    // Saavn 320kbps catalog gets a subtle bitrate preference (+0.25).
    // YouTube Official Topic / VEVO / Studio tracks get +0.22.
    // Clean independent/single audio tracks get +0.18.
    if (song.source == 'saavn') {
      score += 0.25;
    } else if (song.artist.toLowerCase().contains('topic') ||
               song.artist.toLowerCase().contains('vevo') ||
               song.hasOfficialAlbumArt) {
      score += 0.22;
    } else {
      score += 0.18;
    }

    // 2. Official Square Studio Album Art (1000x1000 / 500x500 CDN vs thumbnail)
    if (song.hasOfficialAlbumArt) {
      score += 0.30;
    } else if (song.coverUrl.isNotEmpty && !song.coverUrl.contains('default.jpg') && !song.coverUrl.contains('mqdefault.jpg')) {
      score += 0.20;
    } else {
      score += 0.05;
    }

    // 3. Duration Sanity (standard studio song 90s - 360s)
    if (song.duration >= 90 && song.duration <= 360) {
      score += 0.25;
    } else if (song.duration >= 45 && song.duration <= 600) {
      score += 0.15;
    }

    // 4. Clean studio title (not a remix/lofi/bootleg unless requested)
    if (song.versionTag == 'Original') {
      score += 0.20;
    } else {
      score += 0.10;
    }

    return score.clamp(0.0, 1.0);
  }

  /// Stage 4: Multi-Factor Relevance Scoring Component 3: UserAffinity (Weight 0.20)
  /// Checks whether the song artist is in HistoryManager (listening history)
  /// or FavoritesManager (liked songs), boosting familiar and loved artists.
  static double calculateUserAffinity(
    Song song, {
    List<Song>? history,
    List<Song>? favorites,
  }) {
    final hist = history ?? (HistoryManager.historyNotifier.value);
    final favs = favorites ?? (FavoritesManager.favoritesNotifier.value);

    final candArtist = song.primaryArtist.toLowerCase();
    final candAlbum = song.album.toLowerCase();
    if (candArtist.isEmpty && candAlbum.isEmpty) return 0.0;

    // 1. Liked in favorites -> highest affinity 1.0
    for (final fav in favs) {
      if (fav.id == song.id) return 1.0;
      if (candArtist.isNotEmpty &&
          (fav.primaryArtist.toLowerCase() == candArtist ||
           SongRepository.normalizeArtist(fav.artist).toLowerCase() == candArtist)) {
        return 1.0;
      }
      if (candAlbum.isNotEmpty &&
          candAlbum != 'studio album' &&
          candAlbum != 'single' &&
          candAlbum != 'unknown' &&
          fav.album.toLowerCase() == candAlbum) {
        return 0.95;
      }
    }

    // 2. Played in history
    int playCount = 0;
    for (final h in hist) {
      if (h.id == song.id) return 0.90;
      if (candArtist.isNotEmpty &&
          (h.primaryArtist.toLowerCase() == candArtist ||
           SongRepository.normalizeArtist(h.artist).toLowerCase() == candArtist)) {
        playCount++;
      } else if (candAlbum.isNotEmpty &&
                 candAlbum != 'studio album' &&
                 candAlbum != 'single' &&
                 candAlbum != 'unknown' &&
                 h.album.toLowerCase() == candAlbum) {
        playCount += 2;
      }
    }

    if (playCount >= 5) return 1.0;
    if (playCount >= 3) return 0.75;
    if (playCount == 2) return 0.50;
    if (playCount == 1) return 0.25;

    return 0.0;
  }

  /// Computes composite multi-factor relevance score:
  /// Score = (0.45 * StringSimilarity) + (0.35 * SourcePopularity) + (0.20 * UserAffinity)
  static double calculateCompositeRelevance(
    Song song,
    QueryIntent intent, {
    List<Song>? history,
    List<Song>? favorites,
    List<String>? preferredLanguages,
    UserAffinityContext? affinityContext,
  }) {
    // If query has explicit language override, strictly reject any cross-language mismatch
    if (intent.explicitLanguage != null &&
        SongRepository.isLanguageMismatch(song, intent.explicitLanguage!)) {
      return 0.0;
    }

    final stringSim = calculateStringSimilarity(song, intent);
    final qLower = intent.cleanQuery.toLowerCase();
    final songLang = song.language?.toLowerCase().trim() ?? '';
    final cleanTitle = SearchQueryPlanner.cleanTitle(song.title).toLowerCase();
    final isExactTitleMatch = cleanTitle == qLower || song.normalizedTitle == qLower;
    final isArtistTarget = song.primaryArtist.isNotEmpty &&
        (qLower == song.primaryArtist.toLowerCase() || song.primaryArtist.toLowerCase().contains(qLower));

    // Purge non-Indian foreign language songs (Arabic, Spanish, French, etc.)
    // unless explicit foreign query, exact global hit match (e.g. "Despacito"), or artist match (e.g. "BTS")
    const nonRegionalLanguages = {
      'arabic', 'spanish', 'french', 'turkish', 'russian', 'korean', 'chinese', 'german', 'italian', 'persian', 'japanese'
    };
    final isExplicitForeign = intent.explicitLanguage != null && nonRegionalLanguages.contains(intent.explicitLanguage!.toLowerCase());
    final isForeignInQuery = nonRegionalLanguages.any((l) => qLower.contains(l));

    if (!isExplicitForeign && !isForeignInQuery) {
      // Arabic, Turkish, and Persian tracks or Arabic script are strictly purged unless Urdu
      if (songLang == 'arabic' || songLang == 'turkish' || songLang == 'persian') {
        return 0.0;
      }
      if (songLang != 'urdu') {
        if (ArtistSanitizer.isMiddleEasternOrForeignArtist(song.artist) ||
            ArtistSanitizer.isMiddleEasternOrForeignArtist(song.title) ||
            _arabicScriptRegex.hasMatch('${song.title} ${song.artist}')) {
          return 0.0;
        }
      }
      // Other non-regional foreign languages (Spanish, Korean, Japanese, French, etc.)
      // are purged unless the user searched for the exact global song title or artist
      if (songLang.isNotEmpty && nonRegionalLanguages.contains(songLang)) {
        if (!isExactTitleMatch && !isArtistTarget) {
          return 0.0;
        }
      }
    }

    // Spoken dialogue / movie scene rejection:
    // If query does not explicitly ask for dialogue/scene/ringtone, reject spoken dialogue tracks
    // (Bypassed ONLY when user explicitly typed the exact song title or artist)
    final titleLower = song.title.toLowerCase();
    if (_dialogueRegex.hasMatch(titleLower)) {
      final queryAsksDialogue = qLower.contains('dialogue') || qLower.contains('scene') || qLower.contains('ringtone');
      if (!queryAsksDialogue && !isExactTitleMatch && !isArtistTarget) {
        return 0.0;
      }
    }

    // For very short queries (<= 3 chars, e.g. "hi"), reject non-Indian English bedroom-pop noise
    if (qLower.length <= 3) {
      final userPrefLangs = (preferredLanguages != null && preferredLanguages.isNotEmpty) ? preferredLanguages.map((l) => l.toLowerCase().trim()).toSet() : {'tamil'};

      final hasRegionalMatch = song.source == 'saavn' ||
          userPrefLangs.contains(song.language?.toLowerCase().trim()) ||
          userPrefLangs.any((l) => song.title.toLowerCase().contains(l) || song.album.toLowerCase().contains(l));
      if (song.source == 'youtube' && !hasRegionalMatch) {
        final titleAndArtist = '${song.title} ${song.artist} ${song.album}'.toLowerCase();
        if (!_knownIndianArtistsRegex.hasMatch(titleAndArtist) && !userPrefLangs.any((l) => titleAndArtist.contains(l))) {
          return 0.0;
        }
      }
    }
    final popularity = calculateSourcePopularity(song);
    final affinity = affinityContext?.computeAffinity(song) ??
        calculateUserAffinity(song, history: history, favorites: favorites);

    // Multi-factor formula with query-gated affinity:
    // Personal affinity cannot promote a song that does not match the typed query
    final double effectiveAffinity;
    if (stringSim >= 0.60) {
      effectiveAffinity = affinity;
    } else if (stringSim >= 0.25) {
      effectiveAffinity = affinity * ((stringSim - 0.25) / 0.35);
    } else {
      effectiveAffinity = 0.0;
    }

    double score = (0.50 * stringSim) + (0.30 * popularity) + (0.20 * effectiveAffinity);

    // Exact title matches establish a strong confidence baseline (>= 0.75)
    if (stringSim >= 0.98) {
      score = math.max(score, 0.75);
    }

    // Lyrics match promotion: if query matches indexed lyrics, boost relevance
    if (song.matchedLyricSnippet != null && song.matchedLyricSnippet!.isNotEmpty) {
      score = math.max(score, 0.90);
    }

    // Album unpack promotion: if song belongs to an album matching query, promote it directly to Songs top rank
    final albLower = song.album.toLowerCase().trim();
    if (qLower.isNotEmpty && albLower.isNotEmpty) {
      final isAlbMatch = isAlbumOrMovieEntityMatch(albLower, qLower) || (intent.effectiveCoreQuery.isNotEmpty && isAlbumOrMovieEntityMatch(albLower, intent.effectiveCoreQuery));
      if (isAlbMatch) {
        score = 1.0;
      } else if (albLower.startsWith('$qLower ') || albLower.startsWith('$qLower-') || albLower.startsWith('$qLower (')) {
        score = (score + 0.35).clamp(0.0, 1.0);
      }
    }

    // Harsh suppression for unrelated items when query is short (<= 3 chars)
    if (qLower.length <= 3 && stringSim < 0.80) {
      score = score * 0.30;
    }

    // Subtle language match boost if preferred languages provided
    if (preferredLanguages != null && preferredLanguages.isNotEmpty) {
      final userLangs = preferredLanguages.map((l) => l.toLowerCase().trim()).toSet();
      final songLang = song.language?.toLowerCase().trim() ?? '';
      if (userLangs.contains(songLang) || userLangs.any((l) => song.title.toLowerCase().contains(l))) {
        score = (score + 0.05).clamp(0.0, 1.0);
      }
    }

    return score.clamp(0.0, 1.0);
  }

  /// Backward-compatible adapter for scoreSong utilizing the unified Multi-Factor Relevance Ranker.
  static double scoreSong(
    Song song,
    QueryIntent intent, {
    required List<String> preferredLanguages,
    List<Song>? history,
    List<Song>? favorites,
  }) {
    return calculateCompositeRelevance(
      song,
      intent,
      history: history,
      favorites: favorites,
      preferredLanguages: preferredLanguages,
    );
  }

  /// Stage 3 & 4: Normalization, Cross-Source Canonical Fingerprint Deduplication,
  /// and Unified Multi-Factor Relevance Ranking.
  /// Deterministic 5-tier ranking comparison:
  /// 1. Composite Relevance Score (descending)
  /// 2. Exact Title Equality
  /// 3. Studio Source Authority (Saavn 320k vs YT)
  /// 4. Release Year (newer first)
  /// 5. Stable Canonical ID
  static int compareRankedEntries(
    MapEntry<double, Song> a,
    MapEntry<double, Song> b,
    String queryLower, {
    Map<String, int>? arrivalOrder,
  }) {
    final scoreCmp = b.key.compareTo(a.key);
    if (scoreCmp != 0) return scoreCmp;

    final songA = a.value;
    final songB = b.value;

    // 1. Movie Soundtrack Match Precedence: Child tracks of matched film entity outrank standalone singles
    final albA = songA.album.toLowerCase().trim();
    final albB = songB.album.toLowerCase().trim();
    final aAlbumMatch = isAlbumOrMovieEntityMatch(albA, queryLower) ? 1 : 0;
    final bAlbumMatch = isAlbumOrMovieEntityMatch(albB, queryLower) ? 1 : 0;
    if (aAlbumMatch != bAlbumMatch) return bAlbumMatch.compareTo(aAlbumMatch);

    // If both tracks belong to the SAME matched movie/soundtrack entity, preserve official tracklist order!
    if (aAlbumMatch == 1 && bAlbumMatch == 1 && albA == albB && arrivalOrder != null) {
      final aExact = (songA.title.toLowerCase().trim() == queryLower) ? 1 : 0;
      final bExact = (songB.title.toLowerCase().trim() == queryLower) ? 1 : 0;
      if (aExact != bExact) return bExact.compareTo(aExact);

      final idxA = arrivalOrder[songA.id] ?? 0;
      final idxB = arrivalOrder[songB.id] ?? 0;
      if (idxA != idxB) return idxA.compareTo(idxB);
    }

    final aExact = (songA.title.toLowerCase().trim() == queryLower) ? 1 : 0;
    final bExact = (songB.title.toLowerCase().trim() == queryLower) ? 1 : 0;
    if (aExact != bExact) return bExact.compareTo(aExact);

    // Direct Title Match Precedence for tied non-album tracks
    bool titleMatches(String title) {
      final t = title.toLowerCase().trim();
      if (t == queryLower || t.contains(queryLower) || queryLower.contains(t)) return true;
      if (t.length >= 3 && queryLower.length >= 3 && (t.length - queryLower.length).abs() <= 2) {
        return BkTree.levenshteinDistance(t, queryLower, maxDistance: 2) <= 2;
      }
      return false;
    }

    final aTitleMatch = titleMatches(songA.title) ? 1 : 0;
    final bTitleMatch = titleMatches(songB.title) ? 1 : 0;
    if (aTitleMatch != bTitleMatch) return bTitleMatch.compareTo(aTitleMatch);

    final aStudio = (songA.source.toLowerCase() == 'saavn') ? 1 : 0;
    final bStudio = (songB.source.toLowerCase() == 'saavn') ? 1 : 0;
    if (aStudio != bStudio) return bStudio.compareTo(aStudio);

    final aArt = songA.hasOfficialAlbumArt ? 1 : 0;
    final bArt = songB.hasOfficialAlbumArt ? 1 : 0;
    if (aArt != bArt) return bArt.compareTo(aArt);

    if (arrivalOrder != null) {
      final idxA = arrivalOrder[songA.id] ?? 0;
      final idxB = arrivalOrder[songB.id] ?? 0;
      if (idxA != idxB) return idxA.compareTo(idxB);
    }

    return songA.id.compareTo(songB.id);
  }

  static List<Song> deduplicateAndRankUnified({
    required List<Song> saavnSongs,
    required List<Song> ytSongs,
    List<Song> audiusSongs = const [],
    required QueryIntent intent,
    List<String>? preferredLanguages,
    List<Song>? history,
    List<Song>? favorites,
    UserAffinityContext? affinityContext,
  }) {
    final Map<String, Song> canonicalMap = {};
    final List<Song> deduplicatedPool = [];

    // 1. Ingest JioSaavn songs first: clean Indian/regional metadata, 320kbps audio, studio square cover art
    for (final song in saavnSongs) {
      final fp = SearchQueryPlanner.generateCanonicalFingerprint(song.title, song.artist);
      if (fp.isNotEmpty && !canonicalMap.containsKey(fp)) {
        canonicalMap[fp] = song;
        deduplicatedPool.add(song);
      }
    }

    // 2. Ingest YouTube Music songs: attach to existing canonical as version if duplicate, else add as new candidate
    for (final ytSong in ytSongs) {
      final fp = SearchQueryPlanner.generateCanonicalFingerprint(ytSong.title, ytSong.artist);
      Song? matchedPrimary = canonicalMap[fp];

      // Secondary check via isSameSong if fingerprint differed slightly
      if (matchedPrimary == null) {
        for (final existing in deduplicatedPool) {
          if (SearchQueryPlanner.isSameSong(
            titleA: existing.title,
            artistsA: existing.artist,
            titleB: ytSong.title,
            artistsB: ytSong.artist,
          )) {
            matchedPrimary = existing;
            break;
          }
        }
      }

      if (matchedPrimary != null) {
        // Merge YouTube track into versions list of the primary studio track
        final existingVersions = List<TrackEntity>.from(matchedPrimary.versions);
        if (!existingVersions.any((v) => v.id == ytSong.id)) {
          existingVersions.add(ytSong);
          final updated = matchedPrimary.copyWith(versions: existingVersions);
          final idx = deduplicatedPool.indexOf(matchedPrimary);
          if (idx != -1) {
            deduplicatedPool[idx] = updated;
          }
          canonicalMap[fp] = updated;
        }
      } else {
        var processedYt = ytSong;
        if (!processedYt.hasOfficialAlbumArt) {
          final studioCover = CatalogDatabase.getSongCoverArt(
            processedYt.title,
            artist: processedYt.artist,
            album: processedYt.album,
          );
          if (studioCover != null && studioCover.isNotEmpty) {
            processedYt = processedYt.copyWith(coverUrl: studioCover);
          }
        }
        if (fp.isNotEmpty) canonicalMap[fp] = processedYt;
        deduplicatedPool.add(processedYt);
      }
    }

    final Map<String, int> arrivalOrder = {
      for (int i = 0; i < deduplicatedPool.length; i++) deduplicatedPool[i].id: i
    };

    final effAffinityContext = affinityContext ?? UserAffinityContext.fromSongs(
      favorites: favorites,
      history: history,
    );

    // 4. Score every song in the unified deduplicated pool (O(1) affinity per song)
    final scored = deduplicatedPool.map((song) {
      final score = calculateCompositeRelevance(
        song,
        intent,
        history: history,
        favorites: favorites,
        preferredLanguages: preferredLanguages,
        affinityContext: effAffinityContext,
      );
      return MapEntry(score, song);
    }).where((e) => e.key > 0.0).toList();

    // 5. Sort descending by Multi-Factor Relevance Score with tracklist order preservation
    scored.sort((a, b) => compareRankedEntries(
      a,
      b,
      intent.cleanQuery.toLowerCase(),
      arrivalOrder: arrivalOrder,
    ));

    return scored.map((e) => e.value).toList();
  }

  /// Interleaves primary (JioSaavn) and secondary (YouTube) search candidates (fallback ranker).
  static List<Song> interleaveRankedResults(
    List<Song> primarySongs,
    List<Song> secondarySongs,
  ) {
    if (primarySongs.isEmpty) return secondarySongs;
    if (secondarySongs.isEmpty) return primarySongs;

    final List<Song> merged = [];
    final Set<String> seenKeys = {};

    for (final song in primarySongs) {
      final key = song.cleanTitleKey;
      if (key.isNotEmpty) seenKeys.add(key);
    }

    final List<Song> distinctSecondary = [];
    for (final song in secondarySongs) {
      final key = song.cleanTitleKey;
      if (key.isEmpty || !seenKeys.contains(key)) {
        if (key.isNotEmpty) seenKeys.add(key);
        distinctSecondary.add(song);
      }
    }

    int primIdx = 0;
    int secIdx = 0;

    while (primIdx < primarySongs.length || secIdx < distinctSecondary.length) {
      for (int i = 0; i < 2 && primIdx < primarySongs.length; i++) {
        merged.add(primarySongs[primIdx++]);
      }
      if (secIdx < distinctSecondary.length) {
        merged.add(distinctSecondary[secIdx++]);
      }
    }

    return merged;
  }

  /// Progressive search yielding JioSaavn results immediately (~300ms),
  /// followed by progressively merged YouTube and Audius results.
  /// All providers are capped with a strict 3-second safety timeout.
  static Stream<SearchResults> searchProgressive(
    String rawQuery, {
    String? language,
    QueryIntent? precomputedIntent,
    int limit = 25,
  }) async* {
    final normalizedRaw = rawQuery.trim().toLowerCase();
    final intent = precomputedIntent ?? understandQuery(normalizedRaw);
    if (intent.cleanQuery.isEmpty) {
      yield SearchResults();
      return;
    }

    final prefLangs = SettingsManager.preferredLanguages;
    final effectiveLang = intent.explicitLanguage ??
        (language != null && language.isNotEmpty && language.toLowerCase() != 'all' && language.toLowerCase() != 'any' ? language : null);

    // SWR (Stale-While-Revalidate): Yield fast LRU in-memory cache immediately (0ms),
    // then continue executing network pipeline to revalidate fresh catalog versions.
    final cached = SearchCache.get(rawQuery, language: effectiveLang) ?? SearchCache.get(rawQuery);
    if (cached != null) {
      yield SearchResults(
        songs: cached.songs,
        ytSongs: cached.ytSongs,
        saavnSongs: cached.saavnSongs,
        audiusSongs: cached.audiusSongs,
        albums: cached.albums,
        artists: cached.artists,
        playlists: cached.playlists,
        topResult: cached.topResult,
        didYouMean: cached.didYouMean,
        error: null,
        isCached: true,
        isFinal: false,
      );
    }

    List<Song> catalogSongs = [];
    List<Song> rawSaavn = [];
    List<Map<String, dynamic>> initialAlbums = [];
    List<Map<String, dynamic>> initialArtists = [];
    List<Map<String, dynamic>> initialPlaylists = [];
    SearchResults? lastEmittedBundle;
    final queryAffinityCtx = UserAffinityContext.fromSongs();

    try {
      bool saavnFailed = false;
      bool ytFailed = false;

      // Preserve explicit language in search query via centralized provider formatter
      final saavnSearchQuery = SearchQueryPlanner.formatProviderQuery(intent.cleanQuery, explicitLanguage: effectiveLang);

      final Future<List<Song>> saavnFuture = () async {
        try {
          var results = await SaavnClient.search(
            saavnSearchQuery,
            limit: limit,
            language: effectiveLang,
          ).timeout(const Duration(seconds: 5), onTimeout: () {
            saavnFailed = true;
            return <Song>[];
          });
          if (results.isNotEmpty) saavnFailed = false;
          if (results.isEmpty && intent.effectiveCoreQuery != intent.cleanQuery) {
            final coreSearch = SearchQueryPlanner.formatProviderQuery(intent.effectiveCoreQuery, explicitLanguage: effectiveLang);
            results = await SaavnClient.search(
              coreSearch,
              limit: limit,
              language: effectiveLang,
            ).timeout(const Duration(seconds: 5), onTimeout: () => <Song>[]);
          }
          return results;
        } catch (e) {
          saavnFailed = true;
          debugPrint('[SearchService] Upstream Saavn primary search fault isolated: $e');
          return <Song>[];
        }
      }();

      final Future<List<Song>> transliteratedSaavnFuture = () async {
        if (intent.transliteratedQuery == intent.cleanQuery) return <Song>[];
        try {
          final transQuery = SearchQueryPlanner.formatProviderQuery(intent.transliteratedQuery, explicitLanguage: effectiveLang);
          return await SaavnClient.search(
            transQuery,
            limit: limit,
            language: effectiveLang,
          ).timeout(const Duration(seconds: 2), onTimeout: () => <Song>[]);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn transliterated search fault isolated: $e');
          return <Song>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> albumsFuture = () async {
        try {
          var alb = await SaavnClient.searchAlbums(saavnSearchQuery, limit: 16)
              .timeout(const Duration(milliseconds: 2000), onTimeout: () => <Map<String, dynamic>>[]);
          if (alb.isEmpty && intent.effectiveCoreQuery != intent.cleanQuery && intent.effectiveCoreQuery != saavnSearchQuery) {
            alb = await SaavnClient.searchAlbums(intent.effectiveCoreQuery, limit: 16)
                .timeout(const Duration(milliseconds: 2000), onTimeout: () => <Map<String, dynamic>>[]);
          }
          if (alb.isEmpty && intent.cleanQuery.toLowerCase() != saavnSearchQuery.toLowerCase()) {
            final cleanAlbs = await SaavnClient.searchAlbums(intent.cleanQuery, limit: 16)
                .timeout(const Duration(milliseconds: 2000), onTimeout: () => <Map<String, dynamic>>[]);
            alb.addAll(cleanAlbs);
          }
          return alb;
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn albums search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> artistsFuture = () async {
        try {
          final isGeneric = intent.cleanQuery.toLowerCase() == 'top hits' ||
              intent.cleanQuery.toLowerCase() == 'hits' ||
              intent.cleanQuery.toLowerCase() == 'top songs' ||
              intent.cleanQuery.toLowerCase() == 'songs';
          final artistSearchQuery = SearchQueryPlanner.formatArtistQuery(intent.effectiveCoreQuery, explicitLanguage: effectiveLang, isGeneric: isGeneric);
          final rawArtists = await SaavnClient.searchArtists(artistSearchQuery, limit: 12, language: effectiveLang)
              .timeout(const Duration(seconds: 2), onTimeout: () => <Map<String, dynamic>>[]);
          return filterArtistsByLanguage(rawArtists, language: effectiveLang, query: intent.effectiveCoreQuery);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn artists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> playlistsFuture = () async {
        try {
          return await SaavnClient.searchPlaylists(saavnSearchQuery, limit: 10, language: effectiveLang)
              .timeout(const Duration(seconds: 2), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn playlists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final ytSearchQuery = SearchQueryPlanner.formatProviderQuery(intent.cleanQuery, explicitLanguage: effectiveLang);

      final Future<List<Song>> ytFuture = () async {
        try {
          final res = await YouTubeClient.search(ytSearchQuery, limit: limit)
              .timeout(const Duration(milliseconds: 3500), onTimeout: () {
            ytFailed = true;
            return <Song>[];
          });
          if (res.isNotEmpty) ytFailed = false;
          return res;
        } catch (e, stack) {
          ytFailed = true;
          AppLogger.recordError(e, stack, context: 'SearchService: YouTube search failed for query "$ytSearchQuery"');
          AppLogger.log('SearchService', 'Upstream YouTube search fault isolated: $e');
          debugPrint('[SearchService] Upstream YouTube search fault isolated: $e');
          return <Song>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> ytPlaylistsFuture = () async {
        try {
          return await YouTubeClient.searchPlaylists(ytSearchQuery, limit: 8)
              .timeout(const Duration(milliseconds: 2500), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          debugPrint('[SearchService] Upstream YouTube playlists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      // ── PHASE 0: Instant Local Master Catalog Yield (0-15ms) ──
      catalogSongs = [];
      List<Map<String, dynamic>> catMovies = [];
      List<Map<String, dynamic>> catArtists = [];
      try {
        final catQuery = intent.effectiveCoreQuery;
        catalogSongs = await CatalogDatabase.searchCatalog(
          catQuery,
          limit: limit,
          language: effectiveLang,
        );
        if (catalogSongs.isEmpty && catQuery != intent.cleanQuery) {
          catalogSongs = await CatalogDatabase.searchCatalog(
            intent.cleanQuery,
            limit: limit,
            language: effectiveLang,
          );
        }
        if (catalogSongs.isEmpty && intent.transliteratedQuery != intent.cleanQuery) {
          catalogSongs = await CatalogDatabase.searchCatalog(
            intent.transliteratedQuery,
            limit: limit,
            language: effectiveLang,
          );
        }
        catMovies = await CatalogDatabase.searchMovies(catQuery, limit: 8);
        if (catMovies.isEmpty && catQuery != intent.cleanQuery) {
          catMovies = await CatalogDatabase.searchMovies(intent.cleanQuery, limit: 8);
        }
        if (catMovies.isEmpty && intent.transliteratedQuery != intent.cleanQuery) {
          catMovies = await CatalogDatabase.searchMovies(intent.transliteratedQuery, limit: 8);
        }
        catArtists = await CatalogDatabase.searchArtists(catQuery, limit: 6);
        if (catArtists.isEmpty && catQuery != intent.cleanQuery) {
          catArtists = await CatalogDatabase.searchArtists(intent.cleanQuery, limit: 6);
        }
        if (catArtists.isEmpty && intent.transliteratedQuery != intent.cleanQuery) {
          catArtists = await CatalogDatabase.searchArtists(intent.transliteratedQuery, limit: 6);
        }
      } catch (e, stack) {
        AppLogger.log('SearchService', 'Phase 0 local catalog search error: $e', level: LogLevel.warn);
        AppLogger.recordError(e, stack, context: 'Phase 0 local catalog search failed for query "${intent.cleanQuery}"');
      }

      final phase0Albums = catMovies.map((m) => {
        ...m,
        'image': m['image'] ?? m['cover_url'] ?? '',
      }).toList();
      final phase0Playlists = generateAutoPlaylistsFromAlbums(phase0Albums);

      if (catalogSongs.isNotEmpty || phase0Albums.isNotEmpty || catArtists.isNotEmpty) {
        yield SearchResults(
          songs: catalogSongs,
          ytSongs: const [],
          saavnSongs: catalogSongs,
          audiusSongs: const [],
          albums: phase0Albums,
          artists: catArtists,
          playlists: phase0Playlists,
          topResult: null,
          didYouMean: null,
          error: null,
        );
      }

      // ── PHASE 1A: Ultra-Fast Saavn Songs Yield (~200-300ms) ──
      // Yield primary JioSaavn songs immediately as soon as saavnFuture completes!
      // Do NOT block songs on transliteration, albums, artists, or playlists.
      rawSaavn = await saavnFuture;

      final qClean = intent.cleanQuery.toLowerCase().trim();
      final qCore = intent.effectiveCoreQuery.toLowerCase().trim();

      final List<Song> combinedSaavnEarly = [...catalogSongs];
      for (final s in rawSaavn) {
        if (!combinedSaavnEarly.any((x) => x.id == s.id)) combinedSaavnEarly.add(s);
      }

      final canonicalSaavnEarly = SongRepository.groupCanonicalSongs(
        combinedSaavnEarly,
        preferredLanguage: effectiveLang,
      );

      List<Song> candidateSaavnEarly = intent.explicitLanguage != null
          ? SongRepository.filterByLanguage(canonicalSaavnEarly, intent.explicitLanguage!)
          : canonicalSaavnEarly;
      bool bypassedExplicitLangSaavnEarly = false;
      if (candidateSaavnEarly.isEmpty && canonicalSaavnEarly.isNotEmpty && intent.explicitLanguage != null) {
        candidateSaavnEarly = canonicalSaavnEarly;
        bypassedExplicitLangSaavnEarly = true;
      }

      final scoredSaavnEarly = candidateSaavnEarly.map((s) {
        final score = calculateCompositeRelevance(
          s,
          bypassedExplicitLangSaavnEarly ? intent.copyWith(explicitLanguage: null) : intent,
          preferredLanguages: prefLangs,
          affinityContext: queryAffinityCtx,
        );
        return MapEntry(score, s);
      }).where((e) => e.key > 0.0).toList();

      final Map<String, int> saavnArrivalEarly = {
        for (int i = 0; i < candidateSaavnEarly.length; i++) candidateSaavnEarly[i].id: i
      };
      scoredSaavnEarly.sort((a, b) => compareRankedEntries(a, b, qClean, arrivalOrder: saavnArrivalEarly));
      final rankedSaavnEarly = scoredSaavnEarly.map((e) => e.value).toList();

      Map<String, dynamic>? initialTopResultEarly;
      if (scoredSaavnEarly.isNotEmpty && scoredSaavnEarly.first.key >= 0.70) {
        final top = scoredSaavnEarly.first.value;
        initialTopResultEarly = {
          'type': 'song',
          'id': top.id,
          'title': top.title,
          'artist': top.artist,
          'cover_url': top.coverUrl,
          'duration': top.duration,
          'source': top.source,
          'score': scoredSaavnEarly.first.key,
          'versions': top.versions.map((v) => v.toMap()).toList(),
        };
      }

      if (rankedSaavnEarly.isNotEmpty) {
        final List<Map<String, dynamic>> earlyExtractedAlbums = [...phase0Albums];
        final Set<String> earlySeenAlbums = {
          for (final a in earlyExtractedAlbums) (a['title'] ?? '').toString().toLowerCase().trim()
        };
        for (final s in rankedSaavnEarly.take(6)) {
          final alb = s.album.trim();
          final albLower = alb.toLowerCase();
          if (alb.isNotEmpty &&
              albLower != 'single' &&
              albLower != 'unknown' &&
              albLower != 'various artists' &&
              albLower != 'studio album' &&
              earlySeenAlbums.add(albLower)) {
            earlyExtractedAlbums.add({
              'id': s.album.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase(),
              'title': alb,
              'artist': s.artist,
              'image': s.coverUrl,
              'type': 'Album',
              'is_movie': true,
              'source': s.source,
            });
          }
        }

        lastEmittedBundle = SearchResults(
          songs: rankedSaavnEarly,
          ytSongs: const [],
          saavnSongs: rankedSaavnEarly,
          audiusSongs: const [],
          albums: earlyExtractedAlbums,
          artists: catArtists,
          playlists: phase0Playlists,
          topResult: initialTopResultEarly,
          didYouMean: null,
          error: null,
        );
        yield lastEmittedBundle;
      }

      // ── PHASE 1B: Metadata & Tabs Enrichment (~400-600ms) ──
      // Now await remaining Saavn endpoints for transliterated variants, albums, artists, playlists
      final saavnMeta = await Future.wait([
        transliteratedSaavnFuture,
        albumsFuture,
        artistsFuture,
        playlistsFuture,
      ]);

      final transSaavn = saavnMeta[0] as List<Song>;
      final rawAlbums = saavnMeta[1] as List<Map<String, dynamic>>;
      final artists = saavnMeta[2] as List<Map<String, dynamic>>;
      final rawPlaylists = saavnMeta[3] as List<Map<String, dynamic>>;

      // If the query matches an album/movie (e.g. "Hi", "Hi Nanna", "Leo", "Mersal"),
      // fetch all soundtrack tracks of that album so they are directly presented in song search.
      final List<Map<String, dynamic>> matchingAlbums = [];
      for (final a in rawAlbums) {
        final t = (a['title'] ?? a['name'] ?? '').toString();
        if (isAlbumOrMovieEntityMatch(t, qClean) || (qCore.isNotEmpty && isAlbumOrMovieEntityMatch(t, qCore))) {
          matchingAlbums.add(a);
        }
      }
      for (final cm in catMovies) {
        final t = (cm['title'] ?? '').toString();
        if ((isAlbumOrMovieEntityMatch(t, qClean) || (qCore.isNotEmpty && isAlbumOrMovieEntityMatch(t, qCore))) &&
            !matchingAlbums.any((x) => (x['title'] ?? '').toString().toLowerCase().trim() == t.toLowerCase().trim())) {
          matchingAlbums.add(cm);
        }
      }

      // Parallel async fetch of soundtrack songs for matching albums
      final Future<List<Song>> soundtrackFuture = () async {
        final List<Song> results = [];
        final targetAlbums = matchingAlbums.take(3).toList();
        final detailFutures = targetAlbums.map((alb) async {
          final albId = alb['id']?.toString() ?? '';
          final albTitle = (alb['title'] ?? alb['name'] ?? '').toString();
          if (albId.isNotEmpty || albTitle.isNotEmpty) {
            try {
              final details = await SongRepository.getAlbumDetails(albumId: albId, albumTitle: albTitle)
                  .timeout(const Duration(milliseconds: 2500), onTimeout: () => null);
              return details?['songs'] as List<Song>? ?? <Song>[];
            } catch (e) {
              AppLogger.log('SearchService', 'Phase 1 album details fetch fault: $e', level: LogLevel.debug);
              return <Song>[];
            }
          }
          return <Song>[];
        });
        final allLists = await Future.wait(detailFutures);
        for (final list in allLists) {
          for (final asong in list) {
            if (!results.any((x) => x.id == asong.id)) {
              results.add(asong);
            }
          }
        }
        return results;
      }();

      final List<Song> combinedSaavn = [];
      combinedSaavn.addAll(catalogSongs);
      for (final s in rawSaavn) {
        if (!combinedSaavn.any((x) => x.id == s.id)) {
          combinedSaavn.add(s);
        }
      }
      for (final s in transSaavn) {
        if (!combinedSaavn.any((x) => x.id == s.id)) {
          combinedSaavn.add(s);
        }
      }

      final canonicalSaavn = SongRepository.groupCanonicalSongs(
        combinedSaavn,
        preferredLanguage: effectiveLang,
      );

      List<Song> candidateSaavn = intent.explicitLanguage != null
          ? SongRepository.filterByLanguage(canonicalSaavn, intent.explicitLanguage!)
          : canonicalSaavn;
      bool bypassedExplicitLangSaavn = false;
      if (candidateSaavn.isEmpty && canonicalSaavn.isNotEmpty && intent.explicitLanguage != null) {
        candidateSaavn = canonicalSaavn;
        bypassedExplicitLangSaavn = true;
      }

      final scoredSaavn = candidateSaavn.map((s) {
        final score = calculateCompositeRelevance(
          s,
          bypassedExplicitLangSaavn ? intent.copyWith(explicitLanguage: null) : intent,
          preferredLanguages: prefLangs,
          affinityContext: queryAffinityCtx,
        );
        return MapEntry(score, s);
      }).where((e) => e.key > 0.0).toList();

      final Map<String, int> saavnArrival = {
        for (int i = 0; i < candidateSaavn.length; i++) candidateSaavn[i].id: i
      };
      scoredSaavn.sort((a, b) => compareRankedEntries(a, b, qClean, arrivalOrder: saavnArrival));
      final rankedSaavn = scoredSaavn.map((e) => e.value).toList();

      // If the search query targets an artist (e.g. "Anirudh Ravichander", "A.R. Rahman"),
      // fetch their full official discography of albums with verified artwork.
      Map<String, dynamic>? matchingArtist;
      for (final a in artists) {
        final aName = (a['name'] ?? '').toString().toLowerCase().trim();
        final canon = ArtistSanitizer.canonicalArtistName(aName).toLowerCase();
        if (qClean.length <= 2) {
          if ((aName.isNotEmpty && aName == qClean) ||
              (canon.isNotEmpty && canon == qClean) ||
              (aName.length >= 2 && aName.startsWith(qClean)) ||
              (canon.length >= 2 && canon.startsWith(qClean))) {
            matchingArtist = a;
            break;
          }
        } else {
          if ((aName.isNotEmpty && aName == qClean) ||
              (canon.isNotEmpty && canon == qClean) ||
              (qCore.length >= 3 && aName.contains(qCore)) ||
              (canon.length >= 3 && qClean.contains(canon))) {
            matchingArtist = a;
            break;
          }
        }
      }

      final Future<List<Map<String, dynamic>>> artistOfficialAlbumsFuture = () async {
        if (matchingArtist == null || qClean.length < 3) return <Map<String, dynamic>>[];
        final artId = matchingArtist['id']?.toString() ?? '';
        if (artId.isEmpty) return <Map<String, dynamic>>[];
        try {
          return await SaavnClient.getArtistAlbums(artId, limit: 40)
              .timeout(const Duration(seconds: 4), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          AppLogger.log('SearchService', 'Phase 2 artist albums fetch fault: $e', level: LogLevel.debug);
          return <Map<String, dynamic>>[];
        }
      }();

      // Populate Albums Tab: Prioritize regional movie/soundtrack albums correlated with top songs
      initialAlbums = [];
      final Set<String> seenAlbumNames = {};

      // 1. Correlate matched songs with their parent movie/soundtrack albums (Highest user relevance, e.g. "Kiss" by Jen Martin)
      for (final s in rankedSaavn.take(6)) {
        final alb = s.album.trim();
        final albLower = alb.toLowerCase();
        if (alb.isNotEmpty &&
            albLower != 'single' &&
            albLower != 'unknown' &&
            albLower != 'various artists' &&
            albLower != 'studio album' &&
            seenAlbumNames.add(albLower)) {
          initialAlbums.add({
            'id': s.album.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase(),
            'title': alb,
            'artist': s.artist,
            'image': s.coverUrl,
            'type': 'Album',
            'is_movie': true,
            'source': s.source,
          });
        }
      }

      // 2. Master Catalog verified movies
      for (final cm in catMovies) {
        final t = (cm['title'] ?? '').toString().toLowerCase().trim();
        if (t.isNotEmpty && seenAlbumNames.add(t)) {
          var img = cm['image'] ?? cm['cover_url'] ?? '';
          if (img.toString().isEmpty || img.toString().contains('default')) {
            img = CatalogDatabase.getMoviePoster(cm['title']?.toString() ?? '') ?? '';
          }
          initialAlbums.add({
            ...cm,
            'image': img,
            'artist': cm['artist'] ?? cm['composer'] ?? '',
          });
        }
      }

      // 3. Raw albums from JioSaavn search (filtered to ensure regional parity)
      for (final alb in filterGenuineAlbums(rawAlbums, query: intent.cleanQuery)) {
        final t = (alb['title'] ?? alb['name'] ?? '').toString().toLowerCase().trim();
        if (t.isNotEmpty && seenAlbumNames.add(t)) {
          initialAlbums.add(alb);
        }
      }

      // Auto-playlists: Synthesize 'Movie Soundtrack' playlists directly from albums & catalog movies
      final autoPlaylists = generateAutoPlaylistsFromAlbums(initialAlbums);
      final filteredRawPlaylists = filterPlaylistsByRelevanceAndLanguage(
        rawPlaylists,
        query: intent.cleanQuery,
        language: effectiveLang,
      );
      initialPlaylists = mergePlaylists(autoPlaylists, filteredRawPlaylists);

      // Populate Artists Tab: Merge direct artists with Master Catalog artists and song composers/singers
      initialArtists = [];
      final Set<String> seenArtistNames = {};

      void addCleanArtist(Map<String, dynamic> artMap) {
        final raw = Song.sanitize(artMap['name'] ?? artMap['title'] ?? '').trim();
        if (raw.isEmpty || raw.toLowerCase() == 'unknown artist') return;
        if (ArtistSanitizer.isCompositeOrMultiArtist(raw)) return;
        final canon = ArtistSanitizer.canonicalArtistName(raw);
        final canonLower = canon.toLowerCase();
        if (seenArtistNames.add(canonLower)) {
          final existingImg = artMap['image']?.toString() ?? '';
          final verifiedImg = existingImg.isNotEmpty && !existingImg.contains('default')
              ? existingImg
              : (SongRepository.verifiedArtistAvatars[canonLower] ?? CatalogDatabase.getArtistProfileImage(canon) ?? '');
          
          final isVerified = verifiedImg.isNotEmpty || SongRepository.isArtistVerified(canon);

          initialArtists.add({
            ...artMap,
            'name': canon,
            'image': verifiedImg,
            'is_verified': isVerified,
          });
        }
      }

      for (final ca in catArtists) {
        addCleanArtist(ca);
      }
      for (final a in artists) {
        addCleanArtist(a);
      }

      if (initialArtists.isEmpty) {
        final songArtists = CatalogDatabase.extractArtistsFromSongs(combinedSaavn, limit: 6);
        for (final sa in songArtists) {
          addCleanArtist(sa);
        }
      }

      Map<String, dynamic>? initialTopResult;
      String? didYouMean;

      final exactMovieMatch = initialAlbums.where(
        (a) => (a['title'] ?? '').toString().toLowerCase().trim() == intent.cleanQuery.toLowerCase().trim(),
      ).firstOrNull;

      if (exactMovieMatch != null) {
        initialTopResult = {
          'type': 'album',
          'id': exactMovieMatch['id']?.toString() ?? '',
          'title': exactMovieMatch['title']?.toString() ?? '',
          'artist': exactMovieMatch['artist']?.toString() ?? exactMovieMatch['composer']?.toString() ?? 'Soundtrack',
          'cover_url': exactMovieMatch['image']?.toString() ?? exactMovieMatch['cover_url']?.toString() ?? '',
          'score': 1.0,
        };
      } else if (scoredSaavn.isNotEmpty && scoredSaavn.first.key >= 0.70) {
        final top = scoredSaavn.first.value;
        initialTopResult = {
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
      }

      final hasStrongMatch = (initialTopResult != null && (initialTopResult['score'] as num? ?? 0.0) >= 0.80) ||
          exactMovieMatch != null ||
          initialAlbums.any((a) => isAlbumOrMovieEntityMatch((a['title'] ?? '').toString(), intent.cleanQuery));

      if (hasStrongMatch) {
        didYouMean = null;
      } else if (intent.transliteratedQuery.toLowerCase() != intent.cleanQuery.toLowerCase() &&
          !IndicRomanizer.hasIndicScript(intent.cleanQuery)) {
        didYouMean = intent.transliteratedQuery;
      } else {
        final correction = FuzzySearchService.findCorrection(intent.cleanQuery);
        if (correction != null && correction.corrected.toLowerCase() != intent.cleanQuery.toLowerCase()) {
          didYouMean = correction.corrected;
        }
      }

      if (rankedSaavn.isNotEmpty || initialAlbums.isNotEmpty || initialArtists.isNotEmpty || initialPlaylists.isNotEmpty) {
        lastEmittedBundle = SearchResults(
          songs: rankedSaavn,
          ytSongs: const [],
          saavnSongs: rankedSaavn,
          audiusSongs: const [],
          albums: initialAlbums,
          artists: initialArtists,
          playlists: initialPlaylists,
          topResult: initialTopResult,
          didYouMean: didYouMean,
          error: null,
        );
        yield lastEmittedBundle;
      }

      // ── PHASE 2: Merge YouTube Results & Background Soundtracks ──
      // Await YouTube songs and soundtrack songs concurrently
      final ytAndSoundtrack = await Future.wait([
        ytFuture,
        soundtrackFuture,
      ]);
      final rawYt = ytAndSoundtrack[0];
      final albumSoundtrackSongs = ytAndSoundtrack[1];

      final extraMeta = await Future.wait([
        ytPlaylistsFuture,
        artistOfficialAlbumsFuture,
      ]);
      final rawYtPlaylists = extraMeta[0];
      final artistOfficialAlbums = extraMeta[1];

      for (final alb in artistOfficialAlbums) {
        final t = (alb['title'] ?? alb['name'] ?? '').toString().toLowerCase().trim();
        if (t.isNotEmpty && seenAlbumNames.add(t)) {
          initialAlbums.insert(0, alb);
        }
      }

      final filteredYtPlaylists = filterPlaylistsByRelevanceAndLanguage(
        rawYtPlaylists,
        query: intent.cleanQuery,
        language: effectiveLang,
      );
      final finalPlaylists = mergePlaylists(initialPlaylists, filteredYtPlaylists);

      final groupedYt = SongRepository.groupCanonicalSongs(rawYt, preferredLanguage: effectiveLang);
      final deduplicatedYt = SongRepository.deduplicateSongs(groupedYt);
      List<Song> candidateYt = intent.explicitLanguage != null
          ? SongRepository.filterByLanguage(deduplicatedYt, intent.explicitLanguage!)
          : deduplicatedYt;
      bool bypassedExplicitLangYt = false;
      if (candidateYt.isEmpty && deduplicatedYt.isNotEmpty && intent.explicitLanguage != null) {
        candidateYt = deduplicatedYt;
        bypassedExplicitLangYt = true;
      }
      if (ytFailed && candidateYt.isEmpty && cached != null && cached.ytSongs.isNotEmpty) {
        candidateYt = cached.ytSongs;
      }
      final ytSongs = candidateYt;

      final scoredYt = candidateYt.map((s) {
        final score = calculateCompositeRelevance(
          s,
          bypassedExplicitLangYt ? intent.copyWith(explicitLanguage: null) : intent,
          preferredLanguages: prefLangs,
          affinityContext: queryAffinityCtx,
        );
        return MapEntry(score, s);
      }).where((e) => e.key > 0.0).toList();
      final Map<String, int> ytArrival = {
        for (int i = 0; i < candidateYt.length; i++) candidateYt[i].id: i
      };
      scoredYt.sort((a, b) => compareRankedEntries(a, b, qClean, arrivalOrder: ytArrival));
      final rankedYt = scoredYt.map((e) => e.value).toList();

      // Elevate exact singles first, then soundtrack songs, then remaining Saavn tracks
      final List<Song> enrichedSaavn = [];
      for (final s in rankedSaavn) {
        final sim = calculateStringSimilarity(s, intent);
        if (sim >= 0.95 && !enrichedSaavn.any((x) => x.id == s.id)) {
          enrichedSaavn.add(s);
        }
      }
      for (final s in albumSoundtrackSongs) {
        if (!enrichedSaavn.any((x) => x.id == s.id)) {
          enrichedSaavn.add(s);
        }
      }
      for (final s in rankedSaavn) {
        if (!enrichedSaavn.any((x) => x.id == s.id)) {
          enrichedSaavn.add(s);
        }
      }

      final List<Song> mergedSongs = deduplicateAndRankUnified(
        saavnSongs: enrichedSaavn,
        ytSongs: candidateYt,
        audiusSongs: const [],
        intent: intent,
        preferredLanguages: prefLangs,
        affinityContext: queryAffinityCtx,
      );

      // Asynchronous Write-Through Ingestion: store newly discovered songs in local CatalogDatabase
      for (final s in mergedSongs.take(5)) {
        CatalogDatabase.insertDynamicSong(s);
      }

      // Dynamic On-Device Personal Preference Matrix re-ranking
      final userRankedSongs = UserPreferenceMatrix.reRankWithPreferences(
        mergedSongs,
        intent.cleanQuery,
        intent: intent,
      );

      // Crown Top Result from userRankedSongs.first AFTER preference re-ranking
      Map<String, dynamic>? finalTopResult = initialTopResult;
      if (exactMovieMatch != null) {
        finalTopResult = initialTopResult;
      } else if (userRankedSongs.isNotEmpty) {
        final top = userRankedSongs.first;
        final topScore = calculateCompositeRelevance(top, intent, preferredLanguages: prefLangs);
        if (topScore >= 0.70) {
          finalTopResult = {
            'type': 'song',
            'id': top.id,
            'title': top.title,
            'artist': top.artist,
            'cover_url': top.coverUrl,
            'duration': top.duration,
            'source': top.source,
            'score': topScore,
            'versions': top.versions.map((v) => v.toMap()).toList(),
          };
        }
      }

      final List<Map<String, dynamic>> finalArtists = List<Map<String, dynamic>>.from(initialArtists);
      if (finalArtists.length < 5) {
        for (final sa in CatalogDatabase.extractArtistsFromSongs(userRankedSongs, limit: 8)) {
          final raw = Song.sanitize(sa['name'] ?? sa['title'] ?? '').trim();
          if (raw.isEmpty || raw.toLowerCase() == 'unknown artist') continue;
          if (ArtistSanitizer.isCompositeOrMultiArtist(raw)) continue;
          final canon = ArtistSanitizer.canonicalArtistName(raw);
          final canonLower = canon.toLowerCase();
          if (seenArtistNames.add(canonLower)) {
            final existingImg = sa['image']?.toString() ?? '';
            final verifiedImg = existingImg.isNotEmpty && !existingImg.contains('default')
                ? existingImg
                : (SongRepository.verifiedArtistAvatars[canonLower] ?? CatalogDatabase.getArtistProfileImage(canon) ?? '');

            final isVerified = verifiedImg.isNotEmpty || SongRepository.isArtistVerified(canon);

            finalArtists.add({
              ...sa,
              'name': canon,
              'image': verifiedImg,
              'is_verified': isVerified,
            });
          }
        }
      }

      FuzzySearchService.registerSongs(userRankedSongs.where((s) => s.source == 'saavn' && s.title.length <= 40).toList());

      if (didYouMean != null) {
        final hasStrongMatchPhase2 = (finalTopResult != null && (finalTopResult['score'] as num? ?? 0.0) >= 0.80) ||
            (userRankedSongs.isNotEmpty && calculateStringSimilarity(userRankedSongs.first, intent) >= 0.85);
        if (hasStrongMatchPhase2) {
          didYouMean = null;
        }
      }

      AppError? searchError;
      if (userRankedSongs.isEmpty && ytSongs.isEmpty && initialAlbums.isEmpty && finalArtists.isEmpty && finalPlaylists.isEmpty && (saavnFailed && ytFailed)) {
        searchError = AppError.offline(debugDetails: 'All upstream providers failed for "${intent.cleanQuery}"');
      }

      final finalBundle = SearchResults(
        songs: userRankedSongs,
        ytSongs: rankedYt.isNotEmpty ? rankedYt : ytSongs,
        saavnSongs: rankedSaavn,
        audiusSongs: const [],
        albums: initialAlbums,
        artists: finalArtists,
        playlists: finalPlaylists,
        topResult: finalTopResult,
        didYouMean: didYouMean,
        error: searchError,
        isFinal: true,
      );

      SearchCache.put(rawQuery, finalBundle, language: effectiveLang);
      yield finalBundle;
    } catch (e, stack) {
      debugPrint('[SearchService] Search error: $e');
      final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'SearchService.searchProgressive');
      if (cached != null && cached.songs.isNotEmpty) {
        yield SearchResults(
          songs: cached.songs,
          ytSongs: cached.ytSongs,
          saavnSongs: cached.saavnSongs,
          audiusSongs: cached.audiusSongs,
          albums: cached.albums,
          artists: cached.artists,
          playlists: cached.playlists,
          topResult: cached.topResult,
          didYouMean: cached.didYouMean,
          error: appErr,
          isFinal: true,
        );
      } else if (lastEmittedBundle != null && !lastEmittedBundle.isEmpty) {
        yield SearchResults(
          songs: lastEmittedBundle.songs,
          ytSongs: lastEmittedBundle.ytSongs,
          saavnSongs: lastEmittedBundle.saavnSongs,
          audiusSongs: lastEmittedBundle.audiusSongs,
          albums: lastEmittedBundle.albums,
          artists: lastEmittedBundle.artists,
          playlists: lastEmittedBundle.playlists,
          topResult: lastEmittedBundle.topResult,
          didYouMean: lastEmittedBundle.didYouMean,
          error: lastEmittedBundle.error ?? appErr,
          isFinal: true,
        );
      } else if (catalogSongs.isNotEmpty) {
        yield SearchResults(
          songs: catalogSongs,
          saavnSongs: catalogSongs,
          albums: initialAlbums,
          artists: initialArtists,
          playlists: initialPlaylists,
          error: appErr,
          isFinal: true,
        );
      } else {
        yield SearchResults(error: appErr, isFinal: true);
      }
    }
  }

  /// High-precision unified search across JioSaavn & YouTube Music.
  /// Consumes the progressive stream and awaits the final merged result.
  static Future<SearchResults> searchUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
  }) async {
    SearchResults lastResult = SearchResults();
    await for (final res in searchProgressive(rawQuery, language: language, limit: limit)) {
      lastResult = res;
    }
    return lastResult;
  }

  static int _searchGenerationId = 0;
  static int get currentGenerationId => _searchGenerationId;
  static int nextGenerationId() => ++_searchGenerationId;

  static final LruCache<String, ClassifiedSearchPayload> _classifiedLruCache =
      LruCache<String, ClassifiedSearchPayload>(capacity: 25);
  static final LruCache<String, List<Song>> _hydratedCollectionCache =
      LruCache<String, List<Song>>(capacity: 30);

  /// Clusters raw candidate songs into ClusteredTrackResults.
  /// Identifies official studio songs and nests fan mixes, slowed+reverb, mashups, and BGMs as alternateVersions.
  static List<ClusteredTrackResult> clusterAndClassifySongs(
    List<Song> songs, {
    required String query,
    bool isExplicitMixRequest = false,
  }) {
    if (songs.isEmpty) return const [];

    final Map<String, List<Song>> groups = {};
    final Map<String, ContentClassification> classifications = {};

    for (final song in songs) {
      final classification = TrackQualityFilter.classifyTrack(
        title: song.title,
        durationSec: song.duration,
        source: song.source,
        artist: song.artist,
        query: query,
      );

      // Hard-drop non-music reviews/trailers/junk
      if (classification == ContentClassification.rejectedJunk) {
        continue;
      }

      classifications[song.id] = classification;

      // Group key: canonical core title + primary artist
      final coreTitle = SearchQueryPlanner.extractNormalizedCoreTitle(song.title);
      final primaryArtist = song.primaryArtist.toLowerCase().trim();
      final groupKey = '$coreTitle|$primaryArtist';

      groups.putIfAbsent(groupKey, () => []).add(song);
    }

    final List<ClusteredTrackResult> clusters = [];

    for (final entry in groups.entries) {
      final candidates = entry.value;
      if (candidates.isEmpty) continue;

      candidates.sort((a, b) {
        final classA = classifications[a.id] ?? ContentClassification.officialTrack;
        final classB = classifications[b.id] ?? ContentClassification.officialTrack;

        if (classA == ContentClassification.officialTrack && classB != ContentClassification.officialTrack) {
          return -1;
        }
        if (classB == ContentClassification.officialTrack && classA != ContentClassification.officialTrack) {
          return 1;
        }

        final scoreA = SearchQueryPlanner.calculateRelevanceScore(
          query: query,
          song: a,
          classification: classA,
          isExplicitMixRequest: isExplicitMixRequest,
        );
        final scoreB = SearchQueryPlanner.calculateRelevanceScore(
          query: query,
          song: b,
          classification: classB,
          isExplicitMixRequest: isExplicitMixRequest,
        );
        return scoreB.compareTo(scoreA);
      });

      final primary = candidates.first;
      final alternates = candidates.skip(1).toList();
      final primaryClass = classifications[primary.id] ?? ContentClassification.officialTrack;

      final confidence = SearchQueryPlanner.calculateRelevanceScore(
        query: query,
        song: primary,
        classification: primaryClass,
        isExplicitMixRequest: isExplicitMixRequest,
      );

      final combinedVersions = <Song>[
        ...primary.versions,
        ...alternates.where((alt) => !primary.versions.any((v) => v.id == alt.id && v.source == alt.source)),
      ];

      final hydratedPrimary = primary.copyWith(
        versions: combinedVersions,
      );

      clusters.add(ClusteredTrackResult(
        primaryTrack: hydratedPrimary,
        category: primaryClass,
        confidenceScore: confidence,
        alternateVersions: combinedVersions,
      ));
    }

    clusters.sort((a, b) {
      final cmp = b.confidenceScore.compareTo(a.confidenceScore);
      if (cmp != 0) return cmp;
      return a.primaryTrack.id.compareTo(b.primaryTrack.id);
    });
    return clusters;
  }

  /// Evaluates whether the top clustered result meets the threshold (>= 0.85) to be crowned Top Result.
  static ClusteredTrackResult? evaluateTopResult(
    List<ClusteredTrackResult> clusters, {
    required String query,
    bool isExplicitMixRequest = false,
  }) {
    if (clusters.isEmpty) return null;
    final top = clusters.first;

    if (top.confidenceScore < 0.85) {
      return null;
    }

    if (top.category != ContentClassification.officialTrack && !isExplicitMixRequest) {
      return null;
    }

    return top;
  }

  /// Converts raw album maps into lightweight CollectionSummary objects
  static List<CollectionSummary> parseAlbumSummaries(List<Map<String, dynamic>> rawAlbums) {
    final List<CollectionSummary> list = [];
    final Set<String> seen = {};
    for (final alb in rawAlbums) {
      final title = alb['title']?.toString() ?? alb['name']?.toString() ?? '';
      if (title.isEmpty) continue;
      final key = title.toLowerCase().trim();
      if (seen.contains(key)) continue;
      seen.add(key);

      list.add(CollectionSummary(
        id: alb['id']?.toString() ?? '',
        title: title,
        subtitle: alb['artist']?.toString() ?? alb['subtitle']?.toString() ?? 'Album',
        artworkUrl: alb['image']?.toString() ?? alb['cover_url']?.toString() ?? '',
        type: CollectionType.album,
        trackCount: (alb['song_count'] as num?)?.toInt(),
      ));
    }
    return list;
  }

  /// Converts raw playlist maps into lightweight CollectionSummary objects
  static List<CollectionSummary> parsePlaylistSummaries(List<Map<String, dynamic>> rawPlaylists) {
    final List<CollectionSummary> list = [];
    final Set<String> seen = {};
    for (final pl in rawPlaylists) {
      final title = pl['title']?.toString() ?? pl['name']?.toString() ?? '';
      if (title.isEmpty) continue;
      final key = title.toLowerCase().trim();
      if (seen.contains(key)) continue;
      seen.add(key);

      list.add(CollectionSummary(
        id: pl['id']?.toString() ?? '',
        title: title,
        subtitle: pl['subtitle']?.toString() ?? 'Playlist',
        artworkUrl: pl['image']?.toString() ?? pl['cover_url']?.toString() ?? '',
        type: CollectionType.playlist,
        trackCount: (pl['song_count'] as num?)?.toInt(),
      ));
    }
    return list;
  }

  /// Lazily hydrates the full tracklist for an album or playlist on demand.
  static Future<List<Song>> hydrateCollectionTracks(CollectionSummary summary) async {
    final cached = _hydratedCollectionCache.get(summary.id);
    if (cached != null) return cached;

    List<Song> songs = [];
    try {
      if (summary.type == CollectionType.album) {
        final details = await SongRepository.getAlbumDetails(
          albumId: summary.id,
          albumTitle: summary.title,
        );
        if (details != null && details['songs'] is List<Song>) {
          songs = details['songs'] as List<Song>;
        }
      } else {
        final src = (summary.id.startsWith('VL') || summary.id.startsWith('RD')) ? 'youtube' : 'saavn';
        final details = await SongRepository.getRemotePlaylistTracks(
          playlistId: summary.id,
          playlistTitle: summary.title,
          source: src,
        );
        if (details['tracks'] is List<Song>) {
          songs = details['tracks'] as List<Song>;
        }
      }
    } catch (e) {
      AppLogger.log('SearchService', 'Error hydrating collection ${summary.title}: $e');
    }

    if (songs.isNotEmpty) {
      _hydratedCollectionCache.put(summary.id, songs);
    }
    return songs;
  }

  /// High-performance classified search returning grouped studio tracks + fan mixes.
  static Future<ClassifiedSearchPayload> searchClassifiedUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
    int? generationId,
  }) async {
    final clean = rawQuery.trim();
    if (clean.isEmpty) {
      return const ClassifiedSearchPayload(query: '');
    }

    final cacheKey = '${clean.toLowerCase()}__${language?.toLowerCase() ?? ""}';
    final cached = _classifiedLruCache.get(cacheKey);
    if (cached != null) {
      return cached;
    }

    final intent = SearchQueryPlanner.analyzeQuery(clean, explicitLanguage: language);
    final rawResults = await searchUnified(clean, language: language, limit: limit);

    if (generationId != null && generationId != _searchGenerationId) {
      return const ClassifiedSearchPayload(query: '');
    }

    final allRawSongs = [
      ...rawResults.songs,
      ...rawResults.saavnSongs,
      ...rawResults.ytSongs,
    ];

    final clusters = clusterAndClassifySongs(
      allRawSongs,
      query: clean,
      isExplicitMixRequest: intent.isExplicitMixRequest,
    );

    final topResult = evaluateTopResult(
      clusters,
      query: clean,
      isExplicitMixRequest: intent.isExplicitMixRequest,
    );

    final albums = parseAlbumSummaries(rawResults.albums);
    final playlists = parsePlaylistSummaries(rawResults.playlists);

    final payload = ClassifiedSearchPayload(
      query: clean,
      clusteredSongs: clusters,
      albums: albums,
      playlists: playlists,
      artists: rawResults.artists,
      topResult: topResult,
      didYouMean: rawResults.didYouMean,
    );

    if (!payload.isEmpty) {
      _classifiedLruCache.put(cacheKey, payload);
    }

    return payload;
  }
}