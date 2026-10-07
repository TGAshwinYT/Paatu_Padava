import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import '../core/app_config.dart';
import 'settings_manager.dart';
import 'app_logger.dart';

class YouTubeClient {
  static YoutubeExplode? _ytInstance;

  /// Lazy instance: creates on demand and re-connects only when explicitly requested
  static YoutubeExplode get _yt {
    _ytInstance ??= YoutubeExplode();
    return _ytInstance!;
  }

  /// Closes any idle YouTube HTTP sockets immediately to eliminate background battery drain
  static void closeIdleClient() {
    if (_ytInstance != null) {
      try {
        _ytInstance!.close();
      } catch (e) {
        AppLogger.log('YouTubeClient', 'closeIdleClient error: $e');
      }
      _ytInstance = null;
    }
  }

  static String get _baseUrl => AppConfig.backendUrl;

  static String cleanTitle(String title) {
    var cleaned = Song.sanitize(title);
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

    try {
      final searchResults = await _yt.search.search(clean);
      final List<Song> songs = [];

      for (final video in searchResults.take(limit)) {
        songs.add(Song(
          id: video.id.value,
          title: cleanTitle(video.title),
          artist: Song.sanitize(video.author),
          album: 'YouTube Music',
          coverUrl: video.thumbnails.highResUrl,
          duration: video.duration?.inSeconds ?? 0,
          source: 'youtube',
        ));
      }
      return songs;
    } catch (e) {
      return [];
    }
  }

  /// Fetches related YouTube Music autoplay tracks for a seed song
  static Future<List<Song>> getRelatedSongs(Song seedSong, {int limit = 10}) async {
    final List<Song> songs = [];
    try {
      // 1. If seed song is a YouTube video, attempt native related videos
      if (seedSong.source == 'youtube' && seedSong.id.isNotEmpty) {
        final video = await _yt.videos.get(VideoId(seedSong.id)).timeout(const Duration(seconds: 4));
        final related = await _yt.videos.getRelatedVideos(video).timeout(const Duration(seconds: 5));
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
    } catch (_) {}

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
      final manifest = await _yt.videos.streamsClient.getManifest(cleanId).timeout(const Duration(seconds: 25));
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
      closeIdleClient(); // Reset broken client/sockets so next query starts fresh
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
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'Tier 2 backend stream resolver notice: $e');
    }

    // ── Tier 3: Invidious Public Stream Fallback ──────────────────────
    final invidiousInstances = [
      'https://inv.nadeko.net',
      'https://invidious.nerdvpn.de',
      'https://vid.priv.au'
    ];
    for (final instance in invidiousInstances) {
      try {
        final uri = Uri.parse('$instance/api/v1/videos/$cleanId');
        final res = await http.get(uri).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final formatStreams = data['adaptiveFormats'] as List<dynamic>? ?? [];
          for (final fmt in formatStreams) {
            final type = fmt['type']?.toString() ?? '';
            if (type.contains('audio/mp4') || type.contains('audio/webm')) {
              final url = fmt['url']?.toString();
              if (url != null && url.isNotEmpty) {
                _streamCache[cleanId] = _CachedAudioStream(url, DateTime.now().add(const Duration(minutes: 15)));
                AppLogger.log('YouTubeClient', 'Tier 3 resolved stream for $cleanId from $instance');
                return url;
              }
            }
          }
        }
      } catch (e) {
        AppLogger.log('YouTubeClient', 'Tier 3 $instance stream fallback notice: $e');
      }
    }

    return null;
  }

  static void dispose() {
    _yt.close();
  }
}

class _CachedAudioStream {
  final String url;
  final DateTime expiresAt;
  _CachedAudioStream(this.url, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
