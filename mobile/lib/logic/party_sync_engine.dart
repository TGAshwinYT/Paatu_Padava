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
  /// 1. Prioritizes clean LAN samples when available.
  /// 2. Applies Cristian's algorithm: filters samples whose RTT exceeds 1.4x of minimum RTT.
  /// 3. If [previousOffset] is provided, applies Exponential Moving Average (EMA) to prevent clock jumps.
  static int calculateOffset(List<NtpSample> samples, {int? previousOffset}) {
    if (samples.isEmpty) return previousOffset ?? 0;
    if (samples.length == 1) {
      if (previousOffset != null && previousOffset != 0) {
        final alpha = samples.first.isLan ? 0.50 : 0.25;
        return ((1.0 - alpha) * previousOffset + alpha * samples.first.offset).round();
      }
      return samples.first.offset;
    }

    // Prefer clean LAN samples when available (LAN RTT is typically 1-5ms vs Cloud 40-150ms)
    final lanSamples = samples.where((s) => s.isLan).toList();
    final activeSamples = lanSamples.isNotEmpty ? lanSamples : samples;

    // Sort by RTT ascending (cleanest network paths first)
    final sorted = List<NtpSample>.from(activeSamples)..sort((a, b) => a.rtt.compareTo(b.rtt));

    // Reject samples whose RTT exceeds 1.4x of minimum RTT (when >= 3 samples)
    final minRtt = sorted.first.rtt;
    final rttThreshold = max(minRtt + 12, (minRtt * 1.4).round());
    final cleanSamples = sorted.length >= 3
        ? sorted.where((s) => s.rtt <= rttThreshold).toList()
        : sorted;

    final candidates = cleanSamples.isNotEmpty ? cleanSamples : sorted;

    // Keep lowest 4 RTT samples or 50%
    final countToKeep = candidates.length >= 8 ? 4 : max(1, (candidates.length * 0.5).ceil());
    final bestSamples = candidates.take(countToKeep).toList();

    final sumOffset = bestSamples.fold<int>(0, (sum, s) => sum + s.offset);
    final rawCalculated = (sumOffset / bestSamples.length).round();

    // If previous offset exists, apply Exponential Moving Average (EMA) to prevent timeline jumps
    if (previousOffset != null && previousOffset != 0) {
      final isLan = activeSamples.any((s) => s.isLan);
      final alpha = isLan ? 0.35 : 0.20;
      return ((1.0 - alpha) * previousOffset + alpha * rawCalculated).round();
    }

    return rawCalculated;
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
  /// Computes a jitter-aware deadband threshold.
  /// On local Wi-Fi (LAN), keeps a crisp 25ms window for multi-speaker acoustic alignment.
  /// On cloud/cellular, scales with RTT to absorb network jitter and prevent speed hunting/pitch warble.
  static int calculateAdaptiveDeadband({required int rttMs, bool isLan = false}) {
    if (isLan) return 25;
    // Cloud / Internet: 35ms floor up to 110ms ceiling based on 40% of RTT
    return max(35, min(110, (rttMs * 0.4).round()));
  }

  /// Computes the micro-adjustment ceiling threshold before falling back to hard seek.
  /// Expanded to 1500ms so minor network jitter and buffer variance are smoothed by
  /// pitch-preserved time-stretching instead of destructive ExoPlayer buffer-flush seeks.
  static int calculateAdaptiveMicroAdjustMax({required int rttMs, bool isLan = false}) {
    if (isLan) return 1000;
    return max(1200, min(1800, (rttMs * 2.0).round()));
  }

  /// Reconciles local playback position against expected host position.
  ///
  /// - Deadband with hysteresis:
  ///   - Speaker Mode (LAN): deadband ~25-30ms.
  ///   - Listen Together Mode (Cloud): deadband ~35-45ms.
  /// - Gentle rate changes:
  ///   - Small drift (deadband to 120ms): gentle ±0.8% (0.992x / 1.008x), inaudible to human ear.
  ///   - Moderate drift (120ms to 450ms): ±2.0% (0.98x / 1.02x).
  ///   - High drift (450ms to microAdjustMaxMs, up to 1500ms): ±4.0% (0.96x / 1.04x) for rapid catch-up.
  ///   - Macro drift (>= microAdjustMaxMs, default 1500ms): quick muted hard seek.
  static DriftAction reconcileDrift({
    required int currentPositionMs,
    required int expectedPositionMs,
    int deadbandMs = 30,
    int microAdjustMaxMs = 1500,
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
      // Tier 1: Small drift (under 120ms) -> Gentle ±0.8% speed adjustment
      if (absDrift < 120) {
        return DriftAction(
          type: drift > 0 ? DriftActionType.slowDown : DriftActionType.speedUp,
          playbackSpeed: drift > 0 ? 0.992 : 1.008,
          driftMs: drift,
        );
      }

      // Tier 2: Moderate drift (120ms to 450ms) -> ±2.0% speed adjustment
      if (absDrift < 450) {
        return DriftAction(
          type: drift > 0 ? DriftActionType.slowDown : DriftActionType.speedUp,
          playbackSpeed: drift > 0 ? 0.980 : 1.020,
          driftMs: drift,
        );
      }

      // Tier 3: High drift (450ms to 1500ms) -> ±4.0% speed adjustment for rapid smooth alignment
      return DriftAction(
        type: drift > 0 ? DriftActionType.slowDown : DriftActionType.speedUp,
        playbackSpeed: drift > 0 ? 0.960 : 1.040,
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
  /// Computes the presentation lead time for scheduled play / track transition barriers.
  /// Adapts dynamically based on the highest peer RTT in the session.
  /// Local LAN only: ~1200ms.
  /// Cloud / High latency / Long distance: scales up to 1500-2800ms to guarantee all phones buffer in time.
  static int calculateAdaptiveLeadTimeMs({
    required List<int> peerRtts,
    bool isLan = false,
  }) {
    if (isLan && (peerRtts.isEmpty || peerRtts.every((rtt) => rtt < 20))) {
      return 1200;
    }
    final maxRtt = peerRtts.isNotEmpty ? peerRtts.reduce(max) : 100;
    // Base 1500ms + max RTT + 750ms headroom for ExoPlayer buffer fill
    return max(1500, min(2800, maxRtt + 750));
  }

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
