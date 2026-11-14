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
      // LAN bounds: 140ms
      final lanMicro = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 10, isLan: true);
      expect(lanMicro, equals(140));

      final lanHighMicro = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 150, isLan: true);
      expect(lanHighMicro, equals(140));

      // WAN bounds: 160ms - 300ms (90% of RTT)
      final wanLow = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 50, isLan: false);
      expect(wanLow, equals(160)); // 50 * 0.9 = 45 -> floored to 160ms

      final wanMedium = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 250, isLan: false);
      expect(wanMedium, equals(225)); // 250 * 0.9 = 225ms

      final wanExtreme = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: 500, isLan: false);
      expect(wanExtreme, equals(300)); // clamped to 300ms ceiling
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
      // Empty peers on LAN -> 1000ms baseline
      final lanEmpty = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [],
        isLan: true,
      );
      expect(lanEmpty, equals(1000));

      // Peers with low RTTs on LAN (< 20ms) -> 1000ms
      final lanPeers = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [5, 12, 15],
        isLan: true,
      );
      expect(lanPeers, equals(1000));
    });

    test('Calculates adaptive lead time on WAN scaling with slowest peer', () {
      // Empty peers on WAN -> 1100ms baseline
      final wanEmpty = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [],
        isLan: false,
      );
      expect(wanEmpty, equals(1100));

      // Slow peer with 1000ms RTT on WAN -> 1000 + 500 = 1500ms lead time
      final wanSlowPeer = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [60, 110, 1000],
        isLan: false,
      );
      expect(wanSlowPeer, equals(1500));

      // Extreme RTT peer (2500ms) -> Clamped to 2400ms
      final wanExtremePeer = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [2500],
        isLan: false,
      );
      expect(wanExtremePeer, equals(2400));
    });
  });
}
