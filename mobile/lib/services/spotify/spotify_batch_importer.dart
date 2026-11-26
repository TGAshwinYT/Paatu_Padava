part of '../spotify_import_service.dart';

Future<SpotifyImportResult> _importPlaylistWithProgressImpl({
  required SpotifyPlaylistMetadata metadata,
  required void Function(
    int current,
    int total,
    double progress,
    String status,
    Song? matched,
  ) onProgress,
  String? preferredLanguage,
  bool Function()? isCancelled,
  bool Function(SpotifyTrackItem track)? isAlreadyImported,
}) async {
  final total = metadata.tracks.length;
  if (total == 0) {
    return SpotifyImportResult(
      playlistTitle: metadata.title,
      coverUrl: metadata.coverUrl,
      totalTracks: 0,
      importedSongs: const [],
      skippedTracks: const [],
      alreadyPresentCount: 0,
      handledKeys: const [],
    );
  }

  final matchedSlots = List<Song?>.filled(total, null);
  final skippedSlots = List<SpotifyTrackItem?>.filled(total, null);
  final isPresentSlots = List<bool>.filled(total, false);
  final handledKeySlots = List<String?>.filled(total, null);

  int completedCount = 0;
  DateTime lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);

  unawaited(BatteryOptimizationService.startDataSync(
    title: 'Importing Spotify Playlist',
    message: 'Matching tracks (0/$total)...',
    progress: 0,
    max: total,
  ));

  void emitProgress(int current, double prog, String status, Song? matched) {
    final now = DateTime.now();
    if (now.difference(lastProgressEmit).inMilliseconds >= 80 || current == total) {
      lastProgressEmit = now;
      onProgress(current, total, prog, status, matched);
      unawaited(BatteryOptimizationService.updateDataSyncProgress(
        title: 'Importing Spotify Playlist',
        message: '$status ($current/$total)',
        progress: current,
        max: total,
      ));
    }
  }

  final indexQueue = Queue<int>.from(List.generate(total, (i) => i));
  final concurrency = total < 5 ? total : 5;
  final workers = List.generate(concurrency, (_) async {
    while (true) {
      if (isCancelled?.call() == true) {
        debugPrint('[SpotifyImportService] Import cancelled by user');
        break;
      }
      if (indexQueue.isEmpty) break;
      final i = indexQueue.removeFirst();

      final track = metadata.tracks[i];
      final cleanTitle = SpotifyImportService.cleanTrackTitle(track.title);

      if (isAlreadyImported != null && isAlreadyImported(track)) {
        isPresentSlots[i] = true;
        handledKeySlots[i] = SpotifyImportService.trackKey(track);
        completedCount++;
        emitProgress(
          completedCount,
          completedCount / total,
          'Already in playlist: "$cleanTitle"',
          null,
        );
        continue;
      }

      emitProgress(completedCount, completedCount / total, 'Matching: "$cleanTitle"...', null);

      try {
        final matched = await SpotifyImportService.matchSingleTrack(
          track,
          preferredLanguage: preferredLanguage,
        ).timeout(
          const Duration(milliseconds: 5000),
          onTimeout: () => SpotifyImportService._synthesizeTrack(track, effectiveCover: track.coverUrl),
        );

        final effective = matched ?? SpotifyImportService._synthesizeTrack(track, effectiveCover: track.coverUrl);
        matchedSlots[i] = effective;
        handledKeySlots[i] = SpotifyImportService.trackKey(track);
        completedCount++;
        emitProgress(completedCount, completedCount / total, 'Matched "$cleanTitle"', effective);
      } catch (e) {
        final fallback = SpotifyImportService._synthesizeTrack(track, effectiveCover: track.coverUrl);
        matchedSlots[i] = fallback;
        handledKeySlots[i] = SpotifyImportService.trackKey(track);
        completedCount++;
        emitProgress(completedCount, completedCount / total, 'Matched "$cleanTitle"', fallback);
      }

      await Future.delayed(const Duration(milliseconds: 15));
    }
  });

  final masterWatchdog = Duration(seconds: (total * 2).clamp(25, 240));
  await Future.wait(workers).timeout(
    masterWatchdog,
    onTimeout: () {
      debugPrint('[SpotifyImportService] Master watchdog triggered after ${masterWatchdog.inSeconds}s');
      for (int i = 0; i < total; i++) {
        matchedSlots[i] ??= SpotifyImportService._synthesizeTrack(
          metadata.tracks[i],
          effectiveCover: metadata.tracks[i].coverUrl,
        );
      }
      return [];
    },
  );
  unawaited(BatteryOptimizationService.stopDataSync());

  return SpotifyImportResult(
    playlistTitle: metadata.title,
    coverUrl: metadata.coverUrl,
    totalTracks: total,
    importedSongs: matchedSlots.whereType<Song>().toList(),
    skippedTracks: skippedSlots.whereType<SpotifyTrackItem>().toList(),
    alreadyPresentCount: isPresentSlots.where((p) => p).length,
    handledKeys: handledKeySlots.whereType<String>().toList(),
  );
}
