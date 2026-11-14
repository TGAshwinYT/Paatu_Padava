import 'dart:convert';
import 'package:dart_des/dart_des.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/des_decrypt.dart';
import 'package:paatu_padava_mobile/services/dynamic_scraper_config_service.dart';
import 'package:paatu_padava_mobile/services/innertube_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DynamicScraperConfigService.resetToDefaults();
  });

  group('Dynamic Scraper Configuration Service - Defaults & State', () {
    test('Loads built-in defaults when initialized', () {
      expect(DynamicScraperConfigService.saavnDesKey, equals('38346591'));
      expect(DynamicScraperConfigService.saavnFallbackDesKeys, contains('38346591'));
      expect(DynamicScraperConfigService.saavnFallbackDesKeys, contains('29471958'));
      expect(DynamicScraperConfigService.saavnBaseUrl, equals('https://www.jiosaavn.com/api.php'));
      expect(DynamicScraperConfigService.isBackendResolverEnabled, isTrue);

      final clients = DynamicScraperConfigService.innertubeClients;
      expect(clients.length, greaterThanOrEqualTo(6));
      final names = clients.map((c) => c['name']).toList();
      expect(names, contains('IOS'));
      expect(names, contains('ANDROID_VR'));
      expect(names, contains('WEB_REMIX'));
    });

    test('markClientTemporarilyFailing demotes blocked client from healthy list', () {
      expect(DynamicScraperConfigService.healthyClientConfigs.any((c) => c['name'] == 'ANDROID_VR'), isTrue);

      // Simulate YouTube blocking ANDROID_VR
      DynamicScraperConfigService.markClientTemporarilyFailing('ANDROID_VR');

      // Verify ANDROID_VR is filtered out from healthyClientConfigs
      final healthy = DynamicScraperConfigService.healthyClientConfigs;
      expect(healthy.any((c) => c['name'] == 'ANDROID_VR'), isFalse);
      expect(healthy.any((c) => c['name'] == 'IOS'), isTrue);

      // Backward compatibility bridge in InnerTubeConfigService
      expect(InnerTubeConfigService.healthyClientConfigs.any((c) => c['name'] == 'ANDROID_VR'), isFalse);
    });

    test('Demoting all clients falls back to full list to avoid empty execution', () {
      for (final client in DynamicScraperConfigService.innertubeClients) {
        DynamicScraperConfigService.markClientTemporarilyFailing(client['name'].toString());
      }

      // When all are demoted, healthyClientConfigs returns all clients as a last resort
      expect(DynamicScraperConfigService.healthyClientConfigs, isNotEmpty);
    });
  });

  group('Multi-Key Trial DES Decryption', () {
    String encryptWithKey(String rawUrl, String key) {
      final bytes = utf8.encode(rawUrl);
      final pad = 8 - (bytes.length % 8);
      final padded = List<int>.from(bytes)..addAll(List.filled(pad, pad));
      final des = DES(key: key.codeUnits, mode: DESMode.ECB);
      final encrypted = des.encrypt(padded);
      return base64.encode(encrypted);
    }

    test('decryptSaavnMediaUrl successfully decrypts with primary dynamic key', () {
      const rawUrl = 'https://aac.saavncdn.com/999/song_primary_320.mp4';
      final enc = encryptWithKey(rawUrl, '38346591');

      final decrypted = decryptSaavnMediaUrl(enc);
      expect(decrypted, equals(rawUrl));
    });

    test('decryptSaavnMediaUrl cascades to fallback keys when encrypted with alternate key', () {
      // Simulate JioSaavn using a secondary key (e.g. '29471958' in fallback keys)
      const rawUrl = 'https://aac.saavncdn.com/888/song_fallback_320.mp4';
      final enc = encryptWithKey(rawUrl, '29471958');

      // Primary key ('38346591') will fail decryption, but multi-key trial must succeed on fallback key!
      final decrypted = decryptSaavnMediaUrl(enc);
      expect(decrypted, equals(rawUrl));
    });

    test('decryptSaavnMediaUrl returns empty string when all keys fail without throwing', () {
      const rawUrl = 'https://aac.saavncdn.com/777/song_unknown_320.mp4';
      final enc = encryptWithKey(rawUrl, '99999999'); // Unknown key not in primary or fallbacks

      final decrypted = decryptSaavnMediaUrl(enc);
      expect(decrypted, isEmpty);
    });

    test('decryptSaavnMediaUrl responds dynamically to OTA key updates', () {
      const rawUrl = 'https://aac.saavncdn.com/555/song_ota_320.mp4';
      const newOtaKey = '77778888';
      final enc = encryptWithKey(rawUrl, newOtaKey);

      // Initially fails because new key is not known
      expect(decryptSaavnMediaUrl(enc), isEmpty);

      // OTA configuration arrives and updates the key dynamically
      DynamicScraperConfigService.setCustomConfigForTesting(
        saavnKey: newOtaKey,
        fallbackKeys: [newOtaKey, '38346591'],
      );

      // Now decrypts successfully with the updated OTA key!
      expect(decryptSaavnMediaUrl(enc), equals(rawUrl));
    });
  });
}
