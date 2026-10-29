import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hive/hive.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/cover_art_resolver.dart';

class FakeBox extends Fake implements Box {
  final Map<dynamic, dynamic> map = {};

  @override
  bool get isOpen => true;

  @override
  int get length => map.length;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => map[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    map[key] = value;
  }

  @override
  Future<int> clear() async {
    final count = map.length;
    map.clear();
    return count;
  }
}

void main() {
  group('CoverArtResolver Unit Tests', () {
    late FakeBox fakeBox;

    setUp(() {
      fakeBox = FakeBox();
      CoverArtResolver.setTestingOverrides(box: fakeBox, client: null);
      CoverArtResolver.clearMemoryCache();
    });

    test('1. JioSaavn: Upgrades 50x50 and 150x150 thumbnails to 500x500 square', () async {
      final song = Song(
        id: 'saavn_test_1',
        title: 'Arabic Kuthu',
        artist: 'Anirudh Ravichander',
        coverUrl: 'http://c.saavncdn.com/123/Arabic-Kuthu-150x150.jpg',
        duration: 280,
        source: 'saavn',
      );

      final resolved = await CoverArtResolver.resolveCover(song);
      expect(resolved, 'https://c.saavncdn.com/123/Arabic-Kuthu-500x500.jpg');
      expect(fakeBox.get('saavn_test_1'), 'https://c.saavncdn.com/123/Arabic-Kuthu-500x500.jpg');
    });

    test('2. YouTube Music: Upgrades googleusercontent thumbnails to 1000x1000 square', () async {
      final song = Song(
        id: 'ytm_test_1',
        title: 'Kesariya',
        artist: 'Pritam',
        coverUrl: 'https://lh3.googleusercontent.com/abc123xyz=w120-h120-l90-rj',
        duration: 268,
        source: 'youtube',
      );

      final resolved = await CoverArtResolver.resolveCover(song);
      expect(resolved, 'https://lh3.googleusercontent.com/abc123xyz=w1000-h1000-l90-rj');
      expect(fakeBox.get('ytm_test_1'), 'https://lh3.googleusercontent.com/abc123xyz=w1000-h1000-l90-rj');
    });

    test('3. iTunes API: Successfully matches and upgrades 100x100bb to 1000x1000bb', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host.contains('itunes.apple.com')) {
          final payload = {
            'resultCount': 1,
            'results': [
              {
                'trackName': 'Arabic Kuthu (From "Beast")',
                'artistName': 'Anirudh Ravichander & Jonita Gandhi',
                'trackTimeMillis': 280000,
                'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/100x100bb.jpg',
              }
            ]
          };
          return http.Response(jsonEncode(payload), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"results":[]}', 200);
      });

      CoverArtResolver.setTestingOverrides(box: fakeBox, client: mockClient);

      final song = Song(
        id: 'yt_vid_1',
        title: 'Arabic Kuthu - Video Song | Beast | Thalapathy Vijay',
        artist: 'Anirudh Ravichander',
        coverUrl: 'https://img.youtube.com/vi/yt_vid_1/hqdefault.jpg',
        duration: 280,
        source: 'youtube',
      );

      final resolved = await CoverArtResolver.resolveCover(song);
      expect(resolved, 'https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/1000x1000bb.jpg');
      expect(fakeBox.get('yt_vid_1'), 'https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/1000x1000bb.jpg');
    });

    test('4. Safeguard: Rejects iTunes candidate if duration differs by > 4 seconds', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host.contains('itunes.apple.com')) {
          return http.Response(
            jsonEncode({
              'resultCount': 1,
              'results': [
                {
                  'trackName': 'Arabic Kuthu',
                  'artistName': 'Anirudh Ravichander',
                  // 180 seconds vs 280 seconds (duration mismatch!)
                  'trackTimeMillis': 180000,
                  'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/wrong/100x100bb.jpg',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"data":[]}', 200);
      });

      CoverArtResolver.setTestingOverrides(box: fakeBox, client: mockClient);

      final song = Song(
        id: 'yt_vid_duration_test',
        title: 'Arabic Kuthu',
        artist: 'Anirudh Ravichander',
        coverUrl: 'https://img.youtube.com/vi/yt_vid_duration_test/hqdefault.jpg',
        duration: 280,
        source: 'youtube',
      );

      final resolved = await CoverArtResolver.resolveCover(song);
      // Mismatched iTunes art is rejected, safely falls back to YouTube thumbnail
      expect(resolved, 'https://img.youtube.com/vi/yt_vid_duration_test/hqdefault.jpg');
    });

    test('5. Safeguard: Rejects iTunes candidate if artist does not match', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host.contains('itunes.apple.com')) {
          return http.Response(
            jsonEncode({
              'resultCount': 1,
              'results': [
                {
                  'trackName': 'Kesariya',
                  'artistName': 'Unrelated Artist Name',
                  'trackTimeMillis': 268000,
                  'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/wrong/100x100bb.jpg',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"data":[]}', 200);
      });

      CoverArtResolver.setTestingOverrides(box: fakeBox, client: mockClient);

      final song = Song(
        id: 'yt_artist_mismatch',
        title: 'Kesariya',
        artist: 'Pritam',
        coverUrl: 'https://img.youtube.com/vi/yt_artist_mismatch/hqdefault.jpg',
        duration: 268,
        source: 'youtube',
      );

      final resolved = await CoverArtResolver.resolveCover(song);
      expect(resolved, 'https://img.youtube.com/vi/yt_artist_mismatch/hqdefault.jpg');
    });

    test('6. Deezer Fallback: Used when iTunes fails or returns no matches', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host.contains('itunes.apple.com')) {
          return http.Response('{"resultCount":0,"results":[]}', 200);
        }
        if (request.url.host.contains('deezer.com')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'title': 'Blinding Lights',
                  'artist': {'name': 'The Weeknd'},
                  'duration': 200,
                  'album': {
                    'cover_xl': 'https://e-cdns-images.dzcdn.net/images/cover/1000x1000-000000-80-0-0.jpg',
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      CoverArtResolver.setTestingOverrides(box: fakeBox, client: mockClient);

      final song = Song(
        id: 'blinding_lights_id',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        coverUrl: 'https://img.youtube.com/vi/blinding_lights_id/hqdefault.jpg',
        duration: 200,
        source: 'youtube',
      );

      final resolved = await CoverArtResolver.resolveCover(song);
      expect(resolved, 'https://e-cdns-images.dzcdn.net/images/cover/1000x1000-000000-80-0-0.jpg');
      expect(fakeBox.get('blinding_lights_id'), 'https://e-cdns-images.dzcdn.net/images/cover/1000x1000-000000-80-0-0.jpg');
    });

    test('7. Cache Hit: Cached results return immediately without executing network calls', () async {
      await fakeBox.put('cached_song_id', 'https://cached-art.com/1000x1000.jpg');

      var networkCalls = 0;
      final mockClient = MockClient((request) async {
        networkCalls++;
        return http.Response('{}', 200);
      });

      CoverArtResolver.setTestingOverrides(box: fakeBox, client: mockClient);

      final song = Song(
        id: 'cached_song_id',
        title: 'Any Song',
        artist: 'Any Artist',
        coverUrl: 'https://img.youtube.com/vi/cached_song_id/hqdefault.jpg',
        duration: 210,
        source: 'youtube',
      );

      final resolved = await CoverArtResolver.resolveCover(song);
      expect(resolved, 'https://cached-art.com/1000x1000.jpg');
      expect(networkCalls, 0); // No network calls made!
    });

    test('8. Placeholders: Stock Unsplash photos are rejected and never returned', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"resultCount":0,"results":[]}', 200);
      });

      CoverArtResolver.setTestingOverrides(box: fakeBox, client: mockClient);

      final song = Song(
        id: 'saavn_no_cover',
        title: 'Rare Regional Track',
        artist: 'Local Singer',
        coverUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500',
        duration: 180,
        source: 'saavn',
      );

      final resolved = await CoverArtResolver.resolveCover(song);
      expect(resolved, ''); // Neutral gradient fallback
    });

    test('9. isYouTubeThumbnail correctly detects 16:9 YouTube video thumbnails', () {
      expect(CoverArtResolver.isYouTubeThumbnail('https://img.youtube.com/vi/abc123xyz/hqdefault.jpg'), isTrue);
      expect(CoverArtResolver.isYouTubeThumbnail('https://i.ytimg.com/vi/abc123xyz/maxresdefault.jpg'), isTrue);
      expect(CoverArtResolver.isYouTubeThumbnail('https://c.saavncdn.com/123/album-500x500.jpg'), isFalse);
      expect(CoverArtResolver.isYouTubeThumbnail('https://is1-ssl.mzstatic.com/image/1000x1000bb.jpg'), isFalse);
      expect(CoverArtResolver.isYouTubeThumbnail(''), isFalse);
    });
  });
}
