import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'app_logger.dart';

/// InnerTube Client Configuration Service
/// Loads client configurations from a remote JSON endpoint (e.g. GitHub raw or backend API)
/// with local asset caching and robust built-in defaults.
/// Allows dynamic client and header rotation without requiring full application updates.
class InnerTubeConfigService {
  static const String defaultRemoteUrl =
      'https://raw.githubusercontent.com/TGAshwinYT/Paatu_Padava/main/innertube_clients.json';

  static const String vrUserAgent =
      'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 2; Build/SQ3A.220605.009.A1) gzip';
  static const String iosUserAgent =
      'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)';
  static const String androidUserAgent =
      'com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UQ1A.240205.004) gzip';

  /// Built-in default client definitions (guaranteed to be available offline)
  static final List<Map<String, dynamic>> builtInDefaults = [
    {
      'name': 'IOS',
      'client': {
        'clientName': 'IOS',
        'clientVersion': '19.45.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '18.1.0.22B83',
        'hl': 'en',
        'gl': 'IN',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent': iosUserAgent,
        'X-YouTube-Client-Name': '5',
        'X-YouTube-Client-Version': '19.45.4',
        'Accept': '*/*',
      },
    },
    {
      'name': 'IOS_UPDATED',
      'client': {
        'clientName': 'IOS',
        'clientVersion': '21.26.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '18.1.0.22B83',
        'hl': 'en',
        'gl': 'IN',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent':
            'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)',
        'X-YouTube-Client-Name': '5',
        'X-YouTube-Client-Version': '21.26.4',
        'Accept': '*/*',
      },
    },
    {
      'name': 'ANDROID_VR',
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.56.21',
        'androidSdkVersion': 32,
        'gl': 'IN',
        'hl': 'en',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent': vrUserAgent,
        'X-YouTube-Client-Name': '28',
        'X-YouTube-Client-Version': '1.56.21',
        'Accept': '*/*',
      },
    },
    {
      'name': 'ANDROID',
      'client': {
        'clientName': 'ANDROID',
        'clientVersion': '19.29.37',
        'androidSdkVersion': 34,
        'gl': 'IN',
        'hl': 'en',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent': androidUserAgent,
        'X-YouTube-Client-Name': '3',
        'X-YouTube-Client-Version': '19.29.37',
        'Accept': '*/*',
      },
    },
    {
      'name': 'WEB_REMIX',
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20240722.01.00',
        'gl': 'IN',
        'hl': 'en',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        'X-YouTube-Client-Name': '67',
        'X-YouTube-Client-Version': '1.20240722.01.00',
        'Referer': 'https://music.youtube.com/',
        'Accept': '*/*',
      },
    },
    {
      'name': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
      'client': {
        'clientName': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
        'clientVersion': '2.0',
        'gl': 'IN',
        'hl': 'en',
      },
      'headers': {
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (PlayStation; PlayStation 4/10.01) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/10.01 Safari/605.1.15',
        'X-YouTube-Client-Name': '85',
        'X-YouTube-Client-Version': '2.0',
        'Accept': '*/*',
      },
    },
  ];

  static List<Map<String, dynamic>> _activeConfigs = List.from(builtInDefaults);
  static bool _hasLoadedRemote = false;

  /// Returns the current active list of InnerTube client configurations
  static List<Map<String, dynamic>> get clientConfigs => _activeConfigs;

  /// Allows unit and integration tests to set custom configs
  @visibleForTesting
  static void setConfigsForTesting(List<Map<String, dynamic>> configs) {
    _activeConfigs = configs;
    _hasLoadedRemote = true;
  }

  /// Resets back to builtInDefaults
  @visibleForTesting
  static void resetToDefaults() {
    _activeConfigs = List.from(builtInDefaults);
    _hasLoadedRemote = false;
  }

  /// Asynchronously fetches client configurations from remote JSON endpoint,
  /// falling back to local asset bundled in the app, or built-in defaults.
  static Future<void> initialize({String? remoteUrl}) async {
    if (_hasLoadedRemote) return;

    final targetUrl = remoteUrl ?? defaultRemoteUrl;
    try {
      final res = await http.get(Uri.parse(targetUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        if (parsed is List && parsed.isNotEmpty) {
          final validated = <Map<String, dynamic>>[];
          for (final item in parsed) {
            if (item is Map<String, dynamic> && item.containsKey('client') && item.containsKey('headers')) {
              validated.add(item);
            }
          }
          if (validated.isNotEmpty) {
            _activeConfigs = validated;
            _hasLoadedRemote = true;
            AppLogger.log('InnerTubeConfigService', 'Loaded ${_activeConfigs.length} client configs from remote JSON ($targetUrl)');
            return;
          }
        }
      }
    } catch (e) {
      AppLogger.log('InnerTubeConfigService', 'Notice: Remote config fetch failed ($e). Trying bundled asset...');
    }

    // Fallback: try loading from asset bundle
    try {
      final assetJson = await rootBundle.loadString('assets/innertube_clients.json');
      final parsed = jsonDecode(assetJson);
      if (parsed is List && parsed.isNotEmpty) {
        final validated = <Map<String, dynamic>>[];
        for (final item in parsed) {
          if (item is Map<String, dynamic> && item.containsKey('client') && item.containsKey('headers')) {
            validated.add(item);
          }
        }
        if (validated.isNotEmpty) {
          _activeConfigs = validated;
          _hasLoadedRemote = true;
          AppLogger.log('InnerTubeConfigService', 'Loaded ${_activeConfigs.length} client configs from bundled asset');
          return;
        }
      }
    } catch (e) {
      AppLogger.log('InnerTubeConfigService', 'Bundled asset load notice: $e. Using built-in defaults.');
    }

    // Default built-in list remains active
    _activeConfigs = List.from(builtInDefaults);
  }
}
