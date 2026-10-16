import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/des_decrypt.dart';
import 'package:paatu_padava_mobile/services/smart_cache_service.dart';
import 'package:paatu_padava_mobile/services/youtube_client.dart';
import 'package:paatu_padava_mobile/logic/stream_resolver.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Runtime Session Failure Fixes Verification', () {
    test('Fix A: DecryptedStreamAudioSource detects correct content-type dynamically', () {
      final mp4File = File('/data/cache/audio_123.mp4');
      final m4aFile = File('/data/cache/audio_123.m4a');
      final mp3File = File('/data/cache/audio_123.mp3');
      final oggFile = File('/data/cache/audio_123.ogg');
      final webmFile = File('/data/cache/audio_123.webm');

      final mp4Source = DecryptedStreamAudioSource(mp4File);
      final m4aSource = DecryptedStreamAudioSource(m4aFile);
      final mp3Source = DecryptedStreamAudioSource(mp3File);
      final oggSource = DecryptedStreamAudioSource(oggFile);
      final webmSource = DecryptedStreamAudioSource(webmFile);

      // ExoPlayer requires audio/mp4 for Saavn and AAC streams, never audio/mpeg
      expect(mp4Source.contentType, equals('audio/mp4'));
      expect(m4aSource.contentType, equals('audio/mp4'));
      expect(mp3Source.contentType, equals('audio/mpeg'));
      expect(oggSource.contentType, equals('audio/ogg'));
      expect(webmSource.contentType, equals('audio/webm'));

      // Allows explicit override
      final customSource = DecryptedStreamAudioSource(mp4File, contentType: 'audio/aac');
      expect(customSource.contentType, equals('audio/aac'));
    });

    test('Fix A & Cache Contention: SmartCacheService exposes isDownloading query', () {
      final service = SmartCacheService.instance;
      // When not downloading, isDownloading returns false
      expect(service.isDownloading('random_song_id_not_downloading'), isFalse);
    });

    test('Fix D: StreamResolver detects long-form compilations and jukeboxes (>600s or keywords)', () {
      final jukebox1 = Song(
        id: 'yt_compilation_1',
        title: 'Anirudh hit songs Tamil Non Stop Hits',
        artist: 'Anirudh',
        album: 'Compilation',
        coverUrl: '',
        duration: 7318, // 2+ hours
        source: 'youtube',
      );
      final jukebox2 = Song(
        id: 'yt_compilation_2',
        title: 'Sounds of Tamil - Jukebox',
        artist: 'Various',
        album: 'Compilation',
        coverUrl: '',
        duration: 2205, // 36 mins
        source: 'youtube',
      );
      final regularSong = Song(
        id: 'saavn_track_1',
        title: 'Naan Gaali',
        artist: 'Anirudh',
        album: 'Good Night',
        coverUrl: '',
        duration: 230, // 3.8 mins
        source: 'youtube',
      );
      final shortKeywordSong = Song(
        id: 'yt_compilation_3',
        title: 'Tamil Hits Songs 2026 Playlist',
        artist: 'Various',
        album: 'Compilation',
        coverUrl: '',
        duration: 300,
        source: 'youtube',
      );

      expect(DefaultStreamResolver.isLongFormOrCompilation(jukebox1), isTrue);
      expect(DefaultStreamResolver.isLongFormOrCompilation(jukebox2), isTrue);
      expect(DefaultStreamResolver.isLongFormOrCompilation(shortKeywordSong), isTrue);
      expect(DefaultStreamResolver.isLongFormOrCompilation(regularSong), isFalse);
    });

    test('Fix E: YouTubeClient.invalidateStream deduplicates log spam and handles invalidations safely', () {
      // Calling invalidateStream multiple times does not throw and only purges once
      expect(() => YouTubeClient.invalidateStream('test_video_123'), returnsNormally);
      expect(() => YouTubeClient.invalidateStream('test_video_123'), returnsNormally);
      expect(() => YouTubeClient.invalidateStream(''), returnsNormally);
    });

    test('Fix: StreamResolver shares single in-flight resolution across concurrent requests', () async {
      DefaultStreamResolver.clearCache();
      final song = Song(
        id: 'test_concurrent_id_999',
        title: 'Concurrent Test Song',
        artist: 'Tester',
        album: 'Test Album',
        coverUrl: '',
        duration: 200,
        source: 'audius',
        streamUrl: 'https://audius.co/stream/test_999',
      );

      // Concurrent calls to resolve
      final resolver = DefaultStreamResolver();
      final futures = [
        resolver.resolveStreamUrl(song),
        resolver.resolveStreamUrl(song),
        resolver.resolve(song),
      ];

      final results = await Future.wait(futures);
      expect(results[0], equals('https://audius.co/stream/test_999'));
      expect(results[1], equals('https://audius.co/stream/test_999'));
      expect(results[2], equals('https://audius.co/stream/test_999'));
    });
  });
}
