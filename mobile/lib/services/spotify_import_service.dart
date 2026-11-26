import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/dsa/string_similarity.dart';
import 'package:html_unescape/html_unescape.dart';
import '../models/song.dart';
import '../domain/models/track_entity.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';
import 'catalog_database.dart';
import 'app_logger.dart';
import 'cover_art_resolver.dart';
import '../core/app_config.dart';
import 'spotify_track_key.dart';
import 'battery_optimization_service.dart';
import 'download_manager.dart';

part 'spotify/spotify_metadata_fetcher.dart';
part 'spotify/spotify_track_matcher.dart';
part 'spotify/spotify_batch_importer.dart';
part 'spotify/spotify_discovery_client.dart';

/// Single Spotify Track representation extracted from Spotify Web API or Embed
class SpotifyTrackItem {
  final String title;
  final String artist;
  final String? album;
  final int durationSeconds;
  final String? coverUrl;
  final String? spotifyUri;
  final String? spotifyId;

  const SpotifyTrackItem({
    required this.title,
    required this.artist,
    this.album,
    required this.durationSeconds,
    this.coverUrl,
    this.spotifyUri,
    this.spotifyId,
  });
}

/// Spotify Playlist or Album Metadata containing all paginated tracks
class SpotifyPlaylistMetadata {
  final String title;
  final String? coverUrl;
  final int totalTracks;
  final List<SpotifyTrackItem> tracks;

  const SpotifyPlaylistMetadata({
    required this.title,
    this.coverUrl,
    required this.totalTracks,
    required this.tracks,
  });
}

/// Result of importing and matching tracks from Spotify
class SpotifyImportResult {
  final String playlistTitle;
  final String? coverUrl;
  final int totalTracks;
  final List<Song> importedSongs;
  final List<SpotifyTrackItem> skippedTracks;

  /// Tracks that were already in the target playlist and therefore NOT matched again.
  final int alreadyPresentCount;

  /// SpotifyTrackKey of every track that is now "handled" (newly matched + already present).
  /// Unmatched tracks are deliberately NOT included, so a later import retries them.
  final List<String> handledKeys;

  const SpotifyImportResult({
    required this.playlistTitle,
    this.coverUrl,
    required this.totalTracks,
    required this.importedSongs,
    required this.skippedTracks,
    this.alreadyPresentCount = 0,
    this.handledKeys = const [],
  });

  bool get hasSkipped => skippedTracks.isNotEmpty;
  double get successRate => totalTracks > 0 ? (importedSongs.length / totalTracks) : 0.0;
}

class SpotifyImportService {
  static final HtmlUnescape _unescape = HtmlUnescape();

  static const Map<String, String> _webHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/html, */*',
  };

  /// Parses duration into seconds regardless of format (milliseconds, seconds, or "mm:ss")
  static int parseDurationSeconds(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) {
      if (raw > 1000) return (raw / 1000).round();
      return raw.toInt();
    }
    final str = raw.toString().trim();
    if (str.isEmpty) return 0;
    if (str.contains(':')) {
      final parts = str.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        return (m * 60) + s;
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        return (h * 3600) + (m * 60) + s;
      }
    }
    final numVal = num.tryParse(str);
    if (numVal != null) {
      if (numVal > 1000) return (numVal / 1000).round();
      return numVal.toInt();
    }
    return 0;
  }

  /// Clean raw Spotify track titles:
  /// Strips metadata tags like (From "Movie"), [Remastered], (Original Motion Picture Soundtrack),
  /// [Official Video], and sanitizes HTML entities (&quot;, &#39;, &amp;).
  static String cleanTrackTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';
    var clean = _unescape.convert(Song.sanitize(rawTitle));

    // 0. Handle slash separation in dual-language titles (e.g. "Puthu Mazha / പുതുമഴ")
    if (clean.contains('/')) {
      final parts = clean.split('/');
      final latinPart = parts.firstWhere(
        (p) => RegExp(r'[a-zA-Z]').hasMatch(p),
        orElse: () => parts.first,
      );
      clean = latinPart.trim();
    }

    // 0b. Remove Indian regional scripts in parentheses/brackets e.g. (പുതുമഴ), [புதுமழை]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^\)\]]*[\u0D00-\u0D7F\u0B80-\u0BFF\u0900-\u097F\u0C00-\u0C7F\u0C80-\u0CFF][^\)\]]*[\)\]]'),
      '',
    );

    // 1. Remove: (From "Movie") or [From "Movie"] with all quote characters
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][Ff]rom\s+["\u201c\u201d\u2018\u2019]?[^)\u201d\]]+["\u201c\u201d\u2018\u2019]?[\)\]]', caseSensitive: false),
      '',
    );

    // 2. Remove: (Original Motion Picture Soundtrack), (OST), [Soundtrack Version]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:motion picture|soundtrack|ost)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 3. Remove: [Remastered...] or (Remastered...) or [2023 Remaster]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*remaster(?:ed)?[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 4. Remove: (Official Video) or [Official Audio], (Music Video), (Audio), (Lyric Video)
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:official|audio|lyric|video)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 5. Remove: (Feat. ...) or [feat. ...] or (ft. ...)
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][Ff](?:eat\.?|t\.)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 6. Remove: (Deluxe Edition), [Deluxe], [Bonus Track]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:deluxe|bonus\s*track)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 7. Suffix: " - Live" or " - Single" or " - Remastered"
    clean = clean.replaceAll(RegExp(r'\s*-\s*(?:live|single|stereo|mono|edit|remaster(?:ed)?(?:\s*\d{4})?)$', caseSensitive: false), '');

    // 8. If Latin title exists alongside standalone regional script, strip the regional script
    if (RegExp(r'[a-zA-Z]').hasMatch(clean)) {
      clean = clean.replaceAll(RegExp(r'[\u0D00-\u0D7F\u0B80-\u0BFF\u0900-\u097F\u0C00-\u0C7F\u0C80-\u0CFF]+'), '');
    }

    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : Song.sanitize(rawTitle);
  }

  /// Clean primary artist name (strips secondary featured artists)
  static String cleanArtistName(String rawArtist) {
    final sanitized = _unescape.convert(Song.sanitize(rawArtist));
    final first = sanitized.split(RegExp(r'[,&/]')).first.trim();
    return first.isNotEmpty ? first : sanitized;
  }

  /// Extracts movie or soundtrack name if embedded in the title (e.g. `(From "Narivetta")`, `[From "Shajahaan"]`).
  static String? extractMovieFromTitle(String rawTitle) {
    if (rawTitle.isEmpty) return null;
    final m = RegExp(
      r'[\(\[][Ff]rom\s+["\u201c\u201d\u2018\u2019]?([^)\u201d\]"]+)["\u201c\u201d\u2018\u2019]?[\)\]]',
    ).firstMatch(rawTitle);
    if (m != null && m.group(1) != null) {
      final movie = m.group(1)!.trim();
      return movie.isNotEmpty ? movie : null;
    }
    return null;
  }

  /// Extracts all distinct contributing artists (singers, composers, featured).
  static List<String> extractAllArtists(String rawArtists) {
    if (rawArtists.isEmpty) return const [];
    final sanitized = _unescape.convert(Song.sanitize(rawArtists));
    return sanitized
        .split(RegExp(r'[,&/|]|\b(?:feat\.?|ft\.?|and)\b', caseSensitive: false))
        .map((a) => a.trim().toLowerCase())
        .where((a) => a.isNotEmpty && a != 'various artists' && a != 'artist')
        .toList();
  }

  /// Normalizes common Tanglish / Indic romanization variants for tolerant matching.
  static String normalizeTanglish(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'ae\b'), 'e');
    t = t.replaceAll(RegExp(r'ey\b'), 'e');
    t = t.replaceAll('dh', 'th');
    t = t.replaceAll('oo', 'u');
    t = t.replaceAll('ee', 'i');
    return t;
  }

  /// Generates phonetic transliteration query variants for tolerant cross-platform searching.
  static String? getPhoneticVariant(String s) {
    var lower = s.trim();
    if (lower.toLowerCase().endsWith('e') && !lower.toLowerCase().endsWith('ae')) {
      return '${lower.substring(0, lower.length - 1)}ae';
    } else if (lower.toLowerCase().endsWith('ae')) {
      return '${lower.substring(0, lower.length - 2)}e';
    }
    if (lower.contains('dh')) {
      return lower.replaceAll('dh', 'th');
    }
    if (lower.contains('th')) {
      return lower.replaceAll('th', 'dh');
    }
    return null;
  }

  /// Title similarity with Tanglish transliteration tolerance (e.g. "Melliname" <-> "Mellinamae").
  static int computeTitleSimilarity(String t1, String t2) {
    final sim1 = tokenSetRatio(t1.toLowerCase(), t2.toLowerCase());
    final sim2 = tokenSetRatio(normalizeTanglish(t1), normalizeTanglish(t2));
    return sim1 > sim2 ? sim1 : sim2;
  }

  /// Compares full contributing artist sets to preserve playback singers and music directors.
  static int computeArtistSimilarity(String targetArtists, String candidateArtists) {
    final targetList = extractAllArtists(targetArtists);
    final candidateList = extractAllArtists(candidateArtists);
    if (targetList.isEmpty || candidateList.isEmpty) return 50;

    final targetSet = targetList.toSet();
    final candidateSet = candidateList.toSet();

    final inter = targetSet.intersection(candidateSet);
    if (inter.isNotEmpty) {
      if (inter.length == targetSet.length) return 100;
      return (70 + 30 * (inter.length / targetSet.length)).round();
    }

    int partialMatches = 0;
    for (final t in targetList) {
      for (final c in candidateList) {
        if (t.contains(c) || c.contains(t) || tokenSetRatio(t, c) >= 80) {
          partialMatches++;
          break;
        }
      }
    }

    if (partialMatches > 0) {
      return (65 + 35 * (partialMatches / targetList.length)).round();
    }
    return 20;
  }

  /// Compares album or soundtrack titles if present.
  static int computeAlbumSimilarity(String? targetAlbum, String? candidateAlbum) {
    if (targetAlbum == null || candidateAlbum == null) return 0;
    final cTarget = cleanTrackTitle(targetAlbum).toLowerCase().trim();
    final cCand = cleanTrackTitle(candidateAlbum).toLowerCase().trim();
    if (cTarget.isEmpty || cCand.isEmpty) return 0;
    return tokenSetRatio(cTarget, cCand);
  }

  /// Duration scoring with strict penalties for covers/snippets (> 20s difference).
  static int computeDurationScore(int targetSec, int candidateSec) {
    if (targetSec <= 0 || candidateSec <= 0) return 0;
    final diff = (targetSec - candidateSec).abs();
    if (diff <= 5) return 20;
    if (diff <= 12) return 15;
    if (diff <= 18) return 5;
    if (diff <= 25) return -20;
    return -60;
  }

  static const Set<String> _authoritativeLabels = {
    'sony music south',
    'sony music india',
    't-series',
    'tseries',
    'lahari music',
    'think music india',
    'think music',
    'saregama tamil',
    'saregama',
    'aditya music',
    'zeemusicsouth',
    'zee music company',
    'muzik247',
    'speed records',
    'yrf',
    'tips official',
    'voila! digi',
    'sun tv',
    'suntv',
  };

  /// Multi-dimensional candidate scoring formula combining title, artists, album, and duration.
  static int scoreCandidate({
    required SpotifyTrackItem target,
    required Song candidate,
    String? movieHint,
  }) {
    final cleanTargetTitle = cleanTrackTitle(target.title);
    final cleanCandTitle = cleanTrackTitle(candidate.title);

    final titleSim = computeTitleSimilarity(cleanTargetTitle, cleanCandTitle);
    if (titleSim < 45) return -100;

    int artistSim = computeArtistSimilarity(target.artist, candidate.artist);

    // Label Channel Recognition: Official label channels on YouTube (Sony Music South != Anirudh)
    final isYouTube = candidate.source == 'youtube';
    if (isYouTube && artistSim < 35) {
      final candArtistLower = candidate.artist.toLowerCase();
      final isLabel = _authoritativeLabels.any((l) => candArtistLower.contains(l));
      if (isLabel) {
        if (cleanCandTitle.toLowerCase().contains(cleanTargetTitle.toLowerCase()) || titleSim >= 60) {
          artistSim = 80;
        }
      }
    }

    final targetAlbum = target.album ?? movieHint;
    final albumSim = computeAlbumSimilarity(targetAlbum, candidate.album);

    // If candidate has 0 artist overlap AND 0 album overlap, reject only if not a verified label
    if (artistSim <= 15 && albumSim < 35) {
      return -100;
    }

    // Relaxed Duration Tolerance: Indian music videos have cinematic dialogue intros / end credits (up to 90s)
    final diff = (target.durationSeconds - candidate.duration).abs();
    final maxAllowedDiff = isYouTube ? 90 : 35;
    if (target.durationSeconds > 0 && candidate.duration > 0 && diff > maxAllowedDiff) {
      return -100;
    }

    int durScore = 0;
    if (diff <= 5) {
      durScore = 20;
    } else if (diff <= 15) {
      durScore = 15;
    } else if (diff <= 35) {
      durScore = 5;
    } else if (diff <= maxAllowedDiff) {
      durScore = -10; // Moderate penalty, not disqualifying
    }

    final int baseScore = (titleSim * 0.40 +
            artistSim * 0.35 +
            (targetAlbum != null && targetAlbum.isNotEmpty ? albumSim * 0.25 : artistSim * 0.10))
        .round();

    return baseScore + durScore;
  }

  static final http.Client _probeClient = http.Client();

  /// Probes whether a stream URL actually exists and returns HTTP 200/206.
  /// Prevents adding orphaned/deleted CDN items (HTTP 404) to the user's playlist.
  static Future<bool> isStreamPlayable(String? url) async {
    if (url == null || url.trim().isEmpty) return false;
    final clean = url.trim();
    if (!clean.startsWith('http')) return false;

    Future<bool> probeUrl(String testUrl) async {
      try {
        final uri = Uri.parse(testUrl);
        final req = http.Request('GET', uri);
        req.headers['Range'] = 'bytes=0-1024';
        req.headers['User-Agent'] = _webHeaders['User-Agent']!;
        final streamedRes = await _probeClient.send(req).timeout(const Duration(milliseconds: 1200));
        final isValid = streamedRes.statusCode == 200 || streamedRes.statusCode == 206;
        await streamedRes.stream.drain().timeout(const Duration(milliseconds: 200), onTimeout: () => null);
        return isValid;
      } catch (_) {
        return false;
      }
    }

    if (await probeUrl(clean)) return true;
    if (clean.contains('_320.mp4')) {
      final fallback160 = clean.replaceAll('_320.mp4', '_160.mp4');
      if (await probeUrl(fallback160)) return true;
    }
    return false;
  }

  /// Check if candidate title contains unwanted tags (karaoke, cover, reaction, snippet)
  static bool _isUnwantedType(String candidateTitle, String originalTitle) {
    final lowerCand = candidateTitle.toLowerCase();
    final lowerOrig = originalTitle.toLowerCase();

    const unwantedTags = [
      'karaoke',
      'instrumental',
      'cover by',
      'dance cover',
      'reaction',
      'slowed',
      'reverb',
      '8d audio',
      'chipmunk',
      'lo-fi remix',
      'lofi remix',
      'tribute',
      'ringtone',
      'status',
      'whatsapp status',
    ];

    for (final tag in unwantedTags) {
      if (lowerCand.contains(tag) && !lowerOrig.contains(tag)) {
        return true;
      }
    }
    return false;
  }

  /// Extracts entity type ('playlist', 'album', 'track') and Spotify ID from link
  static Map<String, String>? parseSpotifyUrl(String url) {
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    if (uri == null) return null;

    final segments = uri.pathSegments;
    for (int i = 0; i < segments.length - 1; i++) {
      final type = segments[i].toLowerCase();
      if (type == 'playlist' || type == 'album' || type == 'track') {
        final id = segments[i + 1].split('?').first;
        if (id.isNotEmpty) {
          return {'type': type, 'id': id};
        }
      }
    }
    return null;
  }

  static String? _cachedAccessToken;
  static DateTime? _tokenExpiresAt;

  /// Retrieves a valid Spotify Access Token.
  /// Tier 1: In-memory cached token (refreshed 5 min before expiry).
  /// Tier 1: Paatu Padava FastAPI backend token proxy (/api/music/spotify/token).
  /// Tier 2: Anonymous Spotify Web Player token.
  static Future<String?> getSpotifyAccessToken() async {
    // Return cached token if still valid (with 5 minute safety buffer)
    if (_cachedAccessToken != null &&
        _tokenExpiresAt != null &&
        DateTime.now().isBefore(_tokenExpiresAt!)) {
      return _cachedAccessToken;
    }

    // ── Tier 1: Secure Backend Token Proxy (Primary) ──
    try {
      final uris = [
        Uri.parse('${AppConfig.backendUrl}/api/music/spotify/token'),
        Uri.parse('${AppConfig.backendUrl}/music/spotify/token'),
        Uri.parse('${AppConfig.backendUrl}/api/music/spotify-token'),
      ];
      for (final backendUri in uris) {
        try {
          final response = await http.get(backendUri, headers: _webHeaders).timeout(const Duration(seconds: 3));
          if (response.statusCode == 200) {
            final data = json.decode(response.body) as Map<String, dynamic>;
            final token = data['access_token']?.toString();
            final int expiresIn = data['expires_in'] is int ? data['expires_in'] as int : 3600;
            if (token != null && token.isNotEmpty) {
              _cachedAccessToken = token;
              _tokenExpiresAt = DateTime.now().add(Duration(seconds: (expiresIn - 300).clamp(60, 3600)));
              AppLogger.log('SpotifyImportService', 'Acquired Spotify token via secure backend proxy');
              return token;
            }
          }
        } catch (e) {
          AppLogger.debug('SpotifyImportService', 'Backend token payload parse skipped: $e');
        }
      }
    } catch (e) {
      AppLogger.log('SpotifyImportService', 'Backend token proxy failed: $e');
    }

    // ── Tier 3: Anonymous Web Player Fallback ──
    final anon = await _getAnonymousSpotifyToken();
    if (anon != null) {
      _cachedAccessToken = anon;
      _tokenExpiresAt = DateTime.now().add(const Duration(minutes: 20));
      return anon;
    }

    return null;
  }

  /// Fetches an anonymous temporary Web Player Bearer Token from Spotify
  static Future<String?> _getAnonymousSpotifyToken() async {
    try {
      final tokenUri = Uri.parse(
        'https://open.spotify.com/get_access_token?reason=transport&productType=web_player',
      );
      final response = await http.get(tokenUri, headers: _webHeaders).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['accessToken']?.toString();
      }
    } catch (e) {
      AppLogger.log('SpotifyImportService', 'Token fetch notice: $e');
    }
    return null;
  }

  /// Top 10 Hits for a given language via Spotify Search API.
  /// Queries `GET https://api.spotify.com/v1/search?q=$language%20Top%20Hits&type=track&market=IN&limit=10`,
  /// maps to [TrackEntity] with source='spotify', allowing audio resolution via JioSaavn / YouTube on playback.
  static Future<List<TrackEntity>> getTop10Hits(String language) =>
      _getTop10HitsImpl(language);

  /// Fetches non-editorial Spotify Playlists using /v1/search.
  /// Queries `GET https://api.spotify.com/v1/search?q=$language%20Hits&type=playlist&market=IN&limit=15`
  /// and skips items where item == null or item['owner']?['id'] == 'spotify' to avoid 404 restrictions.
  static Future<List<Map<String, dynamic>>> getPlaylists(String language) =>
      _getPlaylistsImpl(language);

  /// Fetches authentic artist profile image via Spotify Web API.
  /// Queries `GET https://api.spotify.com/v1/search?q=${Uri.encodeComponent(artistName)}&type=artist&market=IN&limit=1`
  /// and returns `artists.items[0].images[0].url`.
  static Future<String?> getArtistProfileImage(String artistName) =>
      _getArtistProfileImageImpl(artistName);

  /// 1. Paginated Spotify Playlist / Album Fetcher:
  /// Fetches all pages recursively (?offset=N&limit=50) until all songs are imported.
  static Future<SpotifyPlaylistMetadata?> fetchSpotifyMetadata(String url) =>
      _fetchSpotifyMetadataImpl(url);

  /// Resolves the authentic Spotify track thumbnail URL using Spotify's public oEmbed endpoint.
  /// Requires zero authentication or API tokens. Upgrades 300x300 to 640x640 studio square art.
  static Future<String?> resolveSpotifyTrackThumbnail(String trackIdOrUri) async {
    try {
      final cleanId = trackIdOrUri.replaceFirst('spotify:track:', '').trim();
      if (cleanId.isEmpty) return null;
      final uri = Uri.parse('https://open.spotify.com/oembed?url=https://open.spotify.com/track/$cleanId');
      final res = await http.get(uri, headers: _webHeaders).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final thumb = data['thumbnail_url']?.toString();
        if (thumb != null && thumb.isNotEmpty && !CoverArtResolver.isPlaylistCover(thumb)) {
          return CoverArtResolver.upgradeSpotifyCover(thumb);
        }
      }
    } catch (e) {
      AppLogger.debug('SpotifyImportService', 'Handled exception: $e');
    }
    return null;
  }

  /// Multi-Pass Smart Matcher:
  /// Uses a 2-stage search pipeline (Title+Artist -> Album+Title -> Title-only),
  /// full-credit multi-artist + album scoring, Tanglish transliteration normalization,
  /// strict duration window (+/- 15s), and live CDN stream verification probing.
  static Future<Song?> matchSingleTrack(
    SpotifyTrackItem track, {
    String? preferredLanguage,
  }) =>
      _matchSingleTrackImpl(track, preferredLanguage: preferredLanguage);

  /// Tier 3 Bloomee Synthesizer: Synthesizes a valid, fully formed playable Song entity from Spotify metadata
  static Song _synthesizeTrack(
    SpotifyTrackItem track, {
    String? effectiveCover,
    Song? fallbackCandidate,
  }) =>
      _synthesizeTrackImpl(track, effectiveCover: effectiveCover, fallbackCandidate: fallbackCandidate);

  /// Stable identity of a Spotify track (used to remember what was already imported).
  static String trackKey(SpotifyTrackItem t) => SpotifyTrackKey.keyFor(cleanTrackTitle(t.title), t.artist);

  /// True when [t] is already present in [songs] (same cleaned title + a shared artist).
  /// Compares text, not ids, because the matcher may pick another source/id next time.
  static bool isTrackInSongs(SpotifyTrackItem t, Iterable<Song> songs) {
    final title = cleanTrackTitle(t.title);
    return songs.any((s) => SpotifyTrackKey.sameTrack(
          titleA: title,
          artistsA: t.artist,
          titleB: cleanTrackTitle(s.title),
          artistsB: s.artist,
        ));
  }

  /// 3. Complete Batch Importer with High-Performance Concurrent Matching
  static Future<SpotifyImportResult> importPlaylistWithProgress({
    required SpotifyPlaylistMetadata metadata,
    required void Function(
      int current,
      int total,
      double progress,
      String status,
      Song? matched,
    ) onProgress,
    String? preferredLanguage,
    bool Function()? isCancelled,
    bool Function(SpotifyTrackItem track)? isAlreadyImported,
  }) =>
      _importPlaylistWithProgressImpl(
        metadata: metadata,
        onProgress: onProgress,
        preferredLanguage: preferredLanguage,
        isCancelled: isCancelled,
        isAlreadyImported: isAlreadyImported,
      );
}
