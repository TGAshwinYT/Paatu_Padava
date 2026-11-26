part of '../spotify_import_service.dart';

Future<SpotifyPlaylistMetadata?> _fetchSpotifyMetadataImpl(String url) async {
  final parsed = SpotifyImportService.parseSpotifyUrl(url);
  if (parsed == null) return null;

  final type = parsed['type']!;
  final id = parsed['id']!;

  // Tier A: Official Spotify Web API with Recursive Offset Pagination
  try {
    final token = await SpotifyImportService.getSpotifyAccessToken();
    if (token != null && token.isNotEmpty) {
      final authHeaders = {
        ...SpotifyImportService._webHeaders,
        'Authorization': 'Bearer $token',
      };

      if (type == 'playlist') {
        final metaUri = Uri.parse('https://api.spotify.com/v1/playlists/$id?fields=name,images,tracks.total');
        final metaRes = await http.get(metaUri, headers: authHeaders).timeout(const Duration(seconds: 8));

        if (metaRes.statusCode == 200) {
          final metaData = json.decode(metaRes.body);
          final title = Song.sanitize(metaData['name'] ?? 'Spotify Playlist');
          final images = metaData['images'] as List<dynamic>? ?? [];
          final coverUrl = images.isNotEmpty ? images[0]['url']?.toString() : null;
          final int totalExpected = metaData['tracks']?['total'] ?? 0;

          final List<SpotifyTrackItem> allTracks = [];
          int offset = 0;
          const int limit = 50;

          while (true) {
            final pageUri = Uri.parse(
              'https://api.spotify.com/v1/playlists/$id/tracks?offset=$offset&limit=$limit&fields=items(track(name,artists(name),album(name,images),duration_ms)),total',
            );
            final pageRes = await http.get(pageUri, headers: authHeaders).timeout(const Duration(seconds: 10));
            if (pageRes.statusCode != 200) break;

            final pageData = json.decode(pageRes.body);
            final items = pageData['items'] as List<dynamic>? ?? [];
            if (items.isEmpty) break;

            for (final item in items) {
              final track = item['track'];
              if (track == null) continue;

              final rawTitle = track['name']?.toString() ?? '';
              final artists = track['artists'] as List<dynamic>? ?? [];
              final artistName = artists.isNotEmpty ? artists[0]['name']?.toString() ?? '' : 'Artist';
              final albumName = track['album']?['name']?.toString();
              final durationSec = SpotifyImportService.parseDurationSeconds(track['duration_ms']);
              final trkImages = track['album']?['images'] as List<dynamic>? ?? [];
              final trkCover = trkImages.isNotEmpty ? trkImages[0]['url']?.toString() : null;
              final trackId = track['id']?.toString();
              final trackUri = track['uri']?.toString();

              if (rawTitle.isNotEmpty) {
                allTracks.add(SpotifyTrackItem(
                  title: Song.sanitize(rawTitle),
                  artist: Song.sanitize(artistName),
                  album: albumName != null ? Song.sanitize(albumName) : null,
                  durationSeconds: durationSec,
                  coverUrl: trkCover,
                  spotifyUri: trackUri,
                  spotifyId: trackId,
                ));
              }
            }

            offset += limit;
            if (totalExpected > 0 && offset >= totalExpected) break;
          }

          if (allTracks.isNotEmpty) {
            return SpotifyPlaylistMetadata(
              title: title,
              coverUrl: coverUrl,
              totalTracks: allTracks.length,
              tracks: allTracks,
            );
          }
        }
      } else if (type == 'album') {
        final metaUri = Uri.parse('https://api.spotify.com/v1/albums/$id?fields=name,images,tracks.total');
        final metaRes = await http.get(metaUri, headers: authHeaders).timeout(const Duration(seconds: 8));

        if (metaRes.statusCode == 200) {
          final metaData = json.decode(metaRes.body);
          final title = Song.sanitize(metaData['name'] ?? 'Spotify Album');
          final images = metaData['images'] as List<dynamic>? ?? [];
          final coverUrl = images.isNotEmpty ? images[0]['url']?.toString() : null;
          final int totalExpected = metaData['tracks']?['total'] ?? 0;

          final List<SpotifyTrackItem> allTracks = [];
          int offset = 0;
          const int limit = 50;

          while (true) {
            final pageUri = Uri.parse('https://api.spotify.com/v1/albums/$id/tracks?offset=$offset&limit=$limit');
            final pageRes = await http.get(pageUri, headers: authHeaders).timeout(const Duration(seconds: 10));
            if (pageRes.statusCode != 200) break;

            final pageData = json.decode(pageRes.body);
            final items = pageData['items'] as List<dynamic>? ?? [];
            if (items.isEmpty) break;

            for (final track in items) {
              final rawTitle = track['name']?.toString() ?? '';
              final artists = track['artists'] as List<dynamic>? ?? [];
              final artistName = artists.isNotEmpty ? artists[0]['name']?.toString() ?? '' : 'Artist';
              final durationSec = SpotifyImportService.parseDurationSeconds(track['duration_ms']);
              final trackId = track['id']?.toString();
              final trackUri = track['uri']?.toString();

              if (rawTitle.isNotEmpty) {
                allTracks.add(SpotifyTrackItem(
                  title: Song.sanitize(rawTitle),
                  artist: Song.sanitize(artistName),
                  album: title,
                  durationSeconds: durationSec,
                  coverUrl: coverUrl,
                  spotifyUri: trackUri,
                  spotifyId: trackId,
                ));
              }
            }

            offset += limit;
            if (totalExpected > 0 && offset >= totalExpected) break;
          }

          if (allTracks.isNotEmpty) {
            return SpotifyPlaylistMetadata(
              title: title,
              coverUrl: coverUrl,
              totalTracks: allTracks.length,
              tracks: allTracks,
            );
          }
        }
      } else if (type == 'track') {
        final trackUri = Uri.parse('https://api.spotify.com/v1/tracks/$id');
        final trackRes = await http.get(trackUri, headers: authHeaders).timeout(const Duration(seconds: 8));
        if (trackRes.statusCode == 200) {
          final track = json.decode(trackRes.body);
          final rawTitle = track['name']?.toString() ?? '';
          final artists = track['artists'] as List<dynamic>? ?? [];
          final artistName = artists.isNotEmpty ? artists[0]['name']?.toString() ?? '' : 'Artist';
          final durationSec = SpotifyImportService.parseDurationSeconds(track['duration_ms']);
          final trkImages = track['album']?['images'] as List<dynamic>? ?? [];
          final trkCover = trkImages.isNotEmpty ? trkImages[0]['url']?.toString() : null;

          if (rawTitle.isNotEmpty) {
            final item = SpotifyTrackItem(
              title: Song.sanitize(rawTitle),
              artist: Song.sanitize(artistName),
              album: track['album']?['name'] != null ? Song.sanitize(track['album']['name']) : null,
              durationSeconds: durationSec,
              coverUrl: trkCover,
              spotifyUri: track['uri']?.toString(),
              spotifyId: id,
            );
            return SpotifyPlaylistMetadata(
              title: item.title,
              coverUrl: trkCover,
              totalTracks: 1,
              tracks: [item],
            );
          }
        }
      }
    }
  } catch (e) {
    debugPrint('[SpotifyImportService] Tier A official API failed: $e');
  }

  // Tier B: Embed Scraping Fallback
  try {
    final embedUri = Uri.parse('https://open.spotify.com/embed/$type/$id');
    final embedRes = await http.get(embedUri, headers: SpotifyImportService._webHeaders).timeout(const Duration(seconds: 8));

    if (embedRes.statusCode == 200) {
      final body = embedRes.body;
      final match = RegExp(r'<script id="__NEXT_DATA__" type="application/json">([^<]+)</script>').firstMatch(body);
      if (match != null) {
        final nextData = json.decode(match.group(1)!);
        final entity = nextData['props']?['pageProps']?['state']?['data']?['entity'];
        if (entity != null) {
          final title = Song.sanitize(entity['title'] ?? entity['name'] ?? 'Spotify Playlist');
          final coverUrl = entity['coverArt']?['sources']?[0]?['url']?.toString();

          if (type == 'track') {
            final rawTitle = entity['title']?.toString() ?? entity['name']?.toString() ?? '';
            final artists = entity['artists'] as List<dynamic>? ?? [];
            final artistName = artists.isNotEmpty ? artists[0]['name']?.toString() ?? '' : (entity['subtitle']?.toString() ?? 'Artist');
            final durationSec = SpotifyImportService.parseDurationSeconds(entity['duration']);
            String? trackCover = coverUrl;
            if (trackCover == null) {
              final images = entity['visualIdentity']?['image'] as List<dynamic>? ?? [];
              if (images.isNotEmpty) trackCover = images.last['url']?.toString();
            }

            if (rawTitle.isNotEmpty) {
              final item = SpotifyTrackItem(
                title: Song.sanitize(rawTitle),
                artist: Song.sanitize(artistName),
                durationSeconds: durationSec,
                coverUrl: trackCover,
                spotifyUri: 'spotify:track:$id',
                spotifyId: id,
              );
              return SpotifyPlaylistMetadata(
                title: item.title,
                coverUrl: trackCover,
                totalTracks: 1,
                tracks: [item],
              );
            }
          }

          final trackList = entity['trackList'] as List<dynamic>? ?? [];
          final List<SpotifyTrackItem> tracks = [];
          for (final item in trackList) {
            final rawTitle = item['title']?.toString() ?? '';
            final subtitle = item['subtitle']?.toString() ?? '';
            final durationSec = SpotifyImportService.parseDurationSeconds(item['duration']);
            final uri = item['uri']?.toString() ?? '';
            final trackId = uri.startsWith('spotify:track:') ? uri.replaceFirst('spotify:track:', '') : null;

            if (rawTitle.isNotEmpty) {
              tracks.add(SpotifyTrackItem(
                title: Song.sanitize(rawTitle),
                artist: Song.sanitize(subtitle),
                durationSeconds: durationSec,
                coverUrl: (type == 'album' ? coverUrl : null),
                spotifyUri: uri.isNotEmpty ? uri : null,
                spotifyId: trackId,
              ));
            }
          }

          if (tracks.isNotEmpty) {
            return SpotifyPlaylistMetadata(
              title: title,
              coverUrl: coverUrl,
              totalTracks: tracks.length,
              tracks: tracks,
            );
          }
        }
      }
    }
  } catch (e) {
    debugPrint('[SpotifyImportService] Tier B embed scrape failed: $e');
  }

  // Tier C: Jina Reader Markdown Fallback
  try {
    final jinaUri = Uri.parse('https://r.jina.ai/${url.trim()}');
    final res = await http.get(jinaUri).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200 && res.body.isNotEmpty) {
      final text = res.body;

      String title = 'Spotify Playlist';
      final tm = RegExp(r'Title:\s*([^|\n]+)').firstMatch(text);
      if (tm != null && tm.group(1) != null) {
        title = Song.sanitize(tm.group(1)!.trim());
      }

      String? coverUrl;
      final cm = RegExp(r'!\[.*?\]\((https://i\.scdn\.co/image/[^\)]+)\)').firstMatch(text);
      if (cm != null && cm.group(1) != null) coverUrl = cm.group(1)!;

      final tracksPattern = RegExp(
        r'\[([^\]]+)\]\(https://open\.spotify\.com/track/([^\)\?]+)[^\)]*\)\s*\n\s*\[([^\]]+)\]\(https://open\.spotify\.com/artist/[^\)]+\)',
      );
      final List<SpotifyTrackItem> tracks = [];
      for (final m in tracksPattern.allMatches(text)) {
        final tTitle = Song.sanitize(m.group(1)?.trim() ?? '');
        final trackId = m.group(2)?.trim();
        final tArtist = Song.sanitize(m.group(3)?.trim() ?? '');
        if (tTitle.isNotEmpty) {
          tracks.add(SpotifyTrackItem(
            title: tTitle,
            artist: tArtist,
            durationSeconds: 0,
            coverUrl: (type == 'album' ? coverUrl : null),
            spotifyUri: trackId != null ? 'spotify:track:$trackId' : null,
            spotifyId: trackId,
          ));
        }
      }

      if (tracks.isNotEmpty) {
        return SpotifyPlaylistMetadata(
          title: title,
          coverUrl: coverUrl,
          totalTracks: tracks.length,
          tracks: tracks,
        );
      }
    }
  } catch (e) {
    AppLogger.log('SpotifyImportService', 'fetchSpotifyMetadata notice: $e');
  }

  return null;
}
