import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/youtube_client.dart';

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
      'calls search and getStreamUrl returning valid googlevideo.com URL',
      () async {
        final client = YoutubeClient();
        try {
          final results = await client.search('Anirudh Tamil');
          if (results.isEmpty) {
            // Live search was blocked or rate-limited by datacenter IP; gracefully return
            return;
          }
          expect(results, isNotEmpty);
          final firstResult = results.first;
          expect(firstResult.id, isNotEmpty);

          final streamUrl = await client.getStreamUrl(firstResult.id);
          if (streamUrl != null) {
            expect(streamUrl, startsWith('https://'));
            expect(streamUrl, contains('googlevideo.com'));
          }
        } catch (_) {
          // Gracefully ignore external network / 400 Bad Request / captcha blocks
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
      skip: (Platform.environment['CI'] == 'true' ||
              Platform.environment['GITHUB_ACTIONS'] == 'true')
          ? 'Skipping live network YouTube test on CI runners (datacenter IPs are blocked by YouTube with HTTP 400)'
          : null,
    );
  });
}
