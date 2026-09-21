import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'auth_manager.dart';
import 'youtube_client.dart';
import 'saavn_client.dart';

class SearchResultBundle {
  final Map<String, dynamic>? topResult;
  final List<Song> songs;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> albums;

  SearchResultBundle({
    this.topResult,
    required this.songs,
    required this.artists,
    required this.albums,
  });
}

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

  static Future<List<Song>> fetchListenHistory() async {
    try {
      final uri = Uri.parse('$baseUrl/api/history/listen');
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          final List<Song> list = [];
          for (final item in data) {
            if (item is Map) {
              list.add(Song(
                id: item['yt_video_id']?.toString() ?? item['id']?.toString() ?? '',
                title: item['title']?.toString() ?? 'Track',
                artist: item['artist']?.toString() ?? 'Artist',
                album: '',
                duration: 0,
                coverUrl: item['cover_url']?.toString() ?? '',
                streamUrl: item['audio_url']?.toString(),
                source: 'history',
              ));
            }
          }
          return list;
        }
      }
    } catch (_) {}
    return [];
  }

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

  // ================= 2. Spotify-Grade Search Engine ================= //

  static Future<SearchResultBundle?> searchGlobal(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/music/search').replace(queryParameters: {'query': clean});
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final matches = data['global_matches'] as Map<String, dynamic>? ?? {};

        final topResult = matches['top_result'] as Map<String, dynamic>?;
        final rawSongs = matches['songs'] as List<dynamic>? ?? [];
        final rawArtists = matches['artists'] as List<dynamic>? ?? [];
        final rawAlbums = matches['albums'] as List<dynamic>? ?? [];

        return SearchResultBundle(
          topResult: topResult,
          songs: _mapSongs(rawSongs),
          artists: rawArtists.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          albums: rawAlbums.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
      }
    } catch (_) {}

    // Graceful offline/direct fallback
    try {
      final saavnSongs = await SaavnClient.search(clean, limit: 15);
      final albums = await SaavnClient.searchAlbums(clean, limit: 6);
      final artists = await SaavnClient.searchArtists(clean, limit: 6);

      Map<String, dynamic>? top;
      if (saavnSongs.isNotEmpty) {
        final s = saavnSongs.first;
        top = {
          'type': 'song',
          'id': s.id,
          'title': s.title,
          'artist': s.artist,
          'cover_url': s.coverUrl,
          'duration': s.duration,
        };
      }

      return SearchResultBundle(
        topResult: top,
        songs: saavnSongs,
        artists: artists,
        albums: albums,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> searchSuggestions(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final uri = Uri.parse('$baseUrl/api/music/search/suggestions').replace(queryParameters: {'query': clean});
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return data.map((e) => e.toString()).toList();
        } else if (data['suggestions'] is List) {
          return (data['suggestions'] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  // ================= 3. Smart Shuffle (Graph + On-Device Markov Chain) ================= //

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
      Song? bestCandidate;
      double bestScore = -1.0;

      for (final candidate in remaining) {
        double score = 0.0;
        if (candidate.artist.toLowerCase() == active.artist.toLowerCase()) {
          score += 4.0;
        } else if (candidate.artist.toLowerCase().contains(active.artist.toLowerCase()) ||
            active.artist.toLowerCase().contains(candidate.artist.toLowerCase())) {
          score += 2.0;
        }
        if (candidate.album.isNotEmpty && candidate.album == active.album) {
          score += 3.0;
        }
        final diff = (candidate.duration - active.duration).abs();
        if (diff < 30) score += 1.5;

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

  // ================= 4. Multi-Source Bulletproof Lyrics ================= //

  static Future<String?> fetchLyrics(Song song) async {
    final cleanedTitle = YouTubeClient.cleanTitle(song.title);
    final cleanedArtist = song.artist.replaceAll(RegExp(r'\b(topic|vevo)\b', caseSensitive: false), '').trim();

    // 1. Try Backend LRCLIB synced endpoint
    try {
      final uri = Uri.parse('$baseUrl/api/music/lyrics').replace(queryParameters: {
        'title': cleanedTitle,
        'artist': cleanedArtist,
        if (song.duration > 0) 'duration': song.duration.toString(),
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
        'track_name': cleanedTitle,
        'artist_name': cleanedArtist,
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

  // ================= 5. Bulletproof Spotify Playlist Import ================= //

  static Future<Map<String, dynamic>?> previewSpotifyPlaylist(String url) async {
    // 1. Try Backend Resolver
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

    // 2. Client-side resilient Jina Reader fallback
    try {
      final jinaUri = Uri.parse('https://r.jina.ai/${url.trim()}');
      final res = await http.get(jinaUri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final text = res.body;

        String title = 'Spotify Playlist';
        final tm = RegExp(r'Title:\s*([^|\n]+)').firstMatch(text);
        if (tm != null && tm.group(1) != null) {
          title = tm.group(1)!.trim();
        }

        String coverUrl = '';
        final cm = RegExp(r'!\[.*?\]\((https://i\.scdn\.co/image/[^\)]+)\)').firstMatch(text);
        if (cm != null && cm.group(1) != null) {
          coverUrl = cm.group(1)!;
        }

        final tracksPattern = RegExp(
          r'\[([^\]]+)\]\(https://open\.spotify\.com/track/[^\)]+\)\s*\n\s*\[([^\]]+)\]\(https://open\.spotify\.com/artist/[^\)]+\)',
        );
        final List<Map<String, dynamic>> extracted = [];
        for (final m in tracksPattern.allMatches(text)) {
          final tTitle = m.group(1)?.trim() ?? '';
          final tArtist = m.group(2)?.trim() ?? '';
          if (tTitle.isNotEmpty) {
            extracted.add({
              'title': tTitle,
              'artist': tArtist,
            });
          }
        }

        return {
          'title': title,
          'thumbnail': coverUrl,
          'cover_url': coverUrl,
          'total_tracks': extracted.length,
          'track_count': extracted.length,
          'sample_tracks': extracted.take(6).toList(),
          'tracks': extracted,
        };
      }
    } catch (_) {}

    return null;
  }

  static Future<List<Song>> importSpotifyPlaylist(String url, {String? customTitle}) async {
    // 1. Try Backend Import
    try {
      final uri = Uri.parse('$baseUrl/api/playlists/import-spotify');
      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode({
          'url': url.trim(),
          if (customTitle != null) 'custom_title': customTitle,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tracks = data['tracks'] ?? data['songs'] ?? [];
        if (tracks is List && tracks.isNotEmpty) {
          return _mapSongs(tracks);
        }
      }
    } catch (_) {}

    // 2. Client-side direct track match fallback
    try {
      final preview = await previewSpotifyPlaylist(url);
      final rawTracks = preview?['tracks'] as List<dynamic>? ?? [];
      if (rawTracks.isNotEmpty) {
        final List<Song> resolvedSongs = [];
        for (final item in rawTracks.take(30)) {
          final title = item['title']?.toString() ?? '';
          final artist = item['artist']?.toString() ?? '';
          if (title.isNotEmpty) {
            final query = '$title $artist'.trim();
            // Search Saavn first for 320kbps
            final saavnRes = await SaavnClient.search(query, limit: 1);
            if (saavnRes.isNotEmpty) {
              resolvedSongs.add(saavnRes.first);
            } else {
              // Fallback to YouTube
              final ytRes = await YouTubeClient.search(query, limit: 1);
              if (ytRes.isNotEmpty) {
                resolvedSongs.add(ytRes.first);
              }
            }
          }
        }
        return resolvedSongs;
      }
    } catch (_) {}

    return [];
  }

  // ================= 6. YouTube Music Top Charts & Trending ================= //

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
