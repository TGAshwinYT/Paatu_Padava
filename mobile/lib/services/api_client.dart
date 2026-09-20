import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'auth_manager.dart';
import 'youtube_client.dart';

class ApiClient {
  static const String baseUrl = 'https://tgashwinyt-paatu-padava.hf.space';

  static Map<String, String> get _headers {
    final map = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = AuthManager.token;
    if (token != null && token.isNotEmpty) {
      map['Authorization'] = 'Bearer $token';
    }
    return map;
  }

  // ================= 1. Machine Learning & Listen History ================= //

  /// Records that the user listened to a track.
  /// Trains the backend recommendation graph and personal_recommender!
  static Future<void> addListenHistory(Song song) async {
    try {
      final uri = Uri.parse('$baseUrl/api/history/listen');
      final body = json.encode({
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        'cover_url': song.coverUrl,
        'audio_url': song.streamUrl ?? '',
        'language': '',
      });

      await http.post(uri, headers: _headers, body: body).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Fetches personalized queue learned from collaborative filtering (Item-Item graph)
  static Future<List<Song>> fetchForYou() async {
    try {
      final uri = Uri.parse('$baseUrl/api/music/for-you');
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final queue = data['queue'] as List<dynamic>? ?? [];
        return _mapSongs(queue);
      }
    } catch (_) {}
    return [];
  }

  /// AI Recommendations / Radio Mix for a specific song
  static Future<List<Song>> fetchRecommendations(String songId, {String? artist, String? language}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/music/recommendations/$songId').replace(queryParameters: {
        if (artist != null && artist.isNotEmpty) 'artist': artist,
        if (language != null && language.isNotEmpty) 'lang': language,
        'limit': '25',
      });

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data is List) ? data : (data['recommendations'] ?? data['data'] ?? []);
        if (list is List) {
          return _mapSongs(list);
        }
      }
    } catch (_) {}
    return [];
  }

  // ================= 2. Smart Shuffle (Graph + On-Device Markov Chain) ================= //

  static Future<List<String>> fetchSmartShuffle(List<Song> queue, Song? currentSong) async {
    final queueIds = queue.map((s) => s.id).toList();
    if (queue.length <= 2) return queueIds;

    // 1. Try Backend Recommendation Graph
    try {
      final uri = Uri.parse('$baseUrl/api/music/shuffle-order');
      final body = json.encode({
        'queue_ids': queueIds,
        'current_song_id': currentSong?.id,
      });

      final response = await http.post(uri, headers: _headers, body: body).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final ordered = (data['ordered_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList();
        if (ordered != null && ordered.length == queueIds.length) {
          return ordered;
        }
      }
    } catch (_) {}

    // 2. Intelligent On-Device Markov Similarity Transition Chain
    return _onDeviceSmartShuffle(queue, currentSong);
  }

  static List<String> _onDeviceSmartShuffle(List<Song> queue, Song? currentSong) {
    final remaining = List<Song>.from(queue);
    final List<String> orderedIds = [];

    Song active = currentSong ?? remaining.first;
    orderedIds.add(active.id);
    remaining.removeWhere((s) => s.id == active.id);

    while (remaining.isNotEmpty) {
      // Score candidates based on metadata & artist similarity
      Song? bestCandidate;
      double bestScore = -1.0;

      for (final candidate in remaining) {
        double score = 0.0;
        // Same artist bonus
        if (candidate.artist.toLowerCase() == active.artist.toLowerCase()) {
          score += 4.0;
        } else if (candidate.artist.toLowerCase().contains(active.artist.toLowerCase()) ||
            active.artist.toLowerCase().contains(candidate.artist.toLowerCase())) {
          score += 2.0;
        }
        // Same album bonus
        if (candidate.album.isNotEmpty && candidate.album == active.album) {
          score += 3.0;
        }
        // Duration similarity (within 30s)
        final diff = (candidate.duration - active.duration).abs();
        if (diff < 30) score += 1.5;

        // Slight randomness to keep transitions organic
        score += (DateTime.now().microsecond % 100) / 100.0;

        if (score > bestScore) {
          bestScore = score;
          bestCandidate = candidate;
        }
      }

      final chosen = bestCandidate ?? remaining.first;
      orderedIds.add(chosen.id);
      remaining.removeWhere((s) => s.id == chosen.id);
      active = chosen;
    }

    return orderedIds;
  }

  // ================= 3. Multi-Source Bulletproof Lyrics ================= //

  static Future<String?> fetchLyrics(Song song) async {
    // 1. Try Backend LRCLIB synced endpoint
    try {
      final uri = Uri.parse('$baseUrl/api/music/lyrics').replace(queryParameters: {
        'title': song.title,
        'artist': song.artist,
        'duration': song.duration.toString(),
      });

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lyrics = data['syncedLyrics'] ?? data['plainLyrics'] ?? data['lyrics'];
        if (lyrics != null && lyrics.toString().trim().isNotEmpty) {
          return lyrics.toString().trim();
        }
      }
    } catch (_) {}

    // 2. Try Direct LRCLIB Public API
    try {
      final uri = Uri.parse('https://lrclib.net/api/get').replace(queryParameters: {
        'track_name': song.title,
        'artist_name': song.artist,
        if (song.duration > 0) 'duration': song.duration.toString(),
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lyrics = data['syncedLyrics'] ?? data['plainLyrics'];
        if (lyrics != null && lyrics.toString().trim().isNotEmpty) {
          return lyrics.toString().trim();
        }
      }
    } catch (_) {}

    // 3. Try Direct JioSaavn Lyrics API
    try {
      final uri = Uri.parse('https://www.jiosaavn.com/api.php').replace(queryParameters: {
        '__call': 'lyrics.getLyrics',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'lyrics_id': song.id,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lyrics = data['lyrics']?.toString();
        if (lyrics != null && lyrics.trim().isNotEmpty) {
          return lyrics.replaceAll('<br>', '\n').replaceAll('<br/>', '\n').trim();
        }
      }
    } catch (_) {}

    return null;
  }

  // ================= 4. Spotify Playlist Import ================= //

  static Future<Map<String, dynamic>?> previewSpotifyPlaylist(String url) async {
    try {
      final uri = Uri.parse('$baseUrl/api/playlists/preview-spotify');
      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode({'url': url.trim()}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<List<Song>> importSpotifyPlaylist(String url, {String? customTitle}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/playlists/import-spotify');
      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode({
          'url': url.trim(),
          if (customTitle != null) 'title': customTitle,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tracks = data['tracks'] ?? data['songs'] ?? [];
        if (tracks is List) {
          return _mapSongs(tracks);
        }
      }
    } catch (_) {}
    return [];
  }

  // ================= 5. YouTube Music Top Charts & Trending ================= //

  static Future<List<Song>> fetchYouTubeTrending() async {
    try {
      return await YouTubeClient.search('Trending Tamil Hindi English Songs', limit: 20);
    } catch (_) {
      return [];
    }
  }

  // ================= Helpers ================= //

  static List<Song> _mapSongs(List<dynamic> list) {
    final List<Song> songs = [];
    for (final item in list) {
      if (item is Map) {
        final stream = item['audio_url'] ?? item['audioUrl'] ?? item['stream_url'] ?? item['streamUrl'];
        final cover = item['cover_url'] ?? item['coverUrl'] ?? item['image'] ?? '';
        songs.add(Song(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? item['name']?.toString() ?? 'Unknown Title',
          artist: item['artist']?.toString() ?? item['primaryArtists']?.toString() ?? 'Unknown Artist',
          album: item['album']?.toString() ?? 'Unknown Album',
          albumId: item['album_id']?.toString() ?? item['albumId']?.toString(),
          artistId: item['artist_id']?.toString() ?? item['artistId']?.toString(),
          coverUrl: cover.toString(),
          streamUrl: stream?.toString(),
          duration: int.tryParse(item['duration']?.toString() ?? '0') ?? 0,
          source: (item['source']?.toString() == 'youtube' || (item['id']?.toString().length == 11)) ? 'youtube' : 'saavn',
        ));
      }
    }
    return songs;
  }
}
