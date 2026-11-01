import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'des_decrypt.dart';
import 'app_logger.dart';
import 'artist_sanitizer.dart';
import '../data/repositories/song_repository.dart';
import '../logic/track_quality_filter.dart';

class SaavnClient {
  static const String baseUrl = 'https://www.jiosaavn.com/api.php';

  static const String allIndianLanguagesCookie =
      'hindi%2Cenglish%2Ctamil%2Ctelugu%2Cpunjabi%2Cmarathi%2Cgujarati%2Cbengali%2Ckannada%2Cbhojpuri%2Cmalayalam%2Curdu%2Charyanvi%2Crajasthani%2Codia%2Cassamese';

  /// Generates dynamic headers with JioSaavn's required regional Cookie.
  /// If language is provided and specific (e.g. 'tamil' or 'hindi'), uses that language.
  /// If language is 'all', 'any', or omitted, uses user's preferred languages or the full multi-language set.
  static Map<String, String> getHeaders([String? language]) {
    String selectedLanguage;
    final lowerLang = language?.toLowerCase().trim();

    if (lowerLang == null || lowerLang.isEmpty || lowerLang == 'all' || lowerLang == 'any') {
      selectedLanguage = allIndianLanguagesCookie;
    } else {
      final parts = lowerLang.split(',').map((l) => Uri.encodeComponent(l.trim())).where((l) => l.isNotEmpty).toList();
      selectedLanguage = parts.join('%2C');
      if (!selectedLanguage.contains('english')) {
        selectedLanguage += '%2Cenglish';
      }
    }

    return {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Cookie': 'L=$selectedLanguage; gdpr_acceptance=true',
    };
  }

  static String _extractHighResImage(String? img) {
    if (img == null || img.isEmpty) {
      return '';
    }
    String highRes = img.replaceAll('50x50', '500x500').replaceAll('150x150', '500x500');
    if (highRes.startsWith('http://')) {
      highRes = highRes.replaceFirst('http://', 'https://');
    }
    return highRes;
  }

  static bool isActorOrCast(String name) {
    return !ArtistSanitizer.isGenuineArtist(name);
  }

  static bool isGenuineMusicArtist(Map<dynamic, dynamic> item) {
    return ArtistSanitizer.isGenuineArtist(item);
  }

  static Song _parseSongItem(Map<String, dynamic> item) {
    final more = (item['more_info'] is Map) ? (item['more_info'] as Map) : {};
    final encUrl = more['encrypted_media_url']?.toString() ?? '';
    final audioUrl = DesDecrypt.decrypt(encUrl);
    final rawLang = item['language']?.toString() ?? more['language']?.toString();

    // Do NOT treat actors or cast members (e.g. Prakash Raj) as music artists.
    // Check primary_artists, music_directors, or singers roles first.
    String? resolvedArtist;
    String? resolvedArtistId;
    final artistMap = more['artistMap'];
    if (artistMap is Map) {
      final primary = artistMap['primary_artists'] as List<dynamic>? ?? [];
      final singers = artistMap['singers'] as List<dynamic>? ?? [];
      final musicDirs = artistMap['music_directors'] as List<dynamic>? ?? [];

      // Prioritize genuine music directors and playback singers over actors
      final genuineMusicians = [...musicDirs, ...singers].where((a) {
        final n = a['name']?.toString() ?? '';
        return n.isNotEmpty && ArtistSanitizer.isGenuineArtist(n);
      }).toList();

      if (genuineMusicians.isNotEmpty) {
        final seen = <String>{};
        final names = <String>[];
        for (final m in genuineMusicians) {
          final n = m['name']?.toString() ?? '';
          if (n.isNotEmpty && seen.add(n.toLowerCase())) {
            names.add(n);
          }
        }
        resolvedArtist = names.join(', ');
        resolvedArtistId = genuineMusicians.first['id']?.toString();
      } else {
        final validPrimary = primary.where((a) {
          final n = a['name']?.toString() ?? '';
          return n.isNotEmpty && ArtistSanitizer.isGenuineArtist(n);
        }).toList();
        if (validPrimary.isNotEmpty) {
          resolvedArtist = validPrimary.map((a) => a['name']?.toString() ?? '').where((n) => n.isNotEmpty).join(', ');
          resolvedArtistId = validPrimary.first['id']?.toString();
        }
      }
    }

    final musicCandidate = more['music']?.toString() ?? more['singers']?.toString();
    if (musicCandidate != null && ArtistSanitizer.isGenuineArtist(musicCandidate)) {
      resolvedArtist ??= musicCandidate;
    }

    if (resolvedArtist == null || resolvedArtist.isEmpty) {
      final subtitle = item['subtitle']?.toString() ?? '';
      if (ArtistSanitizer.isGenuineArtist(subtitle)) {
        resolvedArtist = subtitle;
      }
    }

    return Song(
      id: item['id']?.toString() ?? '',
      title: Song.sanitize(item['title'] ?? item['name'], fallback: 'Unknown Title'),
      artist: Song.sanitize(resolvedArtist, fallback: 'Various Artists'),
      album: Song.sanitize(more['album'], fallback: 'Unknown Album'),
      albumId: more['album_id']?.toString() ?? item['albumid']?.toString(),
      artistId: resolvedArtistId ?? more['artistMap']?['primary_artists']?[0]?['id']?.toString() ?? item['artist_id']?.toString(),
      coverUrl: _extractHighResImage(item['image']?.toString()),
      streamUrl: audioUrl.isNotEmpty ? audioUrl : null,
      duration: int.tryParse(more['duration']?.toString() ?? '0') ?? 0,
      source: 'saavn',
      language: rawLang?.toLowerCase().trim(),
    );
  }

  /// Direct client-side autocomplete via JioSaavn autocomplete.get endpoint.
  /// Sub-100ms response fetching top query, songs, albums, and artist names.
  static Future<List<String>> getSearchSuggestions(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final uri = Uri.parse('$baseUrl?__call=autocomplete.get&_format=json&query=${Uri.encodeComponent(clean)}');
      final response = await http.get(uri, headers: getHeaders()).timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          final Set<String> suggestions = {};

          void extractFromSection(dynamic section) {
            if (section is Map && section['data'] is List) {
              for (final item in section['data']) {
                if (item is Map) {
                  final title = (item['title'] ?? item['name'] ?? '').toString().trim();
                  if (title.isNotEmpty) {
                    final decoded = ArtistSanitizer.decodeHtml(title);
                    if (decoded.isNotEmpty) {
                      suggestions.add(decoded);
                    }
                  }
                }
              }
            }
          }

          extractFromSection(data['topquery']);
          extractFromSection(data['songs']);
          extractFromSection(data['artists']);
          extractFromSection(data['albums']);
          extractFromSection(data['playlists']);

          return suggestions.toList();
        }
      }
    } catch (e) {
      debugPrint('[SaavnClient] getSearchSuggestions notice: $e');
    }
    return [];
  }

  static Future<List<Song>> search(String query, {int limit = 10, String? language}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final bool isSpecificLang = language != null &&
          language.isNotEmpty &&
          language.toLowerCase().trim() != 'all' &&
          language.toLowerCase().trim() != 'any';

      final langParam = isSpecificLang
          ? '&languages=${Uri.encodeComponent(language.toLowerCase().trim())}'
          : '';
      final url = 'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=$limit&p=1&q=${Uri.encodeComponent(clean)}$langParam';
      final uri = Uri.parse(url);
      final response = await http.get(uri, headers: getHeaders(language)).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return [];

      final dynamic data = (response.body.isNotEmpty) ? json.decode(response.body) : null;
      final results = (data is Map && data['results'] is List)
          ? (data['results'] as List<dynamic>)
          : <dynamic>[];

      final List<Song> songs = [];
      for (final item in results) {
        if (item is Map<String, dynamic>) {
          songs.add(_parseSongItem(item));
        } else if (item is Map) {
          songs.add(_parseSongItem(Map<String, dynamic>.from(item)));
        }
      }

      // If an explicit language filter was specified (e.g. from dedicated language tab/chip), filter by it
      if (isSpecificLang) {
        final targetLang = language.toLowerCase().trim();
        return songs.where((s) => !SongRepository.isLanguageMismatch(s, targetLang)).toList();
      }

      return songs;
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.ClientException {
      rethrow;
    } catch (e) {
      return [];
    }
  }

  /// Trending songs endpoint with safe null-aware map access and fallback
  static Future<List<Song>> getTrendingSongs({String language = 'Tamil'}) async {
    try {
      final songs = await getTrending(language: language);
      if (songs.isNotEmpty) return songs;
    } catch (e) {
      AppLogger.log('SaavnClient', 'getTrendingSongs error: $e');
    }
    return search('Tamil Top Hits', language: language);
  }

  static Future<List<Song>> getTrending({String language = 'Tamil'}) async {
    try {
      final songs = await search('$language Hit Songs', limit: 30, language: language);
      final targetLang = language.toLowerCase().trim();
      // Strictly filter out tracks where track['language'] != selectedLanguage for regional charts
      final languageFiltered = songs.where((s) {
        if (s.language != null && s.language!.isNotEmpty) {
          return s.language!.toLowerCase().trim() == targetLang;
        }
        return true;
      }).toList();
      final filtered = SongRepository.filterByLanguage(languageFiltered, language);
      if (filtered.isNotEmpty) return filtered;
      if (languageFiltered.isNotEmpty) return languageFiltered;
    } catch (e) {
      AppLogger.log('SaavnClient', 'getTrending error: $e');
    }
    return search('Tamil Top Hits', language: language);
  }

  /// Direct on-device artist avatar lookup via JioSaavn
  static Future<String?> getArtistImage(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    try {
      final url = 'https://www.jiosaavn.com/api.php?__call=search.getArtistResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=2&p=1&q=${Uri.encodeComponent(clean)}';
      final response = await http.get(Uri.parse(url), headers: getHeaders()).timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      if (data is Map && data['results'] is List && (data['results'] as List).isNotEmpty) {
        final first = (data['results'] as List).first;
        if (first is Map && first['image'] != null) {
          final rawImg = first['image'].toString();
          return _extractHighResImage(rawImg);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>> searchAlbums(String query, {int limit = 15, String? language}) async {
    try {
      final bool isSpecificLang = language != null &&
          language.isNotEmpty &&
          language.toLowerCase().trim() != 'all' &&
          language.toLowerCase().trim() != 'any';

      // Fetch larger batch (at least 35) because JioSaavn indexes promotional single releases first,
      // while full multi-track soundtrack albums are placed at indices 20-30.
      final fetchCount = math.max(limit * 2, 35);

      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'search.getAlbumResults',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'p': '1',
        'n': fetchCount.toString(),
        'q': query.trim(),
        if (isSpecificLang) 'languages': language.toLowerCase().trim(),
      });

      final response = await http.get(uri, headers: getHeaders(language)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final results = data['results'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> multiSongAlbums = [];
      final List<Map<String, dynamic>> otherAlbums = [];

      for (final item in results) {
        if (item is! Map) continue;
        final more = item['more_info'] ?? {};
        final songCount = int.tryParse(more['song_count']?.toString() ?? '0') ??
            int.tryParse(item['song_count']?.toString() ?? '0') ?? 0;
        final rawTitle = (item['title'] ?? '').toString();
        final title = rawTitle.toLowerCase();

        // When a specific language was requested (e.g. from language tab), apply language match
        if (isSpecificLang) {
          final targetLang = language.toLowerCase().trim();
          if (targetLang == 'tamil' && RegExp(r'[ऀ-ॿ]').hasMatch(title)) {
            continue;
          }
        }

        final rawArtistStr = Song.sanitize(more['music'] ?? item['subtitle'] ?? '', fallback: 'Various Artists');
        final genuineArtists = ArtistSanitizer.extractAllGenuineArtists(rawArtistStr);
        if (rawArtistStr.isNotEmpty &&
            rawArtistStr != 'Various Artists' &&
            !rawArtistStr.toLowerCase().contains('various') &&
            genuineArtists.isEmpty &&
            !ArtistSanitizer.isGenuineArtist(rawArtistStr)) {
          continue;
        }
        final artistName = genuineArtists.isNotEmpty ? genuineArtists.join(', ') : rawArtistStr;

        final albumEntry = {
          'id': item['id']?.toString() ?? '',
          'title': Song.sanitize(item['title'], fallback: 'Unknown Album'),
          'artist': artistName,
          'image': _extractHighResImage(item['image']?.toString()),
          'year': item['year']?.toString() ?? more['year']?.toString() ?? '',
          'song_count': songCount,
          'language': item['language']?.toString() ?? more['language']?.toString() ?? '',
        };

        if (songCount > 1) {
          multiSongAlbums.add(albumEntry);
        } else if (!title.contains('single') && !title.contains('teaser') && !title.contains('trailer')) {
          otherAlbums.add(albumEntry);
        }
      }

      // Prioritize full multi-track albums first, then relevant promotional releases as fallback
      final validAlbums = [...multiSongAlbums, ...otherAlbums];
      return validAlbums.take(limit).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchArtists(String query, {int limit = 15, String? language}) async {
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'search.getArtistResults',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'p': '1',
        'n': limit.toString(),
        'q': query.trim(),
        if (language != null && language.isNotEmpty) 'languages': language.toLowerCase().trim(),
      });

      final response = await http.get(uri, headers: getHeaders(language)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final results = data['results'] as List<dynamic>? ?? [];

      final seenNames = <String>{};
      final validArtists = <Map<String, dynamic>>[];
      for (final item in results) {
        if (item is Map) {
          final rawName = Song.sanitize(item['name'] ?? item['title'] ?? '').trim();
          if (rawName.isEmpty || rawName.toLowerCase() == 'unknown artist') continue;
          if (ArtistSanitizer.isCompositeOrMultiArtist(rawName)) continue;
          if (!isGenuineMusicArtist(item)) continue;

          final canon = ArtistSanitizer.canonicalArtistName(rawName).toLowerCase();
          if (seenNames.add(canon)) {
            validArtists.add({
              'id': item['id']?.toString() ?? '',
              'name': ArtistSanitizer.canonicalArtistName(rawName),
              'image': _extractHighResImage(item['image']?.toString()),
              'role': item['role']?.toString() ?? item['extra']?.toString() ?? 'Artist',
            });
          }
        }
      }

      return validArtists;
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchPlaylists(
    String query, {
    int limit = 15,
    String? language,
  }) async {
    try {
      final bool isSpecificLang = language != null &&
          language.isNotEmpty &&
          language.toLowerCase().trim() != 'all' &&
          language.toLowerCase().trim() != 'any';

      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'search.getPlaylistResults',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'p': '1',
        'n': limit.toString(),
        'q': query.trim(),
        if (isSpecificLang) 'languages': language.toLowerCase().trim(),
      });

      final response = await http.get(uri, headers: getHeaders(language)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final results = data['results'] as List<dynamic>? ?? [];
      final validPlaylists = <Map<String, dynamic>>[];

      for (final item in results) {
        if (item is! Map) continue;
        final more = item['more_info'] ?? {};
        final songCount = int.tryParse(more['song_count']?.toString() ?? '') ??
            int.tryParse(item['song_count']?.toString() ?? '') ?? 0;
        final title = Song.sanitize(item['title'] ?? item['name'], fallback: 'Playlist');
        final subtitle = item['subtitle']?.toString().isNotEmpty == true
            ? item['subtitle'].toString()
            : (songCount > 0 ? '$songCount Songs' : 'JioSaavn Playlist');

        validPlaylists.add({
          'id': item['id']?.toString() ?? '',
          'title': title,
          'subtitle': subtitle,
          'image': _extractHighResImage(item['image']?.toString()),
          'song_count': songCount,
          'source': 'saavn',
          'type': 'playlist',
        });
      }

      return validPlaylists;
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getPlaylistDetails(String playlistId) async {
    if (playlistId.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'playlist.getDetails',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'listid': playlistId.trim(),
      });

      final response = await http.get(uri, headers: getHeaders()).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final playlistImage = _extractHighResImage(data['image']?.toString());
      final list = data['list'] as List<dynamic>? ?? data['songs'] as List<dynamic>? ?? [];
      final List<Song> songs = [];

      for (final item in list) {
        if (item is! Map) continue;
        final parsed = _parseSongItem(Map<String, dynamic>.from(item));
        if (TrackQualityFilter.shouldKeep(title: parsed.title, durationSec: parsed.duration)) {
          if (parsed.coverUrl.isEmpty && playlistImage.isNotEmpty) {
            songs.add(parsed.copyWith(coverUrl: playlistImage));
          } else {
            songs.add(parsed);
          }
        }
      }

      return {
        'id': data['id']?.toString() ?? playlistId,
        'title': Song.sanitize(data['title'] ?? data['name'], fallback: 'JioSaavn Playlist'),
        'subtitle': data['subtitle']?.toString() ?? '${songs.length} Songs',
        'image': playlistImage,
        'songs': songs,
        'source': 'saavn',
      };
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getAlbumDetails(String albumId) async {
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'content.getAlbumDetails',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'albumid': albumId,
      });

      final response = await http.get(uri, headers: getHeaders()).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final albumImage = _extractHighResImage(data['image']?.toString());
      final list = data['list'] as List<dynamic>? ?? [];
      final List<Song> songs = [];
      for (final item in list) {
        final parsed = _parseSongItem(Map<String, dynamic>.from(item));
        if (parsed.coverUrl.isEmpty && albumImage.isNotEmpty) {
          songs.add(parsed.copyWith(coverUrl: albumImage));
        } else {
          songs.add(parsed);
        }
      }

      return {
        'id': data['id']?.toString() ?? albumId,
        'title': Song.sanitize(data['title'] ?? data['name'], fallback: 'Unknown Album'),
        'artist': Song.sanitize(data['primary_artists'], fallback: 'Various Artists'),
        'image': albumImage,
        'year': data['year']?.toString() ?? '',
        'songs': songs,
      };
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getArtistDetails(String artistId) async {
    if (artistId.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'artist.getArtistPageDetails',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'artistId': artistId,
        'n_song': '50',
        'n_album': '20',
      });

      final response = await http.get(uri, headers: getHeaders()).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final topSongs = data['topSongs'] as List<dynamic>? ?? [];
      final moreSongs = (data['songs'] is List) ? (data['songs'] as List<dynamic>) : [];
      final combined = [...topSongs, ...moreSongs];
      final List<Song> songs = [];
      for (final item in combined) {
        if (item is Map) {
          songs.add(_parseSongItem(Map<String, dynamic>.from(item)));
        }
      }

      return {
        'id': data['artistId']?.toString() ?? artistId,
        'name': Song.sanitize(data['name'], fallback: 'Artist'),
        'image': _extractHighResImage(data['image']?.toString()),
        'songs': songs,
      };
    } catch (e) {
      return null;
    }
  }

  /// Fetches extensive songs for an artist across top hits and catalog
  static Future<List<Song>> getArtistSongs(String artistName, {int limit = 50}) async {
    final clean = artistName.trim();
    if (clean.isEmpty) return [];
    try {
      final hits = await search('$clean Hit Songs', limit: (limit / 2).ceil());
      final catalog = await search(clean, limit: (limit / 2).ceil());
      return [...hits, ...catalog];
    } catch (_) {
      return [];
    }
  }

  /// Fetch related recommendation tracks from JioSaavn (`reco.getreco`)
  static Future<List<Song>> getRelatedSongs(String songId, {String? language}) async {
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'reco.getreco',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'pid': songId,
        if (language != null && language.isNotEmpty) 'language': language.toLowerCase(),
      });

      final response = await http.get(uri, headers: getHeaders(language)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final dynamic data = (response.body.isNotEmpty) ? json.decode(response.body) : null;
      final list = (data is List)
          ? data
          : (data is Map ? (data['songs'] ?? data['data'] ?? []) : []);
      final List<Song> songs = [];
      for (final item in list) {
        if (item is Map) {
          songs.add(_parseSongItem(Map<String, dynamic>.from(item)));
        }
      }

      // If an explicit language was targeted, filter out direct mismatches, otherwise return all related tracks
      if (language != null && language.isNotEmpty && language.toLowerCase().trim() != 'all' && language.toLowerCase().trim() != 'any') {
        final targetLang = language.toLowerCase().trim();
        return songs.where((s) => !SongRepository.isLanguageMismatch(s, targetLang)).toList();
      }

      return songs;
    } catch (e) {
      AppLogger.log('SaavnClient', 'getRelatedSongs error: $e');
      return [];
    }
  }
}
