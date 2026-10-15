import 'dart:convert';
import 'package:dart_des/dart_des.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/des_decrypt.dart';
import 'package:paatu_padava_mobile/services/innertube_config_service.dart';
import 'package:paatu_padava_mobile/services/youtube_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fix 1: Forced-320 Bug & Saavn Bitrate Helper', () {
    test('decryptSaavnMediaUrl preserves genuine decrypted bitrate (does not force _320.mp4)', () {
      // Create a known DES encrypted string with a 160kbps URL
      const rawUrl = 'https://aac.saavncdn.com/123/sample_song_160.mp4';
      const key = '38346591';
      final bytes = utf8.encode(rawUrl);
      // PKCS5 pad
      final pad = 8 - (bytes.length % 8);
      final padded = List<int>.from(bytes)..addAll(List.filled(pad, pad));
      final des = DES(key: key.codeUnits, mode: DESMode.ECB);
      final encrypted = des.encrypt(padded);
      final encBase64 = base64.encode(encrypted);

      final decrypted = decryptSaavnMediaUrl(encBase64);

      // Verify that decrypt does NOT force replace _160.mp4 with _320.mp4
      expect(decrypted, equals(rawUrl));
      expect(decrypted, contains('_160.mp4'));
      expect(decrypted, isNot(contains('_320.mp4')));
    });

    test('SaavnBitrateHelper.getBitrateCandidates returns preferred order and fallbacks', () {
      const url = 'https://aac.saavncdn.com/123/sample_song_160.mp4';

      // Default 320kbps quality
      final candidates320 = SaavnBitrateHelper.getBitrateCandidates(url, targetQuality: '320kbps');
      expect(candidates320, contains('https://aac.saavncdn.com/123/sample_song_320.mp4'));
      expect(candidates320, contains('https://aac.saavncdn.com/123/sample_song_160.mp4'));
      expect(candidates320, contains('https://aac.saavncdn.com/123/sample_song_96.mp4'));
      expect(candidates320.first, endsWith('_320.mp4'));

      // 96kbps quality
      final candidates96 = SaavnBitrateHelper.getBitrateCandidates(url, targetQuality: '96kbps');
      expect(candidates96.first, endsWith('_96.mp4'));

      // 160kbps quality
      final candidates160 = SaavnBitrateHelper.getBitrateCandidates(url, targetQuality: '160kbps');
      expect(candidates160.first, endsWith('_160.mp4'));
    });

    test('SaavnBitrateHelper.getNextFallbackUrl steps down from 320 -> 160 -> 96', () {
      const url320 = 'https://aac.saavncdn.com/123/sample_song_320.mp4';
      final fallback1 = SaavnBitrateHelper.getNextFallbackUrl(url320);
      expect(fallback1, equals('https://aac.saavncdn.com/123/sample_song_160.mp4'));

      final fallback2 = SaavnBitrateHelper.getNextFallbackUrl(fallback1!);
      expect(fallback2, equals('https://aac.saavncdn.com/123/sample_song_96.mp4'));

      final fallback3 = SaavnBitrateHelper.getNextFallbackUrl(fallback2!);
      expect(fallback3, isNull);
    });

    test('SaavnBitrateHelper.toBitrate correctly handles both .mp4 and .mp3 containers', () {
      const mp4Url = 'https://aac.saavncdn.com/123/test_160.mp4';
      expect(SaavnBitrateHelper.toBitrate(mp4Url, '320'), equals('https://aac.saavncdn.com/123/test_320.mp4'));
      expect(SaavnBitrateHelper.toBitrate(mp4Url, '96'), equals('https://aac.saavncdn.com/123/test_96.mp4'));

      const mp3Url = 'https://aac.saavncdn.com/123/test_96.mp3';
      expect(SaavnBitrateHelper.toBitrate(mp3Url, '320'), equals('https://aac.saavncdn.com/123/test_320.mp3'));
      expect(SaavnBitrateHelper.toBitrate(mp3Url, '160'), equals('https://aac.saavncdn.com/123/test_160.mp3'));
    });
  });

  group('Fix 2: InnerTube Client Configs with Built-in Defaults & Remote JSON Support', () {
    test('InnerTubeConfigService has complete built-in defaults with valid headers and clients', () {
      final defaults = InnerTubeConfigService.builtInDefaults;
      expect(defaults, isNotEmpty);
      expect(defaults.length, greaterThanOrEqualTo(5));

      final names = defaults.map((d) => d['name']).toList();
      expect(names, contains('IOS'));
      expect(names, contains('ANDROID_VR'));
      expect(names, contains('ANDROID'));
      expect(names, contains('WEB_REMIX'));

      for (final config in defaults) {
        expect(config.containsKey('client'), isTrue);
        expect(config.containsKey('headers'), isTrue);
        final client = config['client'] as Map<String, dynamic>;
        expect(client.containsKey('clientName'), isTrue);
        expect(client.containsKey('clientVersion'), isTrue);
        final headers = config['headers'] as Map<String, dynamic>;
        expect(headers.containsKey('User-Agent'), isTrue);
      }
    });

    test('InnerTubeConfigService allows test configuration injection and reset', () {
      final customConfig = [
        {
          'name': 'CUSTOM_CLIENT',
          'client': {'clientName': 'CUSTOM', 'clientVersion': '1.0'},
          'headers': {'User-Agent': 'CustomUA/1.0'},
        }
      ];

      InnerTubeConfigService.setConfigsForTesting(customConfig);
      expect(InnerTubeConfigService.clientConfigs.length, equals(1));
      expect(InnerTubeConfigService.clientConfigs.first['name'], equals('CUSTOM_CLIENT'));

      InnerTubeConfigService.resetToDefaults();
      expect(InnerTubeConfigService.clientConfigs.length, equals(InnerTubeConfigService.builtInDefaults.length));
    });

    test('userAgentForUrl returns appropriate User-Agent for standard clients and WEB_REMIX', () {
      expect(
        YouTubeClient.userAgentForUrl('https://rr1---sn.googlevideo.com/videoplayback?c=ANDROID_VR'),
        contains('com.google.android.apps.youtube.vr.oculus'),
      );
      expect(
        YouTubeClient.userAgentForUrl('https://rr1---sn.googlevideo.com/videoplayback?c=IOS'),
        contains('com.google.ios.youtube'),
      );
      expect(
        YouTubeClient.userAgentForUrl('https://rr1---sn.googlevideo.com/videoplayback?c=WEB_REMIX'),
        contains('Mozilla/5.0'),
      );
    });
  });

  group('Fix 3: Bitrate Fallback on YouTube Streams', () {
    test('YouTubeClient.probeStreamUrl correctly inspects URL without throwing', () async {
      final emptyResult = await YouTubeClient.probeStreamUrl('');
      expect(emptyResult, isFalse);
    });

    test('headersForUrl for googlevideo.com includes User-Agent and omits Range header', () {
      const gvUrl = 'https://rr3---sn-h5576nsr.googlevideo.com/videoplayback?expire=999999999';
      final headers = YouTubeClient.headersForUrl(gvUrl);
      expect(headers['User-Agent'], isNotNull);
      expect(headers['Accept'], equals('*/*'));
      expect(headers.containsKey('Range'), isFalse);
    });
  });
}
