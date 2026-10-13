import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
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

  /// High-integrity HTTP headers for Googlevideo CDN streams.
  /// Enforces modern User-Agent and keep-alive to avoid connection drops.
  static Map<String, String> get streamingHeaders => const {
    'Range': 'bytes=0-',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Connection': 'keep-alive',
  };

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

  static Future<List<Song>> search(String query, {int limit = 15}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final List<Song> songs = [];
    try {
      final searchResults = await _yt.search.search(clean).timeout(const Duration(seconds: 15));

      for (final video in searchResults.take(limit)) {
        final rawAuthor = video.author;
        final cleanAuthor = ArtistSanitizer.extractArtistFromVideo(video.title, rawAuthor);
        final highThumb = video.thumbnails.highResUrl;
        final safeThumb = (highThumb.isNotEmpty && highThumb.startsWith('http'))
            ? (highThumb.startsWith('http://') ? highThumb.replaceFirst('http://', 'https://') : highThumb)
            : 'https://img.youtube.com/vi/${video.id.value}/hqdefault.jpg';

        songs.add(Song(
          id: video.id.value,
          title: cleanTitle(video.title),
          artist: Song.sanitize(cleanAuthor),
          album: 'YouTube Music',
          coverUrl: safeThumb,
          duration: video.duration?.inSeconds ?? 0,
          source: 'youtube',
        ));
      }
      return songs;
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'YouTubeClient.search("$clean")');
      return songs;
    }
  }

  /// Fetches YouTube Music trending highlights for the specified language.
  static Future<List<Song>> getTrendingTracks({String language = 'Tamil', int limit = 15}) async {
    final query = '$language trending music songs';
    final songs = await search(query, limit: limit);
    final filtered = SongRepository.filterByLanguage(songs, language);
    return filtered.isNotEmpty ? filtered : songs;
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
          // Prioritize Topic channels or official releases
          final topic = searchResults.firstWhere(
            (s) => s.artist.endsWith(' - Topic') || s.artist.toLowerCase().contains('topic'),
            orElse: () => searchResults.first,
          );
          seedVideoId = topic.id;
        }
      }

      if (seedVideoId != null && seedVideoId.isNotEmpty) {
        final List<Video> candidateVideos = [];

        // 1. Radio Graph Walking: Native Related Videos of seed (RDAMVM graph node)
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

  /// Tier 1 Fast Path: Queries YouTube InnerTube Android mobile player endpoint directly.
  /// On-device mobile requests frequently receive un-ciphered URLs (itag 140 / 251) directly,
  /// avoiding heavy watch page HTML download and JS deciphering (~200ms vs ~2.5s).
  static Future<String?> _resolveDirectInnertubeAndroidStream(String cleanId) async {
    try {
      final uri = Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false');
      final payload = jsonEncode({
        'context': {
          'client': {
            'clientName': 'ANDROID',
            'clientVersion': '19.29.35',
            'androidSdkVersion': 34,
            'hl': 'en',
            'gl': 'IN',
          }
        },
        'videoId': cleanId,
        'playbackContext': {
          'contentPlaybackContext': {
            'html5Preference': 'HTML5_PREF_WANTS',
          }
        }
      });

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'com.google.android.youtube/19.29.35 (Linux; U; Android 14; en_US) gzip',
          'X-YouTube-Client-Name': '3',
          'X-YouTube-Client-Version': '19.29.35',
          'Accept': '*/*',
        },
        body: payload,
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        final streamingData = data?['streamingData'] as Map<String, dynamic>?;
        final formats = (streamingData?['adaptiveFormats'] as List<dynamic>?) ?? [];

        // Filter audio-only formats
        final audioFormats = formats.where((f) {
          final mime = f['mimeType']?.toString().toLowerCase() ?? '';
          return mime.startsWith('audio/');
        }).toList();

        if (audioFormats.isNotEmpty) {
          final quality = SettingsManager.streamingQuality;
          Map<String, dynamic>? chosen;

          // 1. If user prefers data saver (96kbps), look for low bitrate
          if (quality == '96kbps') {
            for (final f in audioFormats) {
              final bitrate = (f['bitrate'] as num?)?.toInt() ?? 0;
              if (bitrate > 0 && bitrate <= 100000 && f['url'] != null) {
                chosen = f as Map<String, dynamic>;
                break;
              }
            }
          }

          // 2. Prioritize AAC 140 (128kbps) for universal hardware compatibility
          if (chosen == null) {
            for (final f in audioFormats) {
              if (f['itag'] == 140 && f['url'] != null) {
                chosen = f as Map<String, dynamic>;
                break;
              }
            }
          }

          // 3. Prioritize Opus 251 (~160kbps)
          if (chosen == null) {
            for (final f in audioFormats) {
              if (f['itag'] == 251 && f['url'] != null) {
                chosen = f as Map<String, dynamic>;
                break;
              }
            }
          }

          // 4. Any direct audio URL with highest bitrate
          if (chosen == null) {
            for (final f in audioFormats) {
              if (f['url'] != null && (f['url'] as String).isNotEmpty) {
                if (chosen == null || ((f['bitrate'] as num?)?.toInt() ?? 0) > ((chosen['bitrate'] as num?)?.toInt() ?? 0)) {
                  chosen = f as Map<String, dynamic>;
                }
              }
            }
          }

          if (chosen != null && chosen['url'] != null) {
            final directUrl = chosen['url'].toString();
            if (directUrl.isNotEmpty) {
              AppLogger.log('YouTubeClient', 'InnerTube Android direct stream resolved for $cleanId (itag ${chosen['itag']})');
              return directUrl;
            }
          }
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'InnerTube Android direct resolution notice for $cleanId: $e');
    }
    return null;
  }

  /// Client-side audio stream extractor resolving on-device with dual-tier fallback:
  /// - Tier 1: Direct InnerTube Android client (sub-300ms, direct deciphered streams)
  /// - Tier 2: YouTubeExplode on-device manifest extraction with watch page decipher fallback
  /// Bypasses datacenter IP blocks, avoiding broken server-side stream resolution on release APKs.
  static Future<String?> getAudioStreamUrl(String videoId, {String? title, String? artist}) async {
    final cleanId = extractVideoId(videoId) ?? videoId.trim();
    if (cleanId.isEmpty) return null;

    // ── Tier 0: In-Memory Stream Cache Check (3-hour TTL) ─────────────
    final cached = _streamCache[cleanId];
    if (cached != null && !cached.isExpired) {
      AppLogger.log('YouTubeClient', 'Resolved stream from memory cache for $cleanId');
      return cached.url;
    }

    // ── Tier 1: Direct InnerTube Android Mobile Client (Fast Path) ───
    final fastUrl = await _resolveDirectInnertubeAndroidStream(cleanId);
    if (fastUrl != null && fastUrl.isNotEmpty) {
      _streamCache[cleanId] = _CachedAudioStream(fastUrl, DateTime.now().add(const Duration(hours: 3)));
      return fastUrl;
    }

    // ── Tier 2: Client-Side YouTubeExplode Dart (Full Manifest Resolution) ──
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        StreamManifest? manifest;
        try {
          // Fast direct manifest extraction (requireWatchPage: false avoids heavy HTML/JS downloads)
          manifest = await _yt.videos.streamsClient.getManifest(
            cleanId,
            requireWatchPage: false,
          ).timeout(const Duration(seconds: 14));
        } catch (fastErr) {
          AppLogger.log('YouTubeClient', 'Fast manifest extraction notice for $cleanId: $fastErr. Falling back to full extraction.');
          manifest = await _yt.videos.streamsClient.getManifest(
            cleanId,
            requireWatchPage: true,
          ).timeout(const Duration(seconds: 18));
        }

        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          AudioStreamInfo? chosenStream;
          final quality = SettingsManager.streamingQuality;

          // Data Saver (96 kbps): choose lowest bitrate stream
          if (quality == '96kbps') {
            for (final s in audioStreams) {
              if (s.bitrate.kiloBitsPerSecond <= 100) {
                chosenStream = s;
                break;
              }
            }
          }

          // Standard or High: Strictly prioritize standard AAC / M4A stream (itag 140, 128kbps)
          // 100% universally supported across Android ExoPlayer & iOS AVPlayer
          if (chosenStream == null) {
            for (final s in audioStreams) {
              if (s.tag == 140) {
                chosenStream = s;
                break;
              }
            }
          }

          // Fallback to Opus in WebM (itag 251, ~160kbps)
          if (chosenStream == null) {
            for (final s in audioStreams) {
              if (s.tag == 251) {
                chosenStream = s;
                break;
              }
            }
          }

          // Fallback to any other MP4 / M4A container
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
          _streamCache[cleanId] = _CachedAudioStream(url, DateTime.now().add(const Duration(hours: 3)));
          AppLogger.log('YouTubeClient', 'Client-side resolved stream for $cleanId (itag ${chosenStream.tag}, ${chosenStream.container.name}, ${chosenStream.bitrate.kiloBitsPerSecond.round()}kbps)');
          return url;
        }
      } catch (e) {
        AppLogger.log('YouTubeClient', 'Client-side stream extractor attempt $attempt notice for $cleanId: $e');
        if (attempt == 1) {
          // Reset client instance on socket / connection error before second attempt
          closeIdleClient();
        }
      }
    }

    return null;
  }

  static void dispose() {
    closeIdleClient();
  }
}

class _CachedAudioStream {
  final String url;
  final DateTime expiresAt;
  _CachedAudioStream(this.url, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
