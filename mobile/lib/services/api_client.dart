import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'auth_manager.dart';
import 'settings_manager.dart';
import 'youtube_client.dart';
import 'saavn_client.dart';
import 'spotify_import_service.dart';

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
    final user = AuthManager.currentUser;
    if (user != null && !user.isGuest) {
      map['X-User-ID'] = user.id;
      map['X-User-Email'] = user.email;
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
        'language': song.language ?? '',
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
                title: Song.sanitize(item['title'], fallback: 'Track'),
                artist: Song.sanitize(item['artist'], fallback: 'Artist'),
                album: '',
                duration: 0,
                coverUrl: item['cover_url']?.toString() ?? '',
                streamUrl: item['audio_url']?.toString(),
                source: 'history',
                language: item['language']?.toString(),
              ));
            }
          }
          return list;
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Song>> fetchForYou({String? language}) async {
    final targetLang = language ?? (SettingsManager.preferredLanguages.isNotEmpty ? SettingsManager.preferredLanguages.first : 'Tamil');
    try {
      final uri = Uri.parse('$baseUrl/api/music/for-you').replace(queryParameters: {
        'language': targetLang.toLowerCase(),
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final queue = data['queue'] as List<dynamic>? ?? [];
        final mapped = _mapSongs(queue);

        // Strict post-fetch filtering: prevent injecting random foreign tracks when language preference is set
        final prefLangs = SettingsManager.preferredLanguages.map((l) => l.toLowerCase()).toSet();
        if (prefLangs.isNotEmpty) {
          final strictlyFiltered = mapped.where((s) {
            if (s.language == null || s.language!.isEmpty) return true;
            return prefLangs.contains(s.language!.toLowerCase());
          }).toList();
          return strictlyFiltered.isNotEmpty ? strictlyFiltered : mapped;
        }
        return mapped;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Song>> fetchRecommendations(String songId, {String? artist, String? language}) async {
    final targetLang = (language != null && language.isNotEmpty)
        ? language
        : (SettingsManager.preferredLanguages.isNotEmpty ? SettingsManager.preferredLanguages.first : 'Tamil');
    try {
      final uri = Uri.parse('$baseUrl/api/music/recommendations/$songId').replace(queryParameters: {
        if (artist != null && artist.isNotEmpty) 'artist': artist,
        'lang': targetLang.toLowerCase(),
        'language': targetLang.toLowerCase(),
        'limit': '25',
      });

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data is List) ? data : (data['recommendations'] ?? data['data'] ?? []);
        if (list is List) {
          final mapped = _mapSongs(list);
          final prefLangs = SettingsManager.preferredLanguages.map((l) => l.toLowerCase()).toSet();
          if (prefLangs.isNotEmpty) {
            final strictlyFiltered = mapped.where((s) {
              if (s.language == null || s.language!.isEmpty) return true;
              return prefLangs.contains(s.language!.toLowerCase());
            }).toList();
            return strictlyFiltered.isNotEmpty ? strictlyFiltered : mapped;
          }
          return mapped;
        }
      }
    } catch (_) {}
    return [];
  }

  // ================= 2. Spotify-Grade Search Engine ================= //

  static Future<SearchResultBundle?> searchGlobal(String query, {String? language}) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;

    final targetLang = language ?? (SettingsManager.preferredLanguages.isNotEmpty ? SettingsManager.preferredLanguages.first : 'Tamil');

    try {
      final uri = Uri.parse('$baseUrl/api/music/search').replace(queryParameters: {
        'query': clean,
        'language': targetLang.toLowerCase(),
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final matches = data['global_matches'] as Map<String, dynamic>? ?? {};

        final topResult = matches['top_result'] as Map<String, dynamic>?;
        final rawSongs = matches['songs'] as List<dynamic>? ?? [];
        final rawArtists = matches['artists'] as List<dynamic>? ?? [];
        final rawAlbums = matches['albums'] as List<dynamic>? ?? [];

        return SearchResultBundle(
          topResult: topResult != null
              ? {
                  ...topResult,
                  'title': Song.sanitize(topResult['title']),
                  'artist': Song.sanitize(topResult['artist']),
                }
              : null,
          songs: _mapSongs(rawSongs),
          artists: rawArtists.map((e) => Map<String, dynamic>.from(e as Map).map(
                (k, v) => MapEntry(k, (k == 'name' || k == 'title') ? Song.sanitize(v) : v),
              )).toList(),
          albums: rawAlbums.map((e) => Map<String, dynamic>.from(e as Map).map(
                (k, v) => MapEntry(k, (k == 'title' || k == 'artist') ? Song.sanitize(v) : v),
              )).toList(),
        );
      }
    } catch (_) {}

    // Graceful offline/direct fallback with language filter
    try {
      final saavnSongs = await SaavnClient.search(clean, limit: 15, language: targetLang);
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

    // 1. Try Direct JioSaavn Lyrics API FIRST for regional tracks to guarantee language match!
    if (song.source != 'youtube' && song.id.isNotEmpty && song.id.length != 11) {
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
            final formatted = lyrics.replaceAll('<br>', '\n').replaceAll('<br/>', '\n').trim();
            return Song.sanitize(formatted);
          }
        }
      } catch (_) {}
    }

    // 2. Try Backend LRCLIB synced endpoint passing original track language
    try {
      final uri = Uri.parse('$baseUrl/api/music/lyrics').replace(queryParameters: {
        'title': cleanedTitle,
        'artist': cleanedArtist,
        if (song.duration > 0) 'duration': song.duration.toString(),
        if (song.language != null && song.language!.isNotEmpty) 'language': song.language!,
      });

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lyrics = data['syncedLyrics'] ?? data['plainLyrics'] ?? data['lyrics'];
        if (lyrics != null && lyrics.toString().trim().isNotEmpty) {
          return Song.sanitize(lyrics.toString().trim());
        }
      }
    } catch (_) {}

    // 3. Try Direct LRCLIB Public API
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
          return Song.sanitize(lyrics.toString().trim());
        }
      }
    } catch (_) {}

    return null;
  }

  // ================= 5. Bulletproof Spotify Playlist Import ================= //

  static Future<Map<String, dynamic>?> previewSpotifyPlaylist(String url) async {
    // 1. Client-Side Spotify Service with recursive pagination & anonymous token
    try {
      final meta = await SpotifyImportService.fetchSpotifyMetadata(url);
      if (meta != null) {
        return {
          'title': meta.title,
          'thumbnail': meta.coverUrl,
          'cover_url': meta.coverUrl,
          'total_tracks': meta.totalTracks,
          'track_count': meta.totalTracks,
          'sample_tracks': meta.tracks.take(6).map((t) => {'title': t.title, 'artist': t.artist}).toList(),
          'tracks': meta.tracks.map((t) => {'title': t.title, 'artist': t.artist, 'duration': t.durationSeconds}).toList(),
        };
      }
    } catch (_) {}

    // 2. Try Backend Resolver
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
    // 1. Client-Side Spotify Import Service with Bloomee Two-Tier matching & duration tolerance
    try {
      final meta = await SpotifyImportService.fetchSpotifyMetadata(url);
      if (meta != null && meta.tracks.isNotEmpty) {
        final result = await SpotifyImportService.importPlaylistWithProgress(
          metadata: meta,
          onProgress: (_, __, ___, ____, _____) {},
        );
        if (result.importedSongs.isNotEmpty) {
          return result.importedSongs;
        }
      }
    } catch (_) {}

    // 2. Backend Fallback
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

    return [];
  }

  // ================= 6. YouTube Music Top Charts & Trending ================= //

  static Future<List<Song>> fetchYouTubeTrending({String? language}) async {
    final lang = language ?? (SettingsManager.preferredLanguages.isNotEmpty ? SettingsManager.preferredLanguages.first : 'Tamil');
    try {
      return await YouTubeClient.search('Trending $lang Hit Songs', limit: 20);
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
        final lang = item['language']?.toString() ?? item['lang']?.toString();
        songs.add(Song(
          id: item['id']?.toString() ?? '',
          title: Song.sanitize(item['title'] ?? item['name'], fallback: 'Unknown Title'),
          artist: Song.sanitize(item['artist'] ?? item['primaryArtists'] ?? item['singers'], fallback: 'Unknown Artist'),
          album: Song.sanitize(item['album'], fallback: 'Unknown Album'),
          albumId: item['album_id']?.toString() ?? item['albumId']?.toString(),
          artistId: item['artist_id']?.toString() ?? item['artistId']?.toString(),
          coverUrl: cover.toString(),
          streamUrl: stream?.toString(),
          duration: int.tryParse(item['duration']?.toString() ?? '0') ?? 0,
          source: (item['source']?.toString() == 'youtube' || (item['id']?.toString().length == 11)) ? 'youtube' : 'saavn',
          language: lang?.toLowerCase().trim(),
        ));
      }
    }
    return songs;
  }
}
