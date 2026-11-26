import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paatu_padava_mobile/services/device_connect_coordinator.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/stereo_balance_card.dart';

void main() {
  group('StereoBalanceCard formatting', () {
    test('formats center, left-favored, and right-favored labels', () {
      expect(StereoBalanceCard.formatBalanceLabel(0.0), 'Balanced (Center)');
      expect(StereoBalanceCard.formatBalanceLabel(0.01), 'Balanced (Center)');
      expect(
        StereoBalanceCard.formatBalanceLabel(-0.5),
        'Left favored • Right -15.0 dB',
      );
      expect(
        StereoBalanceCard.formatBalanceLabel(0.5),
        'Right favored • Left -15.0 dB',
      );
    });
  });

  group('SettingsManager stereoBalance persistence', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pp_balance_test_');
      Hive.init(tempDir.path);
      await SettingsManager.init();
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('clamps and persists stereoBalance in Hive', () async {
      expect(SettingsManager.stereoBalance, 0.0);

      await SettingsManager.setStereoBalance(-0.4);
      expect(SettingsManager.stereoBalance, closeTo(-0.4, 0.0001));

      await SettingsManager.setStereoBalance(-2.5);
      expect(SettingsManager.stereoBalance, -1.0);

      await SettingsManager.setStereoBalance(3.0);
      expect(SettingsManager.stereoBalance, 1.0);

      await SettingsManager.init();
      expect(SettingsManager.stereoBalance, 1.0);
    });
  });

  group('DeviceConnectCoordinator route classification', () {
    test('distinguishes local Bluetooth route from remote Cast session', () async {
      const btBuds = ConnectedDevice(
        id: 'bt_1',
        name: 'Air Buds',
        type: DeviceType.speaker,
        protocol: ConnectionProtocol.local,
        status: 'Connected • Bluetooth Active',
      );
      const castTv = ConnectedDevice(
        id: 'cast_1',
        name: 'Living Room TV',
        type: DeviceType.tv,
        protocol: ConnectionProtocol.googleCast,
        ipAddress: '192.168.1.50',
        status: 'Connected • Streaming',
      );

      expect(btBuds.isExternalLocalRoute, isTrue);
      expect(btBuds.isRemoteSession, isFalse);
      expect(castTv.isExternalLocalRoute, isFalse);
      expect(castTv.isRemoteSession, isTrue);

      DeviceConnectCoordinator.instance.currentDeviceNotifier.value = btBuds;
      expect(await DeviceConnectCoordinator.instance.disconnect(), isFalse);
      expect(DeviceConnectCoordinator.instance.currentDevice.id, 'bt_1');

      DeviceConnectCoordinator.instance.currentDeviceNotifier.value = castTv;
      expect(await DeviceConnectCoordinator.instance.disconnect(), isTrue);
      expect(DeviceConnectCoordinator.instance.currentDevice.isLocal, isTrue);
    });
  });
}
