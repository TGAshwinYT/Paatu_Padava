import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/party_sync_engine.dart';

void main() {
  group('PartySync Adaptive Deadband & Micro-Adjust Calculations', () {
    test('calculateAdaptiveDeadband scales dynamically with RTT on LAN and WAN', () {
      // 1. LAN mode tests (25ms window for crisp acoustic alignment)
      final lanFast = DriftReconciler.calculateAdaptiveDeadband(rttMs: 4, isLan: true);
      expect(lanFast, equals(25));

      final lanHighRtt = DriftReconciler.calculateAdaptiveDeadband(rttMs: 120, isLan: true);
      expect(lanHighRtt, equals(25));

      // 2. WAN / Cellular mode tests (35ms floor up to 110ms ceiling based on 40% of RTT)
      final wanFast = DriftReconciler.calculateAdaptiveDeadband(rttMs: 40, isLan: false);
      expect(wanFast, equals(35)); // 40 * 0.4 = 16 -> floored to 35ms

      final wanMedium = DriftReconciler.calculateAdaptiveDeadband(rttMs: 150, isLan: false);
      expect(wanMedium, equals(60)); // 150 * 0.4 = 60ms

      final wanSatellite = DriftReconciler.calculateAdaptiveDeadband(rttMs: 600, isLan: false);
      expect(wanSatellite, equals(110)); // clamped to 110ms ceiling
    });

    test('calculateAdaptiveMicroAdjustMax scales dynamically without causing jarring seeks', () {
      // LAN bounds: 1000ms
      final lanMicro = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 10, isLan: true);
      expect(lanMicro, equals(1000));

      final lanHighMicro = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 150, isLan: true);
      expect(lanHighMicro, equals(1000));

      // WAN bounds: 1200ms - 1800ms
      final wanLow = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 50, isLan: false);
      expect(wanLow, equals(1200)); // 50 * 2.0 = 100 -> floored to 1200ms

      final wanMedium = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 700, isLan: false);
      expect(wanMedium, equals(1400)); // 700 * 2.0 = 1400ms

      final wanExtreme = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 1200, isLan: false);
      expect(wanExtreme, equals(1800)); // clamped to 1800ms ceiling
    });

    test('Tiered drift reconciliation applies smooth speed adjustments before hard seek', () {
      // Tier 1 (< 120ms): ±0.8%
      final tier1 = DriftReconciler.reconcileDrift(
        currentPositionMs: 5080,
        expectedPositionMs: 5000,
        deadbandMs: 30,
        microAdjustMaxMs: 1500,
      );
      expect(tier1.playbackSpeed, equals(0.992));

      // Tier 2 (120ms - 450ms): ±2.0%
      final tier2 = DriftReconciler.reconcileDrift(
        currentPositionMs: 4700,
        expectedPositionMs: 5000,
        deadbandMs: 30,
        microAdjustMaxMs: 1500,
      );
      expect(tier2.playbackSpeed, equals(1.020));

      // Tier 3 (450ms - 1500ms): ±4.0%
      final tier3 = DriftReconciler.reconcileDrift(
        currentPositionMs: 6000,
        expectedPositionMs: 5000,
        deadbandMs: 30,
        microAdjustMaxMs: 1500,
      );
      expect(tier3.playbackSpeed, equals(0.960));

      // Macro drift (>= 1500ms): Hard seek
      final macro = DriftReconciler.reconcileDrift(
        currentPositionMs: 8000,
        expectedPositionMs: 5000,
        deadbandMs: 30,
        microAdjustMaxMs: 1500,
      );
      expect(macro.isHardSeek, isTrue);
      expect(macro.seekTargetMs, equals(5000));
    });

    test('Adaptive Deadband absorbs network jitter and prevents playback stutter', () {
      // With adaptive deadband, a 55ms drift on cellular (RTT 150ms -> deadband 60ms) stays In Sync
      final deadband = DriftReconciler.calculateAdaptiveDeadband(rttMs: 150, isLan: false);
      final microMax = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 150, isLan: false);

      final action = DriftReconciler.reconcileDrift(
        currentPositionMs: 5055,
        expectedPositionMs: 5000, // +55ms jitter drift
        deadbandMs: deadband,
        microAdjustMaxMs: microMax,
        wasInSync: true,
      );

      // Must NOT alter speed or seek because jitter is within adaptive deadband
      expect(action.type, equals(DriftActionType.inSync));
      expect(action.isInSync, isTrue);
      expect(action.playbackSpeed, equals(1.0));
      expect(action.isHardSeek, isFalse);
    });
  });

  group('NTP Calculator EMA Smoothing & Outlier Rejection', () {
    test('Calculates raw offset cleanly when no prior offset exists', () {
      final samples = [
        const NtpSample(t0: 1000, t1: 1040, t2: 1041, t3: 1011), // RTT: 10ms, offset: 35ms
        const NtpSample(t0: 2000, t1: 2042, t2: 2043, t3: 2013), // RTT: 12ms, offset: 36ms
        const NtpSample(t0: 3000, t1: 3043, t2: 3044, t3: 3014), // RTT: 13ms, offset: 36ms
        const NtpSample(t0: 4000, t1: 4044, t2: 4045, t3: 4016), // RTT: 15ms, offset: 36ms
        const NtpSample(t0: 5000, t1: 5200, t2: 5201, t3: 5120), // RTT: 119ms, skewed outlier
      ];

      final offset = NtpCalculator.calculateOffset(samples);
      expect(offset, inInclusiveRange(35, 36));
    });

    test('Applies Exponential Moving Average (EMA) smoothing to prevent clock jumps', () {
      // WAN samples (alpha = 0.20): 0.80 * 35 + 0.20 * 55 = 39ms
      final wanSamples = [
        const NtpSample(t0: 1000, t1: 1060, t2: 1061, t3: 1011), // offset: 55ms
        const NtpSample(t0: 2000, t1: 2060, t2: 2061, t3: 2012), // offset: 55ms
      ];
      final wanSmoothed = NtpCalculator.calculateOffset(wanSamples, previousOffset: 35);
      expect(wanSmoothed, equals(39));

      // LAN samples (alpha = 0.35): 0.65 * 35 + 0.35 * 55 = 42ms
      final lanSamples = [
        const NtpSample(t0: 1000, t1: 1060, t2: 1061, t3: 1011, isLan: true), // offset: 55ms
        const NtpSample(t0: 2000, t1: 2060, t2: 2061, t3: 2012, isLan: true), // offset: 55ms
      ];
      final lanSmoothed = NtpCalculator.calculateOffset(lanSamples, previousOffset: 35);
      expect(lanSmoothed, equals(42));
    });
  });

  group('Adaptive Lead Time & Playback Barrier Calculations', () {
    test('Calculates adaptive lead time on LAN for low latency starts', () {
      // Empty peers on LAN -> 1200ms baseline
      final lanEmpty = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [],
        isLan: true,
      );
      expect(lanEmpty, equals(1200));

      // Peers with low RTTs on LAN (< 20ms) -> 1200ms
      final lanPeers = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [5, 12, 15],
        isLan: true,
      );
      expect(lanPeers, equals(1200));
    });

    test('Calculates adaptive lead time on WAN scaling with slowest peer', () {
      // Empty peers on WAN -> 1500ms baseline
      final wanEmpty = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [],
        isLan: false,
      );
      expect(wanEmpty, equals(1500));

      // Slow peer with 1000ms RTT on WAN -> 1000 + 750 = 1750ms lead time
      final wanSlowPeer = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [60, 110, 1000],
        isLan: false,
      );
      expect(wanSlowPeer, equals(1750));

      // Extreme RTT peer (2500ms) -> Clamped to 2800ms
      final wanExtremePeer = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [2500],
        isLan: false,
      );
      expect(wanExtremePeer, equals(2800));
    });
  });
}
