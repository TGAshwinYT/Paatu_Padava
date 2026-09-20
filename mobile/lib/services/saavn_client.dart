import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'des_decrypt.dart';

class SaavnClient {
  static const String baseUrl = 'https://www.jiosaavn.com/api.php';
  static final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/plain, */*'
  };

  static String _extractHighResImage(String? img) {
    if (img == null || img.isEmpty) {
      return 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop';
    }
    return img.replaceAll('50x50', '500x500').replaceAll('150x150', '500x500');
  }

  static Future<List<Song>> search(String query, {int limit = 20}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        '__call': 'search.getResults',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'p': '1',
        'n': limit.toString(),
        'q': clean,
      });

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final results = data['results'] as List<dynamic>? ?? [];

      final List<Song> songs = [];
      for (final item in results) {
        final more = item['more_info'] ?? {};
        final encUrl = more['encrypted_media_url']?.toString() ?? '';
        final audioUrl = decryptSaavnMediaUrl(encUrl);

        songs.add(Song(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? 'Unknown Title',
          artist: more['music']?.toString() ?? more['singers']?.toString() ?? 'Various Artists',
          album: more['album']?.toString() ?? 'Unknown Album',
          coverUrl: _extractHighResImage(item['image']?.toString()),
          streamUrl: audioUrl.isNotEmpty ? audioUrl : null,
          duration: int.tryParse(more['duration']?.toString() ?? '0') ?? 0,
          source: 'saavn',
        ));
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
          'title': item['title']?.toString() ?? 'Unknown Album',
          'artist': more['music']?.toString() ?? item['subtitle']?.toString() ?? 'Various Artists',
          'image': _extractHighResImage(item['image']?.toString()),
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }
}
