import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../domain/models/track_entity.dart';
import 'app_logger.dart';

/// Client for the decentralized Audius Music catalog (100% Free, No API Key required).
/// Provides open music search, trending charts, and high-bitrate audio streams.
class AudiusClient {
  static const String _appName = 'PaatuPadava';
  static const String _defaultHost = 'https://api.audius.co';
  static String _activeHost = _defaultHost;
  static DateTime? _hostLastChecked;

  static final http.Client _httpClient = http.Client();

  /// Dynamically selects a healthy discovery node from https://api.audius.co
  static Future<String> getHealthyHost() async {
    if (_hostLastChecked != null &&
        DateTime.now().difference(_hostLastChecked!) < const Duration(hours: 1) &&
        _activeHost.isNotEmpty) {
      return _activeHost;
    }

    try {
      final uri = Uri.parse('https://api.audius.co');
      final response = await _httpClient.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List? nodes = decoded['data'] as List?;
        if (nodes != null && nodes.isNotEmpty) {
          final healthy = nodes.first.toString().replaceAll(RegExp(r'/+$'), '');
          if (healthy.startsWith('http')) {
            _activeHost = healthy;
            _hostLastChecked = DateTime.now();
            AppLogger.log('AudiusClient', 'Selected healthy discovery node: $_activeHost');
            return _activeHost;
          }
        }
      }
    } catch (e) {
      AppLogger.log('AudiusClient', 'Dynamic host resolution notice: $e. Falling back to $_defaultHost');
    }

    _activeHost = _defaultHost;
    _hostLastChecked = DateTime.now();
    return _activeHost;
  }

  /// Resolves the direct, playable audio stream URL for an Audius track.
  static String getStreamUrl(String trackId, {String? host}) {
    final cleanId = trackId.trim();
    final node = host ?? _activeHost;
    return '$node/v1/tracks/$cleanId/stream?app_name=$_appName';
  }

  /// Searches the Audius catalog returning a list of [TrackEntity] instances.
  static Future<List<TrackEntity>> searchTracks(String query, {int limit = 20}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final host = await getHealthyHost();
    final hostsToTry = [host, _defaultHost];

    for (final node in hostsToTry.toSet()) {
      try {
        final uri = Uri.parse('$node/v1/tracks/search').replace(queryParameters: {
          'query': cleanQuery,
          'app_name': _appName,
          'limit': limit.toString(),
        });

        final response = await _httpClient.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List tracks = data['data'] ?? [];
          return tracks.map((t) => _mapToTrackEntity(t, node)).whereType<TrackEntity>().toList();
        }
      } catch (e) {
        AppLogger.log('AudiusClient', 'Search failed on $node for "$cleanQuery": $e');
      }
    }
    return [];
  }

  /// Searches the Audius catalog returning a list of [Song] instances for app-wide player compatibility.
  static Future<List<Song>> search(String query, {int limit = 20}) async {
    final tracks = await searchTracks(query, limit: limit);
    return tracks.map((t) => t.toSong()).toList();
  }

  /// Fetches top trending tracks on Audius returning a list of [TrackEntity] instances.
  static Future<List<TrackEntity>> getTrendingTrackEntities({int limit = 20}) async {
    final host = await getHealthyHost();
    final hostsToTry = [host, _defaultHost];

    for (final node in hostsToTry.toSet()) {
      try {
        final uri = Uri.parse('$node/v1/tracks/trending').replace(queryParameters: {
          'app_name': _appName,
          'limit': limit.toString(),
        });

        final response = await _httpClient.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List tracks = data['data'] ?? [];
          return tracks.map((t) => _mapToTrackEntity(t, node)).whereType<TrackEntity>().toList();
        }
      } catch (e) {
        AppLogger.log('AudiusClient', 'Trending tracks failed on $node: $e');
      }
    }
    return [];
  }

  /// Fetches top trending tracks on Audius as [Song] instances.
  static Future<List<Song>> getTrendingTracks({int limit = 20}) async {
    final entities = await getTrendingTrackEntities(limit: limit);
    return entities.map((t) => t.toSong()).toList();
  }

  /// Helper to map Audius JSON payload to a strongly typed [TrackEntity].
  static TrackEntity? _mapToTrackEntity(dynamic jsonMap, String host) {
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
    final streamUrl = '$host/v1/tracks/$id/stream?app_name=$_appName';

    return TrackEntity(
      id: id,
      title: Song.sanitize(rawTitle),
      artist: Song.sanitize(artistName),
      album: genre,
      coverUrl: coverUrl,
      duration: durationSec,
      streamUrl: streamUrl,
      source: 'audius',
    );
  }
}
