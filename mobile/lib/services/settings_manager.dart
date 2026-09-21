import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SettingsManager {
  static const String boxName = 'settings_box';

  static final ValueNotifier<String> streamingQualityNotifier = ValueNotifier<String>('320kbps');
  static final ValueNotifier<String> downloadQualityNotifier = ValueNotifier<String>('320kbps');
  static final ValueNotifier<String> eqPresetNotifier = ValueNotifier<String>('flat');
  static final ValueNotifier<List<double>> eqBandsNotifier = ValueNotifier<List<double>>([0.0, 0.0, 0.0, 0.0, 0.0]);
  static final ValueNotifier<List<String>> languagesNotifier = ValueNotifier<List<String>>(['Tamil', 'Hindi', 'English', 'Telugu']);

  static String get streamingQuality => streamingQualityNotifier.value;
  static String get downloadQuality => downloadQualityNotifier.value;
  static String get eqPreset => eqPresetNotifier.value;
  static List<double> get eqBands => eqBandsNotifier.value;
  static List<String> get preferredLanguages => languagesNotifier.value;

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
  }

  static Future<void> setStreamingQuality(String quality) async {
    streamingQualityNotifier.value = quality;
    await _box.put('streaming_quality', quality);
  }

  static Future<void> setDownloadQuality(String quality) async {
    downloadQualityNotifier.value = quality;
    await _box.put('download_quality', quality);
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
  }
}
