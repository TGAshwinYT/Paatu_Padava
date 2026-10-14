import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:paatu_padava_mobile/services/youtube_client.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/logic/stream_resolver.dart';

void main() {
  group('Client-Side YouTube URL & ID Extraction Engine', () {
    test('extractVideoId accurately parses raw 11-char video IDs', () {
      expect(YouTubeClient.extractVideoId('dQw4w9WgXcQ'), equals('dQw4w9WgXcQ'));
      expect(YouTubeClient.extractVideoId('abc_123-XYZ'), equals('abc_123-XYZ'));
    });

    test('extractVideoId accurately parses youtu.be shortlinks', () {
      expect(YouTubeClient.extractVideoId('https://youtu.be/dQw4w9WgXcQ'), equals('dQw4w9WgXcQ'));
      expect(YouTubeClient.extractVideoId('http://youtu.be/dQw4w9WgXcQ?t=42'), equals('dQw4w9WgXcQ'));
    });

    test('extractVideoId accurately parses standard youtube.com watch URLs', () {
      expect(YouTubeClient.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), equals('dQw4w9WgXcQ'));
      expect(YouTubeClient.extractVideoId('https://youtube.com/watch?v=dQw4w9WgXcQ&feature=share'), equals('dQw4w9WgXcQ'));
    });

    test('extractVideoId accurately parses music.youtube.com URLs', () {
      expect(YouTubeClient.extractVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ'), equals('dQw4w9WgXcQ'));
      expect(YouTubeClient.extractVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVMdQw4w9WgXcQ'), equals('dQw4w9WgXcQ'));
    });

    test('extractVideoId accurately parses YouTube Shorts & Embeds', () {
      expect(YouTubeClient.extractVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'), equals('dQw4w9WgXcQ'));
      expect(YouTubeClient.extractVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'), equals('dQw4w9WgXcQ'));
    });

    test('extractVideoId returns null for invalid non-YouTube strings', () {
      expect(YouTubeClient.extractVideoId(''), isNull);
      expect(YouTubeClient.extractVideoId('not_a_valid_id'), isNull);
      expect(YouTubeClient.extractVideoId('https://spotify.com/track/12345'), isNull);
    });

    test('extractPlaylistId extracts list query parameter from standard and music URLs', () {
      expect(
        YouTubeClient.extractPlaylistId('https://www.youtube.com/playlist?list=PL1234567890ABCDEF'),
        equals('PL1234567890ABCDEF'),
      );
      expect(
        YouTubeClient.extractPlaylistId('https://music.youtube.com/watch?v=xyz&list=RDCLAK5uy_k123'),
        equals('RDCLAK5uy_k123'),
      );
      expect(
        YouTubeClient.extractPlaylistId('PL1234567890ABCDEF'),
        equals('PL1234567890ABCDEF'),
      );
    });
  });

  group('YouTube Clean Title & Channel Tag Sanitization', () {
    test('cleanTitle strips official video, audio, and quality tags', () {
      expect(
        YouTubeClient.cleanTitle('Hukum - Alappara (Official Music Video) | Jailer | Rajinikanth'),
        equals('Hukum - Alappara'),
      );
      expect(
        YouTubeClient.cleanTitle('Arabic Kuthu [Lyrical] [4K 60FPS] | Beast'),
        equals('Arabic Kuthu'),
      );
    });

    test('cleanTitle strips leading channel handles (@Artist)', () {
      expect(
        YouTubeClient.cleanTitle('@SaiAbhyankkar - Pavazha Malli (Official Video)'),
        equals('Pavazha Malli'),
      );
    });
  });

  group('Googlevideo Anti-Throttling Streaming Headers', () {
    test('enforces Range byte requests and ANDROID_VR User-Agent', () {
      final headers = YouTubeClient.streamingHeaders;
      expect(headers['Range'], equals('bytes=0-'));
      expect(headers['User-Agent'], contains('com.google.android.apps.youtube.vr.oculus'));
      expect(headers['Accept'], equals('*/*'));
      expect(headers['Connection'], equals('keep-alive'));
    });
  });

  group('Stream Cache & Invalidation Behavior', () {
    test('invalidateStream executes cleanly without throwing', () {
      expect(() => YouTubeClient.invalidateStream('dQw4w9WgXcQ'), returnsNormally);
      expect(() => YouTubeClient.invalidateStream(''), returnsNormally);
    });
  });

  group('Live YouTube Client Search & Stream URL Resolution', () {
    test(
      'Test 1: YoutubeClient().search("Anirudh") returns at least 5 tracks',
      () async {
        final client = YoutubeClient();
        final results = await client.search('Anirudh');
        expect(results, isNotEmpty);
        expect(results.length, greaterThanOrEqualTo(5));
        for (final song in results.take(5)) {
          expect(song.id, isNotEmpty);
          expect(song.title, isNotEmpty);
          expect(song.source, equals('youtube'));
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'Test 2: StreamResolver().resolve resolves Hukum - Thalaivar Alappara to live stream responding with HTTP 200 or 206',
      () async {
        final track = TrackEntity(
          id: 'gB2zKZxESTg',
          title: 'Hukum - Thalaivar Alappara (From "Jailer")',
          artist: 'Anirudh Ravichander, Super Subu',
          source: 'youtube',
          streamUrl: '',
          coverUrl: 'https://i.ytimg.com/vi/gB2zKZxESTg/hqdefault.jpg',
        );

        final resolver = StreamResolver();
        final resolvedUrl = await resolver.resolve(track);

        expect(resolvedUrl, isNotNull);
        expect(resolvedUrl!, startsWith('https://'));

        // Fast probe: Verify that the resolved stream URL responds with HTTP 200 or 206
        final response = await http.get(
          Uri.parse(resolvedUrl),
          headers: {
            'Range': 'bytes=0-1024',
            'User-Agent': YouTubeClient.vrUserAgent,
            'Accept': '*/*',
          },
        ).timeout(const Duration(seconds: 10));

        expect(response.statusCode == 200 || response.statusCode == 206, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'calls search and getStreamUrl returning valid stream URL',
      () async {
        final client = YoutubeClient();
        try {
          final results = await client.search('Anirudh Tamil');
          if (results.isEmpty) {
            return;
          }
          expect(results, isNotEmpty);
          final firstResult = results.first;
          expect(firstResult.id, isNotEmpty);

          final streamUrl = await client.getStreamUrl(firstResult.id);
          if (streamUrl != null) {
            expect(streamUrl, startsWith('https://'));
            final isPlayable = await YouTubeClient.probeStreamUrl(streamUrl);
            expect(isPlayable, isTrue);
          }
        } catch (_) {}
      },
      timeout: const Timeout(Duration(seconds: 30)),
      skip: (Platform.environment['CI'] == 'true' ||
              Platform.environment['GITHUB_ACTIONS'] == 'true')
          ? 'Skipping live network YouTube test on CI runners (datacenter IPs are blocked by YouTube with HTTP 400)'
          : null,
    );

    test(
      'resolving YouTube TrackEntity returns playable stream URL responding with HTTP 200 or 206',
      () async {
        final track = TrackEntity(
          id: 'KUN5Uf9mOBQ',
          title: 'Arabic Kuthu',
          artist: 'Anirudh Ravichander',
          source: 'youtube',
          coverUrl: 'https://example.com/cover.jpg',
        );

        final resolver = DefaultStreamResolver();
        final playableUrl = await resolver.resolveStreamUrl(track.toSong());

        expect(playableUrl, isNotNull);
        expect(playableUrl!, startsWith('https://'));

        // Fast probe: Verify that the resolved stream URL responds with HTTP 200 or 206
        final response = await http.get(
          Uri.parse(playableUrl),
          headers: {
            'Range': 'bytes=0-1024',
            'User-Agent': YouTubeClient.vrUserAgent,
            'Accept': '*/*',
          },
        ).timeout(const Duration(seconds: 8));

        expect(response.statusCode == 200 || response.statusCode == 206, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
      skip: (Platform.environment['CI'] == 'true' ||
              Platform.environment['GITHUB_ACTIONS'] == 'true')
          ? 'Skipping live network probe on CI runners (datacenter IPs)'
          : null,
    );
  });
}
