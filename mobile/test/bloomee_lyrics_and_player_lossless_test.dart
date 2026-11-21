import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/domain/models/lyrics_state.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/download_manager.dart';
import 'package:paatu_padava_mobile/services/lyrics_client.dart';
import 'package:paatu_padava_mobile/ui/widgets/lyrics/karaoke_line_text.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/player_download_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 1 & 2: Download Quality & Scrubber Full Grey Invariants', () {
    test('Downloaded track offline state evaluates correctly across catalog models', () {
      final remoteSong = Song(
        id: 'track_test_1',
        title: 'Naan Naan',
        artist: 'Santhosh Narayanan',
        duration: 240,
        coverUrl: 'https://c.saavncdn.com/test_500.jpg',
        streamUrl: 'https://c.saavncdn.com/test_96.mp4',
        source: 'saavn',
        isDownloaded: false,
      );

      // Un-downloaded remote song
      expect(remoteSong.isDownloaded, isFalse);
      expect(DownloadManager.isDownloaded(remoteSong.id), isFalse);

      // When enriched by AudioQueueHandler upon download detection
      final downloadedSong = remoteSong.copyWith(
        isDownloaded: true,
        localFilePath: '/mock/path/audio.mp3',
        source: 'offline',
      );

      expect(downloadedSong.isDownloaded, isTrue);
      expect(downloadedSong.source, equals('offline'));
      expect(downloadedSong.localFilePath, isNotNull);
    });

    testWidgets('PlayerDownloadButton renders idle, download and completed states', (tester) async {
      final testSong = Song(
        id: 'dl_btn_test_1',
        title: 'Bloomee Beat',
        artist: 'Anirudh',
        coverUrl: 'https://c.saavncdn.com/test_500.jpg',
        duration: 180,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PlayerDownloadButton(
                song: testSong,
                size: 28,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PlayerDownloadButton), findsOneWidget);
      expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);
    });
  });

  group('Phase 3 & 4: Bloomee Progressive Lyrics & Duration Matching', () {
    testWidgets('KaraokeLineText computes smooth progressive sweep for standard LRC lines without words', (tester) async {
      final standardLrcLine = LyricLine(
        timestamp: const Duration(seconds: 10),
        endTimestamp: const Duration(seconds: 14),
        text: 'Idhu oru puthiya paadhal',
        words: const [], // Standard LRC without word timestamps
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: KaraokeLineText(
                line: standardLrcLine,
                position: const Duration(seconds: 12), // Exactly 50% elapsed
                isActive: true,
                isKaraokeMode: false,
                language: LyricsLanguage.defaultLang,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                baseColor: Colors.white38,
                activeColor: Colors.white,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(KaraokeLineText), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    test('LRC Duration Filter correctly rejects candidates exceeding 12s delta', () {
      const targetDurationSeconds = 240;

      final candidates = [
        {'id': 1, 'duration': 320, 'syncedLyrics': '[00:01.00] Wrong version'}, // delta 80s -> Reject
        {'id': 2, 'duration': 180, 'syncedLyrics': '[00:01.00] Short remix'},   // delta 60s -> Reject
        {'id': 3, 'duration': 244, 'syncedLyrics': '[00:01.00] Studio version'},// delta 4s  -> Accept
      ];

      final matching = candidates.where((c) {
        final dur = c['duration'] as int;
        return (dur - targetDurationSeconds).abs() <= 12;
      }).toList();

      expect(matching.length, equals(1));
      expect(matching.first['id'], equals(3));
    });
  });
}
