import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/crossfade_engine.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/party_sync_coordinator.dart';
import 'package:paatu_padava_mobile/services/sleep_timer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SleepTimerService updates isActiveNotifier for End of Queue and cancel', () {
    final timer = SleepTimerService.instance;
    timer.cancel();
    expect(timer.isActive, isFalse);
    expect(timer.isActiveNotifier.value, isFalse);

    timer.setTimer(Duration.zero, stopAtEndOfQueue: true);
    expect(timer.isActive, isTrue);
    expect(timer.stopAtEndOfQueue, isTrue);
    expect(timer.isActiveNotifier.value, isTrue);

    timer.cancel();
    expect(timer.isActive, isFalse);
    expect(timer.stopAtEndOfQueue, isFalse);
    expect(timer.isActiveNotifier.value, isFalse);
  });

  test('CrossfadeEngine.reset clears active beat-match transition plan', () {
    final player = AudioPlayer();
    final engine = CrossfadeEngine(primaryPlayer: player);
    engine.reset();
    expect(engine.activeBeatMatchPlan, isNull);
  });

  test('PartySyncCoordinator.resolveLocalDownloadedCopy matches verified local file by ID or canonicalBaseKey', () async {
    final tempDir = await Directory.systemTemp.createTemp('paatu_partysync_test_');
    try {
      final audioFile = File('${tempDir.path}/track_1.mp3');
      await audioFile.writeAsBytes([1, 2, 3, 4]);

      final hostSong = Song(
        id: 'yt_host_123',
        title: 'Vennilave Vennilave',
        artist: 'A.R. Rahman',
        album: 'Minsara Kanavu',
        duration: 280,
        coverUrl: 'https://example.com/art.jpg',
        source: 'youtube',
      );

      final localDownloadedDifferentId = Song(
        id: 'saavn_local_456',
        title: 'Vennilave Vennilave',
        artist: 'A.R. Rahman',
        album: 'Minsara Kanavu',
        duration: 280,
        coverUrl: 'https://example.com/art.jpg',
        localFilePath: audioFile.path,
        isDownloaded: true,
        source: 'offline',
      );

      final resolvedByKey = PartySyncCoordinator.resolveLocalDownloadedCopy(
        hostSong,
        pathLookup: (_) => null,
        coverLookup: (_) => null,
        downloadedListLookup: () => [localDownloadedDifferentId],
      );

      expect(resolvedByKey, isNotNull);
      expect(resolvedByKey!.isDownloaded, isTrue);
      expect(resolvedByKey.source, 'offline');
      expect(resolvedByKey.localFilePath, audioFile.path);

      // Missing file on disk should return null
      final missingResolved = PartySyncCoordinator.resolveLocalDownloadedCopy(
        hostSong,
        pathLookup: (_) => '${tempDir.path}/does_not_exist.mp3',
        coverLookup: (_) => null,
        downloadedListLookup: () => [],
      );
      expect(missingResolved, isNull);
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
