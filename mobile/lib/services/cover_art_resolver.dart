import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import '../models/song.dart';
import 'app_logger.dart';
import 'catalog_database.dart';
import 'saavn_client.dart';
import '../logic/search_query_planner.dart';

/// Service responsible for resolving studio-quality 1000x1000 square album artwork
/// for all audio tracks across Paatu Padava.
///
/// Priority Resolution Order:
/// 1. JioSaavn high-res (500x500 square) if already present.
/// 2. YouTube Music high-res square art (=w1000-h1000) for official audio/topics.
/// 3. iTunes Search API lookup (upgraded to 1000x1000bb) with title/artist/duration safeguards.
/// 4. Deezer Search API lookup (cover_xl) fallback with title/artist/duration safeguards.
/// 5. YouTube video thumbnail fallback (maxresdefault/hqdefault) for display with blurred background.
/// 6. Neutral gradient fallback (empty string) - eliminates stock photos and artist avatars.
///
/// Note on Attribution & Terms:
/// Metadata and artwork fetched via iTunes Search API and Deezer Public API are subject
/// to Apple and Deezer developer terms of service. Proper attribution should be maintained
/// if published in public application distributions.
class CoverArtResolver {
  static const String boxName = 'cover_art_cache';
  static Box? _cacheBox;
  static http.Client? _httpClient;

  /// In-memory LRU cache for ultra-fast synchronous lookup during UI rebuilds
  static final Map<String, String> _memoryCache = {};

  /// In-flight deduplication to prevent duplicate concurrent network queries for the same song
  static final Map<String, Future<String>> _inFlightRequests = {};

  /// Duration tolerance in seconds for audio verification
  static const int durationToleranceSec = 4;

  /// Default timeout for external artwork resolution calls
  static const Duration requestTimeout = Duration(milliseconds: 3500);

  /// Initializes the Hive cache box for cover art persistence
  static Future<void> init({Box? box}) async {
    if (box != null) {
      _cacheBox = box;
      return;
    }
    try {
      if (!Hive.isBoxOpen(boxName)) {
        _cacheBox = await Hive.openBox(boxName);
      } else {
        _cacheBox = Hive.box(boxName);
      }
      AppLogger.log('CoverArtResolver', 'Cover art cache box opened (${_cacheBox?.length ?? 0} entries)');
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'CoverArtResolver.init');
    }
  }

  /// Sets custom client for unit testing
  static void setTestingOverrides({Box? box, http.Client? client}) {
    _cacheBox = box;
    _httpClient = client;
    _memoryCache.clear();
    _inFlightRequests.clear();
  }

  /// Clears in-memory and in-flight caches
  static void clearMemoryCache() {
    _memoryCache.clear();
    _inFlightRequests.clear();
  }

  /// Synchronously checks if a resolved cover URL is already cached in memory or Hive
  static String? getCachedCover(String songId) {
    if (songId.isEmpty) return null;
    final mem = _memoryCache[songId];
    if (mem != null && mem.isNotEmpty) return mem;

    try {
      if (_cacheBox != null && _cacheBox!.isOpen) {
        final cached = _cacheBox!.get(songId)?.toString();
        if (cached != null && cached.isNotEmpty) {
          _memoryCache[songId] = cached;
          return cached;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Persists a resolved cover in memory and Hive
  static Future<void> _cacheResult(String songId, String coverUrl) async {
    if (songId.isEmpty || coverUrl.isEmpty) return;
    _memoryCache[songId] = coverUrl;

    try {
      if (_cacheBox != null && _cacheBox!.isOpen) {
        await _cacheBox!.put(songId, coverUrl);
      }
    } catch (e) {
      AppLogger.log('CoverArtResolver', 'Failed to persist cover cache for $songId: $e');
    }
  }

  /// Resolves the highest quality square artwork for the given [song].
  static Future<String> resolveCover(Song song, {bool skipNetwork = false}) async {
    final songId = song.id.trim();
    if (songId.isEmpty) return song.coverUrl;

    // 0. Check memory and persistent Hive cache
    final cached = getCachedCover(songId);
    if (cached != null && cached.isNotEmpty && !_isPlaceholder(cached)) {
      return cached;
    }

    // In-flight request deduplication
    if (_inFlightRequests.containsKey(songId)) {
      return _inFlightRequests[songId]!;
    }

    final future = _resolveInternal(song, skipNetwork: skipNetwork);
    _inFlightRequests[songId] = future;

    try {
      final result = await future;
      if (result.isNotEmpty && !_isPlaceholder(result)) {
        await _cacheResult(songId, result);
      }
      return result;
    } finally {
      _inFlightRequests.remove(songId);
    }
  }

  /// Enriches a [Song] entity with resolved high-resolution artwork
  static Future<Song> resolveSong(Song song, {bool skipNetwork = false}) async {
    final cover = await resolveCover(song, skipNetwork: skipNetwork);
    if (cover.isNotEmpty && cover != song.coverUrl) {
      return song.copyWith(coverUrl: cover);
    }
    return song;
  }

  static Future<String> _resolveInternal(Song song, {required bool skipNetwork}) async {
    final rawCover = song.coverUrl.trim();

    // 1. Keep JioSaavn cover if it exists (upgrade 50x50/150x150 to 500x500 square)
    if (_isSaavnCover(rawCover)) {
      final upgraded = _upgradeSaavnCover(rawCover);
      if (upgraded.isNotEmpty) {
        return upgraded;
      }
    }

    // 2. YouTube Music square art (=w1000-h1000) from InnerTube / Google User Content
    if (_isYouTubeMusicSquareCover(rawCover)) {
      final upgraded = _upgradeYouTubeMusicSquareCover(rawCover);
      if (upgraded.isNotEmpty) {
        return upgraded;
      }
    }

    // 3. Fast offline lookup in CatalogDatabase (0ms) - skipped during mock testing
    if (_httpClient == null) {
      final catalogCover = CatalogDatabase.getSongCoverArt(song.title, artist: song.artist, album: song.album);
      if (catalogCover != null && catalogCover.isNotEmpty) {
        return catalogCover;
      }
    }

    // If skipNetwork is requested (e.g. offline mode), fallback to local/existing thumbnail
    if (skipNetwork) {
      return _getThumbnailOrEmpty(song);
    }

    // 4. JioSaavn Live Search API (500x500 official studio square art) - skipped during mock testing
    if (_httpClient == null) {
      try {
        final saavnCover = await _querySaavn(song);
        if (saavnCover != null && saavnCover.isNotEmpty) {
          return saavnCover;
        }
      } catch (_) {}
    }

    // 5. iTunes Search API (1000x1000 studio square art)
    try {
      final itunesCover = await _queryITunes(song);
      if (itunesCover != null && itunesCover.isNotEmpty) {
        return itunesCover;
      }
    } catch (e) {
      AppLogger.log('CoverArtResolver', 'iTunes lookup failed for "${song.title}": $e');
    }

    // 6. Deezer API (cover_xl studio square art fallback)
    try {
      final deezerCover = await _queryDeezer(song);
      if (deezerCover != null && deezerCover.isNotEmpty) {
        return deezerCover;
      }
    } catch (e) {
      AppLogger.log('CoverArtResolver', 'Deezer lookup failed for "${song.title}": $e');
    }

    // 7. Fallback to YouTube video thumbnail (rendered with blurred background in UI)
    return _getThumbnailOrEmpty(song);
  }

  /// Queries JioSaavn for studio album artwork matching the track
  static Future<String?> _querySaavn(Song song) async {
    try {
      final clean = SearchQueryPlanner.cleanTitle(song.title);
      if (clean.isEmpty) return null;
      final results = await SaavnClient.search(clean, limit: 1).timeout(const Duration(seconds: 3), onTimeout: () => <Song>[]);
      if (results.isNotEmpty && _isSaavnCover(results.first.coverUrl)) {
        return _upgradeSaavnCover(results.first.coverUrl);
      }
    } catch (_) {}
    return null;
  }

  /// Checks if URL is from JioSaavn CDN
  static bool _isSaavnCover(String url) {
    if (url.isEmpty || _isPlaceholder(url)) return false;
    final lower = url.toLowerCase();
    return lower.contains('saavncdn.com') || lower.contains('jiosaavn');
  }

  /// Upgrades JioSaavn thumbnail to 500x500 square
  static String _upgradeSaavnCover(String url) {
    var upgraded = url.replaceAll('50x50', '500x500').replaceAll('150x150', '500x500');
    if (upgraded.startsWith('http://')) {
      upgraded = upgraded.replaceFirst('http://', 'https://');
    }
    return upgraded;
  }

  /// Checks if URL is official YouTube Music album art hosted on GoogleUserContent CDN
  static bool _isYouTubeMusicSquareCover(String url) {
    if (url.isEmpty || _isPlaceholder(url)) return false;
    final lower = url.toLowerCase();
    return lower.contains('googleusercontent.com') || lower.contains('yt3.ggpht.com');
  }

  /// Upgrades GoogleUserContent thumbnail to 1000x1000 square
  static String _upgradeYouTubeMusicSquareCover(String url) {
    var upgraded = url;
    if (upgraded.startsWith('http://')) {
      upgraded = upgraded.replaceFirst('http://', 'https://');
    }

    // Match =w...-h... or =s... parameters and replace with high-res =w1000-h1000-l90-rj
    final dimRegex = RegExp(r'=w\d+-h\d+.*$|=s\d+.*$');
    if (dimRegex.hasMatch(upgraded)) {
      upgraded = upgraded.replaceFirst(dimRegex, '=w1000-h1000-l90-rj');
    } else if (!upgraded.contains('=')) {
      upgraded = '$upgraded=w1000-h1000-l90-rj';
    }
    return upgraded;
  }

  /// Queries the iTunes Search API and validates match against title, artist, and duration
  static Future<String?> _queryITunes(Song song) async {
    final client = _httpClient ?? http.Client();
    final cleanTitle = _cleanSongTitle(song.title);
    final primaryArtist = _cleanArtistName(song.primaryArtist.isNotEmpty ? song.primaryArtist : song.artist);

    if (cleanTitle.isEmpty) return null;

    final query = primaryArtist.isNotEmpty ? '$cleanTitle $primaryArtist' : cleanTitle;
    final uri = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeQueryComponent(query)}&entity=song&limit=5');

    final response = await client.get(uri, headers: {
      'User-Agent': 'PaatuPadava/1.0 (Mobile; Android/iOS)',
      'Accept': 'application/json',
    }).timeout(requestTimeout);

    if (response.statusCode != 200) return null;

    final data = json.decode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? [];

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;

      final trackName = item['trackName']?.toString() ?? '';
      final artistName = item['artistName']?.toString() ?? '';
      final trackTimeMillis = item['trackTimeMillis'] as num?;
      final artworkUrl100 = item['artworkUrl100']?.toString() ?? '';

      if (artworkUrl100.isEmpty) continue;

      // Safeguard 1: Duration verification (relaxed for video intro/outro padding)
      if (song.duration > 0 && trackTimeMillis != null) {
        final candDurationSec = (trackTimeMillis / 1000).round();
        final diff = (candDurationSec - song.duration).abs();
        final maxTolerance = song.source == 'youtube' ? 35 : durationToleranceSec;
        if (diff > maxTolerance) {
          continue; // Rejected due to duration mismatch
        }
      }

      // Safeguard 2: Title verification
      if (!_isTitleMatch(cleanTitle, trackName)) {
        continue;
      }

      // Safeguard 3: Artist verification (if artist is specified)
      if (primaryArtist.isNotEmpty && !_isArtistMatch(primaryArtist, artistName)) {
        continue;
      }

      // Match validated! Upgrade artwork from 100x100 to 1000x1000bb
      var highRes = artworkUrl100
          .replaceAll('100x100bb', '1000x1000bb')
          .replaceAll('100x100', '1000x1000');
      if (highRes.startsWith('http://')) {
        highRes = highRes.replaceFirst('http://', 'https://');
      }

      AppLogger.log('CoverArtResolver', 'Matched iTunes studio cover for "${song.title}" -> $highRes');
      return highRes;
    }

    return null;
  }

  /// Queries the Deezer Search API as secondary fallback
  static Future<String?> _queryDeezer(Song song) async {
    final client = _httpClient ?? http.Client();
    final cleanTitle = _cleanSongTitle(song.title);
    final primaryArtist = _cleanArtistName(song.primaryArtist.isNotEmpty ? song.primaryArtist : song.artist);

    if (cleanTitle.isEmpty) return null;

    final query = primaryArtist.isNotEmpty ? '$cleanTitle $primaryArtist' : cleanTitle;
    final uri = Uri.parse('https://api.deezer.com/search?q=${Uri.encodeQueryComponent(query)}&limit=5');

    final response = await client.get(uri, headers: {
      'User-Agent': 'PaatuPadava/1.0',
      'Accept': 'application/json',
    }).timeout(requestTimeout);

    if (response.statusCode != 200) return null;

    final data = json.decode(response.body) as Map<String, dynamic>;
    final results = data['data'] as List<dynamic>? ?? [];

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;

      final trackTitle = item['title']?.toString() ?? '';
      final artist = item['artist'] as Map<String, dynamic>?;
      final artistName = artist?['name']?.toString() ?? '';
      final durationSec = item['duration'] as num?;
      final album = item['album'] as Map<String, dynamic>?;
      final coverUrl = album?['cover_xl']?.toString() ?? album?['cover_big']?.toString() ?? '';

      if (coverUrl.isEmpty) continue;

      // Safeguard 1: Duration verification
      if (song.duration > 0 && durationSec != null) {
        final diff = (durationSec.toInt() - song.duration).abs();
        if (diff > durationToleranceSec) {
          continue;
        }
      }

      // Safeguard 2: Title verification
      if (!_isTitleMatch(cleanTitle, trackTitle)) {
        continue;
      }

      // Safeguard 3: Artist verification
      if (primaryArtist.isNotEmpty && !_isArtistMatch(primaryArtist, artistName)) {
        continue;
      }

      var highRes = coverUrl;
      if (highRes.startsWith('http://')) {
        highRes = highRes.replaceFirst('http://', 'https://');
      }

      AppLogger.log('CoverArtResolver', 'Matched Deezer studio cover for "${song.title}" -> $highRes');
      return highRes;
    }

    return null;
  }

  /// Clean root title for search and verification
  static String _cleanSongTitle(String rawTitle) {
    var text = rawTitle.toLowerCase();
    text = text.replaceAll(RegExp(r'^@[a-z0-9_.]+\s*[-:|~–—]?\s*'), ' ');
    text = text.replaceAll(RegExp(r'\|.*$'), ' ');
    text = text.replaceAll(RegExp(r'\([^)]*\)'), ' ').replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    text = text.replaceAll(
      RegExp(
        r'\b(from|lyric|lyrical|lyrics|video|official|audio|single|song|remix|lofi|lo-fi|full video|hd|4k|teaser|trailer|ost|track|promo)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    return text.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Clean artist name for search and verification
  static String _cleanArtistName(String rawArtist) {
    var text = rawArtist.toLowerCase();
    final parts = text.split(RegExp(r'[,&/|]|\bfeat\.?\b|\bft\.?\b|\bwith\b'));
    final first = parts.isNotEmpty ? parts.first.trim() : text.trim();
    return first.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalizes string for token-based fuzzy matching
  static String _normalizeTokens(String text) {
    var s = text.toLowerCase();
    s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ').replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    s = s.replaceAll(RegExp(r'\b(from|movie|film|soundtrack|ost|audio|video|song|remix)\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Validates if candidate title corresponds to the song's clean title
  static bool _isTitleMatch(String targetTitle, String candidateTitle) {
    final normTarget = _normalizeTokens(targetTitle);
    final normCand = _normalizeTokens(candidateTitle);

    if (normTarget.isEmpty || normCand.isEmpty) return false;
    if (normTarget == normCand) return true;
    if (normCand.contains(normTarget) || normTarget.contains(normCand)) return true;

    // Check token overlap
    final targetTokens = normTarget.split(' ').where((t) => t.length > 2).toSet();
    final candTokens = normCand.split(' ').where((t) => t.length > 2).toSet();

    if (targetTokens.isEmpty || candTokens.isEmpty) return false;
    final intersection = targetTokens.intersection(candTokens);
    return intersection.length >= targetTokens.length;
  }

  /// Validates if candidate artist matches target primary artist
  static bool _isArtistMatch(String targetArtist, String candidateArtist) {
    final normTarget = _normalizeTokens(targetArtist);
    final normCand = _normalizeTokens(candidateArtist);

    if (normTarget.isEmpty || normCand.isEmpty) return true;
    if (normTarget == normCand) return true;
    if (normCand.contains(normTarget) || normTarget.contains(normCand)) return true;

    final targetTokens = normTarget.split(' ').where((t) => t.length > 2).toSet();
    final candTokens = normCand.split(' ').where((t) => t.length > 2).toSet();

    return targetTokens.intersection(candTokens).isNotEmpty;
  }

  /// Returns valid YouTube video thumbnail or empty string
  static String _getThumbnailOrEmpty(Song song) {
    if (song.coverUrl.isNotEmpty && !_isPlaceholder(song.coverUrl)) {
      return song.coverUrl;
    }
    if (song.source == 'youtube' || song.id.length == 11) {
      return 'https://img.youtube.com/vi/${song.id}/hqdefault.jpg';
    }
    return '';
  }

  /// Detects whether a cover URL is an unwanted placeholder (Unsplash stock photo)
  static bool _isPlaceholder(String url) {
    return url.contains('unsplash.com') || url.contains('photo-1470225620780-dba8ba36b745');
  }

  /// Helper to test if a given URL is a 16:9 YouTube video thumbnail (letterboxed or frame capture)
  static bool isYouTubeThumbnail(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    return (lower.contains('img.youtube.com') || lower.contains('i.ytimg.com')) &&
        (lower.contains('hqdefault') || lower.contains('mqdefault') || lower.contains('maxresdefault') || lower.contains('sddefault'));
  }
}
