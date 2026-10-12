import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'app_logger.dart';

/// Client for the decentralized Audius Music catalog (100% Free, No API Key required).
/// Provides open music search, trending charts, and high-bitrate audio streams.
class AudiusClient {
  static const String _appName = 'paatu_padava';
  static const String _primaryHost = 'https://discoveryprovider.audius.co/v1';
  static const List<String> _fallbackHosts = [
    'https://audius-discovery-3.altego.net/v1',
    'https://discoveryprovider.audius.co/v1',
  ];

  static final http.Client _httpClient = http.Client();

  /// Resolves the direct, playable audio stream URL for an Audius track.
  static String getStreamUrl(String trackId) {
    final cleanId = trackId.trim();
    return '$_primaryHost/tracks/$cleanId/stream?app_name=$_appName';
  }

  /// Searches the Audius catalog for tracks matching the query.
  static Future<List<Song>> search(String query, {int limit = 20}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    for (final host in [_primaryHost, ..._fallbackHosts]) {
      try {
        final uri = Uri.parse('$host/tracks/search').replace(queryParameters: {
          'query': cleanQuery,
          'app_name': _appName,
          'limit': limit.toString(),
        });

        final response = await _httpClient.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List tracks = data['data'] ?? [];
          return tracks.map((t) => _mapToSong(t)).whereType<Song>().toList();
        }
      } catch (e) {
        AppLogger.log('AudiusClient', 'Search failed on $host for "$cleanQuery": $e');
      }
    }
    return [];
  }

  /// Fetches top trending tracks on Audius.
  static Future<List<Song>> getTrendingTracks({int limit = 20}) async {
    for (final host in [_primaryHost, ..._fallbackHosts]) {
      try {
        final uri = Uri.parse('$host/tracks/trending').replace(queryParameters: {
          'app_name': _appName,
          'limit': limit.toString(),
        });

        final response = await _httpClient.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List tracks = data['data'] ?? [];
          return tracks.map((t) => _mapToSong(t)).whereType<Song>().toList();
        }
      } catch (e) {
        AppLogger.log('AudiusClient', 'Trending tracks failed on $host: $e');
      }
    }
    return [];
  }

  /// Helper to map Audius JSON payload to a strongly typed [Song].
  static Song? _mapToSong(dynamic jsonMap) {
    if (jsonMap == null || jsonMap is! Map) return null;
    final id = jsonMap['id']?.toString() ?? jsonMap['track_id']?.toString() ?? '';
    if (id.isEmpty) return null;

    final rawTitle = jsonMap['title']?.toString() ?? 'Unknown Track';
    final user = jsonMap['user'] as Map<String, dynamic>?;
    final artistName = user?['name']?.toString() ?? user?['handle']?.toString() ?? 'Audius Artist';
    final durationSec = (jsonMap['duration'] as num?)?.toInt() ?? 0;

    final artwork = jsonMap['artwork'] as Map<String, dynamic>?;
    final coverUrl = artwork?['480x480']?.toString() ??
        artwork?['150x150']?.toString() ??
        artwork?['1000x1000']?.toString() ??
        '';

    final genre = jsonMap['genre']?.toString() ?? 'Audius Music';

    return Song(
      id: id,
      title: Song.sanitize(rawTitle),
      artist: Song.sanitize(artistName),
      album: genre,
      coverUrl: coverUrl,
      duration: durationSec,
      streamUrl: getStreamUrl(id),
      source: 'audius',
    );
  }
}
