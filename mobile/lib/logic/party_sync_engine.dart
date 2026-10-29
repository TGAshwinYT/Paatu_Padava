import 'dart:math';

/// Party Synchronization Modes:
enum PartySyncMode {
  /// Local Wi-Fi network: sub-millisecond precision, speaker synchronization
  speakerMode,

  /// Cloud / Internet: cross-location listening together
  listenTogether,
}

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
  final bool isLan;

  const NtpSample({
    required this.t0,
    required this.t1,
    required this.t2,
    required this.t3,
    this.isLan = false,
  });

  /// Round Trip Time (excluding processing time on host)
  int get rtt => max(0, (t3 - t0) - (t2 - t1));

  /// Clock offset of host relative to client:
  /// θ = ((t1 - t0) + (t2 - t3)) / 2
  /// When θ > 0, host clock is ahead of client clock.
  /// When θ < 0, host clock is behind client clock.
  int get offset => (((t1 - t0) + (t2 - t3)) / 2).round();

  Map<String, dynamic> toMap() => {
    't0': t0,
    't1': t1,
    't2': t2,
    't3': t3,
    'rtt': rtt,
    'offset': offset,
    'isLan': isLan,
  };
}

/// NTP-style clock offset calculator with sliding-window outlier rejection.
class NtpCalculator {
  /// Computes a robust clock offset from multiple NTP exchange samples.
  ///
  /// Enhancements:
  /// 1. Prioritizes LAN samples if present and recent.
  /// 2. Filters out samples whose RTT exceeds 1.5x of the minimum observed RTT.
  /// 3. Sorts remaining samples by RTT ascending and averages the best lowest-RTT samples.
  static int calculateOffset(List<NtpSample> samples) {
    if (samples.isEmpty) return 0;
    if (samples.length == 1) return samples.first.offset;

    // Prefer clean LAN samples when available (LAN RTT is typically 1-5ms vs Cloud 40-150ms)
    final lanSamples = samples.where((s) => s.isLan).toList();
    final activeSamples = lanSamples.isNotEmpty ? lanSamples : samples;

    // Sort by RTT ascending (cleanest network paths first)
    final sorted = List<NtpSample>.from(activeSamples)..sort((a, b) => a.rtt.compareTo(b.rtt));

    // Reject samples whose RTT exceeds 1.5x of minimum RTT (when >= 3 samples)
    final minRtt = sorted.first.rtt;
    final rttThreshold = max(minRtt + 15, (minRtt * 1.5).round());
    final cleanSamples = sorted.length >= 3
        ? sorted.where((s) => s.rtt <= rttThreshold).toList()
        : sorted;

    final candidates = cleanSamples.isNotEmpty ? cleanSamples : sorted;

    // When 8 consecutive ping packets are sent, average lowest 4 RTT samples.
    // Otherwise keep lowest 50%.
    final countToKeep = candidates.length >= 8 ? 4 : max(1, (candidates.length * 0.5).ceil());
    final bestSamples = candidates.take(countToKeep).toList();

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

/// Drift reconciler to preserve audio lockstep without audible clicks/pops or pitch warble.
class DriftReconciler {
  /// Reconciles local playback position against expected host position.
  ///
  /// - Deadband with hysteresis:
  ///   - Speaker Mode (LAN): deadband ~30ms (hysteresis margin +10ms).
  ///   - Listen Together Mode (Cloud): deadband ~40-50ms.
  /// - Gentle rate changes:
  ///   - Small drift (deadband to 80ms): gentle ±0.5% (0.995x / 1.005x), inaudible to human ear.
  ///   - Moderate drift (80ms to microAdjustMaxMs): ±1.5% (0.985x / 1.015x).
  ///   - Macro drift (>= microAdjustMaxMs, default 150-200ms): quick muted hard seek.
  static DriftAction reconcileDrift({
    required int currentPositionMs,
    required int expectedPositionMs,
    int deadbandMs = 30,
    int microAdjustMaxMs = 150,
    int seekLatencyMs = 0,
    bool wasInSync = false,
  }) {
    final drift = currentPositionMs - expectedPositionMs;
    final absDrift = drift.abs();

    // Hysteresis deadband: if previously in sync, allow slightly larger margin (deadband + 10ms)
    // before kicking out of inSync, preventing hunting/oscillation on boundary.
    final effectiveDeadband = wasInSync ? (deadbandMs + 10) : deadbandMs;

    if (absDrift < effectiveDeadband) {
      return DriftAction(
        type: DriftActionType.inSync,
        playbackSpeed: 1.0,
        driftMs: drift,
      );
    }

    if (absDrift < microAdjustMaxMs) {
      // Tier 1: Small drift (under 80ms) -> Gentle ±0.5% speed adjustment (inaudible pitch change)
      if (absDrift < 80) {
        return DriftAction(
          type: drift > 0 ? DriftActionType.slowDown : DriftActionType.speedUp,
          playbackSpeed: drift > 0 ? 0.995 : 1.005,
          driftMs: drift,
        );
      }

      // Tier 2: Moderate drift (80ms to microAdjustMaxMs) -> ±1.5% speed adjustment
      return DriftAction(
        type: drift > 0 ? DriftActionType.slowDown : DriftActionType.speedUp,
        playbackSpeed: drift > 0 ? 0.985 : 1.015,
        driftMs: drift,
      );
    }

    // Macro-drift (>= microAdjustMaxMs): hard seek directly to anticipated future position
    final target = expectedPositionMs + seekLatencyMs;
    return DriftAction(
      type: DriftActionType.hardSeek,
      playbackSpeed: 1.0,
      driftMs: drift,
      seekTargetMs: max(0, target),
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
  /// factoring in elapsed time, host clock offset, manual Bluetooth audio delay,
  /// and device-specific hardware audio driver latency.
  ///
  /// [bluetoothDelayMs]: Manual user adjustment (-500ms to +500ms) to compensate
  /// for Bluetooth headphone/speaker hardware DAC buffer latency (A2DP typical 100-250ms).
  /// [hardwareLatencyMs]: Manual calibration adjustment (-150ms to +150ms) to compensate
  /// for Android chipset OpenSL ES / AAudio buffer differences.
  static int calculateExpectedPositionMs({
    required int referenceHostEpochMs,
    required int referenceTrackPositionMs,
    required int currentLocalEpochMs,
    int clockOffsetMs = 0,
    int bluetoothDelayMs = 0,
    int hardwareLatencyMs = 0,
    double speed = 1.0,
    bool isPlaying = true,
  }) {
    if (!isPlaying) {
      return max(0, referenceTrackPositionMs + bluetoothDelayMs + hardwareLatencyMs);
    }

    final currentEstimatedHostTime = currentLocalEpochMs + clockOffsetMs;
    final elapsedMs = ((currentEstimatedHostTime - referenceHostEpochMs) * speed).round();
    final rawExpected = referenceTrackPositionMs + elapsedMs;

    return max(0, rawExpected + bluetoothDelayMs + hardwareLatencyMs);
  }

  /// Calculates the exact playback position when the scheduled start epoch has already passed
  /// (e.g. when CDN stream URL resolution or buffering on joiner took longer than lead time).
  static int calculateElapsedPositionMs({
    required int startAtEpochMs,
    required int positionMs,
    required int currentLocalEpochMs,
    int clockOffsetMs = 0,
    int bluetoothDelayMs = 0,
    int hardwareLatencyMs = 0,
  }) {
    final estimatedHostTimeMs = currentLocalEpochMs + clockOffsetMs;
    if (estimatedHostTimeMs <= startAtEpochMs) {
      return positionMs;
    }
    final elapsedMs = estimatedHostTimeMs - startAtEpochMs;
    return max(0, positionMs + elapsedMs + bluetoothDelayMs + hardwareLatencyMs);
  }
}
