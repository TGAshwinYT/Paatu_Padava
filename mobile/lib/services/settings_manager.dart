import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'auth_manager.dart';

enum NextTrackStrategyMode {
  spotifyStyle,
  ytMusicStyle,
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
  static final ValueNotifier<List<String>> languagesNotifier = ValueNotifier<List<String>>(['Tamil', 'English']);
  static final ValueNotifier<NextTrackStrategyMode> nextTrackStrategyNotifier =
      ValueNotifier<NextTrackStrategyMode>(NextTrackStrategyMode.spotifyStyle);
  static final ValueNotifier<int> maxCacheSizeMbNotifier = ValueNotifier<int>(500);
  static final ValueNotifier<int> bluetoothDelayMsNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<String> lyricsPreferredLanguageNotifier = ValueNotifier<String>('default');
  static final ValueNotifier<bool> playerGesturesEnabledNotifier = ValueNotifier<bool>(true);

  static String get streamingQuality => streamingQualityNotifier.value;
  static String get downloadQuality => downloadQualityNotifier.value;
  static bool get isVolumeNormalizationEnabled => volumeNormalizationNotifier.value;
  static bool get isAutoplayEnabled => autoplayNotifier.value;
  static int get crossfadeSeconds => crossfadeDurationNotifier.value;
  static String get eqPreset => eqPresetNotifier.value;
  static List<double> get eqBands => eqBandsNotifier.value;
  static NextTrackStrategyMode get nextTrackStrategy => nextTrackStrategyNotifier.value;
  static int get maxCacheSizeMb => maxCacheSizeMbNotifier.value;
  static int get bluetoothDelayMs => bluetoothDelayMsNotifier.value;
  static String get lyricsPreferredLanguage => lyricsPreferredLanguageNotifier.value;
  static bool get isPlayerGesturesEnabled => playerGesturesEnabledNotifier.value;

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
    'bass_boost': [5.5, 4.0, 1.0, 0.0, 0.0],
    'vocal': [-1.0, 2.0, 4.5, 3.0, 1.0],
    'rock': [4.0, 2.0, -1.0, 2.5, 4.0],
    'pop': [-1.0, 1.5, 3.5, 2.0, -1.0],
    'classical': [3.0, 2.0, 0.0, 2.5, 3.5],
    'electronic': [4.5, 3.0, 0.0, 2.0, 4.0],
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
    lyricsPreferredLanguageNotifier.value = _box.get('lyrics_preferred_language', defaultValue: 'default') as String;
    playerGesturesEnabledNotifier.value = _box.get('player_gestures_enabled', defaultValue: true) as bool;
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

  static Future<void> setPreferredLanguages(List<String> langs) async {
    languagesNotifier.value = List<String>.from(langs);
    await _box.put('languages', langs);
    // Coordinated sync to AuthManager and Supabase
    await AuthManager.updateLanguagePreferences(langs);
  }
}
