import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/party_sync_engine.dart';

void main() {
  group('NTP Clock Skew & Offset Calculations', () {
    test('Calculates RTT and clock offset accurately for symmetric delay', () {
      // Client sends at t0 = 1000
      // Host receives at t1 = 1050 (host clock +30ms ahead, transmission 20ms)
      // Host replies at t2 = 1052 (2ms host processing)
      // Client receives at t3 = 1072 (20ms transmission back)
      final sample = NtpSample(t0: 1000, t1: 1050, t2: 1052, t3: 1072);

      // Total RTT = (1072 - 1000) - (1052 - 1050) = 72 - 2 = 70ms
      expect(sample.rtt, equals(70));

      // Offset = ((1050 - 1000) + (1052 - 1072)) / 2 = (50 - 20) / 2 = +15ms
      expect(sample.offset, equals(15));
    });

    test('Rejects high-latency outlier samples and averages lowest RTT paths', () {
      final samples = [
        // Clean low-latency samples with consistent offset ~ +50ms
        const NtpSample(t0: 1000, t1: 1055, t2: 1056, t3: 1012), // RTT: 11ms, offset: 49ms
        const NtpSample(t0: 2000, t1: 2056, t2: 2057, t3: 2014), // RTT: 13ms, offset: 49ms
        const NtpSample(t0: 3000, t1: 3056, t2: 3057, t3: 3013), // RTT: 12ms, offset: 50ms
        // Jitter / delayed queue outliers
        const NtpSample(t0: 4000, t1: 4180, t2: 4181, t3: 4060), // RTT: 59ms, skewed offset: 150ms
        const NtpSample(t0: 5000, t1: 5300, t2: 5301, t3: 5120), // RTT: 119ms, skewed offset: 240ms
      ];

      // Outlier rejection filters out the 2 high-RTT spikes and averages the best 3 samples
      final filteredOffset = NtpCalculator.calculateOffset(samples);
      expect(filteredOffset, inInclusiveRange(49, 50));
    });

    test('Estimates host and local epoch timestamps accurately', () {
      const localTime = 1700000000000;
      const clockOffset = 85; // Host is 85ms ahead

      final hostTime = NtpCalculator.estimateHostTime(
        localTimeMs: localTime,
        clockOffsetMs: clockOffset,
      );
      expect(hostTime, equals(localTime + 85));

      final convertedBack = NtpCalculator.estimateLocalTime(
        hostTimeMs: hostTime,
        clockOffsetMs: clockOffset,
      );
      expect(convertedBack, equals(localTime));
    });
  });

  group('Playback Drift Reconciliation & Micro Speed Adjustments', () {
    test('Drift within deadband (< 50ms) maintains normal speed 1.0x', () {
      final actionAhead = DriftReconciler.reconcileDrift(
        currentPositionMs: 15030,
        expectedPositionMs: 15000, // drift = +30ms
      );
      expect(actionAhead.type, equals(DriftActionType.inSync));
      expect(actionAhead.playbackSpeed, equals(1.0));
      expect(actionAhead.isInSync, isTrue);

      final actionBehind = DriftReconciler.reconcileDrift(
        currentPositionMs: 14960,
        expectedPositionMs: 15000, // drift = -40ms
      );
      expect(actionBehind.type, equals(DriftActionType.inSync));
      expect(actionBehind.playbackSpeed, equals(1.0));
      expect(actionBehind.isInSync, isTrue);
    });

    test('Drift between 50ms and 200ms ahead applies imperceptible slow-down (0.98x)', () {
      final action = DriftReconciler.reconcileDrift(
        currentPositionMs: 15120,
        expectedPositionMs: 15000, // drift = +120ms
      );
      expect(action.type, equals(DriftActionType.slowDown));
      expect(action.playbackSpeed, equals(0.98));
      expect(action.isMicroAdjusting, isTrue);
      expect(action.seekTargetMs, isNull);
    });

    test('Drift between 50ms and 200ms behind applies imperceptible speed-up (1.02x)', () {
      final action = DriftReconciler.reconcileDrift(
        currentPositionMs: 14880,
        expectedPositionMs: 15000, // drift = -120ms
      );
      expect(action.type, equals(DriftActionType.speedUp));
      expect(action.playbackSpeed, equals(1.02));
      expect(action.isMicroAdjusting, isTrue);
      expect(action.seekTargetMs, isNull);
    });

    test('Large drift (> 200ms) triggers seamless hard seek', () {
      final action = DriftReconciler.reconcileDrift(
        currentPositionMs: 15450,
        expectedPositionMs: 15000, // drift = +450ms
      );
      expect(action.type, equals(DriftActionType.hardSeek));
      expect(action.isHardSeek, isTrue);
      expect(action.playbackSpeed, equals(1.0));
      expect(action.seekTargetMs, equals(15000));
    });
  });

  group('Scheduled Epoch Starts & Bluetooth Latency Compensation', () {
    test('Calculates delay until scheduled epoch start factoring in clock offset', () {
      const nowLocal = 1000000;
      const clockOffset = 50; // host is 50ms ahead (host time = 1000050)
      const scheduledStart = 1000500; // start 500ms in host future

      final delay = ScheduledPlaybackCalculator.calculateScheduledDelayMs(
        startAtEpochMs: scheduledStart,
        currentLocalEpochMs: nowLocal,
        clockOffsetMs: clockOffset,
      );

      // Remaining delay = 1000500 - (1000000 + 50) = 450ms
      expect(delay, equals(450));
    });

    test('Past scheduled epoch start returns 0ms delay without underflowing', () {
      final delay = ScheduledPlaybackCalculator.calculateScheduledDelayMs(
        startAtEpochMs: 900000,
        currentLocalEpochMs: 1000000,
      );
      expect(delay, equals(0));
    });

    test('Bluetooth audio delay offset shifts expected position correctly', () {
      const refHostEpoch = 1000000;
      const refTrackPos = 5000;
      const currentLocalEpoch = 1002000; // 2000ms elapsed
      const clockOffset = 0;

      // Without Bluetooth delay (phone speaker)
      final posSpeaker = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
        referenceHostEpochMs: refHostEpoch,
        referenceTrackPositionMs: refTrackPos,
        currentLocalEpochMs: currentLocalEpoch,
        clockOffsetMs: clockOffset,
        bluetoothDelayMs: 0,
      );
      expect(posSpeaker, equals(7000));

      // With Bluetooth latency (+150ms DAC buffer)
      final posBt = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
        referenceHostEpochMs: refHostEpoch,
        referenceTrackPositionMs: refTrackPos,
        currentLocalEpochMs: currentLocalEpoch,
        clockOffsetMs: clockOffset,
        bluetoothDelayMs: 150,
      );
      // Audio needs to be fed 150ms earlier into BT buffer
      expect(posBt, equals(7150));
    });

    test('Paused state preserves track position without accumulating elapsed time', () {
      final pos = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
        referenceHostEpochMs: 1000000,
        referenceTrackPositionMs: 45000,
        currentLocalEpochMs: 1020000, // 20 seconds later
        isPlaying: false,
      );
      expect(pos, equals(45000));
    });
  });
}
