import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'des_decrypt.dart';

class SaavnClient {
  static const String baseUrl = 'https://www.jiosaavn.com/api.php';
  static final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
  };

  static String _extractHighResImage(String? img) {
    if (img == null || img.isEmpty) {
      return 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop';
    }
    return img.replaceAll('50x50', '500x500').replaceAll('150x150', '500x500');
  }

  static const Set<String> _excludedArtistKeywords = {
    'gospel',
    'chuchutv',
    'rhymes',
    'nursery',
    'lullaby',
    'devotional',
    'dialogue',
    'comedy',
    'scenes',
    'trailer',
    'teaser',
    'remix',
    'bgm',
    'instrumental',
    'soundtrack',
    'records',
    'music company',
    'official',
    'channel',
    'kids',
    'stories',
    'poems',
  };

  static const Set<String> _nonMusicActors = {
    'prakash raj',
    'nasser',
    'radha ravi',
    'brahmanandam',
    'goundamani',
    'senthil',
    'manivannan',
    'ms bhaskar',
    'kota srinivasa rao',
    'ashish vidyarthi',
  };

  static bool isActorOrCast(String name) {
    final lower = name.toLowerCase().trim();
    for (final actor in _nonMusicActors) {
      if (lower == actor || lower.contains(actor)) return true;
    }
    return false;
  }

  static bool isGenuineMusicArtist(Map<dynamic, dynamic> item) {
    final rawName = (item['name'] ?? item['title'] ?? '').toString().toLowerCase().trim();
    if (rawName.isEmpty) return false;

    // 1. Exclude generic non-artist tags (e.g. "Tamil Gospel", "ChuChuTV")
    for (final kw in _excludedArtistKeywords) {
      if (rawName.contains(kw)) return false;
    }

    // 2. Exclude known non-singer actors (e.g. Prakash Raj)
    if (isActorOrCast(rawName)) return false;

    // 3. Filter candidate artists by checking for 'music' or 'singers' roles
    final role = (item['role'] ?? item['extra'] ?? item['subtitle'] ?? '').toString().toLowerCase().trim();
    if (role.isNotEmpty) {
      final isActor = role.contains('actor') || role.contains('starring') || role.contains('cast');
      final isMusician = role.contains('music') ||
          role.contains('singer') ||
          role.contains('composer') ||
          role.contains('director') ||
          role.contains('lyricist') ||
          role.contains('vocalist') ||
          role.contains('artist');
      if (isActor && !isMusician) {
        return false;
      }
    }

    return true;
  }

  static Song _parseSongItem(Map<String, dynamic> item) {
    final more = item['more_info'] ?? {};
    final encUrl = more['encrypted_media_url']?.toString() ?? '';
    final audioUrl = decryptSaavnMediaUrl(encUrl);
    final rawLang = item['language']?.toString() ?? more['language']?.toString();

    // Do NOT treat actors or cast members (e.g. Prakash Raj) as music artists.
    // Check primary_artists, music_directors, or singers roles first.
    String? resolvedArtist;
    final artistMap = more['artistMap'];
    if (artistMap is Map) {
      final primary = artistMap['primary_artists'] as List<dynamic>? ?? [];
      final singers = artistMap['singers'] as List<dynamic>? ?? [];
      final musicDirs = artistMap['music_directors'] as List<dynamic>? ?? [];

      final valid = primary.isNotEmpty ? primary : (singers.isNotEmpty ? singers : musicDirs);
      if (valid.isNotEmpty) {
        final names = valid
            .map((a) => a['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty && !isActorOrCast(n))
            .toList();
        if (names.isNotEmpty) {
          resolvedArtist = names.join(', ');
        }
      }
    }

    resolvedArtist ??= more['music']?.toString() ?? more['singers']?.toString();
    if (resolvedArtist == null || resolvedArtist.isEmpty) {
      final subtitle = item['subtitle']?.toString() ?? '';
      if (!isActorOrCast(subtitle)) {
        resolvedArtist = subtitle;
      }
    }

    return Song(
      id: item['id']?.toString() ?? '',
      title: Song.sanitize(item['title'] ?? item['name'], fallback: 'Unknown Title'),
      artist: Song.sanitize(resolvedArtist, fallback: 'Various Artists'),
      album: Song.sanitize(more['album'], fallback: 'Unknown Album'),
      albumId: more['album_id']?.toString() ?? item['albumid']?.toString(),
      artistId: more['artistMap']?['primary_artists']?[0]?['id']?.toString() ?? item['artist_id']?.toString(),
      coverUrl: _extractHighResImage(item['image']?.toString()),
      streamUrl: audioUrl.isNotEmpty ? audioUrl : null,
      duration: int.tryParse(more['duration']?.toString() ?? '0') ?? 0,
      source: 'saavn',
      language: rawLang?.toLowerCase().trim(),
    );
  }

  static Future<List<Song>> search(String query, {int limit = 20, String? language}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final queryParams = {
        '__call': 'search.getResults',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'p': '1',
        'n': limit.toString(),
        'q': clean,
      };

      final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final results = data['results'] as List<dynamic>? ?? [];

      final List<Song> songs = [];
      for (final item in results) {
        if (item is Map<String, dynamic>) {
          songs.add(_parseSongItem(item));
        } else if (item is Map) {
          songs.add(_parseSongItem(Map<String, dynamic>.from(item)));
        }
      }

      // Strict regional filtering: if language is specified and the user query
      // does not explicitly ask for another language, prioritize or filter matching tracks
      if (language != null && language.isNotEmpty) {
        final targetLang = language.toLowerCase().trim();
        final bool queryMentionsOtherLang = ['hindi', 'english', 'telugu', 'tamil', 'malayalam', 'kannada', 'punjabi']
            .any((l) => l != targetLang && clean.toLowerCase().contains(l));

        if (!queryMentionsOtherLang) {
          final matched = songs.where((s) => s.language == null || s.language!.isEmpty || s.language == targetLang).toList();
          if (matched.isNotEmpty) {
            return matched;
          }
        }
      }

      return songs;
    } catch (e) {
      return [];
    }
  }

  static Future<List<Song>> getTrending({String language = 'Tamil'}) async {
    return search('$language Hit Songs', limit: 25);
  }

  static Future<List<Map<String, dynamic>>> searchAlbums(String query, {int limit = 15}) async {
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'search.getAlbumResults',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'p': '1',
        'n': limit.toString(),
        'q': query.trim(),
      });

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final results = data['results'] as List<dynamic>? ?? [];

      return results.map((item) {
        final more = item['more_info'] ?? {};
        return {
          'id': item['id']?.toString() ?? '',
          'title': Song.sanitize(item['title'], fallback: 'Unknown Album'),
          'artist': Song.sanitize(more['music'] ?? item['subtitle'], fallback: 'Various Artists'),
          'image': _extractHighResImage(item['image']?.toString()),
          'year': item['year']?.toString() ?? more['year']?.toString() ?? '',
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchArtists(String query, {int limit = 15}) async {
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
      });

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final results = data['results'] as List<dynamic>? ?? [];

      final validArtists = results.where((item) {
        if (item is Map) {
          return isGenuineMusicArtist(item);
        }
        return false;
      }).toList();

      return validArtists.map((item) {
        return {
          'id': item['id']?.toString() ?? '',
          'name': Song.sanitize(item['name'] ?? item['title'], fallback: 'Unknown Artist'),
          'image': _extractHighResImage(item['image']?.toString()),
          'role': item['role']?.toString() ?? item['extra']?.toString() ?? 'Artist',
        };
      }).toList();
    } catch (e) {
      return [];
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

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final list = data['list'] as List<dynamic>? ?? [];
      final List<Song> songs = [];
      for (final item in list) {
        songs.add(_parseSongItem(Map<String, dynamic>.from(item)));
      }

      return {
        'id': data['id']?.toString() ?? albumId,
        'title': Song.sanitize(data['title'] ?? data['name'], fallback: 'Unknown Album'),
        'artist': Song.sanitize(data['primary_artists'], fallback: 'Various Artists'),
        'image': _extractHighResImage(data['image']?.toString()),
        'year': data['year']?.toString() ?? '',
        'songs': songs,
      };
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getArtistDetails(String artistId) async {
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'artist.getArtistPageDetails',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'artistId': artistId,
      });

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final topSongs = data['topSongs'] as List<dynamic>? ?? [];
      final List<Song> songs = [];
      for (final item in topSongs) {
        songs.add(_parseSongItem(Map<String, dynamic>.from(item)));
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

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final list = (data is List) ? data : (data['songs'] ?? data['data'] ?? []);
      final List<Song> songs = [];
      for (final item in list) {
        final parsed = _parseSongItem(Map<String, dynamic>.from(item));
        if (language != null && language.isNotEmpty && parsed.language != null) {
          if (parsed.language!.toLowerCase() != language.toLowerCase()) continue;
        }
        songs.add(parsed);
      }
      return songs;
    } catch (_) {
      return [];
    }
  }
}
