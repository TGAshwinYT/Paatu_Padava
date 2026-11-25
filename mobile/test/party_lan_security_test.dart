import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/party_lan_accelerator.dart';
import 'package:paatu_padava_mobile/services/party_sync_coordinator.dart';
import 'package:paatu_padava_mobile/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel syncChannel = MethodChannel('com.paatupaadava/sync_platform');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(syncChannel, (MethodCall call) async => null);
    SecureStorageService.clearFallbackForTesting();
  });

  tearDown(() async {
    await PartySyncCoordinator.leaveParty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(syncChannel, null);
  });

  group('PartyLanAccelerator HMAC & Replay Protection', () {
    const partyCode = 'SYNC-9K2M4P';
    const roomToken = 'test-room-token-sha256-secret';

    test('accepts validly signed packet within replay window', () {
      const nowMs = 1700000000000;
      final payload = {'seq': 42, 'songId': 'abc123', 'isPlaying': true};
      final sig = PartyLanAccelerator.computePacketSignature(
        partyCode,
        'sync_play',
        nowMs,
        payload,
        roomToken,
      );

      final packet = {
        'partyCode': partyCode,
        'event': 'sync_play',
        'ts': nowMs,
        'sig': sig,
        'payload': payload,
      };

      expect(
        PartyLanAccelerator.verifyIncomingPacket(
          packet,
          expectedCode: partyCode,
          expectedRoomToken: roomToken,
          nowEpochMs: nowMs + 500,
        ),
        isTrue,
      );
    });

    test('canonicalizes nested map key order so signatures match regardless of insertion order', () {
      const nowMs = 1700000000000;
      final payloadA = {
        'b': 2,
        'a': {'y': 10, 'x': 20},
      };
      final payloadB = {
        'a': {'x': 20, 'y': 10},
        'b': 2,
      };

      final sigA = PartyLanAccelerator.computePacketSignature(partyCode, 'sync_play', nowMs, payloadA, roomToken);
      final sigB = PartyLanAccelerator.computePacketSignature(partyCode, 'sync_play', nowMs, payloadB, roomToken);
      expect(sigA, equals(sigB));
    });

    test('rejects forged roomToken, missing sig, tampered payload, wrong partyCode, non-map payload, and stale timestamps', () {
      const nowMs = 1700000000000;
      final payload = {'seq': 1, 'positionMs': 1200};
      final validSig = PartyLanAccelerator.computePacketSignature(
        partyCode,
        'sync_seek',
        nowMs,
        payload,
        roomToken,
      );

      // 1. Wrong roomToken (attacker on same Wi-Fi without PIN)
      expect(
        PartyLanAccelerator.verifyIncomingPacket(
          {'partyCode': partyCode, 'event': 'sync_seek', 'ts': nowMs, 'sig': validSig, 'payload': payload},
          expectedCode: partyCode,
          expectedRoomToken: 'wrong-room-token',
          nowEpochMs: nowMs,
        ),
        isFalse,
      );

      // 2. Missing sig
      expect(
        PartyLanAccelerator.verifyIncomingPacket(
          {'partyCode': partyCode, 'event': 'sync_seek', 'ts': nowMs, 'payload': payload},
          expectedCode: partyCode,
          expectedRoomToken: roomToken,
          nowEpochMs: nowMs,
        ),
        isFalse,
      );

      // 3. Tampered payload
      expect(
        PartyLanAccelerator.verifyIncomingPacket(
          {'partyCode': partyCode, 'event': 'sync_seek', 'ts': nowMs, 'sig': validSig, 'payload': {'seq': 99, 'positionMs': 0}},
          expectedCode: partyCode,
          expectedRoomToken: roomToken,
          nowEpochMs: nowMs,
        ),
        isFalse,
      );

      // 4. Stale replay timestamp (> 30s)
      expect(
        PartyLanAccelerator.verifyIncomingPacket(
          {'partyCode': partyCode, 'event': 'sync_seek', 'ts': nowMs, 'sig': validSig, 'payload': payload},
          expectedCode: partyCode,
          expectedRoomToken: roomToken,
          nowEpochMs: nowMs + PartyLanAccelerator.maxClockSkewMs + 1000,
        ),
        isFalse,
      );

      // 5. Non-map payload
      expect(
        PartyLanAccelerator.verifyIncomingPacket(
          {'partyCode': partyCode, 'event': 'sync_seek', 'ts': nowMs, 'sig': validSig, 'payload': 'invalid'},
          expectedCode: partyCode,
          expectedRoomToken: roomToken,
          nowEpochMs: nowMs,
        ),
        isFalse,
      );

      // 6. Discovery host_beacon remains exempt
      expect(
        PartyLanAccelerator.verifyIncomingPacket(
          {'partyCode': partyCode, 'event': 'host_beacon', 'payload': {'code': partyCode, 'port': 45454}},
          expectedCode: partyCode,
          expectedRoomToken: roomToken,
          nowEpochMs: nowMs,
        ),
        isTrue,
      );
    });
  });

  group('PartySyncCoordinator PIN & SecureStorageService', () {
    test('deriveRoomToken is deterministic and joinParty rejects missing PIN', () async {
      final t1 = PartySyncCoordinator.deriveRoomToken('sync-ab12cd', '4821');
      final t2 = PartySyncCoordinator.deriveRoomToken('SYNC-AB12CD', '4821');
      final t3 = PartySyncCoordinator.deriveRoomToken('SYNC-AB12CD', '9999');

      expect(t1.length, equals(64));
      expect(t1, equals(t2));
      expect(t1, isNot(equals(t3)));

      final joinedWithoutPin = await PartySyncCoordinator.joinParty('SYNC-AB12CD');
      expect(joinedWithoutPin, isFalse);
      expect(PartySyncCoordinator.role, equals(PartyRole.none));
    });

    test('SecureStorageService read/write/delete works cleanly with headless fallback', () async {
      expect(await SecureStorageService.read('auth_access_token'), isNull);
      await SecureStorageService.write('auth_access_token', 'jwt_abc_123');
      expect(await SecureStorageService.containsKey('auth_access_token'), isTrue);
      expect(await SecureStorageService.read('auth_access_token'), equals('jwt_abc_123'));

      await SecureStorageService.delete('auth_access_token');
      expect(await SecureStorageService.read('auth_access_token'), isNull);
    });
  });
}
