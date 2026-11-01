import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../domain/models/app_error.dart';
import '../domain/models/track_entity.dart';
import '../core/dsa/bk_tree.dart';
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

    variants.remove(clean);
    return variants.toList();
  }

  /// Stage 1: Instant Debounced Typeahead (< 150ms).
  /// Queries local PrefixTrie in < 1ms, then merges lightweight autocomplete suggestions
  /// directly from YouTube (suggestqueries.google.com) and JioSaavn in parallel.
  /// Strictly avoids heavy entity or stream resolution while typing.
  static Future<List<String>> getTypeaheadSuggestions(
    String query, {
    PrefixTrie<String>? localTrie,
    int limit = 10,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    final List<String> suggestions = [];
    final Set<String> seenLower = {};

    void addSuggestion(String s) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) return;
      final lower = trimmed.toLowerCase();
      if (!seenLower.contains(lower)) {
        seenLower.add(lower);
        suggestions.add(trimmed);
      }
    }

    // 1. Instant O(K) local Prefix Trie matches (0ms local latency)
    if (localTrie != null) {
      final localMatches = localTrie.findByPrefix(clean, limit: 6);
      for (final m in localMatches) {
        if (suggestions.length >= limit) break;
        addSuggestion(m.term);
      }
    }

    // 2. Parallel lightweight suggestions from YouTube and JioSaavn (<150ms non-blocking)
    try {
      final remoteFutures = await Future.wait([
        YouTubeClient.getSearchSuggestions(clean)
            .timeout(const Duration(milliseconds: 750), onTimeout: () => <String>[]),
        SaavnClient.getSearchSuggestions(clean)
            .timeout(const Duration(milliseconds: 750), onTimeout: () => <String>[]),
      ]);

      final ytSuggestions = remoteFutures[0];
      final saavnSuggestions = remoteFutures[1];

      for (final s in saavnSuggestions) {
        if (suggestions.length >= limit) break;
        addSuggestion(s);
      }
      for (final s in ytSuggestions) {
        if (suggestions.length >= limit) break;
        addSuggestion(s);
      }
    } catch (e) {
      debugPrint('[SearchService] getTypeaheadSuggestions notice: $e');
    }

    return suggestions.take(limit).toList();
  }

  /// Strictly filters out single-song releases, fake albums, and unrelated compilations
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

      if (songCount <= 1 || title.contains('single') || title.contains('teaser')) {
        continue;
      }

      // Filter out completely unrelated albums for specific queries
      if (cleanQuery.length >= 2 && queryTokens.isNotEmpty) {
        final titleTokens = title.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
        final artistTokens = artist.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
        final isRelevant = title.contains(cleanQuery) ||
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

    // Sort: Multi-track soundtrack albums first, then title relevance
    valid.sort((a, b) {
      final scA = int.tryParse(a['song_count']?.toString() ?? '0') ?? 0;
      final scB = int.tryParse(b['song_count']?.toString() ?? '0') ?? 0;
      if ((scA > 1) != (scB > 1)) {
        return (scB > 1) ? 1 : -1;
      }
      return 0;
    });

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
    final prefLang = (language ?? 'tamil').toLowerCase().trim();
    final foreignLangRegex = RegExp(r'\b(kannada|marathi|bhojpuri|punjabi|haryanvi|bengali|gujarati)\b', caseSensitive: false);

    final filtered = <Map<String, dynamic>>[];
    for (final p in rawPlaylists) {
      final title = (p['title'] ?? p['name'] ?? '').toString().toLowerCase().trim();
      if (title.isEmpty) continue;

      // 1. Language mismatch check
      if (prefLang == 'tamil' || (!cleanQuery.contains('kannada') && !cleanQuery.contains('marathi'))) {
        if (foreignLangRegex.hasMatch(title) && !title.contains(prefLang) && !cleanQuery.contains(title)) {
          continue;
        }
      }

      // 2. Query relevance check
      if (queryTokens.length >= 2) {
        final titleTokens = title.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
        final matchesAll = queryTokens.every((token) => title.contains(token));
        final matchesPhrase = title.contains(cleanQuery) || cleanQuery.contains(title);
        final tokenIntersection = titleTokens.intersection(queryTokens).length;
        if (!matchesPhrase && !matchesAll && tokenIntersection < queryTokens.length) {
          continue;
        }
      } else if (queryTokens.isNotEmpty) {
        final token = queryTokens.first;
        if (!title.contains(token)) {
          continue;
        }
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
    final saavnQuery = (intent.explicitLanguage != null &&
            !intent.cleanQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
        ? '${intent.explicitLanguage!} ${intent.cleanQuery}'
        : intent.cleanQuery;

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

    if ((ytVideoId != null && (clean.contains('youtu') || clean.contains('http'))) ||
        (ytPlaylistId != null && (clean.contains('list=') || clean.startsWith('PL')))) {
      if (ytPlaylistId != null && (clean.contains('list=') || clean.startsWith('PL'))) {
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

  /// Tab search: Songs only
  static Future<List<Song>> searchSongsTab(String query, {String? language, int limit = 25}) async {
    try {
      final songs = await SaavnClient.search(query, limit: limit, language: language)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
      final grouped = SongRepository.groupCanonicalSongs(songs, preferredLanguage: language);
      return SongRepository.deduplicateSongs(grouped);
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {}
  }

  /// Strictly filters search artists by language, purging Bollywood/Hindi leaks,
  /// English pop stars (e.g. Justin Bieber) from regional queries, and placeholder images.
  static List<Map<String, dynamic>> filterArtistsByLanguage(
    List<Map<String, dynamic>> artists, {
    String? language,
    required String query,
  }) {
    final filtered = <Map<String, dynamic>>[];
    for (final item in artists) {
      final name = (item['name'] ?? item['title'] ?? '').toString().trim();
      final norm = SongRepository.normalizeArtist(name);
      if (norm.isEmpty) continue;

      // Filter out accidental spam or false substring hits (e.g. Tamilia, Tamil Nambi)
      if (!ArtistSanitizer.isGenuineArtist(name)) continue;

      // Filter out generic placeholder images with camera or mic icons unless officially verified
      final img = item['image']?.toString();
      if (ArtistSanitizer.isPlaceholderImage(img) && !SongRepository.isArtistVerified(name)) {
        continue;
      }

      // If genuine artist matches criteria, keep it
      filtered.add(item);
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

    // Universal multi-language phonetic fallback
    String? universalPhonetic;
    final phoneticVariants = generateUniversalPhoneticVariants(cleanLower);
    if (phoneticVariants.isNotEmpty) {
      universalPhonetic = phoneticVariants.firstWhere(
        (v) => FuzzySearchService.candidateDictionary.any((c) => c.toLowerCase() == v),
        orElse: () => '',
      );
      if (universalPhonetic.isEmpty) {
        universalPhonetic = null;
      }
    }

    if (transliterated.toLowerCase() == cleanLower && universalPhonetic != null) {
      transliterated = universalPhonetic;
    }

    if (didYouMean == null && cleanLower != transliterated.toLowerCase()) {
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
    }

    bool matchesToken(String text, String token) {
      if (token.isEmpty || text.isEmpty) return false;
      if (token.length <= 3) {
        return RegExp(r'\b' + RegExp.escape(token) + r'\b', caseSensitive: false).hasMatch(text);
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

    // 1. Studio release / verified source (Saavn or YouTube Official Topic/VEVO)
    if (song.source == 'saavn') {
      score += 0.40;
    } else if (song.artist.toLowerCase().contains('topic') ||
               song.artist.toLowerCase().contains('vevo') ||
               song.hasOfficialAlbumArt) {
      score += 0.35;
    } else {
      score += 0.15;
    }

    // 2. Official Square Studio Album Art (1000x1000 / 500x500 CDN vs thumbnail)
    if (song.hasOfficialAlbumArt) {
      score += 0.30;
    } else if (song.coverUrl.isNotEmpty && !song.coverUrl.contains('default.jpg')) {
      score += 0.15;
    }

    // 3. Duration Sanity (standard studio song 90s - 360s)
    if (song.duration >= 90 && song.duration <= 360) {
      score += 0.20;
    } else if (song.duration >= 45 && song.duration <= 600) {
      score += 0.10;
    }

    // 4. Clean studio title (not a remix/lofi/bootleg unless requested)
    if (song.versionTag == 'Original') {
      score += 0.10;
    } else {
      score += 0.05;
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

    if (playCount >= 3) return 1.0;
    if (playCount >= 1) return 0.70;

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
  }) {
    // If query has explicit language override, strictly reject any cross-language mismatch
    if (intent.explicitLanguage != null &&
        SongRepository.isLanguageMismatch(song, intent.explicitLanguage!)) {
      return 0.0;
    }

    // Purge non-Indian foreign language songs (Arabic, Spanish, French, etc.)
    // unless the user explicitly searched for that language or query (e.g. "Arabic Kuthu")
    final qLower = intent.cleanQuery.toLowerCase();
    final songLang = song.language?.toLowerCase().trim() ?? '';
    const nonRegionalLanguages = {
      'arabic', 'spanish', 'french', 'turkish', 'russian', 'korean', 'chinese', 'german', 'italian', 'persian', 'japanese'
    };
    if (songLang.isNotEmpty && nonRegionalLanguages.contains(songLang)) {
      final isExplicitForeign = intent.explicitLanguage != null && nonRegionalLanguages.contains(intent.explicitLanguage!.toLowerCase());
      final isForeignInQuery = nonRegionalLanguages.any((l) => qLower.contains(l));
      if (!isExplicitForeign && !isForeignInQuery) {
        return 0.0;
      }
    }

    final stringSim = calculateStringSimilarity(song, intent);
    final popularity = calculateSourcePopularity(song);
    final affinity = calculateUserAffinity(song, history: history, favorites: favorites);

    // Multi-factor formula
    double score = (0.45 * stringSim) + (0.35 * popularity) + (0.20 * affinity);

    // Album unpack promotion: if song belongs to an album matching query, promote it directly to Songs top rank
    final albLower = song.album.toLowerCase();
    if (qLower.isNotEmpty && albLower.isNotEmpty) {
      if (albLower == qLower || (albLower.contains(' - ') && albLower.split(' - ').first.trim() == qLower)) {
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
      final pLang = preferredLanguages.first.toLowerCase().trim();
      final songLang = song.language?.toLowerCase().trim() ?? '';
      if (pLang.isNotEmpty && (songLang == pLang || song.title.toLowerCase().contains(pLang))) {
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
    String queryLower,
  ) {
    final scoreCmp = b.key.compareTo(a.key);
    if (scoreCmp != 0) return scoreCmp;

    final songA = a.value;
    final songB = b.value;

    // 1. Movie Soundtrack Match Precedence: Child tracks of matched film entity outrank standalone singles
    final albA = songA.album.toLowerCase().trim();
    final albB = songB.album.toLowerCase().trim();
    final aAlbumMatch = (albA == queryLower ||
        (albA.contains(' - ') && albA.split(' - ').first.trim() == queryLower) ||
        albA.startsWith('$queryLower (') ||
        albA.startsWith('$queryLower -')) ? 1 : 0;
    final bAlbumMatch = (albB == queryLower ||
        (albB.contains(' - ') && albB.split(' - ').first.trim() == queryLower) ||
        albB.startsWith('$queryLower (') ||
        albB.startsWith('$queryLower -')) ? 1 : 0;
    if (aAlbumMatch != bAlbumMatch) return bAlbumMatch.compareTo(aAlbumMatch);

    final aExact = (songA.title.toLowerCase().trim() == queryLower) ? 1 : 0;
    final bExact = (songB.title.toLowerCase().trim() == queryLower) ? 1 : 0;
    if (aExact != bExact) return bExact.compareTo(aExact);

    final aStudio = (songA.source.toLowerCase() == 'saavn') ? 1 : 0;
    final bStudio = (songB.source.toLowerCase() == 'saavn') ? 1 : 0;
    if (aStudio != bStudio) return bStudio.compareTo(aStudio);

    final aArt = songA.hasOfficialAlbumArt ? 1 : 0;
    final bArt = songB.hasOfficialAlbumArt ? 1 : 0;
    if (aArt != bArt) return bArt.compareTo(aArt);

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

    // 4. Score every song in the unified deduplicated pool
    final scored = deduplicatedPool.map((song) {
      final score = calculateCompositeRelevance(
        song,
        intent,
        history: history,
        favorites: favorites,
        preferredLanguages: preferredLanguages,
      );
      return MapEntry(score, song);
    }).where((e) => e.key > 0.0).toList();

    // 5. Sort descending by Multi-Factor Relevance Score
    scored.sort((a, b) => compareRankedEntries(a, b, intent.cleanQuery.toLowerCase()));

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
    int limit = 25,
  }) async* {
    final normalizedRaw = rawQuery.trim().toLowerCase();
    final intent = understandQuery(normalizedRaw);
    if (intent.cleanQuery.isEmpty) {
      yield SearchResults();
      return;
    }

    final prefLangs = SettingsManager.preferredLanguages;
    final effectiveLang = intent.explicitLanguage ??
        (language != null && language.isNotEmpty && language.toLowerCase() != 'all' && language.toLowerCase() != 'any' ? language : null);

    // Check fast LRU in-memory cache first (0ms)
    final cached = SearchCache.get(rawQuery, language: effectiveLang ?? 'all');
    if (cached != null) {
      yield cached;
      return;
    }

    try {
      bool saavnFailed = false;
      bool ytFailed = false;

      // Preserve explicit language in search query so providers don't default to Bollywood Hindi
      final saavnSearchQuery = (intent.explicitLanguage != null &&
              !intent.cleanQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
          ? '${intent.explicitLanguage!.toLowerCase()} ${intent.cleanQuery.toLowerCase()}'
          : intent.cleanQuery.toLowerCase();

      final Future<List<Song>> saavnFuture = () async {
        try {
          var results = await SaavnClient.search(
            saavnSearchQuery,
            limit: limit,
            language: effectiveLang,
          ).timeout(const Duration(seconds: 5), onTimeout: () => <Song>[]);
          if (results.isEmpty && intent.effectiveCoreQuery != intent.cleanQuery) {
            final coreSearch = (intent.explicitLanguage != null &&
                    !intent.effectiveCoreQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
                ? '${intent.explicitLanguage!} ${intent.effectiveCoreQuery}'
                : intent.effectiveCoreQuery;
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
          final transQuery = (intent.explicitLanguage != null &&
                  !intent.transliteratedQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
              ? '${intent.explicitLanguage!} ${intent.transliteratedQuery}'
              : intent.transliteratedQuery;
          return await SaavnClient.search(
            transQuery,
            limit: limit,
            language: effectiveLang,
          ).timeout(const Duration(seconds: 5), onTimeout: () => <Song>[]);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn transliterated search fault isolated: $e');
          return <Song>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> albumsFuture = () async {
        try {
          var alb = await SaavnClient.searchAlbums(saavnSearchQuery, limit: 16)
              .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
          if (alb.isEmpty && intent.effectiveCoreQuery != intent.cleanQuery) {
            alb = await SaavnClient.searchAlbums(intent.effectiveCoreQuery, limit: 16)
                .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
          }
          if (alb.isEmpty || !alb.any((a) => (int.tryParse(a['song_count']?.toString() ?? '0') ?? 0) > 1)) {
            final cleanAlbs = await SaavnClient.searchAlbums(intent.cleanQuery, limit: 16)
                .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
            for (final a in cleanAlbs) {
              final aId = (a['id'] ?? a['name'] ?? a['title'] ?? '').toString();
              if (aId.isNotEmpty && !alb.any((x) => (x['id'] ?? x['name'] ?? x['title'] ?? '').toString() == aId)) {
                alb.add(a);
              }
            }
          }
          if (intent.transliteratedQuery != intent.cleanQuery) {
            final transAlb = await SaavnClient.searchAlbums(intent.transliteratedQuery, limit: 12)
                .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
            for (final a in transAlb) {
              final aId = (a['id'] ?? a['name'] ?? a['title'] ?? '').toString();
              if (aId.isNotEmpty && !alb.any((x) => (x['id'] ?? x['name'] ?? x['title'] ?? '').toString() == aId)) {
                alb.insert(0, a);
              }
            }
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
          final artistSearchQuery = (intent.explicitLanguage != null &&
                  !intent.effectiveCoreQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
              ? (isGeneric ? 'Top ${intent.explicitLanguage!} Artists' : '${intent.explicitLanguage!} ${intent.effectiveCoreQuery}')
              : intent.effectiveCoreQuery;
          final rawArtists = await SaavnClient.searchArtists(artistSearchQuery, limit: 12, language: effectiveLang)
              .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
          return filterArtistsByLanguage(rawArtists, language: effectiveLang, query: intent.effectiveCoreQuery);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn artists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> playlistsFuture = () async {
        try {
          return await SaavnClient.searchPlaylists(saavnSearchQuery, limit: 10, language: effectiveLang)
              .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn playlists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final ytSearchQuery = (intent.explicitLanguage != null &&
              !intent.cleanQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
          ? '${intent.explicitLanguage!.toLowerCase()} ${intent.cleanQuery.toLowerCase()}'
          : intent.cleanQuery.toLowerCase();

      final Future<List<Song>> ytFuture = () async {
        try {
          return await YouTubeClient.search(ytSearchQuery, limit: limit)
              .timeout(const Duration(seconds: 6), onTimeout: () => <Song>[]);
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
              .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          debugPrint('[SearchService] Upstream YouTube playlists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      // ── PHASE 0: Instant Local Master Catalog Yield (0-15ms) ──
      List<Song> catalogSongs = [];
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
      } catch (_) {}

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

      // ── PHASE 1: Progressive Early Yield (~300ms) ──
      // JioSaavn results return ultra-fast. Yield them immediately without waiting for YouTube.
      final saavnResults = await Future.wait([
        saavnFuture,
        transliteratedSaavnFuture,
        albumsFuture,
        artistsFuture,
        playlistsFuture,
      ]);

      final rawSaavn = saavnResults[0] as List<Song>;
      final transSaavn = saavnResults[1] as List<Song>;
      final rawAlbums = saavnResults[2] as List<Map<String, dynamic>>;
      final artists = saavnResults[3] as List<Map<String, dynamic>>;
      final rawPlaylists = saavnResults[4] as List<Map<String, dynamic>>;

      final qClean = intent.cleanQuery.toLowerCase().trim();
      final qCore = intent.effectiveCoreQuery.toLowerCase().trim();

      // If the query matches an album/movie (e.g. "Hi", "Hi Nanna", "Leo"),
      // fetch all soundtrack tracks of that album so they are directly presented in song search.
      final List<Map<String, dynamic>> matchingAlbums = [];
      for (final a in rawAlbums) {
        final t = (a['title'] ?? a['name'] ?? '').toString().toLowerCase().trim();
        final baseT = t.contains(' - ') ? t.split(' - ').first.trim() : t;
        if (t == qClean || t == qCore || baseT == qClean || (qClean.length >= 3 && t.startsWith(qClean))) {
          matchingAlbums.add(a);
        }
      }
      for (final cm in catMovies) {
        final t = (cm['title'] ?? '').toString().toLowerCase().trim();
        final baseT = t.contains(' - ') ? t.split(' - ').first.trim() : t;
        if ((t == qClean || t == qCore || baseT == qClean) && !matchingAlbums.any((x) => (x['title'] ?? '').toString().toLowerCase().trim() == t)) {
          matchingAlbums.add(cm);
        }
      }

      List<Song> albumSoundtrackSongs = [];
      for (final alb in matchingAlbums.take(2)) {
        final albId = alb['id']?.toString() ?? '';
        final albTitle = (alb['title'] ?? alb['name'] ?? '').toString();
        if (albId.isNotEmpty || albTitle.isNotEmpty) {
          try {
            final details = await SongRepository.getAlbumDetails(albumId: albId, albumTitle: albTitle);
            final albSongs = details?['songs'] as List<Song>? ?? [];
            for (final asong in albSongs) {
              if (!albumSoundtrackSongs.any((x) => x.id == asong.id)) {
                albumSoundtrackSongs.add(asong);
              }
            }
          } catch (_) {}
        }
      }

      final List<Song> combinedSaavn = [];
      for (final s in albumSoundtrackSongs) {
        combinedSaavn.add(s);
      }
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

      final candidateSaavn = intent.explicitLanguage != null
          ? SongRepository.filterByLanguage(canonicalSaavn, intent.explicitLanguage!)
          : canonicalSaavn;

      final scoredSaavn = candidateSaavn.map((s) {
        final score = scoreSong(s, intent, preferredLanguages: prefLangs);
        return MapEntry(score, s);
      }).where((e) => e.key > 0.0).toList();

      scoredSaavn.sort((a, b) => compareRankedEntries(a, b, qClean));
      final rankedSaavn = scoredSaavn.map((e) => e.value).toList();

      // If the search query targets an artist (e.g. "Anirudh Ravichander", "A.R. Rahman"),
      // fetch their full official discography of albums with verified artwork.
      Map<String, dynamic>? matchingArtist;
      for (final a in artists) {
        final aName = (a['name'] ?? '').toString().toLowerCase().trim();
        final canon = ArtistSanitizer.canonicalArtistName(aName).toLowerCase();
        if (aName == qClean || canon == qClean || aName.contains(qCore) || qClean.contains(canon)) {
          matchingArtist = a;
          break;
        }
      }

      List<Map<String, dynamic>> artistOfficialAlbums = [];
      if (matchingArtist != null) {
        final artId = matchingArtist['id']?.toString() ?? '';
        if (artId.isNotEmpty) {
          try {
            artistOfficialAlbums = await SaavnClient.getArtistAlbums(artId, limit: 40);
          } catch (_) {}
        }
      }

      // Populate Albums Tab: Merge genuine albums with artist discography and Master Catalog movies
      final List<Map<String, dynamic>> initialAlbums = [];
      final Set<String> seenAlbumNames = {};

      for (final alb in artistOfficialAlbums) {
        final t = (alb['title'] ?? alb['name'] ?? '').toString().toLowerCase().trim();
        if (t.isNotEmpty && seenAlbumNames.add(t)) {
          initialAlbums.add(alb);
        }
      }

      for (final alb in filterGenuineAlbums(rawAlbums, query: intent.cleanQuery)) {
        final t = (alb['title'] ?? alb['name'] ?? '').toString().toLowerCase().trim();
        if (t.isNotEmpty && seenAlbumNames.add(t)) {
          initialAlbums.add(alb);
        }
      }

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

      // Auto-playlists: Synthesize 'Movie Soundtrack' playlists directly from albums & catalog movies
      final autoPlaylists = generateAutoPlaylistsFromAlbums(initialAlbums);
      final filteredRawPlaylists = filterPlaylistsByRelevanceAndLanguage(
        rawPlaylists,
        query: intent.cleanQuery,
        language: effectiveLang,
      );
      final initialPlaylists = mergePlaylists(autoPlaylists, filteredRawPlaylists);

      // Populate Artists Tab: Merge direct artists with Master Catalog artists and song composers/singers
      final List<Map<String, dynamic>> initialArtists = [];
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
          if (!isVerified) return;

          initialArtists.add({
            ...artMap,
            'name': canon,
            'image': verifiedImg,
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

      if (exactMovieMatch != null || initialAlbums.any((a) => (a['title'] ?? '').toString().toLowerCase().trim() == intent.cleanQuery.toLowerCase().trim())) {
        didYouMean = null;
      } else if (intent.transliteratedQuery.toLowerCase() != intent.cleanQuery.toLowerCase()) {
        didYouMean = intent.transliteratedQuery;
      } else {
        final correction = FuzzySearchService.findCorrection(intent.cleanQuery);
        if (correction != null && correction.corrected.toLowerCase() != intent.cleanQuery.toLowerCase()) {
          didYouMean = correction.corrected;
        }
      }

      if (rankedSaavn.isNotEmpty || initialAlbums.isNotEmpty || initialArtists.isNotEmpty || initialPlaylists.isNotEmpty) {
        yield SearchResults(
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
      }

      // ── PHASE 2: Merge YouTube Results ──
      final remainingResults = await Future.wait([
        ytFuture,
        ytPlaylistsFuture,
      ]);

      final rawYt = remainingResults[0] as List<Song>;
      final rawYtPlaylists = remainingResults[1] as List<Map<String, dynamic>>;

      final filteredYtPlaylists = filterPlaylistsByRelevanceAndLanguage(
        rawYtPlaylists,
        query: intent.cleanQuery,
        language: effectiveLang,
      );
      final finalPlaylists = mergePlaylists(initialPlaylists, filteredYtPlaylists);

      final groupedYt = SongRepository.groupCanonicalSongs(rawYt, preferredLanguage: effectiveLang);
      final deduplicatedYt = SongRepository.deduplicateSongs(groupedYt);
      final candidateYt = intent.explicitLanguage != null
          ? SongRepository.filterByLanguage(deduplicatedYt, intent.explicitLanguage!)
          : deduplicatedYt;
      final ytSongs = candidateYt;

      final scoredYt = candidateYt.map((s) {
        final score = scoreSong(s, intent, preferredLanguages: prefLangs);
        return MapEntry(score, s);
      }).where((e) => e.key > 0.0).toList();
      scoredYt.sort((a, b) => compareRankedEntries(a, b, qClean));
      final rankedYt = scoredYt.map((e) => e.value).toList();

      final List<Song> mergedSongs = deduplicateAndRankUnified(
        saavnSongs: rankedSaavn,
        ytSongs: candidateYt,
        audiusSongs: const [],
        intent: intent,
        preferredLanguages: prefLangs,
      );

      Map<String, dynamic>? finalTopResult = initialTopResult;
      if (exactMovieMatch != null) {
        finalTopResult = initialTopResult;
      } else if (mergedSongs.isNotEmpty) {
        final top = mergedSongs.first;
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

      // Asynchronous Write-Through Ingestion: store newly discovered songs in local CatalogDatabase
      for (final s in mergedSongs.take(5)) {
        CatalogDatabase.insertDynamicSong(s);
      }

      // Dynamic On-Device Personal Preference Matrix re-ranking
      final userRankedSongs = UserPreferenceMatrix.reRankWithPreferences(
        mergedSongs,
        intent.cleanQuery,
      );

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
            if (!isVerified) continue;

            finalArtists.add({
              ...sa,
              'name': canon,
              'image': verifiedImg,
            });
          }
        }
      }

      FuzzySearchService.registerSongs(userRankedSongs);

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
      );

      SearchCache.put(rawQuery, finalBundle, language: effectiveLang);
      yield finalBundle;
    } catch (e, stack) {
      debugPrint('[SearchService] Search error: $e');
      final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'SearchService.searchProgressive');
      yield SearchResults(error: appErr);
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

      final hydratedPrimary = primary.copyWith(
        versions: alternates,
      );

      clusters.add(ClusteredTrackResult(
        primaryTrack: hydratedPrimary,
        category: primaryClass,
        confidenceScore: confidence,
        alternateVersions: alternates,
      ));
    }

    clusters.sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));
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