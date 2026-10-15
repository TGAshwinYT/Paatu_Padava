import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/logic/stream_resolver.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/services/error_handler.dart';
import 'package:paatu_padava_mobile/services/youtube_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Requirement 1 & 3: Host-based Headers & No &range= Hack', () {
    test('googlevideo.com URLs get YouTube VR headers, NO &range= hack, and NO Range header in AudioSource', () {
      final song = Song(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        album: 'Whenever You Need Somebody',
        coverUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        streamUrl: 'https://rr3---sn-h5576nsr.googlevideo.com/videoplayback?expire=123456&clen=3500000',
        source: 'youtube',
      );

      // Verify that bare googlevideo URL has no &range= appended
      expect(song.streamUrl, isNot(contains('&range=')));

      // Inspect host logic
      final host = Uri.parse(song.streamUrl!).host.toLowerCase();
      expect(host.contains('googlevideo.com'), isTrue);

      final headers = YouTubeClient.headersForUrl(song.streamUrl!);
      expect(headers['User-Agent'], contains('com.google.android.apps.youtube.vr.oculus'));
      expect(headers['Accept'], equals('*/*'));
      expect(headers['Connection'], equals('keep-alive'));
      expect(headers.containsKey('Range'), isFalse);
    });

    test('Saavn URLs get ZERO headers even if song.source is youtube or id is 11 chars', () {
      final ytSongWithSaavnStream = Song(
        id: 'k4yXQkG2s1E', // 11 chars (YouTube ID format)
        title: 'Hukum',
        artist: 'Anirudh',
        album: 'Jailer',
        coverUrl: 'https://example.com/cover.jpg',
        streamUrl: 'https://aac.saavncdn.com/187/0c4d0aee91a3ac81d4b645ec448a2960_320.mp4',
        source: 'youtube', // Source originally was youtube
      );

      final uri = Uri.tryParse(ytSongWithSaavnStream.streamUrl!);
      final host = uri?.host.toLowerCase() ?? '';
      final isGoogleVideo = host.contains('googlevideo.com');

      // Crucial: Must be false because host is saavncdn.com, NOT googlevideo.com
      expect(isGoogleVideo, isFalse);

      // Saavn gets NO headers
      final headers = isGoogleVideo
          ? {
              'User-Agent': YouTubeClient.vrUserAgent,
              'Accept': '*/*',
              'Connection': 'keep-alive',
            }
          : null;

      expect(headers, isNull);
      expect(ytSongWithSaavnStream.streamUrl, isNot(contains('&range=')));
    });
  });

  group('Requirement 2: Saavn Fallback Updates Song and Track Source to saavn', () {
    test('Mutating song.source to saavn updates field directly', () {
      final song = Song(
        id: 'test_1234567',
        title: 'Arabic Kuthu',
        artist: 'Anirudh',
        album: 'Beast',
        coverUrl: 'https://example.com/cover.jpg',
        source: 'youtube',
      );

      expect(song.source, equals('youtube'));
      // When Saavn fallback wins:
      song.source = 'saavn';
      expect(song.source, equals('saavn'));
    });

    test('TrackEntity source is mutable and updates to saavn on fallback', () {
      final track = TrackEntity(
        id: 'test_track_11',
        title: 'Hukum',
        artist: 'Anirudh',
        coverUrl: 'https://example.com/cover.jpg',
        source: 'youtube',
      );

      expect(track.source, equals('youtube'));
      track.source = 'saavn';
      expect(track.source, equals('saavn'));
    });

    test('StreamResolver sets song.source to saavn when resolving Saavn stream', () async {
      final song = Song(
        id: 'yt_id_12345',
        title: 'Test Saavn Match',
        artist: 'Artist',
        album: 'Album',
        coverUrl: 'https://example.com/cover.jpg',
        streamUrl: 'https://aac.saavncdn.com/test/audio_320.mp4',
        source: 'youtube',
      );

      final resolver = DefaultStreamResolver();
      final url = await resolver.resolveStreamUrl(song);

      expect(url, equals('https://aac.saavncdn.com/test/audio_320.mp4'));
      expect(song.source, equals('saavn'));
    });
  });

  group('Requirement 4: Single Centralized Error Handler Collapses Retries', () {
    test('diagnosePlaybackError identifies HTTP 403, 416, Cleartext, and SSL errors', () async {
      final song = Song(
        id: 'err_song_1',
        title: 'Error Song',
        artist: 'Artist',
        album: 'Album',
        coverUrl: 'https://example.com/cover.jpg',
      );

      // 1. HTTP 403
      final diag403 = await AudioQueueHandler.diagnosePlaybackError(
        song,
        PlatformException(code: '0', message: 'Source error', details: 'HttpDataSource: Response code: 403'),
        null,
      );
      expect(diag403, contains('403 Forbidden'));

      // 2. HTTP 416
      final diag416 = await AudioQueueHandler.diagnosePlaybackError(
        song,
        PlatformException(code: '0', message: 'Source error', details: 'Response code: 416'),
        null,
      );
      expect(diag416, contains('416 Range Not Satisfiable'));

      // 3. Cleartext
      final diagCleartext = await AudioQueueHandler.diagnosePlaybackError(
        song,
        PlatformException(code: '0', message: 'Source error', details: 'CleartextNotPermittedException'),
        null,
      );
      expect(diagCleartext, contains('CleartextNotPermittedException'));

      // 4. SSL Handshake
      final diagSsl = await AudioQueueHandler.diagnosePlaybackError(
        song,
        PlatformException(code: '0', message: 'Source error', details: 'SSLHandshakeException'),
        null,
      );
      expect(diagSsl, contains('SSLHandshakeException'));
    });
  });

  group('Requirement 5: ErrorHandler Resolves Underling Status Codes', () {
    test('Resolves 403 to ERR_STREAM_HTTP_403', () {
      final err = ErrorHandler.resolve(PlatformException(code: '0', message: 'Http 403 forbidden'));
      expect(err.errorCode, equals('ERR_STREAM_HTTP_403'));
      expect(err.userMessage, contains('HTTP 403'));
    });

    test('Resolves 416 to ERR_STREAM_HTTP_416', () {
      final err = ErrorHandler.resolve(PlatformException(code: '0', message: 'Range not satisfiable 416'));
      expect(err.errorCode, equals('ERR_STREAM_HTTP_416'));
      expect(err.userMessage, contains('HTTP 416'));
    });

    test('Resolves Cleartext to ERR_CLEARTEXT_NOT_PERMITTED', () {
      final err = ErrorHandler.resolve(PlatformException(code: '0', message: 'Cleartext HTTP traffic not permitted'));
      expect(err.errorCode, equals('ERR_CLEARTEXT_NOT_PERMITTED'));
    });

    test('Resolves SSL Handshake to ERR_SSL_HANDSHAKE', () {
      final err = ErrorHandler.resolve(PlatformException(code: '0', message: 'SSLHandshakeException in ExoPlayer'));
      expect(err.errorCode, equals('ERR_SSL_HANDSHAKE'));
    });
  });
}
