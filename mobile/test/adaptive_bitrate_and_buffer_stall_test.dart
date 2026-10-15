import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/connectivity_service.dart';
import 'package:paatu_padava_mobile/services/des_decrypt.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adaptive Bitrate & Auto Quality Resolution', () {
    test('ConnectivityService.recommendedStreamingQuality selects 320kbps on fast Wi-Fi', () {
      ConnectivityService.setMockConditions(
        isOnline: true,
        networkType: 'wifi',
        latencyMs: 45,
      );

      expect(ConnectivityService.recommendedStreamingQuality, equals('320kbps'));
    });

    test('ConnectivityService.recommendedStreamingQuality selects 160kbps on cellular connection', () {
      ConnectivityService.setMockConditions(
        isOnline: true,
        networkType: 'cellular',
        latencyMs: 120,
      );

      expect(ConnectivityService.recommendedStreamingQuality, equals('160kbps'));
    });

    test('ConnectivityService.recommendedStreamingQuality selects 96kbps on weak/high-latency network (>400ms)', () {
      ConnectivityService.setMockConditions(
        isOnline: true,
        networkType: 'cellular',
        latencyMs: 450,
      );

      expect(ConnectivityService.recommendedStreamingQuality, equals('96kbps'));
    });

    test('ConnectivityService.recommendedStreamingQuality selects 96kbps when offline', () {
      ConnectivityService.setMockConditions(
        isOnline: false,
        networkType: 'wifi',
        latencyMs: 30,
      );

      expect(ConnectivityService.recommendedStreamingQuality, equals('96kbps'));
    });

    test('SettingsManager.effectiveStreamingQuality dynamically resolves in auto mode', () {
      SettingsManager.streamingQualityNotifier.value = 'auto';

      // Fast Wi-Fi -> 320kbps
      ConnectivityService.setMockConditions(
        isOnline: true,
        networkType: 'wifi',
        latencyMs: 40,
      );
      expect(SettingsManager.effectiveStreamingQuality, equals('320kbps'));

      // Cellular -> 160kbps
      ConnectivityService.setMockConditions(
        isOnline: true,
        networkType: 'cellular',
        latencyMs: 110,
      );
      expect(SettingsManager.effectiveStreamingQuality, equals('160kbps'));

      // Extreme latency -> 96kbps
      ConnectivityService.setMockConditions(
        isOnline: true,
        networkType: 'cellular',
        latencyMs: 520,
      );
      expect(SettingsManager.effectiveStreamingQuality, equals('96kbps'));
    });

    test('SettingsManager.effectiveStreamingQuality honors explicit manual quality override', () {
      SettingsManager.streamingQualityNotifier.value = '160kbps';
      ConnectivityService.setMockConditions(
        isOnline: true,
        networkType: 'wifi',
        latencyMs: 20,
      );
      // Even though network is fast Wi-Fi, user explicitly asked for 160kbps
      expect(SettingsManager.effectiveStreamingQuality, equals('160kbps'));

      SettingsManager.streamingQualityNotifier.value = '96kbps';
      expect(SettingsManager.effectiveStreamingQuality, equals('96kbps'));

      SettingsManager.streamingQualityNotifier.value = '320kbps';
      expect(SettingsManager.effectiveStreamingQuality, equals('320kbps'));
    });
  });

  group('SaavnBitrateHelper Auto Safety & Buffer Stall Downscaling', () {
    test('SaavnBitrateHelper.toBitrate handles auto without injecting _auto.mp4 into URL', () {
      const original = 'https://aac.saavncdn.com/123/sample_160.mp4';
      final autoUrl = SaavnBitrateHelper.toBitrate(original, 'auto');

      expect(autoUrl, isNot(contains('_auto.mp4')));
      expect(autoUrl, equals('https://aac.saavncdn.com/123/sample_320.mp4'));
    });

    test('SaavnBitrateHelper.getBitrateCandidates includes full ladder when target is auto', () {
      const original = 'https://aac.saavncdn.com/123/sample_160.mp4';
      final candidates = SaavnBitrateHelper.getBitrateCandidates(original, targetQuality: 'auto');

      expect(candidates.first, equals('https://aac.saavncdn.com/123/sample_320.mp4'));
      expect(candidates, contains('https://aac.saavncdn.com/123/sample_160.mp4'));
      expect(candidates, contains('https://aac.saavncdn.com/123/sample_96.mp4'));
    });

    test('Buffer Stall Rescue: getNextFallbackUrl steps down 320 -> 160 -> 96', () {
      const url320 = 'https://aac.saavncdn.com/123/sample_320.mp4';
      final stepDown1 = SaavnBitrateHelper.getNextFallbackUrl(url320);
      expect(stepDown1, equals('https://aac.saavncdn.com/123/sample_160.mp4'));

      final stepDown2 = SaavnBitrateHelper.getNextFallbackUrl(stepDown1!);
      expect(stepDown2, equals('https://aac.saavncdn.com/123/sample_96.mp4'));

      final stepDown3 = SaavnBitrateHelper.getNextFallbackUrl(stepDown2!);
      expect(stepDown3, isNull); // 96k is floor, cannot downscale further
    });
  });
}
