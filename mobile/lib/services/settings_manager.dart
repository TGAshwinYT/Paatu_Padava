import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'auth_manager.dart';
import 'connectivity_service.dart';

enum NextTrackStrategyMode {
  spotifyStyle,
  ytMusicStyle,
  markovCosineRadio,
}

class SettingsManager {
  static const String boxName = 'settings_box';

  static final ValueNotifier<String> streamingQualityNotifier = ValueNotifier<String>('320kbps');
  static final ValueNotifier<String> downloadQualityNotifier = ValueNotifier<String>('320kbps');
  static final ValueNotifier<bool> volumeNormalizationNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> autoplayNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<int> crossfadeDurationNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<String> eqPresetNotifier = ValueNotifier<String>('flat');
  static final ValueNotifier<List<double>> eqBandsNotifier = ValueNotifier<List<double>>([0.0, 0.0, 0.0, 0.0, 0.0]);
  static final ValueNotifier<double> bassBoostNotifier = ValueNotifier<double>(0.0);
  static final ValueNotifier<double> virtualizerNotifier = ValueNotifier<double>(0.0);
  static final ValueNotifier<Map<String, List<double>>> customEqPresetsNotifier =
      ValueNotifier<Map<String, List<double>>>({});
  static final ValueNotifier<List<String>> languagesNotifier = ValueNotifier<List<String>>(['Tamil', 'English']);
  static final ValueNotifier<NextTrackStrategyMode> nextTrackStrategyNotifier =
      ValueNotifier<NextTrackStrategyMode>(NextTrackStrategyMode.spotifyStyle);
  static final ValueNotifier<int> maxCacheSizeMbNotifier = ValueNotifier<int>(500);
  static final ValueNotifier<int> bluetoothDelayMsNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> hardwareAudioLatencyMsNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<String> lyricsPreferredLanguageNotifier = ValueNotifier<String>('default');
  static final ValueNotifier<bool> playerGesturesEnabledNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<String> themeModeNotifier = ValueNotifier<String>('amoled');
  static final ValueNotifier<bool> dynamicBackgroundNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> indicRomanizationNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> keepScreenAwakeNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> downloadWifiOnlyNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<String> downloadPathNotifier = ValueNotifier<String>('Internal Storage');
  static final ValueNotifier<String> homeHeroBannerModeNotifier = ValueNotifier<String>('smart');
  static final ValueNotifier<String> homeTop10ChartLayoutNotifier = ValueNotifier<String>('vertical');
  static final ValueNotifier<bool> homeRememberFeelingNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> homeShowQuickPicksNotifier = ValueNotifier<bool>(true);

  static String get streamingQuality => streamingQualityNotifier.value;
  /// Returns the resolved bitrate string ('320kbps', '160kbps', '96kbps').
  /// If user selected 'auto', dynamically queries ConnectivityService for the optimal bitrate.
  static String get effectiveStreamingQuality {
    final q = streamingQualityNotifier.value;
    if (q == 'auto') {
      return ConnectivityService.recommendedStreamingQuality;
    }
    return q;
  }
  static String get downloadQuality => downloadQualityNotifier.value;
  static bool get isVolumeNormalizationEnabled => volumeNormalizationNotifier.value;
  static bool get isAutoplayEnabled => autoplayNotifier.value;
  static int get crossfadeSeconds => crossfadeDurationNotifier.value;
  static String get eqPreset => eqPresetNotifier.value;
  static List<double> get eqBands => eqBandsNotifier.value;
  static double get bassBoost => bassBoostNotifier.value;
  static double get virtualizer => virtualizerNotifier.value;
  static Map<String, List<double>> get customEqPresets => customEqPresetsNotifier.value;
  static NextTrackStrategyMode get nextTrackStrategy => nextTrackStrategyNotifier.value;
  static int get maxCacheSizeMb => maxCacheSizeMbNotifier.value;
  static int get bluetoothDelayMs => bluetoothDelayMsNotifier.value;
  static int get hardwareAudioLatencyMs => hardwareAudioLatencyMsNotifier.value;
  static String get lyricsPreferredLanguage => lyricsPreferredLanguageNotifier.value;
  static bool get isPlayerGesturesEnabled => playerGesturesEnabledNotifier.value;
  static String get themeMode => themeModeNotifier.value;
  static bool get isDynamicBackgroundEnabled => dynamicBackgroundNotifier.value;
  static bool get isIndicRomanizationEnabled => indicRomanizationNotifier.value;
  static bool get isKeepScreenAwakeEnabled => keepScreenAwakeNotifier.value;
  static bool get isDownloadWifiOnlyEnabled => downloadWifiOnlyNotifier.value;
  static String get downloadPath => downloadPathNotifier.value;
  static String get homeHeroBannerMode => homeHeroBannerModeNotifier.value;
  static String get homeTop10ChartLayout => homeTop10ChartLayoutNotifier.value;
  static bool get isHomeRememberFeelingEnabled => homeRememberFeelingNotifier.value;
  static bool get isHomeShowQuickPicksEnabled => homeShowQuickPicksNotifier.value;

  /// Single coordinated preferred languages accessor:
  /// Uses AuthManager profile preferences as the source of truth,
  /// seamlessly falling back to local settings if unauthenticated.
  static List<String> get preferredLanguages {
    final userLangs = AuthManager.currentUser?.preferredLanguages;
    if (userLangs != null && userLangs.isNotEmpty) {
      return userLangs;
    }
    return languagesNotifier.value;
  }

  static Box get _box => Hive.box(boxName);

  static final Map<String, List<double>> presets = {
    'flat': [0.0, 0.0, 0.0, 0.0, 0.0],
    'bass_boost': [6.0, 4.5, 1.0, 0.0, 0.0],
    'bass_treble': [5.0, 2.5, -1.0, 3.0, 5.0],
    'acoustic': [3.5, 2.5, 1.5, 2.0, 2.5],
    'electronic': [4.5, 3.0, 0.0, 2.0, 4.0],
    'rock': [4.5, 2.5, -1.0, 2.5, 4.5],
    'pop': [-1.0, 2.0, 4.0, 2.5, -1.0],
    'classical': [4.0, 2.5, 0.0, 2.5, 4.0],
    'hip_hop': [5.5, 3.5, 0.0, 2.0, 3.5],
    'vocal_booster': [-1.5, 2.5, 5.5, 3.5, 1.0],
    'deep': [5.0, 3.5, 1.0, -1.0, -2.0],
  };

  static Future<void> init() async {
    await Hive.openBox(boxName);

    streamingQualityNotifier.value = _box.get('streaming_quality', defaultValue: '320kbps') as String;
    downloadQualityNotifier.value = _box.get('download_quality', defaultValue: '320kbps') as String;
    volumeNormalizationNotifier.value = _box.get('volume_normalization', defaultValue: true) as bool;
    autoplayNotifier.value = _box.get('autoplay', defaultValue: true) as bool;
    crossfadeDurationNotifier.value = (_box.get('crossfade_seconds', defaultValue: 0) as num).toInt();
    eqPresetNotifier.value = _box.get('eq_preset', defaultValue: 'flat') as String;

    final rawBands = _box.get('eq_bands');
    if (rawBands is List) {
      eqBandsNotifier.value = rawBands.map((e) => (e as num).toDouble()).toList();
    } else {
      eqBandsNotifier.value = presets['flat']!;
    }

    bassBoostNotifier.value = (_box.get('bass_boost_strength', defaultValue: 0.0) as num).toDouble();
    virtualizerNotifier.value = (_box.get('virtualizer_strength', defaultValue: 0.0) as num).toDouble();

    final rawCustomPresets = _box.get('custom_eq_presets');
    if (rawCustomPresets is Map) {
      final parsed = <String, List<double>>{};
      rawCustomPresets.forEach((k, v) {
        if (v is List) {
          parsed[k.toString()] = v.map((e) => (e as num).toDouble()).toList();
        }
      });
      customEqPresetsNotifier.value = parsed;
    }

    final rawLangs = _box.get('languages');
    if (rawLangs is List) {
      languagesNotifier.value = rawLangs.map((e) => e.toString()).toList();
    }

    final savedStrategyStr = _box.get('next_track_strategy', defaultValue: 'spotifyStyle') as String;
    nextTrackStrategyNotifier.value = NextTrackStrategyMode.values.firstWhere(
      (m) => m.name == savedStrategyStr,
      orElse: () => NextTrackStrategyMode.spotifyStyle,
    );
    maxCacheSizeMbNotifier.value = (_box.get('max_cache_size_mb', defaultValue: 500) as num).toInt();
    bluetoothDelayMsNotifier.value = (_box.get('bluetooth_delay_ms', defaultValue: 0) as num).toInt();
    hardwareAudioLatencyMsNotifier.value = (_box.get('hardware_audio_latency_ms', defaultValue: 0) as num).toInt().clamp(-150, 150);
    lyricsPreferredLanguageNotifier.value = _box.get('lyrics_preferred_language', defaultValue: 'default') as String;
    playerGesturesEnabledNotifier.value = _box.get('player_gestures_enabled', defaultValue: true) as bool;
    themeModeNotifier.value = _box.get('theme_mode', defaultValue: 'amoled') as String;
    dynamicBackgroundNotifier.value = _box.get('dynamic_background', defaultValue: true) as bool;
    indicRomanizationNotifier.value = _box.get('indic_romanization', defaultValue: true) as bool;
    keepScreenAwakeNotifier.value = _box.get('keep_screen_awake', defaultValue: false) as bool;
    downloadWifiOnlyNotifier.value = _box.get('download_wifi_only', defaultValue: false) as bool;
    downloadPathNotifier.value = _box.get('download_path', defaultValue: 'Internal Storage') as String;
    homeHeroBannerModeNotifier.value = _box.get('home_hero_banner_mode', defaultValue: 'smart') as String;
    homeTop10ChartLayoutNotifier.value = _box.get('home_top10_chart_layout', defaultValue: 'vertical') as String;
    homeRememberFeelingNotifier.value = _box.get('home_remember_feeling', defaultValue: false) as bool;
    homeShowQuickPicksNotifier.value = _box.get('home_show_quick_picks', defaultValue: true) as bool;
  }

  static Future<void> setThemeMode(String mode) async {
    themeModeNotifier.value = mode;
    await _box.put('theme_mode', mode);
  }

  static Future<void> setDynamicBackground(bool enabled) async {
    dynamicBackgroundNotifier.value = enabled;
    await _box.put('dynamic_background', enabled);
  }

  static Future<void> setIndicRomanization(bool enabled) async {
    indicRomanizationNotifier.value = enabled;
    await _box.put('indic_romanization', enabled);
  }

  static Future<void> setKeepScreenAwake(bool enabled) async {
    keepScreenAwakeNotifier.value = enabled;
    await _box.put('keep_screen_awake', enabled);
  }

  static Future<void> setDownloadWifiOnly(bool enabled) async {
    downloadWifiOnlyNotifier.value = enabled;
    await _box.put('download_wifi_only', enabled);
  }

  static Future<void> setDownloadPath(String path) async {
    downloadPathNotifier.value = path;
    await _box.put('download_path', path);
  }

  static Future<void> setHomeHeroBannerMode(String mode) async {
    homeHeroBannerModeNotifier.value = mode;
    await _box.put('home_hero_banner_mode', mode);
  }

  static Future<void> setHomeTop10ChartLayout(String layout) async {
    homeTop10ChartLayoutNotifier.value = layout;
    await _box.put('home_top10_chart_layout', layout);
  }

  static Future<void> setHomeRememberFeeling(bool enabled) async {
    homeRememberFeelingNotifier.value = enabled;
    await _box.put('home_remember_feeling', enabled);
  }

  static Future<void> setHomeShowQuickPicks(bool enabled) async {
    homeShowQuickPicksNotifier.value = enabled;
    await _box.put('home_show_quick_picks', enabled);
  }

  static Future<void> setLyricsPreferredLanguage(String lang) async {
    lyricsPreferredLanguageNotifier.value = lang;
    await _box.put('lyrics_preferred_language', lang);
  }

  static Future<void> setPlayerGesturesEnabled(bool enabled) async {
    playerGesturesEnabledNotifier.value = enabled;
    await _box.put('player_gestures_enabled', enabled);
  }

  static Future<void> setBluetoothDelayMs(int ms) async {
    final clamped = ms.clamp(-500, 500);
    bluetoothDelayMsNotifier.value = clamped;
    await _box.put('bluetooth_delay_ms', clamped);
  }

  static Future<void> setHardwareAudioLatencyMs(int ms) async {
    final clamped = ms.clamp(-150, 150);
    hardwareAudioLatencyMsNotifier.value = clamped;
    await _box.put('hardware_audio_latency_ms', clamped);
  }

  static Future<void> setMaxCacheSizeMb(int mb) async {
    maxCacheSizeMbNotifier.value = mb;
    await _box.put('max_cache_size_mb', mb);
  }

  static Future<void> setNextTrackStrategy(NextTrackStrategyMode mode) async {
    nextTrackStrategyNotifier.value = mode;
    await _box.put('next_track_strategy', mode.name);
  }

  static Future<void> setStreamingQuality(String quality) async {
    streamingQualityNotifier.value = quality;
    await _box.put('streaming_quality', quality);
  }

  static Future<void> setDownloadQuality(String quality) async {
    downloadQualityNotifier.value = quality;
    await _box.put('download_quality', quality);
  }

  static Future<void> setVolumeNormalization(bool enabled) async {
    volumeNormalizationNotifier.value = enabled;
    await _box.put('volume_normalization', enabled);
  }

  static Future<void> setAutoplay(bool enabled) async {
    autoplayNotifier.value = enabled;
    await _box.put('autoplay', enabled);
  }

  static Future<void> setCrossfadeSeconds(int seconds) async {
    final clamped = seconds.clamp(0, 12);
    crossfadeDurationNotifier.value = clamped;
    await _box.put('crossfade_seconds', clamped);
  }

  static Future<void> setEqPreset(String presetKey) async {
    if (presets.containsKey(presetKey)) {
      eqPresetNotifier.value = presetKey;
      eqBandsNotifier.value = List<double>.from(presets[presetKey]!);
      await _box.put('eq_preset', presetKey);
      await _box.put('eq_bands', eqBandsNotifier.value);
    } else if (presetKey.startsWith('custom_')) {
      final name = presetKey.substring(7);
      await applyCustomEqPreset(name);
    }
  }

  static Future<void> setEqBand(int index, double gain) async {
    if (index >= 0 && index < eqBandsNotifier.value.length) {
      final updated = List<double>.from(eqBandsNotifier.value);
      updated[index] = gain.clamp(-10.0, 10.0);
      eqBandsNotifier.value = updated;
      eqPresetNotifier.value = 'custom';
      await _box.put('eq_preset', 'custom');
      await _box.put('eq_bands', updated);
    }
  }

  static Future<void> setBassBoost(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    bassBoostNotifier.value = clamped;
    await _box.put('bass_boost_strength', clamped);
  }

  static Future<void> setVirtualizer(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    virtualizerNotifier.value = clamped;
    await _box.put('virtualizer_strength', clamped);
  }

  static Future<void> applyCustomEqPreset(String name) async {
    final currentCustom = customEqPresetsNotifier.value;
    if (currentCustom.containsKey(name)) {
      final bands = List<double>.from(currentCustom[name]!);
      eqPresetNotifier.value = 'custom_$name';
      eqBandsNotifier.value = bands;
      await _box.put('eq_preset', 'custom_$name');
      await _box.put('eq_bands', bands);
    }
  }

  static Future<void> saveCustomEqPreset(String name, List<double> bands) async {
    final updated = Map<String, List<double>>.from(customEqPresetsNotifier.value);
    updated[name] = List<double>.from(bands);
    customEqPresetsNotifier.value = updated;
    await _box.put('custom_eq_presets', updated);
    await applyCustomEqPreset(name);
  }

  static Future<void> deleteCustomEqPreset(String name) async {
    final updated = Map<String, List<double>>.from(customEqPresetsNotifier.value);
    updated.remove(name);
    customEqPresetsNotifier.value = updated;
    await _box.put('custom_eq_presets', updated);
    if (eqPresetNotifier.value == 'custom_$name') {
      await setEqPreset('flat');
    }
  }

  static Future<void> setPreferredLanguages(List<String> langs) async {
    languagesNotifier.value = List<String>.from(langs);
    await _box.put('languages', langs);
    // Coordinated sync to AuthManager and Supabase
    await AuthManager.updateLanguagePreferences(langs);
  }
}
