import 'dart:math';

/// NTP-style 4-timestamp exchange sample:
/// t0: local client send timestamp
/// t1: host receive timestamp
/// t2: host transmit/response timestamp
/// t3: local client receive timestamp
class NtpSample {
  final int t0;
  final int t1;
  final int t2;
  final int t3;

  const NtpSample({
    required this.t0,
    required this.t1,
    required this.t2,
    required this.t3,
  });

  /// Round Trip Time (excluding processing time on host)
  int get rtt => max(0, (t3 - t0) - (t2 - t1));

  /// Clock offset of host relative to client:
  /// θ = ((t1 - t0) + (t2 - t3)) / 2
  /// When θ > 0, host clock is ahead of client clock.
  /// When θ < 0, host clock is behind client clock.
  int get offset => (((t1 - t0) + (t2 - t3)) / 2).round();

  Map<String, dynamic> toMap() => {'t0': t0, 't1': t1, 't2': t2, 't3': t3, 'rtt': rtt, 'offset': offset};
}

/// NTP-style clock offset calculator with outlier rejection.
class NtpCalculator {
  /// Computes a robust clock offset from multiple NTP exchange samples.
  /// Sorts samples by RTT and averages the lowest 50% lowest-latency samples
  /// to eliminate network jitter and queuing delays.
  static int calculateOffset(List<NtpSample> samples) {
    if (samples.isEmpty) return 0;
    if (samples.length == 1) return samples.first.offset;

    // Sort by RTT ascending (cleanest network paths first)
    final sorted = List<NtpSample>.from(samples)..sort((a, b) => a.rtt.compareTo(b.rtt));

    // Keep top 50% lowest RTT samples (at least 1)
    final countToKeep = max(1, (sorted.length * 0.5).ceil());
    final bestSamples = sorted.take(countToKeep).toList();

    final sumOffset = bestSamples.fold<int>(0, (sum, s) => sum + s.offset);
    return (sumOffset / bestSamples.length).round();
  }

  /// Converts a local timestamp to estimated host time
  static int estimateHostTime({required int localTimeMs, required int clockOffsetMs}) {
    return localTimeMs + clockOffsetMs;
  }

  /// Converts a host timestamp to estimated local time
  static int estimateLocalTime({required int hostTimeMs, required int clockOffsetMs}) {
    return hostTimeMs - clockOffsetMs;
  }
}

/// Action determined by drift analysis
enum DriftActionType {
  inSync,
  slowDown,
  speedUp,
  hardSeek,
}

class DriftAction {
  final DriftActionType type;
  final double playbackSpeed;
  final int driftMs;
  final int? seekTargetMs;

  const DriftAction({
    required this.type,
    required this.playbackSpeed,
    required this.driftMs,
    this.seekTargetMs,
  });

  bool get isInSync => type == DriftActionType.inSync;
  bool get isMicroAdjusting => type == DriftActionType.slowDown || type == DriftActionType.speedUp;
  bool get isHardSeek => type == DriftActionType.hardSeek;

  @override
  String toString() => 'DriftAction($type, speed: ${playbackSpeed}x, drift: ${driftMs}ms, seekTarget: $seekTargetMs)';
}

/// Drift reconciler to preserve audio lockstep without audible clicks/pops.
class DriftReconciler {
  /// Reconciles local playback position against expected host position.
  ///
  /// - |drift| < [deadbandMs] (e.g. 50ms): in sync, speed = 1.0x (no-op).
  /// - [deadbandMs] <= |drift| <= [microAdjustMaxMs] (e.g. 50ms - 200ms):
  ///   - drift > 0 (local ahead): soft slow down (speed = 0.98x).
  ///   - drift < 0 (local behind): soft catch up (speed = 1.02x).
  /// - |drift| > [microAdjustMaxMs] (e.g. > 200ms): hard seek to target position.
  static DriftAction reconcileDrift({
    required int currentPositionMs,
    required int expectedPositionMs,
    int deadbandMs = 50,
    int microAdjustMaxMs = 200,
  }) {
    final drift = currentPositionMs - expectedPositionMs;

    if (drift.abs() < deadbandMs) {
      return DriftAction(
        type: DriftActionType.inSync,
        playbackSpeed: 1.0,
        driftMs: drift,
      );
    }

    if (drift.abs() <= microAdjustMaxMs) {
      if (drift > 0) {
        // Local is ahead: gently slow down to 0.98x
        return DriftAction(
          type: DriftActionType.slowDown,
          playbackSpeed: 0.98,
          driftMs: drift,
        );
      } else {
        // Local is behind: gently speed up to 1.02x
        return DriftAction(
          type: DriftActionType.speedUp,
          playbackSpeed: 1.02,
          driftMs: drift,
        );
      }
    }

    // Large drift: hard seek directly to expected position
    return DriftAction(
      type: DriftActionType.hardSeek,
      playbackSpeed: 1.0,
      driftMs: drift,
      seekTargetMs: max(0, expectedPositionMs),
    );
  }
}

/// Scheduled epoch playback and Bluetooth compensation calculator.
class ScheduledPlaybackCalculator {
  /// Calculates the millisecond delay to wait before triggering `player.play()`
  /// so that all participating devices start audio on the exact same millisecond.
  static int calculateScheduledDelayMs({
    required int startAtEpochMs,
    required int currentLocalEpochMs,
    int clockOffsetMs = 0,
  }) {
    final estimatedHostTimeMs = currentLocalEpochMs + clockOffsetMs;
    final delayMs = startAtEpochMs - estimatedHostTimeMs;
    return max(0, delayMs);
  }

  /// Calculates expected track playback position at the current moment,
  /// factoring in elapsed time, host clock offset, and manual Bluetooth audio delay.
  ///
  /// [bluetoothDelayMs]: Manual user adjustment (-500ms to +500ms) to compensate
  /// for Bluetooth headphone/speaker hardware DAC buffer latency (A2DP typical 100-250ms).
  static int calculateExpectedPositionMs({
    required int referenceHostEpochMs,
    required int referenceTrackPositionMs,
    required int currentLocalEpochMs,
    int clockOffsetMs = 0,
    int bluetoothDelayMs = 0,
    double speed = 1.0,
    bool isPlaying = true,
  }) {
    if (!isPlaying) {
      return max(0, referenceTrackPositionMs + bluetoothDelayMs);
    }

    final currentEstimatedHostTime = currentLocalEpochMs + clockOffsetMs;
    final elapsedMs = ((currentEstimatedHostTime - referenceHostEpochMs) * speed).round();
    final rawExpected = referenceTrackPositionMs + elapsedMs;

    return max(0, rawExpected + bluetoothDelayMs);
  }
}
