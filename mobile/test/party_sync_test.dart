import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/party_sync_engine.dart';
import 'package:paatu_padava_mobile/services/party_sync_coordinator.dart';

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

    test('8 consecutive ping packets calculate offset by averaging lowest 4 RTT samples', () {
      final samples = [
        const NtpSample(t0: 1000, t1: 1040, t2: 1041, t3: 1011), // RTT: 10ms, offset: 35ms (Best 1)
        const NtpSample(t0: 2000, t1: 2042, t2: 2043, t3: 2013), // RTT: 12ms, offset: 36ms (Best 2)
        const NtpSample(t0: 3000, t1: 3043, t2: 3044, t3: 3014), // RTT: 13ms, offset: 36ms (Best 3)
        const NtpSample(t0: 4000, t1: 4044, t2: 4045, t3: 4016), // RTT: 15ms, offset: 36ms (Best 4)
        const NtpSample(t0: 5000, t1: 5060, t2: 5061, t3: 5035), // RTT: 34ms, skewed
        const NtpSample(t0: 6000, t1: 6090, t2: 6091, t3: 6070), // RTT: 69ms, skewed
        const NtpSample(t0: 7000, t1: 7120, t2: 7121, t3: 7105), // RTT: 104ms, skewed
        const NtpSample(t0: 8000, t1: 8200, t2: 8201, t3: 8180), // RTT: 179ms, skewed
      ];

      // Averages lowest 4 RTT samples (offsets: 35, 36, 36, 36 -> average = 36ms)
      final offset = NtpCalculator.calculateOffset(samples);
      expect(offset, inInclusiveRange(35, 36));
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
    test('Drift within deadband (< 10ms) maintains normal speed 1.0x', () {
      final actionAhead = DriftReconciler.reconcileDrift(
        currentPositionMs: 15006,
        expectedPositionMs: 15000, // drift = +6ms
      );
      expect(actionAhead.type, equals(DriftActionType.inSync));
      expect(actionAhead.playbackSpeed, equals(1.0));
      expect(actionAhead.isInSync, isTrue);

      final actionBehind = DriftReconciler.reconcileDrift(
        currentPositionMs: 14992,
        expectedPositionMs: 15000, // drift = -8ms
      );
      expect(actionBehind.type, equals(DriftActionType.inSync));
      expect(actionBehind.playbackSpeed, equals(1.0));
      expect(actionBehind.isInSync, isTrue);
    });

    test('Micro-drift between 10ms and 250ms ahead applies imperceptible slow-down (0.98x)', () {
      final action = DriftReconciler.reconcileDrift(
        currentPositionMs: 15120,
        expectedPositionMs: 15000, // drift = +120ms
      );
      expect(action.type, equals(DriftActionType.slowDown));
      expect(action.playbackSpeed, equals(0.98));
      expect(action.isMicroAdjusting, isTrue);
      expect(action.seekTargetMs, isNull);
    });

    test('Micro-drift between 10ms and 250ms behind applies imperceptible speed-up (1.02x)', () {
      final action = DriftReconciler.reconcileDrift(
        currentPositionMs: 14880,
        expectedPositionMs: 15000, // drift = -120ms
      );
      expect(action.type, equals(DriftActionType.speedUp));
      expect(action.playbackSpeed, equals(1.02));
      expect(action.isMicroAdjusting, isTrue);
      expect(action.seekTargetMs, isNull);
    });

    test('Macro-drift (>= 250ms) triggers seamless hard seek', () {
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

  group('Scheduled Epoch Starts & Latency Compensation', () {
    test('Calculates delay until scheduled epoch start factoring in clock offset', () {
      const nowLocal = 1000000;
      const clockOffset = 50; // host is 50ms ahead (host time = 1000050)
      const scheduledStart = 1002000; // start 2000ms in host future

      final delay = ScheduledPlaybackCalculator.calculateScheduledDelayMs(
        startAtEpochMs: scheduledStart,
        currentLocalEpochMs: nowLocal,
        clockOffsetMs: clockOffset,
      );

      // Remaining delay = 1002000 - (1000000 + 50) = 1950ms
      expect(delay, equals(1950));
    });

    test('Past scheduled epoch start returns 0ms delay without underflowing', () {
      final delay = ScheduledPlaybackCalculator.calculateScheduledDelayMs(
        startAtEpochMs: 900000,
        currentLocalEpochMs: 1000000,
      );
      expect(delay, equals(0));
    });

    test('Bluetooth audio delay and hardware audio latency compensate expected position', () {
      const refHostEpoch = 1000000;
      const refTrackPos = 5000;
      const currentLocalEpoch = 1002000; // 2000ms elapsed
      const clockOffset = 0;

      // Without delays (uncalibrated speaker)
      final posSpeaker = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
        referenceHostEpochMs: refHostEpoch,
        referenceTrackPositionMs: refTrackPos,
        currentLocalEpochMs: currentLocalEpoch,
        clockOffsetMs: clockOffset,
        bluetoothDelayMs: 0,
        hardwareLatencyMs: 0,
      );
      expect(posSpeaker, equals(7000));

      // With Bluetooth latency (+150ms DAC buffer) and hardware latency (-30ms AAudio buffer)
      final posCalibrated = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
        referenceHostEpochMs: refHostEpoch,
        referenceTrackPositionMs: refTrackPos,
        currentLocalEpochMs: currentLocalEpoch,
        clockOffsetMs: clockOffset,
        bluetoothDelayMs: 150,
        hardwareLatencyMs: -30,
      );
      expect(posCalibrated, equals(7120));
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

    test('calculateElapsedPositionMs computes accurate catch-up position when joiner resolution exceeds lead time', () {
      const scheduledStart = 1001200; // scheduled start at now + 1200ms
      const nowLocal = 1002000; // joiner took 2000ms to resolve stream (800ms past barrier)
      const clockOffset = 50; // host is 50ms ahead (host time = 1002050)
      const positionMs = 0; // started from beginning

      final catchUpPos = ScheduledPlaybackCalculator.calculateElapsedPositionMs(
        startAtEpochMs: scheduledStart,
        positionMs: positionMs,
        currentLocalEpochMs: nowLocal,
        clockOffsetMs: clockOffset,
        bluetoothDelayMs: 100,
      );

      // elapsedMs = (1002000 + 50) - 1001200 = 850ms
      // total = 0 + 850 + 100 = 950ms
      expect(catchUpPos, equals(950));
    });

    test('calculateElapsedPositionMs returns original position when startAtEpochMs is in the future', () {
      final futurePos = ScheduledPlaybackCalculator.calculateElapsedPositionMs(
        startAtEpochMs: 2000000,
        positionMs: 3500,
        currentLocalEpochMs: 1000000,
      );
      expect(futurePos, equals(3500));
    });
  });

  group('PeerDeviceInfo & Peer Presence Tracking', () {
    test('Serializes and deserializes PeerDeviceInfo with RTT and role', () {
      final peer = PeerDeviceInfo(
        id: 'peer-1234',
        deviceName: 'OnePlus 11 (Speaker)',
        role: 'Speaker',
        rttMs: 42,
        lastSeen: DateTime.now(),
        isSelf: false,
      );

      final map = peer.toMap();
      expect(map['id'], equals('peer-1234'));
      expect(map['deviceName'], equals('OnePlus 11 (Speaker)'));
      expect(map['role'], equals('Speaker'));
      expect(map['rttMs'], equals(42));

      final restored = PeerDeviceInfo.fromMap(map, isSelf: true);
      expect(restored.id, equals('peer-1234'));
      expect(restored.deviceName, equals('OnePlus 11 (Speaker)'));
      expect(restored.role, equals('Speaker'));
      expect(restored.rttMs, equals(42));
      expect(restored.isSelf, isTrue);
    });

    test('PeerDeviceInfo copyWith updates ping and device properties correctly', () {
      final peer = PeerDeviceInfo(
        id: 'host-001',
        deviceName: 'Pixel 8 (Host)',
        role: 'Host',
        rttMs: 0,
        lastSeen: DateTime.now(),
        isSelf: true,
      );

      final updated = peer.copyWith(rttMs: 18, deviceName: 'Pixel 8 Pro (Host)');
      expect(updated.id, equals('host-001'));
      expect(updated.deviceName, equals('Pixel 8 Pro (Host)'));
      expect(updated.rttMs, equals(18));
      expect(updated.isSelf, isTrue);
    });
  });
}

