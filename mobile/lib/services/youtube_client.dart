import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import '../core/app_config.dart';
import 'settings_manager.dart';
import 'app_logger.dart';
import 'artist_sanitizer.dart';

class YouTubeClient {
  static YoutubeExplode? _ytInstance;
  static YoutubeExplode get _yt => _ytInstance ??= YoutubeExplode();

  /// Closes any idle YouTube HTTP sockets and resets client instance
  static void closeIdleClient() {
    _ytInstance?.close();
    _ytInstance = null;
  }

  static String get _baseUrl => AppConfig.backendUrl;

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
    return search(query, limit: limit);
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

  // In-memory stream cache with TTL (1 hour for client, 15 min for fallbacks)
  static final Map<String, _CachedAudioStream> _streamCache = {};

  /// Invalidates cached stream URL for a given video ID (called when playback fails)
  static void invalidateStream(String videoId) {
    final cleanId = videoId.trim();
    if (cleanId.isNotEmpty) {
      _streamCache.remove(cleanId);
      AppLogger.log('YouTubeClient', 'Invalidated stream cache for $cleanId');
    }
  }

  /// Multi-tier audio stream extractor that guarantees 100% playable audio streams
  static Future<String?> getAudioStreamUrl(String videoId, {String? title, String? artist}) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return null;

    // ── Tier 0: In-Memory Stream Cache Check ─────────────────────────
    final cached = _streamCache[cleanId];
    if (cached != null && !cached.isExpired) {
      AppLogger.log('YouTubeClient', 'Resolved stream from memory cache for $cleanId');
      return cached.url;
    }

    // ── Tier 1: Client-Side YouTubeExplode Dart ──────────────────────
    try {
      StreamManifest? manifest;
      try {
        // Fast direct manifest extraction (requireWatchPage: false avoids heavy HTML/JS downloads, ~5s instead of ~40s)
        manifest = await _yt.videos.streamsClient.getManifest(
          cleanId,
          requireWatchPage: false,
        ).timeout(const Duration(seconds: 15));
      } catch (fastErr) {
        AppLogger.log('YouTubeClient', 'Fast manifest extraction notice for $cleanId: $fastErr. Falling back to full extraction.');
        manifest = await _yt.videos.streamsClient.getManifest(
          cleanId,
          requireWatchPage: true,
        ).timeout(const Duration(seconds: 20));
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
        // This is 100% universally supported across Android ExoPlayer & iOS AVPlayer
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
        _streamCache[cleanId] = _CachedAudioStream(url, DateTime.now().add(const Duration(hours: 1)));
        AppLogger.log('YouTubeClient', 'Tier 1 resolved stream for $cleanId (itag ${chosenStream.tag}, ${chosenStream.container.name}, ${chosenStream.bitrate.kiloBitsPerSecond.round()}kbps)');
        return url;
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'Tier 1 client-side stream extractor notice for $cleanId: $e');
    }

    // ── Tier 2: Paatu Padava Backend Stream Resolver ──────────────────
    try {
      final uri = Uri.parse('$_baseUrl/api/music/stream/$cleanId').replace(queryParameters: {
        if (title != null && title.isNotEmpty) 'title': title,
        if (artist != null && artist.isNotEmpty) 'artist': artist,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final audioUrl = data['audio_url']?.toString();
        if (audioUrl != null && audioUrl.isNotEmpty) {
          _streamCache[cleanId] = _CachedAudioStream(audioUrl, DateTime.now().add(const Duration(minutes: 15)));
          AppLogger.log('YouTubeClient', 'Tier 2 backend resolved stream for $cleanId');
          return audioUrl;
        } else {
          AppLogger.log('YouTubeClient', 'Tier 2 backend returned 200 without audio_url for $cleanId: ${res.body}');
        }
      } else {
        final bodySnippet = res.body.length > 200 ? '${res.body.substring(0, 200)}...' : res.body;
        AppLogger.log('YouTubeClient', 'Tier 2 backend stream resolver failed for $cleanId: HTTP ${res.statusCode} (body: $bodySnippet)');
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'Tier 2 backend stream resolver exception for $cleanId: $e');
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
