part of 'settings_manager.dart';

void _initEqFromBoxImpl(Box box) {
  SettingsManager.eqPresetNotifier.value = box.get('eq_preset', defaultValue: 'flat') as String;

  final rawBands = box.get('eq_bands');
  if (rawBands is List) {
    SettingsManager.eqBandsNotifier.value =
        rawBands.map((e) => (e as num).toDouble().clamp(-10.0, 10.0)).toList();
  } else {
    SettingsManager.eqBandsNotifier.value = SettingsManager.presets['flat']!;
  }

  SettingsManager.bassBoostNotifier.value =
      (box.get('bass_boost_strength', defaultValue: 0.0) as num).toDouble().clamp(0.0, 1.0);
  SettingsManager.virtualizerNotifier.value =
      (box.get('virtualizer_strength', defaultValue: 0.0) as num).toDouble().clamp(0.0, 1.0);

  final rawCustomPresets = box.get('custom_eq_presets');
  if (rawCustomPresets is Map) {
    final parsed = <String, List<double>>{};
    rawCustomPresets.forEach((k, v) {
      if (v is List) {
        parsed[k.toString()] = v.map((e) => (e as num).toDouble().clamp(-10.0, 10.0)).toList();
      }
    });
    SettingsManager.customEqPresetsNotifier.value = parsed;
  }

  SettingsManager.stereoBalanceNotifier.value =
      ((box.get('stereo_balance', defaultValue: 0.0) as num).toDouble()).clamp(-1.0, 1.0);
}

Future<void> _setStereoBalanceImpl(double balance) async {
  final clamped = balance.clamp(-1.0, 1.0);
  SettingsManager.stereoBalanceNotifier.value = clamped;
  await SettingsManager._box.put('stereo_balance', clamped);
}

Future<void> _setEqPresetImpl(String presetKey) async {
  if (SettingsManager.presets.containsKey(presetKey)) {
    SettingsManager.eqPresetNotifier.value = presetKey;
    SettingsManager.eqBandsNotifier.value = List<double>.from(SettingsManager.presets[presetKey]!);
    await SettingsManager._box.put('eq_preset', presetKey);
    await SettingsManager._box.put('eq_bands', SettingsManager.eqBandsNotifier.value);
  } else if (presetKey.startsWith('custom_')) {
    final name = presetKey.substring(7);
    await _applyCustomEqPresetImpl(name);
  }
}

Future<void> _setEqBandImpl(int index, double gain) async {
  if (index >= 0 && index < SettingsManager.eqBandsNotifier.value.length) {
    final updated = List<double>.from(SettingsManager.eqBandsNotifier.value);
    updated[index] = gain.clamp(-10.0, 10.0);
    SettingsManager.eqBandsNotifier.value = updated;
    SettingsManager.eqPresetNotifier.value = 'custom';
    await SettingsManager._box.put('eq_preset', 'custom');
    await SettingsManager._box.put('eq_bands', updated);
  }
}

Future<void> _setBassBoostImpl(double value) async {
  final clamped = value.clamp(0.0, 1.0);
  SettingsManager.bassBoostNotifier.value = clamped;
  await SettingsManager._box.put('bass_boost_strength', clamped);
}

Future<void> _setVirtualizerImpl(double value) async {
  final clamped = value.clamp(0.0, 1.0);
  SettingsManager.virtualizerNotifier.value = clamped;
  await SettingsManager._box.put('virtualizer_strength', clamped);
}

Future<void> _applyCustomEqPresetImpl(String name) async {
  final currentCustom = SettingsManager.customEqPresetsNotifier.value;
  if (currentCustom.containsKey(name)) {
    final bands = List<double>.from(currentCustom[name]!);
    SettingsManager.eqPresetNotifier.value = 'custom_$name';
    SettingsManager.eqBandsNotifier.value = bands;
    await SettingsManager._box.put('eq_preset', 'custom_$name');
    await SettingsManager._box.put('eq_bands', bands);
  }
}

Future<void> _saveCustomEqPresetImpl(String name, List<double> bands) async {
  final updated = Map<String, List<double>>.from(SettingsManager.customEqPresetsNotifier.value);
  updated[name] = List<double>.from(bands);
  SettingsManager.customEqPresetsNotifier.value = updated;
  await SettingsManager._box.put('custom_eq_presets', updated);
  await _applyCustomEqPresetImpl(name);
}

Future<void> _deleteCustomEqPresetImpl(String name) async {
  final updated = Map<String, List<double>>.from(SettingsManager.customEqPresetsNotifier.value);
  updated.remove(name);
  SettingsManager.customEqPresetsNotifier.value = updated;
  await SettingsManager._box.put('custom_eq_presets', updated);
  if (SettingsManager.eqPresetNotifier.value == 'custom_$name') {
    await _setEqPresetImpl('flat');
  }
}
