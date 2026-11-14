import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import 'app_logger.dart';
import 'supabase_service.dart';

/// Over-The-Air (OTA) Dynamic Scraper & Decryption Configuration Service.
/// Eliminates scraper fragility by providing hot-updatable DES keys and InnerTube client profiles.
class DynamicScraperConfigService {
  static const String hiveBoxName = 'scraper_config_box';
  static const String hiveConfigKey = 'cached_scraper_config';

  static const String defaultGithubRawUrl =
      'https://raw.githubusercontent.com/TGAshwinYT/Paatu_Padava/main/scraper_config.json';

  static const String defaultSaavnDesKey = '38346591';
  static const List<String> defaultSaavnFallbackKeys = [
    '38346591',
    '29471958',
    '48201948',
  ];
  static const String defaultSaavnBaseUrl = 'https://www.jiosaavn.com/api.php';

  static const String vrUserAgent =
      'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 2; Build/SQ3A.220605.009.A1) gzip';
  static const String iosUserAgent =
      'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)';
  static const String androidUserAgent =
      'com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UQ1A.240205.004) gzip';

  /// Built-in fallback clients guaranteed to be available offline
  static final List<Map<String, dynamic>> builtInInnerTubeClients = [
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

  // In-memory active configuration
  static String _saavnDesKey = defaultSaavnDesKey;
  static List<String> _saavnFallbackDesKeys = List.from(defaultSaavnFallbackKeys);
  static String _saavnBaseUrl = defaultSaavnBaseUrl;
  static List<Map<String, dynamic>> _innertubeClients = List.from(builtInInnerTubeClients);
  static List<String> _fallbackOrder = ['saavn_direct', 'saavn_search', 'youtube_innertube', 'backend_proxy', 'audius'];
  static bool _backendResolverEnabled = true;

  // Client health tracking (demotes 403/captcha blocked clients for 30 min)
  static final Map<String, DateTime> _failingClientsUntil = {};

  static String get saavnDesKey => _saavnDesKey;
  static List<String> get saavnFallbackDesKeys => List.unmodifiable(_saavnFallbackDesKeys);
  static String get saavnBaseUrl => _saavnBaseUrl;
  static List<Map<String, dynamic>> get innertubeClients => List.unmodifiable(_innertubeClients);
  static List<String> get fallbackOrder => List.unmodifiable(_fallbackOrder);
  static bool get isBackendResolverEnabled => _backendResolverEnabled;

  /// Returns active InnerTube clients, filtering out temporarily blocked/failing clients.
  static List<Map<String, dynamic>> get healthyClientConfigs {
    final now = DateTime.now();
    _failingClientsUntil.removeWhere((_, until) => now.isAfter(until));

    final healthy = _innertubeClients.where((c) {
      final name = c['name']?.toString() ?? '';
      return !_failingClientsUntil.containsKey(name);
    }).toList();

    return healthy.isNotEmpty ? healthy : _innertubeClients;
  }

  /// Temporarily demotes a client (e.g. on HTTP 403 / bot challenge) for 30 minutes
  static void markClientTemporarilyFailing(String clientName, {Duration duration = const Duration(minutes: 30)}) {
    _failingClientsUntil[clientName] = DateTime.now().add(duration);
    AppLogger.log('DynamicScraperConfigService', 'Demoted client "$clientName" until ${_failingClientsUntil[clientName]}');
  }

  /// Temporarily demotes a client and asynchronously dispatches failure telemetry to backend
  static void reportClientFailure(String clientName, String reason) {
    markClientTemporarilyFailing(clientName);
    unawaited(_sendFailureTelemetry(clientName, reason));
  }

  static Future<void> _sendFailureTelemetry(String clientName, String reason) async {
    try {
      final base = AppConfig.backendUrl.replaceAll(RegExp(r'/+$'), '');
      if (base.isEmpty) return;
      final uri = Uri.parse('$base/api/config/scraper/report-failure');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'client_name': clientName,
          'reason': reason,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Instant local cold boot: hydrates configuration from Hive disk cache in < 2ms
  static Future<void> initLocal() async {
    try {
      Box box;
      if (Hive.isBoxOpen(hiveBoxName)) {
        box = Hive.box(hiveBoxName);
      } else {
        box = await Hive.openBox(hiveBoxName);
      }

      final rawCached = box.get(hiveConfigKey);
      if (rawCached != null && rawCached is String) {
        final parsed = jsonDecode(rawCached);
        if (parsed is Map<String, dynamic>) {
          _applyConfigMap(parsed);
          AppLogger.log('DynamicScraperConfigService', 'Hydrated scraper config from local Hive cache');
          return;
        }
      }
    } catch (e) {
      AppLogger.log('DynamicScraperConfigService', 'Notice: Local Hive hydration skipped: $e');
    }
  }

  /// Refreshes configuration using a 4-tier remote cascade:
  /// 1. Backend API -> 2. Supabase -> 3. GitHub Raw mirror -> 4. Bundled asset
  static Future<void> refreshRemoteConfig({String? overrideUrl}) async {
    // 1. Try Backend API
    final backendConfig = await _fetchFromBackend(overrideUrl);
    if (backendConfig != null) {
      await _saveAndApply(backendConfig, source: 'Backend API');
      return;
    }

    // 2. Try Supabase Remote Config
    final supabaseConfig = await _fetchFromSupabase();
    if (supabaseConfig != null) {
      await _saveAndApply(supabaseConfig, source: 'Supabase');
      return;
    }

    // 3. Try GitHub Raw Mirror
    final githubConfig = await _fetchFromGithubRaw();
    if (githubConfig != null) {
      await _saveAndApply(githubConfig, source: 'GitHub Raw');
      return;
    }

    // 4. Fallback to Bundled Asset
    await _loadFromBundledAsset();
  }

  static Future<Map<String, dynamic>?> _fetchFromBackend(String? overrideUrl) async {
    try {
      final base = (overrideUrl ?? AppConfig.backendUrl).replaceAll(RegExp(r'/+$'), '');
      if (base.isEmpty) return null;
      final uri = Uri.parse('$base/api/config/scraper');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        if (parsed is Map<String, dynamic>) return parsed;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromSupabase() async {
    try {
      final client = SupabaseService.client;
      if (client != null && SupabaseService.isConfigured) {
        final row = await client.from('app_config').select('config').eq('key', 'scraper_rules').maybeSingle().timeout(const Duration(seconds: 3));
        if (row != null && row['config'] is Map) {
          return Map<String, dynamic>.from(row['config'] as Map);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromGithubRaw() async {
    try {
      final res = await http.get(Uri.parse(defaultGithubRawUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        if (parsed is Map<String, dynamic>) return parsed;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _loadFromBundledAsset() async {
    try {
      final assetStr = await rootBundle.loadString('assets/scraper_config.json');
      final parsed = jsonDecode(assetStr);
      if (parsed is Map<String, dynamic>) {
        _applyConfigMap(parsed);
        AppLogger.log('DynamicScraperConfigService', 'Loaded default scraper config from bundled asset');
      }
    } catch (_) {
      // Keep in-memory defaults
    }
  }

  static Future<void> _saveAndApply(Map<String, dynamic> config, {required String source}) async {
    _applyConfigMap(config);
    AppLogger.log('DynamicScraperConfigService', 'Applied and cached fresh scraper config from $source');
    try {
      Box box;
      if (Hive.isBoxOpen(hiveBoxName)) {
        box = Hive.box(hiveBoxName);
      } else {
        box = await Hive.openBox(hiveBoxName);
      }
      await box.put(hiveConfigKey, jsonEncode(config));
    } catch (_) {}
  }

  static void _applyConfigMap(Map<String, dynamic> map) {
    if (map['saavn'] is Map) {
      final s = map['saavn'] as Map;
      final key = s['primaryDesKey']?.toString();
      if (key != null && key.isNotEmpty) _saavnDesKey = key;

      final fallbacks = s['fallbackDesKeys'];
      if (fallbacks is List) {
        _saavnFallbackDesKeys = fallbacks.map((k) => k.toString()).where((k) => k.isNotEmpty).toList();
        if (!_saavnFallbackDesKeys.contains(_saavnDesKey)) {
          _saavnFallbackDesKeys.insert(0, _saavnDesKey);
        }
      }

      final url = s['baseUrl']?.toString();
      if (url != null && url.isNotEmpty) _saavnBaseUrl = url;
    }

    if (map['innertube'] is Map) {
      final it = map['innertube'] as Map;
      final clients = it['clients'];
      if (clients is List && clients.isNotEmpty) {
        final validated = <Map<String, dynamic>>[];
        for (final c in clients) {
          if (c is Map && c.containsKey('client') && c.containsKey('headers')) {
            validated.add(Map<String, dynamic>.from(c));
          }
        }
        if (validated.isNotEmpty) {
          _innertubeClients = validated;
        }
      }
    }

    if (map['fallbackOrder'] is List) {
      _fallbackOrder = (map['fallbackOrder'] as List).map((e) => e.toString()).toList();
    }

    if (map['backendResolver'] is Map) {
      _backendResolverEnabled = (map['backendResolver'] as Map)['enabled'] != false;
    }
  }

  @visibleForTesting
  static void setCustomConfigForTesting({
    String? saavnKey,
    List<String>? fallbackKeys,
    List<Map<String, dynamic>>? innertubeClients,
    bool? backendEnabled,
  }) {
    if (saavnKey != null) _saavnDesKey = saavnKey;
    if (fallbackKeys != null) _saavnFallbackDesKeys = fallbackKeys;
    if (innertubeClients != null) _innertubeClients = innertubeClients;
    if (backendEnabled != null) _backendResolverEnabled = backendEnabled;
  }

  @visibleForTesting
  static void resetToDefaults() {
    _saavnDesKey = defaultSaavnDesKey;
    _saavnFallbackDesKeys = List.from(defaultSaavnFallbackKeys);
    _saavnBaseUrl = defaultSaavnBaseUrl;
    _innertubeClients = List.from(builtInInnerTubeClients);
    _fallbackOrder = ['saavn_direct', 'saavn_search', 'youtube_innertube', 'backend_proxy', 'audius'];
    _backendResolverEnabled = true;
    _failingClientsUntil.clear();
  }
}
