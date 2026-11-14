import 'package:flutter/foundation.dart';
import 'dynamic_scraper_config_service.dart';

/// InnerTube Client Configuration Service
/// Loads client configurations dynamically via [DynamicScraperConfigService]
/// with local Hive persistence, backend API cascading, and robust built-in defaults.
/// Allows dynamic client and header rotation without requiring full application updates.
class InnerTubeConfigService {
  static const String defaultRemoteUrl =
      'https://raw.githubusercontent.com/TGAshwinYT/Paatu_Padava/main/scraper_config.json';

  static String get vrUserAgent => DynamicScraperConfigService.vrUserAgent;
  static String get iosUserAgent => DynamicScraperConfigService.iosUserAgent;
  static String get androidUserAgent => DynamicScraperConfigService.androidUserAgent;

  /// Built-in default client definitions (guaranteed to be available offline)
  static List<Map<String, dynamic>> get builtInDefaults =>
      DynamicScraperConfigService.builtInInnerTubeClients;

  /// Returns the current active list of InnerTube client configurations
  static List<Map<String, dynamic>> get clientConfigs =>
      DynamicScraperConfigService.innertubeClients;

  /// Returns the healthy subset of InnerTube client configurations
  static List<Map<String, dynamic>> get healthyClientConfigs =>
      DynamicScraperConfigService.healthyClientConfigs;

  /// Allows unit and integration tests to set custom configs
  @visibleForTesting
  static void setConfigsForTesting(List<Map<String, dynamic>> configs) {
    // ignore: invalid_use_of_visible_for_testing_member
    DynamicScraperConfigService.setCustomConfigForTesting(innertubeClients: configs);
  }

  /// Resets back to builtInDefaults
  @visibleForTesting
  static void resetToDefaults() {
    // ignore: invalid_use_of_visible_for_testing_member
    DynamicScraperConfigService.resetToDefaults();
  }

  /// Asynchronously fetches client configurations from remote cascade,
  /// falling back to local Hive cache, bundled asset, or built-in defaults.
  static Future<void> initialize({String? remoteUrl}) async {
    await DynamicScraperConfigService.initLocal();
    await DynamicScraperConfigService.refreshRemoteConfig(overrideUrl: remoteUrl);
  }
}
