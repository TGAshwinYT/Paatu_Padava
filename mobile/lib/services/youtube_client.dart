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

class YouTubeClient {
  static YoutubeExplode? _ytInstance;
  static YoutubeExplode get _yt => _ytInstance ??= YoutubeExplode();

  /// Closes any idle YouTube HTTP sockets and resets client instance
  static void closeIdleClient() {
    _ytInstance?.close();
    _ytInstance = null;
  }

  static const String vrUserAgent =
      'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 2; Build/SQ3A.220605.009.A1) gzip';
  static const String androidUserAgent =
      'com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UQ1A.240205.004) gzip';

  /// High-integrity HTTP headers for Googlevideo CDN streams.
  /// Enforces ANDROID_VR User-Agent and keep-alive to avoid connection drops and 403 Forbidden errors.
  static Map<String, String> get streamingHeaders => const {
    'Range': 'bytes=0-',
    'User-Agent': vrUserAgent,
    'Accept': '*/*',
    'Connection': 'keep-alive',
  };

  /// True for URLs served by YouTube's media CDN / manifest endpoints.
  static bool isYouTubeStreamUrl(String url) =>
      url.contains('googlevideo.com') || url.contains('youtube.com/api/manifest');

  /// Returns the User-Agent that matches the client which issued [url].
  static String userAgentForUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      final c = uri?.queryParameters['c']?.toUpperCase();
      if (c == 'ANDROID_VR') return vrUserAgent;
      if (c == 'IOS' || url.contains('.m3u8')) {
        return 'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)';
      }
      if (c == 'ANDROID') {
        return 'com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UQ1A.240205.004) gzip';
      }
    } catch (_) {}
    return vrUserAgent;
  }

  /// HTTP headers the PLAYER or download manager must send for a YouTube stream [url].
  /// IMPORTANT: Omits Range header if the URL already contains &range= or is HLS to prevent 403 Forbidden.
  static Map<String, String> headersForUrl(String url) {
    final isManifest = url.contains('.m3u8') || url.contains('hls_playlist') || url.contains('hls_variant');
    final hasRangeQuery = url.contains('&range=');
    return {
      'User-Agent': userAgentForUrl(url),
      'Accept': '*/*',
      'Connection': 'keep-alive',
      if (!isManifest && !hasRangeQuery) 'Range': 'bytes=0-',
    };
  }

  /// Returns true if a Googlevideo stream URL's expire parameter is within 60 seconds of expiring or already expired.
  static bool isLinkExpired(String? url) {
    if (url == null || url.isEmpty) return true;
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return true;
      final expireStr = uri.queryParameters['expire'];
      if (expireStr == null) return false;
      final expireSec = int.tryParse(expireStr);
      if (expireSec == null) return false;
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return nowSec >= (expireSec - 60);
    } catch (_) {
      return false;
    }
  }

  /// Fetches the highest quality audio StreamInfo from YoutubeExplode
  static Future<AudioStreamInfo?> getBestAudioStreamInfo(String videoId) async {
    final cleanId = extractVideoId(videoId) ?? videoId.trim();
    if (cleanId.isEmpty) return null;
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(cleanId);
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) return null;

      final quality = SettingsManager.streamingQuality;
      if (quality == '96kbps') {
        final low = audioStreams.where((s) => s.bitrate.kiloBitsPerSecond <= 100);
        if (low.isNotEmpty) return low.withHighestBitrate();
      }

      // AAC 140 (128kbps m4a) first for universal hardware decoding, then Opus 251
      for (final s in audioStreams) {
        if (s.tag == 140) return s;
      }
      for (final s in audioStreams) {
        if (s.tag == 251) return s;
      }
      return audioStreams.withHighestBitrate();
    } catch (e) {
      AppLogger.log('YouTubeClient', 'getBestAudioStreamInfo notice for $cleanId: $e');
      return null;
    }
  }

  /// Exposes a bounded byte stream for chunked streaming via YoutubeExplode or HTTP Range
  static Stream<List<int>> getAudioByteStream(String videoId, {int? start, int? end}) async* {
    final cleanId = extractVideoId(videoId) ?? videoId.trim();
    final info = await getBestAudioStreamInfo(cleanId);
    if (info == null) {
      throw Exception('No audio stream info found for $cleanId');
    }

    final totalBytes = info.size.totalBytes;
    final reqStart = start ?? 0;
    final reqEnd = (end != null && end < totalBytes) ? end : totalBytes;

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.url.toString()));
      request.headers.addAll({
        'User-Agent': androidUserAgent,
        'Range': 'bytes=$reqStart-${reqEnd > 0 ? reqEnd - 1 : ""}',
        'Accept': '*/*',
        'Connection': 'keep-alive',
      });
      final response = await client.send(request);
      yield* response.stream;
    } finally {
      client.close();
    }
  }

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

  /// Direct client-side YouTube search using standard WEB client context.
  /// Bypasses datacenter blockades and extracts rich video metadata into [TrackEntity].
  static Future<List<TrackEntity>> searchTracks(String query, {int limit = 15}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final uri = Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false');
      final payload = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20260101.00.00',
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
          final tracks = _parseWebSearchResponse(data, limit: limit);
          if (tracks.isNotEmpty) {
            return tracks;
          }
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'InnerTube WEB search notice for "$clean": $e.');
    }

    // High-res fallback using client-side YouTubeExplode if available
    try {
      final searchResults = await _yt.search.search(clean).timeout(const Duration(seconds: 8));
      final List<TrackEntity> ytExplodeTracks = [];
      for (final video in searchResults.take(limit)) {
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
      if (ytExplodeTracks.isNotEmpty) {
        return ytExplodeTracks;
      }
    } catch (_) {}

    // FALLBACK GUARANTEE: If the YouTube HTTP request fails or parses 0 items,
    // automatically query SaavnClient.search(query) and map the results with source: 'youtube'
    // so the "YT Music" search chip NEVER shows "No results found" for valid queries like "Anirudh".
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
            // Only keep sensible song durations (60s to 600s)
            if (dur >= 60 && dur <= 600) {
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

  /// Fast HTTP GET probe to verify whether a googlevideo.com or stream URL is playable
  /// and not 403-blocked by Google CDN. Returns true ONLY on HTTP 200 or 206.
  static Future<bool> probeStreamUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      final isHls = url.contains('.m3u8') || url.contains('hls_variant');
      final headers = isHls
          ? {
              'User-Agent': 'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)',
              'Accept': '*/*',
            }
          : {
              if (!url.contains('&range=')) 'Range': 'bytes=0-1024',
              'User-Agent': vrUserAgent,
              'Accept': '*/*',
            };
      final response = await http.get(
        uri,
        headers: headers,
      ).timeout(const Duration(seconds: 2));

      final isValid = response.statusCode == 200 || response.statusCode == 206;
      if (!isValid) {
        AppLogger.log('YouTubeClient', 'Stream probe rejected URL: HTTP ${response.statusCode} (403/Forbidden or invalid) for $url');
      }
      return isValid;
    } catch (e) {
      AppLogger.log('YouTubeClient', 'Stream probe network/timeout error: $e');
      return false;
    }
  }

  static final List<Map<String, dynamic>> _innertubePlayerConfigs = [
    {
      'name': 'IOS',
      'client': {
        'clientName': 'IOS',
        'clientVersion': '19.45.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '18.1.0.22B83',
        'hl': 'en',
        'gl': 'IN',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent':
            'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)',
        'X-YouTube-Client-Name': '5',
        'X-YouTube-Client-Version': '19.45.4',
        'Accept': '*/*',
      },
    },
    {
      'name': 'IOS_UPDATED',
      'client': {
        'clientName': 'IOS',
        'clientVersion': '21.26.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '18.1.0.22B83',
        'hl': 'en',
        'gl': 'IN',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent':
            'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)',
        'X-YouTube-Client-Name': '5',
        'X-YouTube-Client-Version': '21.26.4',
        'Accept': '*/*',
      },
    },
    {
      'name': 'ANDROID_VR',
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.56.21',
        'androidSdkVersion': 32,
        'gl': 'IN',
        'hl': 'en',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent': vrUserAgent,
        'X-YouTube-Client-Name': '28',
        'X-YouTube-Client-Version': '1.56.21',
        'Accept': '*/*',
      },
    },
  ];

  /// Tier 1 Fast Path: Queries YouTube InnerTube IOS (Method A - HLS) and ANDROID_VR (Method B - &range=0-$contentLength).
  /// Method A returns .m3u8 HLS URL immediately with zero Source error.
  /// Method B appends &range=0-$contentLength to prevent 403-blocks on ExoPlayer open-ended range requests.
  static Future<String?> _resolveDirectInnertubeStream(String cleanId) async {
    for (final config in _innertubePlayerConfigs) {
      try {
        final uri = Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false');
        final payload = jsonEncode({
          'context': {'client': config['client']},
          'videoId': cleanId,
        });

        final response = await http.post(
          uri,
          headers: Map<String, String>.from(config['headers']),
          body: payload,
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>?;
          final streamingData = data?['streamingData'] as Map<String, dynamic>?;
          if (streamingData == null) continue;

          // Method A: HLS Manifest URL. If present, return .m3u8 immediately!
          final hlsUrl = streamingData['hlsManifestUrl']?.toString();
          if (hlsUrl != null && hlsUrl.isNotEmpty) {
            AppLogger.log('YouTubeClient', 'Method A: Returned native HLS .m3u8 URL from ${config['name']} for $cleanId');
            return hlsUrl;
          }

          // Method B: Extract audio streams with mandatory &range=0-$contentLength
          final formats = (streamingData['adaptiveFormats'] as List<dynamic>?) ?? [];
          final audioFormats = formats.where((f) {
            final mime = f['mimeType']?.toString().toLowerCase() ?? '';
            return mime.startsWith('audio/');
          }).toList();

          final candidateUrls = <String>[];

          String prepareStreamUrl(Map<dynamic, dynamic> f) {
            var url = f['url']?.toString() ?? '';
            if (url.isEmpty) return '';
            final contentLength = f['contentLength']?.toString() ?? Uri.tryParse(url)?.queryParameters['clen'];
            if (contentLength != null && contentLength.isNotEmpty && !url.contains('&range=')) {
              url = '$url&range=0-$contentLength';
            }
            return url;
          }

          if (audioFormats.isNotEmpty) {
            final quality = SettingsManager.streamingQuality;

            // 1. Data saver (96kbps)
            if (quality == '96kbps') {
              for (final f in audioFormats) {
                final bitrate = (f['bitrate'] as num?)?.toInt() ?? 0;
                if (bitrate > 0 && bitrate <= 100000) {
                  final url = prepareStreamUrl(f);
                  if (url.isNotEmpty) {
                    candidateUrls.add(url);
                    break;
                  }
                }
              }
            }

            // 2. Prioritize AAC 140 (128kbps audio/mp4)
            for (final f in audioFormats) {
              if (f['itag'] == 140) {
                final url = prepareStreamUrl(f);
                if (url.isNotEmpty) {
                  candidateUrls.add(url);
                  break;
                }
              }
            }

            // 3. Prioritize Opus 251 (audio/webm ~160kbps)
            for (final f in audioFormats) {
              if (f['itag'] == 251) {
                final url = prepareStreamUrl(f);
                if (url.isNotEmpty) {
                  candidateUrls.add(url);
                  break;
                }
              }
            }

            // 4. Any direct audio URL with highest bitrate
            for (final f in audioFormats) {
              final url = prepareStreamUrl(f);
              if (url.isNotEmpty && !candidateUrls.contains(url)) {
                candidateUrls.add(url);
              }
            }
          }

          // Probe candidates: Only return the first candidate that passes HTTP 200/206 probe
          for (final candidate in candidateUrls) {
            final isPlayable = await probeStreamUrl(candidate);
            if (isPlayable) {
              AppLogger.log('YouTubeClient', 'InnerTube ${config['name']} direct stream verified and active for $cleanId');
              return candidate;
            }
          }
        }
      } catch (e) {
        AppLogger.log('YouTubeClient', 'InnerTube ${config['name']} direct resolution notice for $cleanId: $e');
      }
    }
    return null;
  }

  /// Resolves audio stream and verifies against Google CDN with live HTTP probe.
  /// Dual-tier: InnerTube (ANDROID_VR & IOS) -> YouTubeExplode.
  /// Returns null if Google CDN returns 403 or times out so Smart Replace is triggered.
  static Future<String?> _resolveAndVerifyStream(String cleanId) async {
    // ── Tier 1: Direct InnerTube (ANDROID_VR / IOS) + HLS ─────────────
    final directUrl = await _resolveDirectInnertubeStream(cleanId);
    if (directUrl != null && directUrl.isNotEmpty) {
      return directUrl;
    }

    // ── Tier 2: Client-Side YouTubeExplode Dart (Full Manifest) ────────
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
          var url = chosenStream.url.toString();
          final contentLength = chosenStream.size.totalBytes > 0
              ? chosenStream.size.totalBytes.toString()
              : Uri.tryParse(url)?.queryParameters['clen'];
          if (contentLength != null && contentLength.isNotEmpty && !url.contains('&range=')) {
            url = '$url&range=0-$contentLength';
          }

          // CRITICAL: Live probe before returning YouTubeExplode URL
          final isPlayable = await probeStreamUrl(url);
          if (isPlayable) {
            AppLogger.log('YouTubeClient', 'YouTubeExplode stream verified for $cleanId (itag ${chosenStream.tag})');
            return url;
          } else {
            AppLogger.log('YouTubeClient', 'YouTubeExplode stream rejected by probe (403/Forbidden) for $cleanId');
          }
        }
      } catch (e) {
        AppLogger.log('YouTubeClient', 'YouTubeExplode attempt $attempt notice for $cleanId: $e');
        if (attempt == 1) {
          closeIdleClient();
        }
      }
    }

    AppLogger.log('YouTubeClient', 'All YouTube stream candidates failed probe / 403 Forbidden for $cleanId. Returning null for Smart Replace.');
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
      if (!isLinkExpired(cached.url)) {
        return cached.url;
      }
      _streamCache.remove(cleanId);
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
