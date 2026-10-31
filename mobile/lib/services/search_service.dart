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
import 'audius_client.dart';
import 'settings_manager.dart';
import 'history_manager.dart';
import 'favorites_manager.dart';
import 'fuzzy_search_service.dart';
import 'error_handler.dart';
import 'app_logger.dart';
import 'artist_sanitizer.dart';
import 'api_client.dart';
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

    final Set<String> suggestions = {};

    // 1. Instant O(K) local Prefix Trie matches (0ms local latency)
    if (localTrie != null) {
      final localMatches = localTrie.findByPrefix(clean, limit: 6);
      for (final m in localMatches) {
        suggestions.add(m.term);
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
        suggestions.add(s);
      }
      for (final s in ytSuggestions) {
        if (suggestions.length >= limit) break;
        suggestions.add(s);
      }
    } catch (e) {
      debugPrint('[SearchService] getTypeaheadSuggestions notice: $e');
    }

    return suggestions.take(limit).toList();
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

  /// Synthesizes dynamic 'Movie - All Songs' auto-playlists directly from album metadata
  static List<Map<String, dynamic>> generateAutoPlaylistsFromAlbums(
    List<Map<String, dynamic>> albums, {
    int maxCount = 2,
  }) {
    final List<Map<String, dynamic>> autoPlaylists = [];
    for (final album in albums.take(maxCount)) {
      final title = (album['title'] ?? album['name'] ?? '').toString().trim();
      final id = album['id']?.toString() ?? '';
      final img = album['image']?.toString() ?? '';
      final artist = album['artist']?.toString() ?? '';
      final songCount = album['song_count'] ?? 0;
      if (title.isNotEmpty && id.isNotEmpty) {
        autoPlaylists.add({
          'id': id,
          'title': '$title (All Songs)',
          'subtitle': songCount > 0 ? '$songCount Tracks • Movie Playlist' : 'Movie Playlist • All Songs',
          'image': img,
          'artist': artist,
          'song_count': songCount,
          'source': 'auto_album',
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

    int sIdx = 0;
    int yIdx = 0;
    while (sIdx < saavnPlaylists.length || yIdx < ytPlaylists.length) {
      if (sIdx < saavnPlaylists.length) {
        final p = saavnPlaylists[sIdx++];
        final key = (p['title'] ?? '').toString().toLowerCase();
        if (key.isNotEmpty && seenTitles.add(key)) merged.add(p);
      }
      if (yIdx < ytPlaylists.length) {
        final p = ytPlaylists[yIdx++];
        final key = (p['title'] ?? '').toString().toLowerCase();
        if (key.isNotEmpty && seenTitles.add(key)) merged.add(p);
      }
    }
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
      final res = await Future.wait([albumsFuture, songsFuture]);
      final directAlbums = res[0] as List<Map<String, dynamic>>;
      final songs = res[1] as List<Song>;

      final List<Map<String, dynamic>> correlatedAlbums = [];
      final Set<String> seenAlbumNames = {};

      for (final song in songs) {
        final albName = song.album.trim();
        final albId = song.albumId?.trim() ?? '';
        if (albName.isNotEmpty && albName.toLowerCase() != 'unknown album') {
          final key = albName.toLowerCase();
          if (!seenAlbumNames.contains(key)) {
            seenAlbumNames.add(key);
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
        if (title.isNotEmpty && !seenAlbumNames.contains(title.toLowerCase())) {
          seenAlbumNames.add(title.toLowerCase());
          correlatedAlbums.add(alb);
        }
      }

      return filterGenuineAlbums(correlatedAlbums);
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
      final res = await Future.wait([artistsFuture, songsFuture]);
      final directArtists = res[0] as List<Map<String, dynamic>>;
      final songs = res[1] as List<Song>;

      final List<Map<String, dynamic>> correlatedArtists = [];
      final Set<String> seenArtistNames = {};

      for (final song in songs) {
        final artName = song.primaryArtist.trim();
        final artId = song.artistId?.trim() ?? '';
        if (artName.isNotEmpty && artName.toLowerCase() != 'various artists') {
          final key = artName.toLowerCase();
          if (!seenArtistNames.contains(key)) {
            seenArtistNames.add(key);
            correlatedArtists.add({
              'id': artId.isNotEmpty ? artId : 'art_${song.id}',
              'name': artName,
              'title': artName,
              'image': song.coverUrl,
              'role': 'Singer / Music Director',
            });
          }
        }
      }

      for (final art in directArtists) {
        final name = (art['name'] ?? art['title'] ?? '').toString().trim();
        if (name.isNotEmpty && !seenArtistNames.contains(name.toLowerCase())) {
          seenArtistNames.add(name.toLowerCase());
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

  /// Tab search: Audius tracks
  static Future<List<Song>> searchAudiusTab(String query, {int limit = 25}) async {
    try {
      return await AudiusClient.search(query, limit: limit)
          .timeout(const Duration(seconds: 5), onTimeout: () => <Song>[]);
    } catch (_) {
      return <Song>[];
    }
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

    // Levenshtein typo-tolerance using BkTree
    final int distClean = BkTree.levenshteinDistance(qLower, cleanTitle);
    final int maxLenClean = math.max(qLower.length, cleanTitle.length);
    final double levClean = maxLenClean == 0 ? 1.0 : (1.0 - (distClean / maxLenClean)).clamp(0.0, 1.0);

    final int distNorm = BkTree.levenshteinDistance(qLower, titleNorm);
    final int maxLenNorm = math.max(qLower.length, titleNorm.length);
    final double levNorm = maxLenNorm == 0 ? 1.0 : (1.0 - (distNorm / maxLenNorm)).clamp(0.0, 1.0);

    final int distTrans = BkTree.levenshteinDistance(transLower, titleNorm);
    final int maxLenTrans = math.max(transLower.length, titleNorm.length);
    final double levTrans = maxLenTrans == 0 ? 1.0 : (1.0 - (distTrans / maxLenTrans)).clamp(0.0, 1.0);

    double similarity = math.max(levClean, math.max(levNorm, levTrans));

    // Word token containment (e.g. query "hukum" inside "Hukum - Thalaivar Alappara")
    if (cleanTitle.contains(qLower) || titleNorm.contains(qLower) || titleNorm.contains(transLower)) {
      final tokenBoost = 0.80 + (0.15 * (qLower.length / math.max(1, titleNorm.length)));
      similarity = math.max(similarity, tokenBoost);
    }

    // Artist token match bonus (e.g. searching "anirudh" finds his songs)
    final artistLower = song.primaryArtist.toLowerCase();
    if (artistLower.isNotEmpty && (artistLower.contains(qLower) || qLower.contains(artistLower))) {
      similarity = math.max(similarity, 0.85);
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
    if (candArtist.isEmpty) return 0.0;

    // 1. Liked in favorites -> highest affinity 1.0
    for (final fav in favs) {
      if (fav.primaryArtist.toLowerCase() == candArtist ||
          SongRepository.normalizeArtist(fav.artist).toLowerCase() == candArtist) {
        return 1.0;
      }
    }

    // 2. Played in history
    int playCount = 0;
    for (final h in hist) {
      if (h.primaryArtist.toLowerCase() == candArtist ||
          SongRepository.normalizeArtist(h.artist).toLowerCase() == candArtist) {
        playCount++;
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

    final stringSim = calculateStringSimilarity(song, intent);
    final popularity = calculateSourcePopularity(song);
    final affinity = calculateUserAffinity(song, history: history, favorites: favorites);

    // Multi-factor formula
    double score = (0.45 * stringSim) + (0.35 * popularity) + (0.20 * affinity);

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
  static List<Song> deduplicateAndRankUnified({
    required List<Song> saavnSongs,
    required List<Song> ytSongs,
    required List<Song> audiusSongs,
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
        if (fp.isNotEmpty) canonicalMap[fp] = ytSong;
        deduplicatedPool.add(ytSong);
      }
    }

    // 3. Ingest Audius songs
    for (final audiusSong in audiusSongs) {
      final fp = SearchQueryPlanner.generateCanonicalFingerprint(audiusSong.title, audiusSong.artist);
      if (fp.isNotEmpty && !canonicalMap.containsKey(fp)) {
        canonicalMap[fp] = audiusSong;
        deduplicatedPool.add(audiusSong);
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
    scored.sort((a, b) => b.key.compareTo(a.key));

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
    final intent = understandQuery(rawQuery);
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
      bool audiusFailed = false;

      // Preserve explicit language in search query so providers don't default to Bollywood Hindi
      final saavnSearchQuery = (intent.explicitLanguage != null &&
              !intent.cleanQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
          ? '${intent.explicitLanguage!} ${intent.cleanQuery}'
          : intent.cleanQuery;

      final Future<List<Song>> saavnFuture = () async {
        try {
          return await SaavnClient.search(
            saavnSearchQuery,
            limit: limit,
            language: effectiveLang,
          ).timeout(const Duration(seconds: 3), onTimeout: () => <Song>[]);
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
          ).timeout(const Duration(seconds: 3), onTimeout: () => <Song>[]);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn transliterated search fault isolated: $e');
          return <Song>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> albumsFuture = () async {
        try {
          return await SaavnClient.searchAlbums(saavnSearchQuery, limit: 12)
              .timeout(const Duration(seconds: 3), onTimeout: () => <Map<String, dynamic>>[]);
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
                  !intent.cleanQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
              ? (isGeneric ? 'Top ${intent.explicitLanguage!} Artists' : '${intent.explicitLanguage!} ${intent.cleanQuery}')
              : intent.cleanQuery;
          final rawArtists = await SaavnClient.searchArtists(artistSearchQuery, limit: 12, language: effectiveLang)
              .timeout(const Duration(seconds: 3), onTimeout: () => <Map<String, dynamic>>[]);
          return filterArtistsByLanguage(rawArtists, language: effectiveLang, query: intent.cleanQuery);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn artists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> playlistsFuture = () async {
        try {
          return await SaavnClient.searchPlaylists(saavnSearchQuery, limit: 10, language: effectiveLang)
              .timeout(const Duration(seconds: 3), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          debugPrint('[SearchService] Upstream Saavn playlists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final ytSearchQuery = (intent.explicitLanguage != null &&
              !intent.cleanQuery.toLowerCase().contains(intent.explicitLanguage!.toLowerCase()))
          ? '${intent.explicitLanguage!} ${intent.cleanQuery}'
          : intent.cleanQuery;

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

      final Future<List<Song>> audiusFuture = () async {
        try {
          return await AudiusClient.search(intent.cleanQuery, limit: limit)
              .timeout(const Duration(seconds: 3), onTimeout: () => <Song>[]);
        } catch (e) {
          audiusFailed = true;
          AppLogger.log('SearchService', 'Upstream Audius search fault isolated: $e');
          debugPrint('[SearchService] Upstream Audius search fault isolated: $e');
          return <Song>[];
        }
      }();

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

      final autoPlaylists = generateAutoPlaylistsFromAlbums(rawAlbums);
      final initialPlaylists = mergePlaylists(autoPlaylists, rawPlaylists);

      final List<Song> combinedSaavn = [];
      combinedSaavn.addAll(rawSaavn);
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

      scoredSaavn.sort((a, b) => b.key.compareTo(a.key));
      final rankedSaavn = scoredSaavn.map((e) => e.value).toList();
      final labeledAlbums = filterGenuineAlbums(rawAlbums);

      Map<String, dynamic>? initialTopResult;
      String? didYouMean;

      if (scoredSaavn.isNotEmpty && scoredSaavn.first.key >= 0.70) {
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
      } else {
        final correction = FuzzySearchService.findCorrection(intent.cleanQuery);
        if (correction != null && correction.corrected.toLowerCase() != intent.cleanQuery.toLowerCase()) {
          didYouMean = correction.corrected;
        } else if (intent.transliteratedQuery != intent.cleanQuery) {
          didYouMean = intent.transliteratedQuery;
        }
      }

      if (rankedSaavn.isNotEmpty || labeledAlbums.isNotEmpty || artists.isNotEmpty || initialPlaylists.isNotEmpty) {
        yield SearchResults(
          songs: rankedSaavn,
          ytSongs: const [],
          saavnSongs: rankedSaavn,
          audiusSongs: const [],
          albums: labeledAlbums,
          artists: artists,
          playlists: initialPlaylists,
          topResult: initialTopResult,
          didYouMean: didYouMean,
          error: null,
        );
      }

      // ── PHASE 2: Merge YouTube & Audius Results ──
      final remainingResults = await Future.wait([
        ytFuture,
        audiusFuture,
        ytPlaylistsFuture,
      ]);

      final rawYt = remainingResults[0] as List<Song>;
      final rawAudius = remainingResults[1] as List<Song>;
      final rawYtPlaylists = remainingResults[2] as List<Map<String, dynamic>>;

      final finalPlaylists = mergePlaylists(initialPlaylists, rawYtPlaylists);

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
      scoredYt.sort((a, b) => b.key.compareTo(a.key));
      final rankedYt = scoredYt.map((e) => e.value).toList();

      final List<Song> mergedSongs = deduplicateAndRankUnified(
        saavnSongs: rankedSaavn,
        ytSongs: candidateYt,
        audiusSongs: rawAudius,
        intent: intent,
        preferredLanguages: prefLangs,
      );

      Map<String, dynamic>? finalTopResult = initialTopResult;
      if (mergedSongs.isNotEmpty) {
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

      FuzzySearchService.registerSongs(mergedSongs);

      AppError? searchError;
      if (mergedSongs.isEmpty && ytSongs.isEmpty && rawAudius.isEmpty && labeledAlbums.isEmpty && artists.isEmpty && finalPlaylists.isEmpty && (saavnFailed && ytFailed && audiusFailed)) {
        searchError = AppError.offline(debugDetails: 'All upstream providers failed for "${intent.cleanQuery}"');
      }

      final finalBundle = SearchResults(
        songs: mergedSongs,
        ytSongs: rankedYt.isNotEmpty ? rankedYt : ytSongs,
        saavnSongs: rankedSaavn,
        audiusSongs: rawAudius,
        albums: labeledAlbums,
        artists: artists,
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
}
