part of '../spotify_import_service.dart';

Future<List<TrackEntity>> _getTop10HitsImpl(String language) async {
  final cleanLang = language.trim();
  if (cleanLang.isEmpty) return [];

  try {
    final token = await SpotifyImportService.getSpotifyAccessToken();
    if (token == null || token.isEmpty) return [];

    final query = Uri.encodeComponent('$cleanLang Top Hits');
    final uri = Uri.parse('https://api.spotify.com/v1/search?q=$query&type=track&market=IN&limit=10');
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      ...SpotifyImportService._webHeaders,
    }).timeout(const Duration(seconds: 3));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['tracks']?['items'] as List<dynamic>? ?? [];
      final List<TrackEntity> tracks = [];

      for (final item in items) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        final rawTitle = item['name']?.toString() ?? '';
        final artists = item['artists'] as List<dynamic>? ?? [];
        final artistName = artists.isNotEmpty ? artists[0]['name']?.toString() ?? 'Artist' : 'Artist';
        final album = item['album']?['name']?.toString() ?? '';
        final images = item['album']?['images'] as List<dynamic>? ?? [];
        final coverUrl = images.isNotEmpty ? images[0]['url']?.toString() ?? '' : '';
        final durationSec = SpotifyImportService.parseDurationSeconds(item['duration_ms']);

        if (rawTitle.isNotEmpty) {
          tracks.add(TrackEntity(
            id: id,
            title: Song.sanitize(rawTitle),
            artist: Song.sanitize(artistName),
            album: Song.sanitize(album),
            coverUrl: coverUrl,
            duration: durationSec,
            streamUrl: '',
            source: 'spotify',
            language: cleanLang.toLowerCase(),
          ));
        }
      }
      return tracks;
    }
  } catch (e) {
    AppLogger.log('SpotifyImportService', 'getTop10Hits failed: $e');
  }
  return [];
}

Future<List<Map<String, dynamic>>> _getPlaylistsImpl(String language) async {
  final cleanLang = language.trim();
  if (cleanLang.isEmpty) return [];

  try {
    final token = await SpotifyImportService.getSpotifyAccessToken();
    if (token == null || token.isEmpty) return [];

    final query = Uri.encodeComponent('$cleanLang Hits');
    final uri = Uri.parse('https://api.spotify.com/v1/search?q=$query&type=playlist&market=IN&limit=15');
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      ...SpotifyImportService._webHeaders,
    }).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['playlists']?['items'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> playlists = [];

      for (final item in items) {
        if (item is! Map) continue;
        final ownerId = item['owner']?['id']?.toString().toLowerCase();
        if (ownerId == 'spotify') continue; // Skip editorial playlists (avoids 404/403)

        final id = item['id']?.toString() ?? '';
        final title = item['name']?.toString() ?? '';
        final images = item['images'] as List<dynamic>? ?? [];
        final coverUrl = images.isNotEmpty ? images[0]['url']?.toString() ?? '' : '';
        final total = item['tracks']?['total'] is int ? item['tracks']['total'] as int : 0;

        if (id.isNotEmpty && title.isNotEmpty) {
          playlists.add({
            'id': id,
            'title': Song.sanitize(title),
            'cover_url': coverUrl,
            'song_count': total,
            'owner': item['owner']?['display_name']?.toString() ?? ownerId ?? '',
          });
        }
      }
      return playlists;
    }
  } catch (e) {
    AppLogger.log('SpotifyImportService', 'getPlaylists failed: $e');
  }
  return [];
}

Future<String?> _getArtistProfileImageImpl(String artistName) async {
  final clean = artistName.trim();
  if (clean.isEmpty) return null;

  try {
    final token = await SpotifyImportService.getSpotifyAccessToken();
    if (token == null || token.isEmpty) return null;

    final query = Uri.encodeComponent(clean);
    final uri = Uri.parse('https://api.spotify.com/v1/search?q=$query&type=artist&market=IN&limit=1');
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      ...SpotifyImportService._webHeaders,
    }).timeout(const Duration(seconds: 6));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['artists']?['items'] as List<dynamic>? ?? [];
      if (items.isNotEmpty) {
        final images = items[0]['images'] as List<dynamic>? ?? [];
        if (images.isNotEmpty) {
          final url = images[0]['url']?.toString();
          if (url != null && url.isNotEmpty) {
            return url;
          }
        }
      }
    }
  } catch (e) {
    AppLogger.log('SpotifyImportService', 'getArtistProfileImage notice: $e');
  }
  return null;
}

Song _synthesizeTrackImpl(
  SpotifyTrackItem track, {
  String? effectiveCover,
  Song? fallbackCandidate,
}) {
  final cleanCover = (effectiveCover != null && effectiveCover.isNotEmpty && !CoverArtResolver.isPlaylistCover(effectiveCover))
      ? effectiveCover
      : ((track.coverUrl != null && track.coverUrl!.isNotEmpty && !CoverArtResolver.isPlaylistCover(track.coverUrl!))
          ? CoverArtResolver.upgradeSpotifyCover(track.coverUrl!)
          : (fallbackCandidate?.coverUrl ?? ''));

  final effectiveId = (fallbackCandidate != null && fallbackCandidate.id.isNotEmpty)
      ? fallbackCandidate.id
      : (track.spotifyId != null ? 'yt_spotify_${track.spotifyId}' : 'synth_${DateTime.now().millisecondsSinceEpoch}_${track.title.hashCode}');

  return Song(
    id: effectiveId,
    title: Song.sanitize(track.title),
    artist: Song.sanitize(track.artist),
    album: track.album != null && track.album!.isNotEmpty ? Song.sanitize(track.album!) : 'Spotify Import',
    coverUrl: cleanCover,
    duration: track.durationSeconds > 0 ? track.durationSeconds : (fallbackCandidate?.duration ?? 0),
    source: 'youtube',
    streamUrl: fallbackCandidate?.streamUrl ?? '',
  );
}
