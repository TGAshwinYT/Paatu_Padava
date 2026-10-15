import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import '../domain/models/track_entity.dart';
import 'saavn_client.dart';
import 'settings_manager.dart';
import 'app_logger.dart';
import 'artist_sanitizer.dart';
import '../data/repositories/song_repository.dart';

/// Outcome of probing a stream URL against the CDN.
enum _ProbeResult { ok, forbidden, unknown }

class YouTubeClient {
  static YoutubeExplode? _ytInstance;
  static YoutubeExplode get _yt => _ytInstance ??= YoutubeExplode();

  /// Closes any idle YouTube HTTP sockets and resets client instance
  static void closeIdleClient() {
    _ytInstance?.close();
    _ytInstance = null;
  }

  // ── User-Agents ────────────────────────────────────────────────────────
  // A googlevideo.com URL is issued for ONE InnerTube client (the `c=` query
  // parameter). The player must request it with that same client's User-Agent,
  // otherwise YouTube answers 403. Never hard-code a single UA for every URL.
  static const String vrUserAgent =
      'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 2; Build/SQ3A.220605.009.A1) gzip';
  static const String visionOsUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
  static const String androidUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  static const String iosUserAgent =
      'com.google.ios.youtube/19.45.4 (iPhone14,3; U; CPU iOS 17_5 like Mac OS X; en_US)';

  /// Exact URL -> User-Agent of the client that produced it (bounded).
  static final Map<String, String> _urlUserAgents = {};

  static void _rememberUserAgent(String url, String ua) {
    if (_urlUserAgents.length > 300) _urlUserAgents.clear();
    _urlUserAgents[url] = ua;
  }

  /// True for URLs served by YouTube's media CDN / manifest endpoints.
  static bool isYouTubeStreamUrl(String url) =>
      url.contains('googlevideo.com') || url.contains('youtube.com/api/manifest');

  /// Returns the User-Agent that matches the client which issued [url].
  static String userAgentForUrl(String url) {
    final known = _urlUserAgents[url];
    if (known != null) return known;
    try {
      final c = Uri.parse(url).queryParameters['c']?.toUpperCase();
      if (c == 'ANDROID_VR') return vrUserAgent;
      if (c == 'ANDROID') return androidUserAgent;
      if (c == 'IOS') return iosUserAgent;
      if (c == 'VISIONOS') return visionOsUserAgent;
    } catch (_) {}
    return vrUserAgent;
  }

  /// HTTP headers the PLAYER must send for a YouTube stream [url].
  static Map<String, String> headersForUrl(String url) {
    final isManifest = url.contains('.m3u8') || url.contains('hls_playlist') || url.contains('hls_variant');
    return {
      'User-Agent': userAgentForUrl(url),
      'Accept': '*/*',
      'Connection': 'keep-alive',
      if (!isManifest) 'Range': 'bytes=0-',
    };
  }

  /// Legacy static headers (VR client). Prefer [headersForUrl].
  static Map<String, String> get streamingHeaders => const {
    'Range': 'bytes=0-',
    'User-Agent': vrUserAgent,
    'Accept': '*/*',
    'Connection': 'keep-alive',
  };

  // ── Non-music filtering (reviews, reactions, audiobooks, trailers…) ─────
  // These are the kinds of long/spoken videos that leaked into the "YT Music"
  // tab because the plain YouTube video search was used.
  static final RegExp _nonMusicTitle = RegExp(
    r'\b(reviews?|reaction|reacts?|reacting|trailer|teaser|full movie|movie scenes?|'
    r'audio ?books?|podcast|interview|press meet|success meet|audio launch|trailer launch|'
    r'making of|behind the scenes|explained|explanation|analysis|breakdown|vlog|comedy|troll|prank|'
    r'promo|shorts?|whatsapp status|jukebox|non-?stop|full album|all songs|back to back|'
    r'live ?stream|tutorial|karaoke|ringtone|public (?:talk|opinion|review)|first day first show|fdfs)\b',
    caseSensitive: false,
  );

  static bool _looksLikeNonMusic(String title) => _nonMusicTitle.hasMatch(title);

  static String cleanTitle(String title) {
    var cleaned = Song.sanitize(title);
    // Remove leading @handle mentions (e.g. "@SaiAbhyankkar - Pavazha Malli" -> "Pavazha Malli")
    cleaned = cleaned.replaceAll(RegExp(r'^@[a-zA-Z0-9_.]+\s*[-:|~–—]?\s*'), '');
    // Remove bracketed info like [Official Video], (4K), | Lyrical
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\b(official|video|audio|lyric|lyrical|hd|4k|full video|song|teaser|trailer)\b', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\|.*$'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : Song.sanitize(title);
  }

  /// Extracts 11-character video ID from YouTube, YouTube Music, or youtu.be URLs
  static String? extractVideoId(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return null;
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) return clean;
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?|shorts)\/|.*[?&]v=)|youtu\.be\/|music\.youtube\.com\/(?:watch\?v=|shorts\/))([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(clean);
    return match?.group(1);
  }

  /// Extracts playlist ID (e.g. PL..., RD..., etc.) from a YouTube playlist URL
  static String? extractPlaylistId(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return null;
    final regExp = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)', caseSensitive: false);
    final match = regExp.firstMatch(clean);
    if (match != null) return match.group(1);
    if (clean.startsWith('PL') || clean.startsWith('RD') || clean.startsWith('OLAK5uy_')) {
      return clean;
    }
    return null;
  }

  /// Direct client-side search autocomplete / suggestions via Google Suggest endpoint.
  /// Zero-server dependency, works with sub-40ms latency directly on device.
  static Future<List<String>> getSearchSuggestions(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    try {
      final uri = Uri.parse('https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=${Uri.encodeComponent(clean)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.length >= 2 && decoded[1] is List) {
          return (decoded[1] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'Search suggestions notice: $e');
    }
    return [];
  }

  /// Resolves track metadata directly from a shared YouTube or YouTube Music URL.
  static Future<Song?> resolveTrackFromUrl(String url) async {
    final videoId = extractVideoId(url);
    if (videoId == null) return null;

    try {
      final video = await _yt.videos.get(VideoId(videoId)).timeout(const Duration(seconds: 10));
      final cleanAuthor = ArtistSanitizer.extractArtistFromVideo(video.title, video.author);
      final highThumb = video.thumbnails.highResUrl;
      final safeThumb = (highThumb.isNotEmpty && highThumb.startsWith('http'))
          ? (highThumb.startsWith('http://') ? highThumb.replaceFirst('http://', 'https://') : highThumb)
          : 'https://img.youtube.com/vi/${video.id.value}/hqdefault.jpg';

      return Song(
        id: video.id.value,
        title: cleanTitle(video.title),
        artist: Song.sanitize(cleanAuthor),
        album: 'YouTube Music',
        coverUrl: safeThumb,
        duration: video.duration?.inSeconds ?? 0,
        source: 'youtube',
      );
    } catch (e, st) {
      AppLogger.recordError(e, st, context: 'YouTubeClient.resolveTrackFromUrl("$url")');
      return null;
    }
  }

  /// Client-side YouTube Playlist importer.
  /// Given a playlist URL or ID, extracts metadata and all playable tracks directly on-device.
  static Future<List<Song>> getPlaylistTracks(String playlistIdOrUrl, {int limit = 50}) async {
    final playlistId = extractPlaylistId(playlistIdOrUrl) ?? playlistIdOrUrl.trim();
    if (playlistId.isEmpty) return [];

    final List<Song> tracks = [];
    try {
      final pId = PlaylistId(playlistId);
      final videoStream = _yt.playlists.getVideos(pId);
      await for (final video in videoStream.take(limit)) {
        final cleanAuthor = ArtistSanitizer.extractArtistFromVideo(video.title, video.author);
        final highThumb = video.thumbnails.highResUrl;
        final safeThumb = (highThumb.isNotEmpty && highThumb.startsWith('http'))
            ? (highThumb.startsWith('http://') ? highThumb.replaceFirst('http://', 'https://') : highThumb)
            : 'https://img.youtube.com/vi/${video.id.value}/hqdefault.jpg';

        tracks.add(Song(
          id: video.id.value,
          title: cleanTitle(video.title),
          artist: Song.sanitize(cleanAuthor),
          album: 'YouTube Playlist',
          coverUrl: safeThumb,
          duration: video.duration?.inSeconds ?? 0,
          source: 'youtube',
        ));
      }
    } catch (e, st) {
      AppLogger.recordError(e, st, context: 'YouTubeClient.getPlaylistTracks("$playlistId")');
    }
    return tracks;
  }

  static int _parseDurationMs(String? text) {
    if (text == null || text.trim().isEmpty) return 0;
    final parts = text.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return ((m * 60) + s) * 1000;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return ((h * 3600) + (m * 60) + s) * 1000;
    }
    return 0;
  }

  /// Parses YouTube InnerTube WEB response into strongly typed [TrackEntity] list
  /// by recursively scanning all nodes for maps containing a "videoRenderer" key.
  static List<TrackEntity> _parseWebSearchResponse(Map<String, dynamic> data, {int limit = 15}) {
    final List<TrackEntity> tracks = [];
    final Set<String> seenIds = {};

    void walkNode(dynamic node) {
      if (node == null || tracks.length >= limit) return;

      if (node is Map<String, dynamic>) {
        if (node.containsKey('videoRenderer')) {
          final vr = node['videoRenderer'];
          if (vr is Map<String, dynamic>) {
            final videoId = vr['videoId']?.toString() ?? '';
            if (videoId.isNotEmpty && !seenIds.contains(videoId)) {
              seenIds.add(videoId);

              final rawTitle = vr['title']?['runs']?[0]?['text']?.toString() ??
                  vr['title']?['simpleText']?.toString() ??
                  '';
              final rawArtist = vr['ownerText']?['runs']?[0]?['text']?.toString() ??
                  vr['longBylineText']?['runs']?[0]?['text']?.toString() ??
                  vr['shortBylineText']?['runs']?[0]?['text']?.toString() ??
                  'YouTube Music';
              final durSimple = vr['lengthText']?['simpleText']?.toString();
              final durationMs = _parseDurationMs(durSimple);
              final durationSec = durationMs ~/ 1000;
              final imageUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

              final cleanAuthor = ArtistSanitizer.extractArtistFromVideo(rawTitle, rawArtist);

              // Filter on the RAW title: cleanTitle() strips words such as
              // "trailer" and bracketed tags like "[Review]" that we need to see.
              if (!_looksLikeNonMusic(rawTitle)) {
                tracks.add(TrackEntity(
                  id: videoId,
                  title: cleanTitle(rawTitle),
                  artist: Song.sanitize(cleanAuthor.isNotEmpty ? cleanAuthor : rawArtist),
                  album: 'YouTube Music',
                  coverUrl: imageUrl,
                  duration: durationSec,
                  streamUrl: '',
                  source: 'youtube',
                ));
              }
            }
          }
        }
        for (final val in node.values) {
          walkNode(val);
          if (tracks.length >= limit) return;
        }
      } else if (node is List) {
        for (final elem in node) {
          walkNode(elem);
          if (tracks.length >= limit) return;
        }
      }
    }

    walkNode(data);
    return tracks;
  }

  // ── YouTube Music "Songs" search (the same shelf the YT Music app shows) ──
  // `params` is the Songs-filter token used by YouTube Music itself. Using it
  // means results are real tracks only - no reviews, reactions or audiobooks.
  static const String _musicSongsFilterParams = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';
  static final RegExp _durationText = RegExp(r'^\d{1,2}(:\d{2}){1,2}$');
  static const Set<String> _musicTypeLabels = {
    'song', 'video', 'album', 'single', 'ep', 'playlist', 'podcast', 'episode', 'artist',
  };

  static int _parseDurationSec(String text) => _parseDurationMs(text) ~/ 1000;

  static TrackEntity? _trackFromMusicListItem(Map item) {
    String videoId = item['playlistItemData']?['videoId']?.toString() ?? '';
    if (videoId.isEmpty) {
      videoId = item['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
              ?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId']
              ?.toString() ??
          '';
    }
    if (videoId.length != 11) return null;

    final flex = item['flexColumns'];
    if (flex is! List || flex.isEmpty) return null;

    List runsOf(int i) {
      if (i >= flex.length) return const [];
      final r = flex[i]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
      return r is List ? r : const [];
    }

    final titleRuns = runsOf(0);
    final title = titleRuns.map((r) => r is Map ? (r['text']?.toString() ?? '') : '').join('').trim();
    if (title.isEmpty) return null;

    // Skip podcasts / episodes outright.
    String? videoType;
    if (titleRuns.isNotEmpty && titleRuns[0] is Map) {
      final endpoint = titleRuns[0]['navigationEndpoint'];
      if (endpoint is Map) {
        final watch = endpoint['watchEndpoint'];
        if (watch is Map) {
          final supported = watch['watchEndpointMusicSupportedConfigs'];
          if (supported is Map) {
            final config = supported['watchEndpointMusicConfig'];
            if (config is Map) {
              videoType = config['musicVideoType']?.toString();
            }
          }
        }
      }
    }
    if (videoType != null && videoType.contains('PODCAST')) return null;

    // Second column looks like: Artist • Album • 3:45   (runs separated by " • ")
    final segments = <String>[];
    var current = StringBuffer();
    for (final r in runsOf(1)) {
      final t = r is Map ? (r['text']?.toString() ?? '') : '';
      if (t.trim() == '•') {
        if (current.isNotEmpty) segments.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(t);
      }
    }
    if (current.isNotEmpty) segments.add(current.toString().trim());

    int durationSec = 0;
    final details = <String>[];
    for (final seg in segments) {
      if (seg.isEmpty) continue;
      if (_durationText.hasMatch(seg)) {
        durationSec = _parseDurationSec(seg);
      } else if (!_musicTypeLabels.contains(seg.toLowerCase())) {
        details.add(seg);
      }
    }
    // Real songs only: reject very long items (mixes, audiobooks) and clips.
    if (durationSec > 0 && (durationSec < 30 || durationSec > 15 * 60)) return null;

    final artist = details.isNotEmpty ? details[0] : '';
    final album = details.length > 1 ? details[1] : 'YouTube Music';

    var cover = '';
    final thumbs = item['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'];
    if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
      cover = thumbs.last['url']?.toString() ?? '';
    }
    if (cover.contains('googleusercontent.com')) {
      // Upgrade the tiny 60px art to a crisp 544px square.
      cover = cover.replaceFirst(RegExp(r'=w\d+-h\d+.*$'), '=w544-h544-l90-rj');
    }
    if (cover.isEmpty || !cover.startsWith('http')) {
      cover = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }

    return TrackEntity(
      id: videoId,
      title: Song.sanitize(title),
      artist: Song.sanitize(artist.isNotEmpty ? artist : 'YouTube Music'),
      album: Song.sanitize(album),
      coverUrl: cover,
      duration: durationSec,
      streamUrl: '',
      source: 'youtube',
    );
  }

  static List<TrackEntity> _parseMusicSearchResponse(dynamic data, {int limit = 15}) {
    final tracks = <TrackEntity>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (node == null || tracks.length >= limit) return;
      if (node is Map) {
        final item = node['musicResponsiveListItemRenderer'];
        if (item is Map) {
          final t = _trackFromMusicListItem(item);
          if (t != null && seen.add(t.id)) tracks.add(t);
        }
        for (final entry in node.entries) {
          if (entry.key == 'musicResponsiveListItemRenderer') continue;
          walk(entry.value);
          if (tracks.length >= limit) return;
        }
      } else if (node is List) {
        for (final elem in node) {
          walk(elem);
          if (tracks.length >= limit) return;
        }
      }
    }

    walk(data);
    return tracks;
  }

  static Future<List<TrackEntity>> _searchYouTubeMusicSongs(String query, {int limit = 15}) async {
    final uri = Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false');
    final payload = jsonEncode({
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20260707.12.00',
          'gl': 'IN',
          'hl': 'en',
        }
      },
      'query': query,
      'params': _musicSongsFilterParams,
    });

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
        'Accept': '*/*',
      },
      body: payload,
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      AppLogger.log('YouTubeClient', 'YT Music songs search HTTP ${response.statusCode} for "$query"');
      return [];
    }
    return _parseMusicSearchResponse(jsonDecode(response.body), limit: limit);
  }

  /// Keeps only things that look like songs and ranks official audio first
  /// ("- Topic" auto-generated channels, VEVO, labels) while preserving the
  /// original relevance order inside each tier.
  static List<TrackEntity> _filterAndRankSongs(List<TrackEntity> input, {int limit = 15}) {
    final indexed = <MapEntry<int, TrackEntity>>[];
    for (var i = 0; i < input.length; i++) {
      final t = input[i];
      if (_looksLikeNonMusic(t.title)) continue;
      // Plain video search: no duration (live/unknown) or very long = not a song.
      if (t.duration < 60 || t.duration > 10 * 60) continue;
      indexed.add(MapEntry(i, t));
    }

    int score(TrackEntity t) {
      final a = t.artist.toLowerCase();
      if (a.endsWith('- topic')) return 3;
      if (a.contains('vevo') || a.contains('records') || a.contains('music') || a.contains('official')) return 2;
      return 1;
    }

    indexed.sort((a, b) {
      final byScore = score(b.value).compareTo(score(a.value));
      return byScore != 0 ? byScore : a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).take(limit).toList();
  }

  /// Direct client-side search that behaves like the YouTube Music app:
  /// 1. YouTube Music "Songs" shelf (real tracks only)
  /// 2. Plain YouTube search, filtered to song-length, non-review content
  /// 3. youtube_explode search, filtered the same way
  /// 4. JioSaavn as a last resort so the chip never shows an empty list
  static Future<List<TrackEntity>> searchTracks(String query, {int limit = 15}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    // 1) YouTube Music Songs shelf
    try {
      final musicTracks = await _searchYouTubeMusicSongs(clean, limit: limit);
      if (musicTracks.isNotEmpty) {
        return musicTracks;
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'YT Music songs search notice for "$clean": $e');
    }

    // 2) Plain YouTube WEB search (needs filtering - it returns reviews, audiobooks, etc.)
    try {
      final uri = Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false');
      final payload = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20260708.00.00',
            'gl': 'IN',
            'hl': 'en',
          }
        },
        'query': clean,
      });

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.youtube.com/',
          'Accept': '*/*',
        },
        body: payload,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          // Parse a wider window, then filter down to `limit` real songs.
          final raw = _parseWebSearchResponse(data, limit: limit * 3);
          final tracks = _filterAndRankSongs(raw, limit: limit);
          if (tracks.isNotEmpty) {
            return tracks;
          }
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'InnerTube WEB search notice for "$clean": $e.');
    }

    // 3) youtube_explode fallback (same filtering)
    try {
      final searchResults = await _yt.search.search(clean).timeout(const Duration(seconds: 8));
      final List<TrackEntity> ytExplodeTracks = [];
      for (final video in searchResults.take(limit * 3)) {
        if (_looksLikeNonMusic(video.title)) continue; // raw title, before cleanTitle()
        final rawAuthor = video.author;
        final cleanAuthor = ArtistSanitizer.extractArtistFromVideo(video.title, rawAuthor);
        final highThumb = video.thumbnails.highResUrl;
        final safeThumb = (highThumb.isNotEmpty && highThumb.startsWith('http'))
            ? (highThumb.startsWith('http://') ? highThumb.replaceFirst('http://', 'https://') : highThumb)
            : 'https://img.youtube.com/vi/${video.id.value}/hqdefault.jpg';

        ytExplodeTracks.add(TrackEntity(
          id: video.id.value,
          title: cleanTitle(video.title),
          artist: Song.sanitize(cleanAuthor),
          album: 'YouTube Music',
          coverUrl: safeThumb,
          duration: video.duration?.inSeconds ?? 0,
          streamUrl: '',
          source: 'youtube',
        ));
      }
      final filtered = _filterAndRankSongs(ytExplodeTracks, limit: limit);
      if (filtered.isNotEmpty) {
        return filtered;
      }
    } catch (_) {}

    // 4) FALLBACK GUARANTEE: never show "No results found" for valid queries like "Anirudh".
    try {
      final saavnMatches = await SaavnClient.search(clean, limit: limit);
      if (saavnMatches.isNotEmpty) {
        return saavnMatches.map((s) => TrackEntity(
          id: s.id,
          title: s.title,
          artist: s.artist,
          album: s.album,
          albumId: s.albumId,
          artistId: s.artistId,
          coverUrl: s.coverUrl,
          streamUrl: s.streamUrl ?? '',
          duration: s.duration,
          source: 'youtube',
        )).toList();
      }
    } catch (fallbackErr) {
      AppLogger.log('YouTubeClient', 'SaavnClient search fallback notice: $fallbackErr');
    }

    return [];
  }

  /// Primary search returning [Song] instances for app-wide player and queue compatibility.
  static Future<List<Song>> search(String query, {int limit = 15}) async {
    final tracks = await searchTracks(query, limit: limit);
    if (tracks.isNotEmpty) {
      return tracks.map((t) => t.toSong()).toList();
    }
    try {
      final saavnSongs = await SaavnClient.search(query, limit: limit);
      return saavnSongs.map((s) => s.copyWith(source: 'youtube')).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches YouTube Music trending highlights for the specified language.
  static Future<List<Song>> getTrendingTracks({String language = 'Tamil', int limit = 15}) async {
    final query = '$language trending music songs';
    final songs = await search(query, limit: limit);
    final filtered = SongRepository.filterByLanguage(songs, language);
    return filtered.isNotEmpty ? filtered : songs;
  }

  /// Direct client-side YouTube Music InnerTube Next endpoint:
  /// `POST https://music.youtube.com/youtubei/v1/next`
  /// with `videoId: videoId` and `playlistId: "RDAMVM$videoId"`.
  /// Extracts authentic YT Music Up-Next automix tracks directly from `musicQueueRenderer`.
  static Future<List<Song>> getUpNextAutomix(String videoId, {int limit = 50}) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return [];

    try {
      final uri = Uri.parse('https://music.youtube.com/youtubei/v1/next');
      final payload = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20260101.01.00',
            'gl': 'IN',
            'hl': 'en',
          }
        },
        'videoId': cleanId,
        'playlistId': 'RDAMVM$cleanId',
      });

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://music.youtube.com/',
          'Accept': '*/*',
        },
        body: payload,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          final tabs = data['contents']?['singleColumnMusicWatchNextResultsRenderer']
              ?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs'] as List<dynamic>? ?? [];

          for (final tab in tabs) {
            final content = tab['tabRenderer']?['content'];
            if (content != null && content['musicQueueRenderer'] != null) {
              final queueItems = content['musicQueueRenderer']?['content']
                  ?['playlistPanelRenderer']?['contents'] as List<dynamic>? ?? [];

              final List<Song> automixSongs = [];
              for (final item in queueItems) {
                if (automixSongs.length >= limit) break;
                final v = item['playlistPanelVideoRenderer'] as Map<String, dynamic>?;
                if (v == null) continue;

                final vId = v['videoId']?.toString() ?? '';
                if (vId.isEmpty || vId == cleanId) continue;

                final titleRuns = v['title']?['runs'] as List<dynamic>? ?? [];
                final title = titleRuns.map((r) => r['text']?.toString() ?? '').join('').trim();

                final bylineRuns = v['longBylineText']?['runs'] as List<dynamic>? ??
                    v['shortBylineText']?['runs'] as List<dynamic>? ?? [];
                final fullByline = bylineRuns.map((r) => r['text']?.toString() ?? '').join('').trim();
                final rawArtist = fullByline.split('•').first.trim();
                final cleanArtist = ArtistSanitizer.extractArtistFromVideo(title, rawArtist);

                final lenRuns = v['lengthText']?['runs'] as List<dynamic>? ?? [];
                final lenStr = lenRuns.isNotEmpty ? lenRuns[0]['text']?.toString() ?? '' : '';
                int durationSec = 0;
                if (lenStr.isNotEmpty && lenStr.contains(':')) {
                  final parts = lenStr.split(':');
                  if (parts.length == 2) {
                    final m = int.tryParse(parts[0]) ?? 0;
                    final s = int.tryParse(parts[1]) ?? 0;
                    durationSec = (m * 60) + s;
                  } else if (parts.length == 3) {
                    final h = int.tryParse(parts[0]) ?? 0;
                    final m = int.tryParse(parts[1]) ?? 0;
                    final s = int.tryParse(parts[2]) ?? 0;
                    durationSec = (h * 3600) + (m * 60) + s;
                  }
                }

                final thumbs = v['thumbnail']?['thumbnails'] as List<dynamic>? ?? [];
                String thumbUrl = '';
                if (thumbs.isNotEmpty) {
                  thumbUrl = thumbs.last['url']?.toString() ?? '';
                }
                if (thumbUrl.isEmpty || !thumbUrl.startsWith('http')) {
                  thumbUrl = 'https://img.youtube.com/vi/$vId/hqdefault.jpg';
                }

                if (title.isNotEmpty) {
                  automixSongs.add(Song(
                    id: vId,
                    title: cleanTitle(title),
                    artist: Song.sanitize(cleanArtist.isNotEmpty ? cleanArtist : 'Artist'),
                    album: 'YouTube Music',
                    coverUrl: thumbUrl,
                    duration: durationSec,
                    source: 'youtube',
                  ));
                }
              }

              if (automixSongs.isNotEmpty) {
                AppLogger.log('YouTubeClient', 'InnerTube Up-Next automix yielded ${automixSongs.length} tracks for video $cleanId');
                return automixSongs;
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'InnerTube Up-Next automix notice: $e');
    }
    return [];
  }

  /// Walks the native YouTube Radio graph (RDAMVM$videoId) and applies Audio-First Master Filtering:
  /// - Topic channel prioritization (- Topic, VEVO, official release metadata)
  /// - Excludes live recordings and fan covers
  /// - Excludes tracks with significant duration deviations (<60s, >600s, or >120s delta from seed)
  /// - Filters out skipped artists/keys (skip reactivity)
  static Future<List<Song>> getRadioTracks(
    Song seedSong, {
    int limit = 20,
    Set<String>? excludedArtists,
    Set<String>? excludedKeys,
  }) async {
    final List<Song> results = [];
    try {
      String? seedVideoId;
      if (seedSong.source == 'youtube' && seedSong.id.isNotEmpty) {
        seedVideoId = seedSong.id;
      } else {
        // Resolve seed song to YouTube video ID via search
        final query = '${cleanTitle(seedSong.title)} ${seedSong.primaryArtist} audio';
        final searchResults = await search(query, limit: 5);
        if (searchResults.isNotEmpty) {
          final topic = searchResults.firstWhere(
            (s) => s.artist.endsWith(' - Topic') || s.artist.toLowerCase().contains('topic'),
            orElse: () => searchResults.first,
          );
          seedVideoId = topic.id;
        }
      }

      if (seedVideoId != null && seedVideoId.isNotEmpty) {
        // 0. Primary: InnerTube Next API with playlistId="RDAMVM$seedVideoId"
        try {
          final automix = await getUpNextAutomix(seedVideoId, limit: limit * 2);
          for (final song in automix) {
            if (excludedKeys != null && (excludedKeys.contains(song.id) || excludedKeys.contains(song.cleanTitleKey))) {
              continue;
            }
            if (excludedArtists != null && excludedArtists.contains(song.primaryArtist.toLowerCase().trim())) {
              continue;
            }
            if (!results.any((r) => r.id == song.id || r.canonicalBaseKey == song.canonicalBaseKey)) {
              results.add(song.copyWith(language: seedSong.language));
              if (results.length >= limit) break;
            }
          }
        } catch (e) {
          AppLogger.log('YouTubeClient', 'InnerTube automix in getRadioTracks notice: $e');
        }

        if (results.length >= limit) {
          return results;
        }

        final List<Video> candidateVideos = [];

        // 1. Fallback Radio Graph Walking: Native Related Videos of seed
        try {
          final video = await _yt.videos.get(VideoId(seedVideoId)).timeout(const Duration(seconds: 8));
          final related = await _yt.videos.getRelatedVideos(video).timeout(const Duration(seconds: 8));
          if (related != null) {
            candidateVideos.addAll(related);
          }
        } catch (e) {
          AppLogger.log('YouTubeClient', 'Radio graph initial step notice: $e');
        }

        // 2. Second-tier walk: If candidate count is low, walk the graph one step deeper
        if (candidateVideos.length < limit && candidateVideos.isNotEmpty) {
          try {
            final nextNode = candidateVideos.firstWhere(
              (v) => v.author.endsWith(' - Topic'),
              orElse: () => candidateVideos.first,
            );
            final deeper = await _yt.videos.getRelatedVideos(nextNode).timeout(const Duration(seconds: 8));
            if (deeper != null) {
              for (final dv in deeper) {
                if (!candidateVideos.any((cv) => cv.id.value == dv.id.value)) {
                  candidateVideos.add(dv);
                }
              }
            }
          } catch (_) {}
        }

        // 3. Audio-First Master Filtering:
        final liveRegex = RegExp(r'\b(live|unplugged|in concert|concert|live at|live from)\b', caseSensitive: false);
        final coverRegex = RegExp(r'\b(cover|fan made|tribute|karaoke|acoustic cover|cover song)\b', caseSensitive: false);

        // Score and filter candidate videos
        final List<MapEntry<int, Song>> scoredCandidates = [];

        for (final video in candidateVideos) {
          final vId = video.id.value;
          final title = video.title;
          final author = video.author;
          final dur = video.duration?.inSeconds ?? 0;

          // Duration sanity check: 60s to 600s
          if (dur < 60 || dur > 600) continue;

          // Duration delta check: if seed has valid duration, reject if > 120s delta
          if (seedSong.duration >= 60 && (dur - seedSong.duration).abs() > 120) {
            continue;
          }

          // Exclude live recordings
          if (liveRegex.hasMatch(title)) continue;

          // Exclude fan covers
          if (coverRegex.hasMatch(title)) continue;

          // Exclude reviews, reactions, audiobooks, trailers, interviews...
          if (_looksLikeNonMusic(title)) continue;

          final cleanedTitle = cleanTitle(title);
          final cleanedAuthor = Song.sanitize(ArtistSanitizer.extractArtistFromVideo(title, author));

          if (excludedKeys != null && excludedKeys.contains(vId)) continue;
          final songObj = Song(
            id: vId,
            title: cleanedTitle,
            artist: cleanedAuthor,
            album: 'YouTube Music',
            coverUrl: video.thumbnails.highResUrl,
            duration: dur,
            source: 'youtube',
            language: seedSong.language,
          );

          if (excludedKeys != null && excludedKeys.contains(songObj.cleanTitleKey)) continue;
          if (excludedArtists != null && excludedArtists.contains(songObj.primaryArtist.toLowerCase().trim())) {
            continue;
          }

          // Scoring:
          // Priority 3: Topic channel
          // Priority 2: VEVO / Official label
          // Priority 1: Other
          int priority = 1;
          final authorLower = author.toLowerCase();
          if (author.endsWith(' - Topic') || authorLower.contains('release - topic')) {
            priority = 3;
          } else if (authorLower.endsWith('vevo') || authorLower.contains('official') || title.toLowerCase().contains('official')) {
            priority = 2;
          }

          scoredCandidates.add(MapEntry(priority, songObj));
        }

        // Sort by priority descending
        scoredCandidates.sort((a, b) => b.key.compareTo(a.key));

        for (final entry in scoredCandidates) {
          if (!results.any((r) => r.id == entry.value.id || r.canonicalBaseKey == entry.value.canonicalBaseKey)) {
            results.add(entry.value);
            if (results.length >= limit) break;
          }
        }
      }
    } catch (e, st) {
      AppLogger.recordError(e, st, context: 'YouTubeClient.getRadioTracks');
    }

    // Fallback: If results are still empty or small, supplement with getRelatedSongs
    if (results.length < limit) {
      final relatedFallback = await getRelatedSongs(seedSong, limit: limit);
      for (final s in relatedFallback) {
        if (!results.any((r) => r.id == s.id || r.canonicalBaseKey == s.canonicalBaseKey)) {
          results.add(s);
          if (results.length >= limit) break;
        }
      }
    }

    return results;
  }

  /// Fetches related YouTube Music autoplay tracks for a seed song
  static Future<List<Song>> getRelatedSongs(Song seedSong, {int limit = 10}) async {
    final List<Song> songs = [];
    try {
      // 1. If seed song is a YouTube video, attempt native related videos
      if (seedSong.source == 'youtube' && seedSong.id.isNotEmpty) {
        final video = await _yt.videos.get(VideoId(seedSong.id)).timeout(const Duration(seconds: 8));
        final related = await _yt.videos.getRelatedVideos(video).timeout(const Duration(seconds: 8));
        if (related != null) {
          for (final relVideo in related.take(limit)) {
            final dur = relVideo.duration?.inSeconds ?? 0;
            // Only keep sensible song durations (60s to 600s), and never reviews/reactions
            if (dur >= 60 && dur <= 600 && !_looksLikeNonMusic(relVideo.title)) {
              songs.add(Song(
                id: relVideo.id.value,
                title: cleanTitle(relVideo.title),
                artist: Song.sanitize(relVideo.author),
                album: 'YouTube Music',
                coverUrl: relVideo.thumbnails.highResUrl,
                duration: dur,
                source: 'youtube',
                language: seedSong.language,
              ));
            }
          }
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'YouTube related tracks notice: $e');
    }

    // 2. Search YouTube for contextual radio mix
    if (songs.length < limit) {
      try {
        final query = '${cleanTitle(seedSong.title)} ${seedSong.primaryArtist} audio';
        final searchResults = await search(query, limit: limit);
        for (final s in searchResults) {
          if (s.id != seedSong.id && !songs.any((x) => x.id == s.id)) {
            songs.add(s.copyWith(language: seedSong.language));
            if (songs.length >= limit) break;
          }
        }
      } catch (_) {}
    }

    return songs;
  }

  // In-memory stream cache with 3-hour TTL (Spotify & YouTube Music CDN rotation model)
  static final Map<String, _CachedAudioStream> _streamCache = {};

  /// Invalidates cached stream URL for a given video ID (called when playback fails or 403 Forbidden is returned)
  static void invalidateStream(String videoId) {
    final cleanId = videoId.trim();
    if (cleanId.isNotEmpty) {
      _streamCache.remove(cleanId);
      AppLogger.log('YouTubeClient', 'Invalidated stream cache for $cleanId');
    }
  }

  /// Visitor id that YouTube returns in every response. Re-sent on later
  /// requests so they look like one continuous session.
  static String? _visitorData;

  /// Public probe kept for compatibility. True only when the CDN accepts the URL.
  static Future<bool> probeStreamUrl(String url) async =>
      (await _probe(url, userAgentForUrl(url))) == _ProbeResult.ok;

  /// Probes a stream URL with the User-Agent of the client that issued it.
  ///
  /// IMPORTANT: only a definite refusal (401/403/404/410) rejects a URL.
  /// A timeout or network hiccup is "unknown" - on a mobile connection a 2s
  /// probe used to throw away perfectly good URLs and cause "song unavailable".
  static Future<_ProbeResult> _probe(String url, String userAgent) async {
    if (url.isEmpty) return _ProbeResult.forbidden;
    final isManifest = url.contains('.m3u8') || url.contains('hls_playlist') || url.contains('hls_variant');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = userAgent;
      req.headers['Accept'] = '*/*';
      if (!isManifest) req.headers['Range'] = 'bytes=0-1';
      final res = await client.send(req).timeout(const Duration(seconds: 6));
      final code = res.statusCode;
      if (code == 200 || code == 206) return _ProbeResult.ok;
      if (code == 401 || code == 403 || code == 404 || code == 410) {
        AppLogger.log('YouTubeClient', 'Stream probe REJECTED: HTTP $code (${_hostOf(url)})');
        return _ProbeResult.forbidden;
      }
      AppLogger.log('YouTubeClient', 'Stream probe inconclusive: HTTP $code (${_hostOf(url)})');
      return _ProbeResult.unknown;
    } catch (e) {
      AppLogger.log('YouTubeClient', 'Stream probe inconclusive (${_hostOf(url)}): $e');
      return _ProbeResult.unknown;
    } finally {
      client.close();
    }
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return 'unknown-host';
    }
  }

  /// InnerTube clients tried in order. Each one carries ITS OWN User-Agent,
  /// which must also be used by the probe and by the audio player.
  ///
  /// Why this order (YouTube now gates most audio-only URLs behind a PO token
  /// for several clients, so a single hard-coded client stops working):
  ///  1. VISIONOS    - currently the JS-less default of yt-dlp, no PO token policy
  ///  2. ANDROID_VR  - the old default; still works on some videos/regions
  ///  3. ANDROID     - without androidSdkVersion (same trick youtube_explode_dart uses)
  ///  4. IOS         - last resort (HLS manifest)
  static final List<Map<String, dynamic>> _innertubePlayerConfigs = [
    {
      'name': 'VISIONOS',
      'userAgent': visionOsUserAgent,
      'clientNameId': '101',
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'userAgent': visionOsUserAgent,
        'gl': 'IN',
        'hl': 'en',
      },
    },
    {
      'name': 'ANDROID_VR',
      'userAgent': vrUserAgent,
      'clientNameId': '28',
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.56.21',
        'androidSdkVersion': 32,
        'gl': 'IN',
        'hl': 'en',
      },
    },
    {
      'name': 'ANDROID',
      'userAgent': androidUserAgent,
      'clientNameId': '3',
      'client': {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.38',
        'userAgent': androidUserAgent,
        'osName': 'Android',
        'osVersion': '11',
        'gl': 'IN',
        'hl': 'en',
      },
    },
    {
      'name': 'IOS',
      'userAgent': iosUserAgent,
      'clientNameId': '5',
      'client': {
        'clientName': 'IOS',
        'clientVersion': '19.45.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone14,3',
        'osName': 'iOS',
        'osVersion': '17.5.0.21F79',
        'gl': 'IN',
        'hl': 'en',
      },
    },
  ];

  /// Calls the InnerTube `player` endpoint as [config]'s client.
  /// Returns null on transport errors / wrong-video responses.
  static Future<Map<String, dynamic>?> _fetchPlayerResponse(Map<String, dynamic> config, String videoId) async {
    final name = config['name'] as String;
    final clientCtx = Map<String, dynamic>.from(config['client'] as Map);
    final visitor = _visitorData;
    if (visitor != null && visitor.isNotEmpty) clientCtx['visitorData'] = visitor;

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': config['userAgent'] as String,
      'X-YouTube-Client-Name': config['clientNameId'] as String,
      'X-YouTube-Client-Version': clientCtx['clientVersion'].toString(),
      'Origin': 'https://www.youtube.com',
      'Accept': '*/*',
      if (visitor != null && visitor.isNotEmpty) 'X-Goog-Visitor-Id': visitor,
    };

    final payload = jsonEncode({
      'context': {'client': clientCtx},
      'videoId': videoId,
      'playbackContext': {
        'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    });

    final response = await http
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
          headers: headers,
          body: payload,
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      AppLogger.log('YouTubeClient', '[$name] player HTTP ${response.statusCode} for $videoId');
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final vd = decoded['responseContext']?['visitorData'];
    if (vd is String && vd.isNotEmpty) _visitorData ??= vd;

    // YouTube sometimes answers with a different video; never trust that.
    final returnedId = decoded['videoDetails']?['videoId']?.toString();
    if (returnedId != null && returnedId.isNotEmpty && returnedId != videoId) {
      AppLogger.log('YouTubeClient', '[$name] returned wrong video ($returnedId != $videoId)');
      return null;
    }

    final status = decoded['playabilityStatus']?['status']?.toString();
    if (status != 'OK') {
      final reason = decoded['playabilityStatus']?['reason']?.toString() ?? '';
      AppLogger.log('YouTubeClient', '[$name] playability=$status $reason');
    }
    return decoded;
  }

  /// Ordered candidate URLs from a player response's `streamingData`:
  /// audio-only (preferred quality first) -> muxed MP4 (e.g. itag 18) -> HLS.
  static List<String> _candidateUrlsFromStreamingData(Map<String, dynamic> streamingData) {
    final out = <String>[];
    void add(String? u) {
      if (u != null && u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    final audioFormats = <Map>[];
    final adaptive = streamingData['adaptiveFormats'];
    if (adaptive is List) {
      for (final f in adaptive) {
        if (f is! Map) continue;
        final mime = f['mimeType']?.toString().toLowerCase() ?? '';
        if (!mime.startsWith('audio/')) continue;
        // Skip auto-dubbed languages - we want the original audio.
        final track = f['audioTrack'];
        if (track is Map && track['audioIsDefault'] == false) continue;
        audioFormats.add(f);
      }
    }
    audioFormats.sort((a, b) {
      final bb = (b['bitrate'] as num?) ?? 0;
      final ab = (a['bitrate'] as num?) ?? 0;
      return bb.compareTo(ab);
    });

    final quality = SettingsManager.streamingQuality;
    if (quality == '96kbps') {
      for (final f in audioFormats.reversed) {
        final br = (f['bitrate'] as num?)?.toInt() ?? 0;
        if (br > 0 && br <= 100000) {
          add(f['url']?.toString());
          break;
        }
      }
    }
    // AAC 140 (128kbps m4a) first for universal hardware decoding, then Opus 251.
    for (final f in audioFormats) {
      if (f['itag'] == 140) {
        add(f['url']?.toString());
        break;
      }
    }
    for (final f in audioFormats) {
      if (f['itag'] == 251) {
        add(f['url']?.toString());
        break;
      }
    }
    for (final f in audioFormats) {
      add(f['url']?.toString());
    }

    // Muxed progressive MP4 (itag 18, 360p + AAC). Heavier, but it is the format
    // YouTube still serves without a PO token on several clients, so it keeps
    // songs playable when every audio-only URL is refused.
    final muxed = streamingData['formats'];
    if (muxed is List) {
      for (final f in muxed) {
        if (f is Map) add(f['url']?.toString());
      }
    }

    add(streamingData['hlsManifestUrl']?.toString());
    return out;
  }

  /// Tier 1: query every InnerTube client in turn; return the first URL the CDN
  /// verifiably accepts. If none is verified but some were merely inconclusive
  /// (timeouts), return the first inconclusive one instead of failing.
  static Future<String?> _resolveDirectInnertubeStream(String cleanId) async {
    final sw = Stopwatch()..start();
    String? softUrl;
    String? softUa;

    for (final config in _innertubePlayerConfigs) {
      if (sw.elapsed > const Duration(seconds: 14)) {
        AppLogger.log('YouTubeClient', 'InnerTube tier time budget exhausted for $cleanId');
        break;
      }
      final name = config['name'] as String;
      final ua = config['userAgent'] as String;
      try {
        final data = await _fetchPlayerResponse(config, cleanId);
        if (data == null) continue;

        final streamingData = data['streamingData'];
        if (streamingData is! Map<String, dynamic>) {
          AppLogger.log('YouTubeClient', '[$name] no streamingData for $cleanId');
          continue;
        }

        final candidates = _candidateUrlsFromStreamingData(streamingData);
        AppLogger.log('YouTubeClient', '[$name] ${candidates.length} candidate URL(s) for $cleanId');

        var probed = 0;
        for (final candidate in candidates) {
          if (probed >= 3) break; // keep worst-case latency bounded
          probed++;
          final result = await _probe(candidate, ua);
          if (result == _ProbeResult.ok) {
            _rememberUserAgent(candidate, ua);
            AppLogger.log('YouTubeClient', '[$name] stream verified for $cleanId');
            return candidate;
          }
          if (result == _ProbeResult.unknown && softUrl == null) {
            softUrl = candidate;
            softUa = ua;
          }
        }
      } catch (e) {
        AppLogger.log('YouTubeClient', '[$name] resolution notice for $cleanId: $e');
      }
    }

    if (softUrl != null && softUa != null) {
      _rememberUserAgent(softUrl, softUa);
      AppLogger.log('YouTubeClient', 'Using unverified (probe inconclusive) stream for $cleanId');
      return softUrl;
    }
    return null;
  }

  /// Resolves an audio stream for [cleanId].
  /// Tier 1: InnerTube client waterfall. Tier 2: youtube_explode_dart.
  /// Returns null only if every YouTube route is refused, so the StreamResolver
  /// can fall back to a matching JioSaavn track.
  static Future<String?> _resolveAndVerifyStream(String cleanId) async {
    // ── Tier 1 ────────────────────────────────────────────────────────
    final directUrl = await _resolveDirectInnertubeStream(cleanId);
    if (directUrl != null && directUrl.isNotEmpty) {
      return directUrl;
    }

    // ── Tier 2: youtube_explode_dart ──────────────────────────────────
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        StreamManifest? manifest;
        try {
          manifest = await _yt.videos.streamsClient.getManifest(
            cleanId,
            requireWatchPage: false,
          ).timeout(const Duration(seconds: 10));
        } catch (fastErr) {
          AppLogger.log('YouTubeClient', 'Fast manifest extraction notice for $cleanId: $fastErr. Falling back to full extraction.');
          manifest = await _yt.videos.streamsClient.getManifest(
            cleanId,
            requireWatchPage: true,
          ).timeout(const Duration(seconds: 14));
        }

        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          AudioStreamInfo? chosenStream;
          final quality = SettingsManager.streamingQuality;

          if (quality == '96kbps') {
            for (final s in audioStreams) {
              if (s.bitrate.kiloBitsPerSecond <= 100) {
                chosenStream = s;
                break;
              }
            }
          }

          if (chosenStream == null) {
            for (final s in audioStreams) {
              if (s.tag == 140) {
                chosenStream = s;
                break;
              }
            }
          }

          if (chosenStream == null) {
            for (final s in audioStreams) {
              if (s.tag == 251) {
                chosenStream = s;
                break;
              }
            }
          }

          if (chosenStream == null) {
            for (final s in audioStreams) {
              if (s.container.name.toLowerCase().contains('mp4') || s.container.name.toLowerCase().contains('m4a')) {
                chosenStream = s;
                break;
              }
            }
          }

          chosenStream ??= audioStreams.withHighestBitrate();
          final url = chosenStream.url.toString();

          // youtube_explode_dart's default client is the Android (sdk-less) one.
          final probe = await _probe(url, androidUserAgent);
          if (probe != _ProbeResult.forbidden) {
            _rememberUserAgent(url, androidUserAgent);
            AppLogger.log('YouTubeClient', 'YouTubeExplode stream accepted for $cleanId (itag ${chosenStream.tag})');
            return url;
          }
          AppLogger.log('YouTubeClient', 'YouTubeExplode stream refused (403) for $cleanId');
        }
      } catch (e) {
        AppLogger.log('YouTubeClient', 'YouTubeExplode attempt $attempt notice for $cleanId: $e');
        if (attempt == 1) {
          closeIdleClient();
        }
      }
    }

    AppLogger.log('YouTubeClient', 'All YouTube routes refused for $cleanId. Returning null so a matching track can be used instead.');
    return null;
  }

  /// Primary stream resolver for YouTube tracks.
  /// Queries InnerTube (ANDROID_VR & IOS) and YouTubeExplode, verifying via live HTTP probe.
  /// Returns null if all candidates fail or return 403 so StreamResolver triggers Smart Replace.
  static Future<String?> getStreamUrl(String videoId, {String? title, String? artist}) async {
    final cleanId = extractVideoId(videoId) ?? videoId.trim();
    if (cleanId.isEmpty) return null;

    final cached = _streamCache[cleanId];
    if (cached != null && !cached.isExpired) {
      return cached.url;
    }

    final verifiedUrl = await _resolveAndVerifyStream(cleanId);
    if (verifiedUrl != null && verifiedUrl.isNotEmpty) {
      _streamCache[cleanId] = _CachedAudioStream(verifiedUrl, DateTime.now().add(const Duration(hours: 3)));
      return verifiedUrl;
    }

    return null;
  }

  /// Backward-compatible alias for [getStreamUrl]
  static Future<String?> getAudioStreamUrl(String videoId, {String? title, String? artist}) =>
      getStreamUrl(videoId, title: title, artist: artist);


  static void dispose() {
    closeIdleClient();
  }
}

/// Instance wrapper for [YouTubeClient] supporting OOP test and injection workflows.
class YoutubeClient {
  Future<List<Song>> search(String query, {int limit = 15}) => YouTubeClient.search(query, limit: limit);
  Future<List<TrackEntity>> searchTracks(String query, {int limit = 15}) => YouTubeClient.searchTracks(query, limit: limit);
  Future<String?> getStreamUrl(String videoId, {String? title, String? artist}) => YouTubeClient.getStreamUrl(videoId, title: title, artist: artist);
  Future<String?> getAudioStreamUrl(String videoId, {String? title, String? artist}) => YouTubeClient.getAudioStreamUrl(videoId, title: title, artist: artist);
}

class _CachedAudioStream {
  final String url;
  final DateTime expiresAt;
  _CachedAudioStream(this.url, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
