part of '../party_sync_coordinator.dart';

Future<void> _notifyHostPlayImpl(
  Song song, {
  int positionMs = 0,
  List<Song>? queue,
  int? currentIndex,
}) async {
  if (!PartySyncCoordinator.isHost) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  PartySyncCoordinator._lastAnnouncedSongId = song.id;
  PartySyncCoordinator._lastAnnouncedTimeMs = now;
  PartySyncCoordinator._cancelPendingScheduledOperations();

  final cmdId = PartySyncCoordinator._uuid.v4();
  PartySyncCoordinator._pendingPrepareCmdId = cmdId;
  final seq = ++PartySyncCoordinator._currentHostSeq;

  final directUrl = song.streamUrl ??
      DefaultStreamResolver.getCachedStream(song.id) ??
      audioHandler.currentSong?.streamUrl;

  final preparePayload = {
    'cmdId': cmdId,
    'seq': seq,
    'token': PartySyncCoordinator._sessionSecret,
    'song': song.toMap(),
    'songId': song.id,
    'streamUrl': directUrl,
    'positionMs': positionMs,
    'currentIndex': currentIndex ?? 0,
    'queue': queue?.take(30).map((s) => s.toMap()).toList(),
  };

  PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
    event: 'sync_prepare',
    payload: preparePayload,
  );
  PartyLanAccelerator.sendSyncEvent('sync_prepare', preparePayload);

  final hasRemotePeers = PartySyncCoordinator._knownPeers.values.any((p) => !p.isSelf);
  if (hasRemotePeers) {
    PartySyncCoordinator._peerReadyCompleter = Completer<void>();
    final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
    final barrierTimeoutMs = isLan ? 1200 : 3500;
    try {
      await PartySyncCoordinator._peerReadyCompleter!.future
          .timeout(Duration(milliseconds: barrierTimeoutMs));
    } catch (e) {
      AppLogger.debug('PartySyncCoordinator', 'Handled exception: $e');
    }
    PartySyncCoordinator._peerReadyCompleter = null;
  }

  if (PartySyncCoordinator._pendingPrepareCmdId != cmdId) {
    AppLogger.debug('PartySyncCoordinator',
        'Prepare cycle for $cmdId superseded; aborting stale play broadcast.');
    return;
  }

  final peerRtts = PartySyncCoordinator._knownPeers.values
      .where((p) => !p.isSelf)
      .map((p) => p.rttMs)
      .toList();
  final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
  final leadTimeMs = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
    peerRtts: peerRtts,
    isLan: isLan,
  );
  final hostNow = DateTime.now().millisecondsSinceEpoch;
  final startAtEpochMs = hostNow + leadTimeMs;

  final playPayload = {
    'cmdId': PartySyncCoordinator._uuid.v4(),
    'prepareCmdId': cmdId,
    'seq': ++PartySyncCoordinator._currentHostSeq,
    'token': PartySyncCoordinator._sessionSecret,
    'song': song.toMap(),
    'songId': song.id,
    'streamUrl': directUrl,
    'positionMs': positionMs,
    'referenceHostEpochMs': startAtEpochMs,
    'referencePositionMs': positionMs,
    'startAtEpochMs': startAtEpochMs,
    'currentIndex': currentIndex ?? 0,
    'isPlaying': true,
  };

  PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
    event: 'sync_play',
    payload: playPayload,
  );
  PartyLanAccelerator.sendSyncEvent('sync_play', playPayload);
  Future.delayed(const Duration(milliseconds: 30), () {
    if (PartySyncCoordinator.isHost) {
      PartyLanAccelerator.sendSyncEvent('sync_play', playPayload);
    }
  });

  await audioHandler.player.pause();
  if (positionMs > 0) {
    await audioHandler.player.seek(Duration(milliseconds: positionMs));
  } else {
    await audioHandler.player.seek(Duration.zero);
  }

  final remainingDelay = startAtEpochMs - DateTime.now().millisecondsSinceEpoch;
  if (remainingDelay > 10) {
    PartySyncCoordinator._pendingScheduledPlayTimer?.cancel();
    PartySyncCoordinator._pendingScheduledPlayTimer = Timer(Duration(milliseconds: remainingDelay), () {
      if (PartySyncCoordinator.isHost) {
        audioHandler.player.play().catchError((e) {
          AppLogger.debug('PartySyncCoordinator', 'Host scheduled play error: $e');
        });
      }
    });
  } else {
    audioHandler.player.play().catchError((e) {
      AppLogger.debug('PartySyncCoordinator', 'Host immediate play error: $e');
    });
  }
}

Future<void> _notifyHostPauseImpl() async {
  if (!PartySyncCoordinator.isHost) return;
  final pos = audioHandler.player.position.inMilliseconds;
  final seq = ++PartySyncCoordinator._currentHostSeq;
  final payload = {
    'cmdId': PartySyncCoordinator._uuid.v4(),
    'seq': seq,
    'token': PartySyncCoordinator._sessionSecret,
    'positionMs': pos,
  };

  PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
    event: 'sync_pause',
    payload: payload,
  );
  PartyLanAccelerator.sendSyncEvent('sync_pause', payload);
}

Future<void> _notifyHostSeekImpl(Duration position) async {
  if (!PartySyncCoordinator.isHost) return;
  final seq = ++PartySyncCoordinator._currentHostSeq;
  final payload = {
    'cmdId': PartySyncCoordinator._uuid.v4(),
    'seq': seq,
    'token': PartySyncCoordinator._sessionSecret,
    'positionMs': position.inMilliseconds,
  };

  PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
    event: 'sync_seek',
    payload: payload,
  );
  PartyLanAccelerator.sendSyncEvent('sync_seek', payload);
}

Future<void> _notifyHostResumeImpl() async {
  if (!PartySyncCoordinator.isHost) return;
  final pos = audioHandler.player.position.inMilliseconds;
  final now = DateTime.now().millisecondsSinceEpoch;
  final curSong = audioHandler.currentSong;
  final seq = ++PartySyncCoordinator._currentHostSeq;

  final peerRtts = PartySyncCoordinator._knownPeers.values.where((p) => !p.isSelf).map((p) => p.rttMs).toList();
  final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
  final leadTimeMs = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
    peerRtts: peerRtts,
    isLan: isLan,
  );
  final startAtEpochMs = now + leadTimeMs;

  final payload = {
    'cmdId': PartySyncCoordinator._uuid.v4(),
    'seq': seq,
    'token': PartySyncCoordinator._sessionSecret,
    'song': curSong?.toMap(),
    'songId': curSong?.id,
    'positionMs': pos,
    'referenceHostEpochMs': startAtEpochMs,
    'referencePositionMs': pos,
    'startAtEpochMs': startAtEpochMs,
    'isPlaying': true,
  };

  PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
    event: 'sync_play',
    payload: payload,
  );
  PartyLanAccelerator.sendSyncEvent('sync_play', {
    'cmdId': payload['cmdId'],
    'seq': seq,
    'token': PartySyncCoordinator._sessionSecret,
    'songId': curSong?.id,
    'positionMs': pos,
    'referenceHostEpochMs': startAtEpochMs,
    'referencePositionMs': pos,
    'startAtEpochMs': startAtEpochMs,
    'isPlaying': true,
  });

  final remainingDelay = startAtEpochMs - DateTime.now().millisecondsSinceEpoch;
  if (remainingDelay > 10) {
    await audioHandler.player.pause();
    PartySyncCoordinator._pendingScheduledPlayTimer?.cancel();
    PartySyncCoordinator._pendingScheduledPlayTimer = Timer(Duration(milliseconds: remainingDelay), () {
      if (PartySyncCoordinator.isHost) {
        audioHandler.player.play().catchError((e) {
          AppLogger.debug('PartySyncCoordinator', 'Host resume error: $e');
        });
      }
    });
  } else {
    audioHandler.player.play().catchError((e) {
      AppLogger.debug('PartySyncCoordinator', 'Host resume error: $e');
    });
  }
}

void _broadcastCurrentStateImpl() {
  if (!PartySyncCoordinator.isHost) return;
  final pos = audioHandler.player.position.inMilliseconds;
  final now = DateTime.now().millisecondsSinceEpoch;
  final isPlaying = audioHandler.playbackState.value.playing;
  final currentSong = audioHandler.currentSong;

  final seq = ++PartySyncCoordinator._currentHostSeq;
  final directUrl = currentSong?.streamUrl ?? DefaultStreamResolver.getCachedStream(currentSong?.id ?? '');
  final payload = {
    'seq': seq,
    'token': PartySyncCoordinator._sessionSecret,
    'isPlaying': isPlaying,
    'songId': currentSong?.id,
    'song': currentSong?.toMap(),
    'streamUrl': directUrl,
    'referenceHostEpochMs': now,
    'referencePositionMs': pos,
    'peers': PartySyncCoordinator._knownPeers.values.map((p) => p.toMap()).toList(),
    'peerCount': PartySyncCoordinator._knownPeers.length,
    'lanIps': PartySyncCoordinator._localIps,
    'lanPort': PartyLanAccelerator.defaultPort,
  };

  PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
    event: 'sync_heartbeat',
    payload: payload,
  );

  PartyLanAccelerator.sendSyncEvent('sync_heartbeat', {
    'seq': seq,
    'token': PartySyncCoordinator._sessionSecret,
    'isPlaying': isPlaying,
    'songId': currentSong?.id,
    'song': currentSong?.toMap(),
    'streamUrl': directUrl,
    'referenceHostEpochMs': now,
    'referencePositionMs': pos,
    'peerCount': PartySyncCoordinator._knownPeers.length,
  });
}

Future<void> _hostTransitionToNextImpl(
  Song nextSong, {
  List<Song>? queue,
  int? currentIndex,
}) async {
  if (!PartySyncCoordinator.isHost) {
    await audioHandler.playSong(nextSong, queue: queue, preserveUserQueue: false);
    return;
  }
  PartySyncCoordinator._cancelPendingScheduledOperations();
  await audioHandler.playSong(
    nextSong,
    queue: queue,
    preserveUserQueue: false,
    autoPlay: false,
    isPartySyncInternal: true,
  );
  await PartySyncCoordinator.notifyHostPlay(nextSong, positionMs: 0, queue: queue, currentIndex: currentIndex);
}

void _notifyHostQueueUpdatedImpl(List<Song> queue, int currentIndex) {
  if (!PartySyncCoordinator.isHost || PartySyncCoordinator._partyChannel == null) return;
  final curSong = audioHandler.currentSong;
  final isPlaying = audioHandler.playbackState.value.playing;
  final seq = ++PartySyncCoordinator._currentHostSeq;

  final payload = {
    'seq': seq,
    'token': PartySyncCoordinator._sessionSecret,
    'queue': queue.take(30).map((s) => s.toMap()).toList(),
    'currentIndex': currentIndex,
    'activeSongId': curSong?.id,
    'isPlaying': isPlaying,
  };

  PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
    event: 'sync_queue',
    payload: payload,
  );
}
