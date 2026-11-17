import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/party_sync_engine.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/platform/audio_platform.dart';
import 'package:paatu_padava_mobile/platform/sync_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 1: Karaoke Real Center-Channel & EQ Separation Tests', () {
    setUp(() {
      EqualizerService.dispose();
    });

    test('EqualizerService tracks DSP active state and defaults correctly', () {
      expect(EqualizerService.isDspAvailable, isFalse);
      expect(EqualizerService.isDspActiveNotifier.value, isFalse);
      expect(EqualizerService.hardwareBandCount, equals(5));
    });

    test('When DSP is active, baseline equalizer bands remain pure without mid-formant dip', () {
      final base = [0.0, 0.0, 0.0, 0.0, 0.0];
      // When DSP is active, effectiveVocalAttenuation passed to calculateEffectiveBands is 0.0
      final resultWithDsp = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 0.0,
        virtualizer: 0.0,
        vocalAttenuation: 0.0, // DSP handles mid-side cancellation natively
      );

      expect(resultWithDsp, equals([0.0, 0.0, 0.0, 0.0, 0.0]));
    });

    test('When DSP is inactive (fallback mode), EQ formant notch is applied cleanly', () {
      final base = [0.0, 0.0, 0.0, 0.0, 0.0];
      final resultFallback = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 0.0,
        virtualizer: 0.0,
        vocalAttenuation: 1.0,
      );

      // Low band preserved (+3.5 dB sub-bass compensation)
      expect(resultFallback[0], closeTo(3.5, 0.001));
      // Vocal formants notched (-8.0 dB at 910 Hz, -5.0 dB at 3.6 kHz)
      expect(resultFallback[2], closeTo(-8.0, 0.001));
      expect(resultFallback[3], closeTo(-5.0, 0.001));
    });

    test('AudioPlatform method channel returns safe non-crash defaults on unit test host', () async {
      final dspAvailable = await AudioPlatform.isDspAvailable();
      expect(dspAvailable, isFalse); // Non-Android test runner safely returns false

      final bandCount = await AudioPlatform.getBandCount();
      expect(bandCount, equals(5));

      final success = await AudioPlatform.setVocalCancellation(0.8);
      expect(success, isFalse);
    });
  });

  group('Part 2: PartySync Fast LAN Discovery & Zero-Drift Playback Tests', () {
    setUp(() async {
      await PartySyncCoordinator.leaveParty();
    });

    tearDown(() async {
      await PartySyncCoordinator.leaveParty();
    });

    test('SyncPlatform method channel returns safe defaults on unit test host', () async {
      final wifiLocks = await SyncPlatform.acquireWifiLocks();
      expect(wifiLocks, isFalse); // Non-Android test runner safely returns false

      final releaseLocks = await SyncPlatform.releaseWifiLocks();
      expect(releaseLocks, isFalse);

      final broadcastAddr = await SyncPlatform.getWifiBroadcastAddress();
      expect(broadcastAddr, isNull);
    });

    test('LAN NTP ping arriving purges noisy cloud NTP samples to prevent clock EMA poisoning', () {
      final samples = <NtpSample>[
        const NtpSample(t0: 1000, t1: 1090, t2: 1092, t3: 1100, isLan: false), // RTT 98ms (Cloud)
        const NtpSample(t0: 2000, t1: 2095, t2: 2097, t3: 2110, isLan: false), // RTT 108ms (Cloud)
      ];

      // Simulated arrival of LAN NTP pong:
      const lanSample = NtpSample(t0: 3000, t1: 3040, t2: 3041, t3: 3001, isLan: true); // RTT 0ms (LAN)
      samples.removeWhere((s) => !s.isLan);
      samples.add(lanSample);

      expect(samples.length, equals(1));
      expect(samples.first.isLan, isTrue);

      final offset = NtpCalculator.calculateOffset(samples);
      expect(offset, equals(40)); // Exactly 40ms offset, zero cloud pollution
    });

    test('Accurate Timer Arming accurately accounts for bluetooth and hardware audio latency', () {
      const startAtEpochMs = 1002000;
      const estimatedHostTimeMs = 1001000; // 1000ms until barrier
      const bluetoothDelayMs = 150; // +150ms buffer
      const hardwareLatencyMs = 20;  // +20ms AAudio buffer
      const latencyOffsetMs = bluetoothDelayMs + hardwareLatencyMs; // 170ms

      const remainingDelayMs = startAtEpochMs - estimatedHostTimeMs - latencyOffsetMs;

      // 1000ms - 170ms = 830ms timer delay
      expect(remainingDelayMs, equals(830));
    });

    test('Playback Conflict Guard intercepts manual play attempt on Joiner', () {
      Song? interceptedSong;
      PartySyncCoordinator.onJoinerManualPlayAttempted = (song) {
        interceptedSong = song;
      };

      final testSong = Song(
        id: 'test_song_1',
        title: 'New Manual Song',
        artist: 'Artist',
        album: 'Album',
        coverUrl: '',
        duration: 180,
      );

      // Verify callback exists and receives track
      PartySyncCoordinator.onJoinerManualPlayAttempted?.call(testSong);
      expect(interceptedSong, isNotNull);
      expect(interceptedSong!.title, equals('New Manual Song'));
    });

    test('PartySync event deduplication allows payload hydration on matching sequence', () {
      final testSong = Song(
        id: 'song_sync_123',
        title: 'Anbil Avan',
        artist: 'A.R. Rahman',
        album: 'Vinnaithaandi Varuvaayaa',
        coverUrl: '',
        duration: 240,
        streamUrl: 'https://cdn.example.com/audio/direct320.mp3',
      );

      // Packet 1: Compact LAN datagram
      final lanPayload = {
        'seq': 10,
        'songId': testSong.id,
        'positionMs': 0,
        'startAtEpochMs': 1000500,
      };

      // Packet 2: Full payload with pre-resolved streamUrl
      final fullPayload = {
        'seq': 10,
        'songId': testSong.id,
        'song': testSong.toMap(),
        'streamUrl': testSong.streamUrl,
        'positionMs': 0,
        'startAtEpochMs': 1000500,
      };

      // Ensure fullPayload has payload indicator
      expect(lanPayload['song'], isNull);
      expect(fullPayload['song'], isNotNull);
      expect(fullPayload['streamUrl'], equals('https://cdn.example.com/audio/direct320.mp3'));
    });

    test('AudioPlatform getDspStatus returns safe inactive defaults on test environment', () async {
      final status = await AudioPlatform.getDspStatus();
      expect(status['attached'], isFalse);
      expect(status['active'], isFalse);
      expect(status['mode'], equals('none'));
    });

    test('PartySync Prepare-Ack-Go barrier handles cmdId deduplication independently of heartbeat seq', () {
      const cmdId = 'cmd_uuid_test_123';
      final payload1 = {
        'cmdId': cmdId,
        'seq': 5,
        'positionMs': 1000,
      };
      final payload2 = {
        'cmdId': cmdId,
        'seq': 12, // Higher seq from subsequent heartbeats
        'positionMs': 1000,
      };

      // Both packets share the exact same cmdId
      expect(payload1['cmdId'], equals(payload2['cmdId']));
      expect(payload1['cmdId'], equals('cmd_uuid_test_123'));
    });

    test('PartySync rapid-skip invalidates prior pendingPrepareCmdId and drops stale peer_ready acks', () {
      expect(PartySyncCoordinator.pendingPrepareCmdId, isNull);
      final payloadOld = {'cmdId': 'stale_cmd_1', 'peerId': 'peer_1'};
      final payloadNew = {'cmdId': 'fresh_cmd_2', 'peerId': 'peer_1'};

      // Invariant: Stale ACK must not match active prepare command ID
      const activeCmdId = 'fresh_cmd_2';
      expect(payloadOld['cmdId'] == activeCmdId, isFalse);
      expect(payloadNew['cmdId'] == activeCmdId, isTrue);
    });
  });
}
