part of '../party_sync_coordinator.dart';

Future<void> _handleRemotePrepareNextImpl(Map<String, dynamic> payload) async {
  try {
    final songData = payload['song'] as Map<dynamic, dynamic>?;
    final songId = payload['songId']?.toString();
    if (songData == null && songId == null) return;
    final song = songData != null
        ? Song.fromMap(Map<String, dynamic>.from(songData))
        : null;
    if (song == null) return;

    final localCopy = PartySyncCoordinator.resolveLocalDownloadedCopy(song);
    if (localCopy == null) {
      final rawUrl = payload['streamUrl']?.toString() ?? song.streamUrl;
      final directUrl = rawUrl != null && rawUrl.isNotEmpty
          ? PartySyncCoordinator._optimizeStreamUrlForNetwork(rawUrl)
          : null;
      if (directUrl != null && directUrl.isNotEmpty) {
        DefaultStreamResolver.cacheStream(song.id, directUrl);
      } else {
        await DefaultStreamResolver.prewarmSongs([song]);
      }
    }

    _lookaheadPreparedIds.add(song.id);
    final ackPayload = {
      'peerId': PartySyncCoordinator._clientId,
      'cmdId': payload['cmdId'],
      'songId': song.id,
      'lookahead': true,
      'token': PartySyncCoordinator._sessionSecret,
    };
    PartyLanAccelerator.sendDirect('peer_ready', ackPayload);
    PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
      event: 'peer_ready',
      payload: ackPayload,
    );
  } catch (e) {
    debugPrint('[PartySyncCoordinator] handleRemotePrepareNext error: $e');
  }
}

Future<void> _handleRemotePrepareImpl(Map<String, dynamic> payload) async {
  PartySyncCoordinator._cancelPendingScheduledOperations();
  try {
    final songData = payload['song'] as Map<dynamic, dynamic>?;
    final songId = payload['songId']?.toString();
    final rawStreamUrl = payload['streamUrl']?.toString() ??
        (songData != null ? songData['streamUrl']?.toString() : null);
    Song? song;
    if (songData != null) {
      song = Song.fromMap(Map<String, dynamic>.from(songData));
    }
    bool hasLocalFile = false;
    if (song != null) {
      final localCopy = PartySyncCoordinator.resolveLocalDownloadedCopy(song);
      if (localCopy != null) {
        song = localCopy;
        hasLocalFile = true;
      } else {
        final directStreamUrl = rawStreamUrl != null
            ? PartySyncCoordinator._optimizeStreamUrlForNetwork(rawStreamUrl)
            : null;
        if (directStreamUrl != null && directStreamUrl.isNotEmpty) {
          song.streamUrl = directStreamUrl;
          DefaultStreamResolver.cacheStream(song.id, directStreamUrl);
        }
      }
    }

    final positionMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
    final currentSong = audioHandler.currentSong;
    final bool isSameSong = (song != null && currentSong?.id == song.id) ||
        (songId != null && currentSong?.id == songId);

    if (!isSameSong && song != null) {
      PartySyncCoordinator._isSyncLoading = true;
      PartySyncCoordinator.syncStatusDescription.value = hasLocalFile
          ? 'Ready (local file): "${song.title}"'
          : 'Preparing "${song.title}"...';
      try {
        final rawQueue = payload['queue'] as List<dynamic>?;
        List<Song>? queue;
        if (rawQueue != null && rawQueue.isNotEmpty) {
          queue = rawQueue.map((item) => Song.fromMap(Map<String, dynamic>.from(item as Map))).toList();
        }
        await audioHandler.playSong(
          song,
          queue: queue ?? [song],
          preserveUserQueue: false,
          isPartySyncInternal: true,
          autoPlay: false,
        );
        if (!hasLocalFile) {
          PartySyncCoordinator._prewarmUpcomingTracks(
            rawQueue,
            currentIndex: (payload['currentIndex'] as num?)?.toInt() ?? 0,
          );
        }
      } finally {
        PartySyncCoordinator._isSyncLoading = false;
      }
    }

    await audioHandler.pause(isPartyDriven: true);
    if (positionMs > 0) {
      await audioHandler.seek(Duration(milliseconds: positionMs), isPartyDriven: true);
    } else {
      await audioHandler.seek(Duration.zero, isPartyDriven: true);
    }

    final ackPayload = {
      'peerId': PartySyncCoordinator._clientId,
      'cmdId': payload['cmdId'],
      'songId': songId ?? song?.id,
      'hasLocalFile': hasLocalFile,
      'token': PartySyncCoordinator._sessionSecret,
    };
    PartyLanAccelerator.sendDirect('peer_ready', ackPayload);
    PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
      event: 'peer_ready',
      payload: ackPayload,
    );
    PartySyncCoordinator.syncStatusDescription.value =
        hasLocalFile ? 'Ready (local file)' : 'Ready (waiting for host)';
  } catch (e) {
    debugPrint('[PartySyncCoordinator] handleRemotePrepare error: $e');
  }
}

Future<void> _handleRemotePlayImpl(Map<String, dynamic> payload) async {
  PartySyncCoordinator._cancelPendingScheduledOperations();

  try {
    final songData = payload['song'] as Map<dynamic, dynamic>?;
    final songId = payload['songId']?.toString();
    final rawStreamUrl = payload['streamUrl']?.toString() ??
        (songData != null ? songData['streamUrl']?.toString() : null);
    final directStreamUrl = rawStreamUrl != null
        ? PartySyncCoordinator._optimizeStreamUrlForNetwork(rawStreamUrl)
        : null;
    Song? song;
    if (songData != null) {
      song = Song.fromMap(Map<String, dynamic>.from(songData));
    }
    if (song != null && directStreamUrl != null && directStreamUrl.isNotEmpty) {
      song.streamUrl = directStreamUrl;
      DefaultStreamResolver.cacheStream(song.id, directStreamUrl);
    }

    final positionMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
    final startAtEpochMs = (payload['startAtEpochMs'] as num?)?.toInt() ?? 0;
    final refHostEpoch = (payload['referenceHostEpochMs'] as num?)?.toInt() ?? startAtEpochMs;
    final refHostPos = (payload['referencePositionMs'] as num?)?.toInt() ?? positionMs;
    final isHostPlaying = payload['isPlaying'] != false;

    final currentSong = audioHandler.currentSong;
    final bool isSameSong = (song != null && currentSong?.id == song.id) ||
        (songId != null && currentSong?.id == songId);

    if (!isSameSong && song != null) {
      PartySyncCoordinator._isSyncLoading = true;
      PartySyncCoordinator.syncStatusDescription.value = 'Syncing "${song.title}"...';
      try {
        final rawQueue = payload['queue'] as List<dynamic>?;
        List<Song>? queue;
        if (rawQueue != null && rawQueue.isNotEmpty) {
          queue = rawQueue.map((item) => Song.fromMap(Map<String, dynamic>.from(item as Map))).toList();
        }
        await audioHandler.playSong(
          song,
          queue: queue ?? [song],
          preserveUserQueue: false,
          isPartySyncInternal: true,
          autoPlay: false,
        );
        PartySyncCoordinator._prewarmUpcomingTracks(
          rawQueue,
          currentIndex: (payload['currentIndex'] as num?)?.toInt() ?? 0,
        );
      } finally {
        PartySyncCoordinator._isSyncLoading = false;
      }
    }

    await audioHandler.pause(isPartyDriven: true);
    if (positionMs > 0) {
      await audioHandler.seek(Duration(milliseconds: positionMs), isPartyDriven: true);
    } else {
      await audioHandler.seek(Duration.zero, isPartyDriven: true);
    }

    final hardwareLatencyMs = SettingsManager.hardwareAudioLatencyMs;
    final bluetoothDelayMs = PartySyncCoordinator._effectiveBluetoothDelayMs;
    final latencyOffsetMs = bluetoothDelayMs + hardwareLatencyMs;

    final nowLocal = DateTime.now().millisecondsSinceEpoch;
    final estimatedHostTimeMs = nowLocal + PartySyncCoordinator.clockOffsetMs;
    final remainingDelayMs = startAtEpochMs - estimatedHostTimeMs - latencyOffsetMs;

    if (remainingDelayMs > 15) {
      PartySyncCoordinator._pendingScheduledPlayTimer?.cancel();
      PartySyncCoordinator._pendingScheduledPlayTimer = Timer(Duration(milliseconds: remainingDelayMs), () {
        if (PartySyncCoordinator.role != PartyRole.joiner) return;
        audioHandler.play().catchError((e) {
          AppLogger.debug('PartySyncCoordinator', 'Joiner play error: $e');
        });
        PartySyncCoordinator.syncStatusDescription.value = 'In Sync';
      });
    } else {
      final targetPosMs = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
        referenceHostEpochMs: refHostEpoch,
        referenceTrackPositionMs: refHostPos,
        currentLocalEpochMs: nowLocal,
        clockOffsetMs: PartySyncCoordinator.clockOffsetMs,
        bluetoothDelayMs: bluetoothDelayMs,
        hardwareLatencyMs: hardwareLatencyMs,
        isPlaying: isHostPlaying,
      );

      if (targetPosMs > 0) {
        await audioHandler.seek(Duration(milliseconds: targetPosMs), isPartyDriven: true);
      }
      if (isHostPlaying) {
        audioHandler.play().catchError((e) {
          AppLogger.debug('PartySyncCoordinator', 'Joiner immediate play error: $e');
        });
      } else {
        await audioHandler.pause(isPartyDriven: true);
      }
      PartySyncCoordinator.syncStatusDescription.value = 'In Sync';
    }
  } catch (e) {
    debugPrint('[PartySyncCoordinator] handleRemotePlay error: $e');
  }
}

void _handleRemotePauseImpl(Map<String, dynamic> payload) {
  PartySyncCoordinator._cancelPendingScheduledOperations();
  final posMs = (payload['positionMs'] as num?)?.toInt();
  audioHandler.pause(isPartyDriven: true);
  if (posMs != null && posMs > 0) {
    audioHandler.seek(Duration(milliseconds: posMs), isPartyDriven: true);
  }
  PartySyncCoordinator.syncStatusDescription.value = 'Host Paused';
}

Future<void> _handleRemoteSeekImpl(Map<String, dynamic> payload) async {
  PartySyncCoordinator._cancelPendingScheduledOperations();
  final posMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
  final startAtEpochMs = (payload['startAtEpochMs'] as num?)?.toInt();
  if (startAtEpochMs != null) {
    await audioHandler.pause(isPartyDriven: true);
    await audioHandler.seek(Duration(milliseconds: posMs), isPartyDriven: true);

    final hardwareLatencyMs = SettingsManager.hardwareAudioLatencyMs;
    final bluetoothDelayMs = PartySyncCoordinator._effectiveBluetoothDelayMs;
    final latencyOffsetMs = bluetoothDelayMs + hardwareLatencyMs;

    final nowLocal = DateTime.now().millisecondsSinceEpoch;
    final estHostTime = nowLocal + PartySyncCoordinator.clockOffsetMs;
    final remainingDelayMs = startAtEpochMs - estHostTime - latencyOffsetMs;

    if (remainingDelayMs > 15) {
      PartySyncCoordinator._pendingSeekTimer = Timer(Duration(milliseconds: remainingDelayMs), () {
        if (PartySyncCoordinator.role != PartyRole.joiner) return;
        audioHandler.play().catchError((_) => null);
      });
      return;
    }
    audioHandler.play().catchError((_) => null);
    return;
  }
  await audioHandler.seek(Duration(milliseconds: posMs), isPartyDriven: true);
}
