import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:html_unescape/html_unescape.dart';
import '../models/song.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';

/// Single Spotify Track representation extracted from Spotify Web API or Embed
class SpotifyTrackItem {
  final String title;
  final String artist;
  final String? album;
  final int durationSeconds;
  final String? coverUrl;

  const SpotifyTrackItem({
    required this.title,
    required this.artist,
    this.album,
    required this.durationSeconds,
    this.coverUrl,
  });
}

/// Spotify Playlist or Album Metadata containing all paginated tracks
class SpotifyPlaylistMetadata {
  final String title;
  final String? coverUrl;
  final int totalTracks;
  final List<SpotifyTrackItem> tracks;

  const SpotifyPlaylistMetadata({
    required this.title,
    this.coverUrl,
    required this.totalTracks,
    required this.tracks,
  });
}

/// Result of importing and matching tracks from Spotify
class SpotifyImportResult {
  final String playlistTitle;
  final String? coverUrl;
  final int totalTracks;
  final List<Song> importedSongs;
  final List<SpotifyTrackItem> skippedTracks;

  const SpotifyImportResult({
    required this.playlistTitle,
    this.coverUrl,
    required this.totalTracks,
    required this.importedSongs,
    required this.skippedTracks,
  });

  bool get hasSkipped => skippedTracks.isNotEmpty;
  double get successRate => totalTracks > 0 ? (importedSongs.length / totalTracks) : 0.0;
}

class SpotifyImportService {
  static final HtmlUnescape _unescape = HtmlUnescape();

  static const Map<String, String> _webHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/html, */*',
  };

  /// Parses duration into seconds regardless of format (milliseconds, seconds, or "mm:ss")
  static int parseDurationSeconds(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) {
      if (raw > 1000) return (raw / 1000).round();
      return raw.toInt();
    }
    final str = raw.toString().trim();
    if (str.isEmpty) return 0;
    if (str.contains(':')) {
      final parts = str.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        return (m * 60) + s;
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        return (h * 3600) + (m * 60) + s;
      }
    }
    final numVal = num.tryParse(str);
    if (numVal != null) {
      if (numVal > 1000) return (numVal / 1000).round();
      return numVal.toInt();
    }
    return 0;
  }

  /// Clean raw Spotify track titles:
  /// Strips metadata tags like (From "Movie"), [Remastered], (Original Motion Picture Soundtrack),
  /// [Official Video], and sanitizes HTML entities (&quot;, &#39;, &amp;).
  static String cleanTrackTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';
    var clean = _unescape.convert(Song.sanitize(rawTitle));

    // 0. Handle slash separation in dual-language titles (e.g. "Puthu Mazha / പുതുമഴ")
    if (clean.contains('/')) {
      final parts = clean.split('/');
      final latinPart = parts.firstWhere(
        (p) => RegExp(r'[a-zA-Z]').hasMatch(p),
        orElse: () => parts.first,
      );
      clean = latinPart.trim();
    }

    // 0b. Remove Indian regional scripts in parentheses/brackets e.g. (പുതുമഴ), [புதுமழை]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^\)\]]*[\u0D00-\u0D7F\u0B80-\u0BFF\u0900-\u097F\u0C00-\u0C7F\u0C80-\u0CFF][^\)\]]*[\)\]]'),
      '',
    );

    // 1. Remove: (From "Movie") or [From "Movie"] with all quote characters
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][Ff]rom\s+["\u201c\u201d\u2018\u2019]?[^)\u201d\]]+["\u201c\u201d\u2018\u2019]?[\)\]]', caseSensitive: false),
      '',
    );

    // 2. Remove: (Original Motion Picture Soundtrack), (OST), [Soundtrack Version]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:motion picture|soundtrack|ost)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 3. Remove: [Remastered...] or (Remastered...) or [2023 Remaster]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*remaster(?:ed)?[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 4. Remove: (Official Video) or [Official Audio], (Music Video), (Audio), (Lyric Video)
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:official|audio|lyric|video)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 5. Remove: (Feat. ...) or [feat. ...] or (ft. ...)
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][Ff](?:eat\.?|t\.)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 6. Remove: (Deluxe Edition), [Deluxe], [Bonus Track]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:deluxe|bonus\s*track)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 7. Suffix: " - Live" or " - Single" or " - Remastered"
    clean = clean.replaceAll(RegExp(r'\s*-\s*(?:live|single|stereo|mono|edit|remaster(?:ed)?(?:\s*\d{4})?)$', caseSensitive: false), '');

    // 8. If Latin title exists alongside standalone regional script, strip the regional script
    if (RegExp(r'[a-zA-Z]').hasMatch(clean)) {
      clean = clean.replaceAll(RegExp(r'[\u0D00-\u0D7F\u0B80-\u0BFF\u0900-\u097F\u0C00-\u0C7F\u0C80-\u0CFF]+'), '');
    }

    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : Song.sanitize(rawTitle);
  }

  /// Clean primary artist name (strips secondary featured artists)
  static String cleanArtistName(String rawArtist) {
    final sanitized = _unescape.convert(Song.sanitize(rawArtist));
    final first = sanitized.split(RegExp(r'[,&/]')).first.trim();
    return first.isNotEmpty ? first : sanitized;
  }

  /// Check if candidate title contains unwanted tags (karaoke, cover, reaction, snippet)
  static bool _isUnwantedType(String candidateTitle, String originalTitle) {
    final lowerCand = candidateTitle.toLowerCase();
    final lowerOrig = originalTitle.toLowerCase();

    const unwantedTags = [
      'karaoke',
      'instrumental',
      'cover by',
      'dance cover',
      'reaction',
      'slowed',
      'reverb',
      '8d audio',
      'chipmunk',
      'lo-fi remix',
      'lofi remix',
      'tribute',
      'ringtone',
      'status',
      'whatsapp status',
    ];

    for (final tag in unwantedTags) {
      if (lowerCand.contains(tag) && !lowerOrig.contains(tag)) {
        return true;
      }
    }
    return false;
  }

  /// Extracts entity type ('playlist', 'album', 'track') and Spotify ID from link
  static Map<String, String>? parseSpotifyUrl(String url) {
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    if (uri == null) return null;

    final segments = uri.pathSegments;
    for (int i = 0; i < segments.length - 1; i++) {
      final type = segments[i].toLowerCase();
      if (type == 'playlist' || type == 'album' || type == 'track') {
        final id = segments[i + 1].split('?').first;
        if (id.isNotEmpty) {
          return {'type': type, 'id': id};
        }
      }
    }
    return null;
  }

  /// Fetches an anonymous temporary Web Player Bearer Token from Spotify
  static Future<String?> _getAnonymousSpotifyToken() async {
    try {
      final tokenUri = Uri.parse(
        'https://open.spotify.com/get_access_token?reason=transport&productType=web_player',
      );
      final response = await http.get(tokenUri, headers: _webHeaders).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['accessToken']?.toString();
      }
    } catch (_) {}
    return null;
  }

  /// 1. Paginated Spotify Playlist / Album Fetcher:
  /// Fetches all pages recursively (?offset=N&limit=50) until all songs are imported.
  static Future<SpotifyPlaylistMetadata?> fetchSpotifyMetadata(String url) async {
    final parsed = parseSpotifyUrl(url);
    if (parsed == null) return null;

    final type = parsed['type']!;
    final id = parsed['id']!;

    // ── Tier A: Official Spotify Web API with Recursive Offset Pagination ──
    try {
      final token = await _getAnonymousSpotifyToken();
      if (token != null && token.isNotEmpty) {
        final authHeaders = {
          ..._webHeaders,
          'Authorization': 'Bearer $token',
        };

        if (type == 'playlist') {
          // Fetch playlist metadata
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

            // Loop offset pagination until all tracks in the playlist are fetched
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
                final durationSec = parseDurationSeconds(track['duration_ms']);
                final trkImages = track['album']?['images'] as List<dynamic>? ?? [];
                final trkCover = trkImages.isNotEmpty ? trkImages[0]['url']?.toString() : coverUrl;

                if (rawTitle.isNotEmpty) {
                  allTracks.add(SpotifyTrackItem(
                    title: Song.sanitize(rawTitle),
                    artist: Song.sanitize(artistName),
                    album: albumName != null ? Song.sanitize(albumName) : null,
                    durationSeconds: durationSec,
                    coverUrl: trkCover,
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
          // Album offset pagination
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
                final durationSec = parseDurationSeconds(track['duration_ms']);

                if (rawTitle.isNotEmpty) {
                  allTracks.add(SpotifyTrackItem(
                    title: Song.sanitize(rawTitle),
                    artist: Song.sanitize(artistName),
                    album: title,
                    durationSeconds: durationSec,
                    coverUrl: coverUrl,
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
          // Single track import
          final trackUri = Uri.parse('https://api.spotify.com/v1/tracks/$id');
          final trackRes = await http.get(trackUri, headers: authHeaders).timeout(const Duration(seconds: 8));
          if (trackRes.statusCode == 200) {
            final track = json.decode(trackRes.body);
            final rawTitle = track['name']?.toString() ?? '';
            final artists = track['artists'] as List<dynamic>? ?? [];
            final artistName = artists.isNotEmpty ? artists[0]['name']?.toString() ?? '' : 'Artist';
            final durationSec = parseDurationSeconds(track['duration_ms']);
            final trkImages = track['album']?['images'] as List<dynamic>? ?? [];
            final trkCover = trkImages.isNotEmpty ? trkImages[0]['url']?.toString() : null;

            if (rawTitle.isNotEmpty) {
              final item = SpotifyTrackItem(
                title: Song.sanitize(rawTitle),
                artist: Song.sanitize(artistName),
                album: track['album']?['name'] != null ? Song.sanitize(track['album']['name']) : null,
                durationSeconds: durationSec,
                coverUrl: trkCover,
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

    // ── Tier B: Embed Scraping Fallback ──
    try {
      final embedUri = Uri.parse('https://open.spotify.com/embed/$type/$id');
      final embedRes = await http.get(embedUri, headers: _webHeaders).timeout(const Duration(seconds: 8));

      if (embedRes.statusCode == 200) {
        final body = embedRes.body;
        final match = RegExp(r'<script id="__NEXT_DATA__" type="application/json">([^<]+)</script>').firstMatch(body);
        if (match != null) {
          final nextData = json.decode(match.group(1)!);
          final entity = nextData['props']?['pageProps']?['state']?['data']?['entity'];
          if (entity != null) {
            final title = Song.sanitize(entity['title'] ?? entity['name'] ?? 'Spotify Playlist');
            final coverUrl = entity['coverArt']?['sources']?[0]?['url']?.toString();
            final trackList = entity['trackList'] as List<dynamic>? ?? [];

            final List<SpotifyTrackItem> tracks = [];
            for (final item in trackList) {
              final rawTitle = item['title']?.toString() ?? '';
              final subtitle = item['subtitle']?.toString() ?? '';
              final durationSec = parseDurationSeconds(item['duration']);

              if (rawTitle.isNotEmpty) {
                tracks.add(SpotifyTrackItem(
                  title: Song.sanitize(rawTitle),
                  artist: Song.sanitize(subtitle),
                  durationSeconds: durationSec,
                  coverUrl: coverUrl,
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

    // ── Tier C: Jina Reader Markdown Fallback ──
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
        if (cm != null && cm.group(1) != null) {
          coverUrl = cm.group(1)!;
        }

        final tracksPattern = RegExp(
          r'\[([^\]]+)\]\(https://open\.spotify\.com/track/[^\)]+\)\s*\n\s*\[([^\]]+)\]\(https://open\.spotify\.com/artist/[^\)]+\)',
        );
        final List<SpotifyTrackItem> tracks = [];
        for (final m in tracksPattern.allMatches(text)) {
          final tTitle = Song.sanitize(m.group(1)?.trim() ?? '');
          final tArtist = Song.sanitize(m.group(2)?.trim() ?? '');
          if (tTitle.isNotEmpty) {
            tracks.add(SpotifyTrackItem(
              title: tTitle,
              artist: tArtist,
              durationSeconds: 0,
              coverUrl: coverUrl,
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
    } catch (_) {}

    return null;
  }

  /// 2. Bloomee-Style Two-Tier Matching:
  /// Matches candidate tracks using fuzzy similarity (tokenSetRatio > 70%)
  /// and duration tolerance (+/- 10s difference from Spotify's duration).
  ///
  /// Priority:
  /// 1. JioSaavn for direct 320kbps CDN stream.
  /// 2. YouTube audio fallback if JioSaavn score < 70.
  static Future<Song?> matchSingleTrack(
    SpotifyTrackItem track, {
    String? preferredLanguage,
  }) async {
    final cleanTitle = cleanTrackTitle(track.title);
    final primaryArtist = cleanArtistName(track.artist);
    final targetDuration = track.durationSeconds;

    // ── Tier 1: Search JioSaavn across all languages for pristine 320kbps Stream ──
    // Do not constrain to a single blanket language filter so multi-lingual playlists match accurately.
    try {
      final saavnResults = await SaavnClient.search(
        '$cleanTitle $primaryArtist',
        limit: 8,
      );

      Song? bestSaavn;
      int bestSaavnScore = -1;

      for (final candidate in saavnResults) {
        if (_isUnwantedType(candidate.title, cleanTitle)) continue;

        final candidateCleanTitle = cleanTrackTitle(candidate.title);
        final candidateCleanArtist = cleanArtistName(candidate.artist);

        final titleSim = tokenSetRatio(cleanTitle.toLowerCase(), candidateCleanTitle.toLowerCase());
        final artistSim = tokenSetRatio(primaryArtist.toLowerCase(), candidateCleanArtist.toLowerCase());

        // Hard rejection if title similarity is too low
        if (titleSim < 50) continue;

        int score = (titleSim * 0.7 + artistSim * 0.3).round();

        // Duration tolerance verification
        if (targetDuration > 0 && candidate.duration > 0) {
          final diff = (candidate.duration - targetDuration).abs();
          if (diff <= 10) {
            score += 15; // Within +/- 10s tolerance
          } else if (diff <= 20) {
            score += 5;
          } else if (diff > 35) {
            score -= 35; // Discard covers, snippets, or teasers
          } else if (diff > 60) {
            score -= 60;
          }
        }

        // Slight tie-breaker bonus for user's preferred language (never exclusionary)
        if (preferredLanguage != null && candidate.language == preferredLanguage.toLowerCase().trim()) {
          score += 5;
        }

        if (score > bestSaavnScore) {
          bestSaavnScore = score;
          bestSaavn = candidate;
        }
      }

      if (bestSaavn != null && bestSaavnScore >= 70) {
        if ((bestSaavn.coverUrl.isEmpty || bestSaavn.coverUrl.contains('default')) &&
            track.coverUrl != null &&
            track.coverUrl!.isNotEmpty) {
          bestSaavn = bestSaavn.copyWith(coverUrl: track.coverUrl);
        }
        return bestSaavn;
      }
    } catch (_) {}

    // ── Tier 2: YouTube Fallback ──
    try {
      final ytResults = await YouTubeClient.search(
        '$cleanTitle $primaryArtist audio',
        limit: 6,
      );

      Song? bestYt;
      int bestYtScore = -1;

      for (final candidate in ytResults) {
        if (_isUnwantedType(candidate.title, cleanTitle)) continue;

        final candidateCleanTitle = cleanTrackTitle(candidate.title);
        final candidateCleanArtist = cleanArtistName(candidate.artist);

        final titleSim = tokenSetRatio(cleanTitle.toLowerCase(), candidateCleanTitle.toLowerCase());
        final artistSim = tokenSetRatio(primaryArtist.toLowerCase(), candidateCleanArtist.toLowerCase());

        if (titleSim < 50) continue;

        int score = (titleSim * 0.7 + artistSim * 0.3).round();

        // Duration tolerance verification
        if (targetDuration > 0 && candidate.duration > 0) {
          final diff = (candidate.duration - targetDuration).abs();
          if (diff <= 10) {
            score += 15;
          } else if (diff <= 20) {
            score += 5;
          } else if (diff > 35) {
            score -= 35;
          } else if (diff > 60) {
            score -= 60;
          }
        }

        if (score > bestYtScore) {
          bestYtScore = score;
          bestYt = candidate;
        }
      }

      if (bestYt != null && bestYtScore >= 65) {
        if (track.coverUrl != null && track.coverUrl!.isNotEmpty) {
          bestYt = bestYt.copyWith(coverUrl: track.coverUrl);
        }
        return bestYt;
      }
    } catch (_) {}

    return null;
  }

  /// 3. Complete Batch Importer with Progress Notification
  static Future<SpotifyImportResult> importPlaylistWithProgress({
    required SpotifyPlaylistMetadata metadata,
    required void Function(
      int current,
      int total,
      double progress,
      String status,
      Song? matched,
    ) onProgress,
    String? preferredLanguage,
    bool Function()? isCancelled,
  }) async {
    final List<Song> importedSongs = [];
    final List<SpotifyTrackItem> skippedTracks = [];
    final total = metadata.tracks.length;

    for (int i = 0; i < total; i++) {
      if (isCancelled?.call() == true) {
        debugPrint('[SpotifyImportService] Import cancelled by user at track $i of $total');
        break;
      }

      final track = metadata.tracks[i];
      final currentNum = i + 1;
      final progress = currentNum / (total > 0 ? total : 1);

      onProgress(
        currentNum,
        total,
        progress,
        'Matching track $currentNum of $total: "${track.title}"...',
        null,
      );

      final matched = await matchSingleTrack(track, preferredLanguage: preferredLanguage);
      if (matched != null) {
        importedSongs.add(matched);
        onProgress(
          currentNum,
          total,
          progress,
          'Matched "${cleanTrackTitle(track.title)}"',
          matched,
        );
      } else {
        skippedTracks.add(track);
        onProgress(
          currentNum,
          total,
          progress,
          'Skipped "${cleanTrackTitle(track.title)}" (no match)',
          null,
        );
      }

      // Small tick delay to keep UI responsive and prevent rate limiting
      await Future.delayed(const Duration(milliseconds: 50));
    }

    return SpotifyImportResult(
      playlistTitle: metadata.title,
      coverUrl: metadata.coverUrl,
      totalTracks: total,
      importedSongs: importedSongs,
      skippedTracks: skippedTracks,
    );
  }
}
