import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';

class ApiClient {
  static const String baseUrl = 'https://tgashwinyt-paatu-padava.hf.space';
  static final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Smart Shuffle: requests recommendation graph nearest-neighbor order from backend
  static Future<List<String>> fetchSmartShuffle(List<String> queueIds, String? currentSongId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/music/shuffle-order');
      final body = json.encode({
        'queue_ids': queueIds,
        'current_song_id': currentSongId,
      });

      final response = await http.post(uri, headers: _headers, body: body).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final ordered = (data['ordered_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList();
        if (ordered != null && ordered.isNotEmpty) {
          return ordered;
        }
      }
    } catch (_) {}
    // Fallback: local shuffle maintaining current song at front
    final fallback = List<String>.from(queueIds);
    if (currentSongId != null) {
      fallback.remove(currentSongId);
      fallback.shuffle();
      fallback.insert(0, currentSongId);
    } else {
      fallback.shuffle();
    }
    return fallback;
  }

  /// AI Recommendations / Radio Mix: fetches personalized similar tracks
  static Future<List<Song>> fetchRecommendations(String songId, {String? artist, String? language}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/music/recommendations');
      final body = json.encode({
        'song_id': songId,
        'artist': artist,
        'language': language,
      });

      final response = await http.post(uri, headers: _headers, body: body).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['recommendations'] ?? data['data'] ?? data) as List<dynamic>? ?? [];
        return _mapSongs(list);
      }
    } catch (_) {}
    return [];
  }

  /// For You Mix: personalized queue learned from collaborative filtering
  static Future<List<Song>> fetchForYou() async {
    try {
      final uri = Uri.parse('$baseUrl/api/music/for-you');
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final queue = data['queue'] as List<dynamic>? ?? [];
        return _mapSongs(queue);
      }
    } catch (_) {}
    return [];
  }

  /// Lyrics
  static Future<String?> fetchLyrics(String songId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/music/lyrics/$songId');
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lyrics = data['lyrics']?.toString() ?? data['snippet']?.toString();
        if (lyrics != null && lyrics.trim().isNotEmpty) {
          return lyrics.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Helper to convert API JSON items to Song models
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
          source: 'saavn',
        ));
      }
    }
    return songs;
  }
}
