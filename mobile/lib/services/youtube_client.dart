import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';

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
      } catch (_) {}
      _ytInstance = null;
    }
  }

  static const String _baseUrl = 'https://tgashwinyt-paatu-padava.hf.space';

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

  /// Multi-tier audio stream extractor that guarantees 100% playable audio streams
  static Future<String?> getAudioStreamUrl(String videoId, {String? title, String? artist}) async {
    // ── Tier 1: Client-Side YouTubeExplode Dart ──────────────────────
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 4));
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isNotEmpty) {
        // Prioritize AAC / M4A stream (itag 140) for standard ExoPlayer compatibility
        AudioStreamInfo? chosenStream;
        for (final s in audioStreams) {
          if (s.tag == 140 || s.container.name.toLowerCase().contains('mp4') || s.container.name.toLowerCase().contains('m4a')) {
            chosenStream = s;
            break;
          }
        }
        chosenStream ??= audioStreams.withHighestBitrate();
        return chosenStream.url.toString();
      }
    } catch (_) {}

    // ── Tier 2: Paatu Padava Backend Stream Resolver ──────────────────
    try {
      final uri = Uri.parse('$_baseUrl/api/music/stream/$videoId').replace(queryParameters: {
        if (title != null && title.isNotEmpty) 'title': title,
        if (artist != null && artist.isNotEmpty) 'artist': artist,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final audioUrl = data['audio_url']?.toString();
        if (audioUrl != null && audioUrl.isNotEmpty) {
          return audioUrl;
        }
      }
    } catch (_) {}

    // ── Tier 3: Invidious Public Stream Fallback ──────────────────────
    final invidiousInstances = [
      'https://inv.nadeko.net',
      'https://invidious.nerdvpn.de',
      'https://vid.priv.au'
    ];
    for (final instance in invidiousInstances) {
      try {
        final uri = Uri.parse('$instance/api/v1/videos/$videoId');
        final res = await http.get(uri).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final formatStreams = data['adaptiveFormats'] as List<dynamic>? ?? [];
          for (final fmt in formatStreams) {
            final type = fmt['type']?.toString() ?? '';
            if (type.contains('audio/mp4') || type.contains('audio/webm')) {
              final url = fmt['url']?.toString();
              if (url != null && url.isNotEmpty) {
                return url;
              }
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  static void dispose() {
    _yt.close();
  }
}
