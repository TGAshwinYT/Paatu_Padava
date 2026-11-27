part of '../party_sync_coordinator.dart';

final Set<String> _lookaheadAckedSongIds = <String>{};
final Set<String> _lookaheadPreparedIds = <String>{};
double _lastAppliedSpeed = 1.0;
int _lastScheduledPlayActualEpochMs = 0;
final DriftSmoother _driftSmoother = DriftSmoother();

void _applySmoothedSpeed(double targetSpeed) {
  if ((targetSpeed - _lastAppliedSpeed).abs() < 0.002) return;
  _lastAppliedSpeed = targetSpeed;
  audioHandler.setSpeed(targetSpeed);
}

void _prewarmUpcomingTracksImpl(List<dynamic>? rawQueue, {int currentIndex = 0}) {
  if (rawQueue == null || rawQueue.isEmpty) return;
  try {
    final upcoming = rawQueue
        .skip(currentIndex + 1)
        .take(3)
        .whereType<Map>()
        .map((m) => Song.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    if (upcoming.isNotEmpty) {
      DefaultStreamResolver.prewarmSongs(upcoming);
    }
  } catch (e) {
    debugPrint('[PartySyncCoordinator] prewarmUpcomingTracks error: $e');
  }
}

void _handleHeartbeatReconciliationImpl(Map<String, dynamic> payload) {
  if (PartySyncCoordinator.role != PartyRole.joiner) return;
  if (PartySyncCoordinator._isSyncLoading) return;

  final nowMs = DateTime.now().millisecondsSinceEpoch;
  if (nowMs - _lastScheduledPlayActualEpochMs < 2500) return;

  final isPlaying = payload['isPlaying'] as bool? ?? false;
  if (!isPlaying) {
    if (audioHandler.playbackState.value.playing) {
      audioHandler.pause(isPartyDriven: true);
    }
    _applySmoothedSpeed(1.0);
    PartySyncCoordinator.syncStatusDescription.value = 'Paused by Host';
    return;
  }

  final refHostEpochMs = (payload['referenceHostEpochMs'] as num?)?.toInt();
  final refPosMs = (payload['referencePositionMs'] as num?)?.toInt();
  if (refHostEpochMs == null || refPosMs == null) return;

  final expectedPos = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
    referenceHostEpochMs: refHostEpochMs,
    referenceTrackPositionMs: refPosMs,
    currentLocalEpochMs: nowMs,
    clockOffsetMs: PartySyncCoordinator.clockOffsetMsNotifier.value,
    bluetoothDelayMs: SettingsManager.bluetoothDelayMs,
    hardwareLatencyMs: SettingsManager.hardwareAudioLatencyMs,
    isPlaying: isPlaying,
  );

  final currentPos = audioHandler.player.position.inMilliseconds;
  final drift = currentPos - expectedPos;
  PartySyncCoordinator.currentDriftMsNotifier.value = drift;

  final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
  final rtt = PartySyncCoordinator.measuredRttMsNotifier.value.round();
  final deadband = DriftReconciler.calculateAdaptiveDeadband(rttMs: rtt, isLan: isLan);
  final microMax = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: rtt, isLan: isLan);

  _driftSmoother.addSample(drift);
  final action = _driftSmoother.computeAction(
    currentPositionMs: currentPos,
    expectedPositionMs: expectedPos,
    deadbandMs: deadband,
    microAdjustMaxMs: microMax,
    wasInSync: PartySyncCoordinator.syncStatusDescription.value.startsWith('In Sync'),
  );

  if (action.isHardSeek && action.seekTargetMs != null) {
    if (nowMs - PartySyncCoordinator._lastHardSeekEpochMs < 8000) {
      final speed = action.driftMs > 0 ? 0.96 : 1.04;
      _applySmoothedSpeed(speed);
      PartySyncCoordinator.syncStatusDescription.value = 'Stabilizing buffer (${speed}x)';
      return;
    }
    PartySyncCoordinator._lastHardSeekEpochMs = nowMs;

    debugPrint('[PartySyncCoordinator] Macro-drift hard seek of ${drift}ms to ${action.seekTargetMs}ms');
    final priorVolume = audioHandler.player.volume;
    audioHandler.player.setVolume(0.0).then((_) async {
      try {
        await audioHandler.seek(Duration(milliseconds: action.seekTargetMs!), isPartyDriven: true);
        _lastScheduledPlayActualEpochMs = DateTime.now().millisecondsSinceEpoch;
        _driftSmoother.reset();
        _applySmoothedSpeed(1.0);
        PartySyncCoordinator.syncStatusDescription.value = 'In Sync';
      } finally {
        await audioHandler.player.setVolume(priorVolume);
      }
    });
  } else if (action.isMicroAdjusting) {
    _applySmoothedSpeed(action.playbackSpeed);
    final pct = ((action.playbackSpeed - 1.0) * 100).toStringAsFixed(1);
    PartySyncCoordinator.syncStatusDescription.value =
        action.playbackSpeed > 1.0 ? 'Catching up (+$pct%)' : 'Slowing down ($pct%)';
  } else {
    _applySmoothedSpeed(1.0);
    PartySyncCoordinator.syncStatusDescription.value = 'In Sync (|drift| < ${deadband}ms)';
  }
}
