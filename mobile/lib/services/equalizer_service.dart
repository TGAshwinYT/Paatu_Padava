import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'settings_manager.dart';

class EqualizerService {
  static const MethodChannel _channel = MethodChannel('com.tamilgaming.paatupadava/equalizer');

  static int? _activeSessionId;
  static StreamSubscription<int?>? _sessionSub;
  static bool _isBound = false;

  static int? get activeSessionId => _activeSessionId;
  static bool get isBound => _isBound;

  static double _vocalAttenuation = 0.0;
  static double get vocalAttenuation => _vocalAttenuation;
  static Timer? _throttleTimer;

  static VoidCallback? _eqBandsListener;
  static VoidCallback? _bassBoostListener;
  static VoidCallback? _virtualizerListener;

  /// Initializes equalizer service and binds to the player's Android Audio Session ID.
  /// Documented as an app-lifetime singleton tied to the active audio player session.
  static void bindToPlayerSession(Stream<int?> sessionIdStream, {int? initialSessionId}) {
    if (initialSessionId != null && initialSessionId != 0 && initialSessionId != _activeSessionId) {
      _activeSessionId = initialSessionId;
      setAudioSessionId(initialSessionId);
    }

    _sessionSub?.cancel();
    _sessionSub = sessionIdStream.listen((sessionId) {
      if (sessionId != null && sessionId != 0 && sessionId != _activeSessionId) {
        _activeSessionId = sessionId;
        setAudioSessionId(sessionId);
      }
    });

    if (_eqBandsListener == null) {
      _eqBandsListener = () {
        applyCurrentBands();
      };
      SettingsManager.eqBandsNotifier.addListener(_eqBandsListener!);
    }

    if (_bassBoostListener == null) {
      _bassBoostListener = () {
        applyBassBoost();
      };
      SettingsManager.bassBoostNotifier.addListener(_bassBoostListener!);
    }

    if (_virtualizerListener == null) {
      _virtualizerListener = () {
        applyVirtualizer();
      };
      SettingsManager.virtualizerNotifier.addListener(_virtualizerListener!);
    }
  }

  /// Sets the native AudioSessionId
  static Future<void> setAudioSessionId(int? sessionId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (sessionId == null || sessionId == 0) {
      _activeSessionId = null;
      _isBound = false;
      return;
    }
    try {
      _activeSessionId = sessionId;
      await _channel.invokeMethod('setAudioSessionId', {'sessionId': sessionId});
      _isBound = true;
      debugPrint('[EqualizerService] Successfully bound to Android AudioSession: $sessionId');
      // Apply existing saved bands and effects immediately
      await applyBassBoost();
      await applyVirtualizer();
      await applyCurrentBands();
    } catch (e) {
      debugPrint('[EqualizerService] setAudioSessionId error: $e');
    }
  }

  /// Calculates effective acoustic frequency bands (-10.0 to +10.0 dB)
  /// Incorporates:
  /// 1. User baseline equalizer band settings
  /// 2. Bass Boost dynamic punch (+0 to +5 dB on 60Hz, +0 to +3 dB on 230Hz)
  /// 3. 3D Spatial virtualizer (+0 to +2.5 dB on 3.6kHz, +0 to +3.5 dB on 14kHz)
  /// 4. Real-time Apple Music Sing-inspired vocal formant notch filtering:
  ///    - Band 2 (910 Hz): Core vocal formant notch (up to -12 dB)
  ///    - Band 3 (3.6 kHz): Consonant & presence notch (up to -8 dB)
  ///    - Band 1 (230 Hz): Lower chest voice resonance attenuation (up to -4 dB)
  ///    - Band 0 (60 Hz): Sub-bass / kick punch compensation (+2 dB) to maintain rhythm drive
  ///    - Band 4 (14 kHz): Air / shimmer preservation (+1.5 dB)
  static List<double> calculateEffectiveBands({
    required List<double> baseBands,
    double bassBoost = 0.0,
    double virtualizer = 0.0,
    double vocalAttenuation = 0.0,
  }) {
    final effectiveBands = List<double>.from(baseBands);
    if (effectiveBands.length >= 5) {
      // 1. Bass boost acoustic curve
      effectiveBands[0] = (effectiveBands[0] + (bassBoost * 5.0)).clamp(-10.0, 10.0);
      effectiveBands[1] = (effectiveBands[1] + (bassBoost * 3.0)).clamp(-10.0, 10.0);

      // 2. Spatial virtualizer presence
      effectiveBands[3] = (effectiveBands[3] + (virtualizer * 2.5)).clamp(-10.0, 10.0);
      effectiveBands[4] = (effectiveBands[4] + (virtualizer * 3.5)).clamp(-10.0, 10.0);

      // 3. Real-time vocal formant notch attenuation
      if (vocalAttenuation > 0.0) {
        final clampedVocal = vocalAttenuation.clamp(0.0, 1.0);
        // Band 2 (~910 Hz): Core vocal formant notch
        effectiveBands[2] = (effectiveBands[2] - (clampedVocal * 12.0)).clamp(-10.0, 10.0);
        // Band 3 (~3.6 kHz): Vocal presence and consonant friction notch
        effectiveBands[3] = (effectiveBands[3] - (clampedVocal * 8.0)).clamp(-10.0, 10.0);
        // Band 1 (~230 Hz): Lower chest resonance attenuation
        effectiveBands[1] = (effectiveBands[1] - (clampedVocal * 4.0)).clamp(-10.0, 10.0);
        // Band 0 (~60 Hz): Sub-bass / kick compensation to maintain rhythm power
        effectiveBands[0] = (effectiveBands[0] + (clampedVocal * 2.0)).clamp(-10.0, 10.0);
        // Band 4 (~14 kHz): Air & shimmer preservation
        effectiveBands[4] = (effectiveBands[4] + (clampedVocal * 1.5)).clamp(-10.0, 10.0);
      }
    }
    return effectiveBands;
  }

  /// Sets the vocal attenuation factor (0.0 = full vocals, 1.0 = full karaoke / vocal suppression)
  /// Throttles native IPC to ~60fps to prevent audio stutter during rapid finger drag.
  static Future<void> setVocalAttenuation(double factor) async {
    final clamped = factor.clamp(0.0, 1.0);
    _vocalAttenuation = clamped;
    if (clamped == 0.0 || clamped == 1.0) {
      _throttleTimer?.cancel();
      await applyCurrentBands();
      return;
    }
    if (_throttleTimer?.isActive == true) return;
    _throttleTimer = Timer(const Duration(milliseconds: 16), () {
      applyCurrentBands();
    });
  }

  /// Converts dB gains (-10.0 to +10.0 dB) to millibels (-1000 to +1000 mB) and sends to native
  /// Incorporates acoustic frequency enhancement so Bass Boost, 3D Spatial, and Vocal Attenuation are audible
  static Future<void> applyCurrentBands() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final baseBands = SettingsManager.eqBands;
      final bassBoostRatio = SettingsManager.bassBoost; // 0.0 to 1.0
      final virtualizerRatio = SettingsManager.virtualizer; // 0.0 to 1.0
      final effectiveBands = calculateEffectiveBands(
        baseBands: baseBands,
        bassBoost: bassBoostRatio,
        virtualizer: virtualizerRatio,
        vocalAttenuation: _vocalAttenuation,
      );

      // Convert dB to millibels (1 dB = 100 mB)
      final millibels = effectiveBands.map((dB) => (dB * 100).round()).toList();
      await _channel.invokeMethod('setAllBands', {'levels': millibels});
    } catch (e) {
      debugPrint('[EqualizerService] applyCurrentBands error: $e');
    }
  }

  /// Sends bass boost strength (0 to 1000) to native DSP and updates acoustic warmth
  static Future<void> applyBassBoost() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final strength = (SettingsManager.bassBoost * 1000).round();
      await _channel.invokeMethod('setBassBoostStrength', {'strength': strength});
      await applyCurrentBands();
    } catch (e) {
      debugPrint('[EqualizerService] applyBassBoost error: $e');
    }
  }

  /// Sends virtualizer strength (0 to 1000) to native DSP and updates acoustic stage
  static Future<void> applyVirtualizer() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final strength = (SettingsManager.virtualizer * 1000).round();
      await _channel.invokeMethod('setVirtualizerStrength', {'strength': strength});
      await applyCurrentBands();
    } catch (e) {
      debugPrint('[EqualizerService] applyVirtualizer error: $e');
    }
  }

  /// Sets bass boost level (0.0 to 1.0)
  static Future<void> setBassBoost(double value) async {
    await SettingsManager.setBassBoost(value);
    await applyBassBoost();
  }

  /// Sets virtualizer / spatial audio simulation level (0.0 to 1.0)
  static Future<void> setVirtualizer(double value) async {
    await SettingsManager.setVirtualizer(value);
    await applyVirtualizer();
  }

  /// Sets a single band gain
  static Future<void> setBandLevel(int bandIndex, double gainDb) async {
    SettingsManager.setEqBand(bandIndex, gainDb);
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final millibels = (gainDb * 100).round();
      await _channel.invokeMethod('setBandLevel', {'band': bandIndex, 'level': millibels});
    } catch (e) {
      debugPrint('[EqualizerService] setBandLevel error: $e');
    }
  }

  /// Sets a preset and applies all band levels to native DSP
  static Future<void> setPreset(String presetKey) async {
    SettingsManager.setEqPreset(presetKey);
    await applyCurrentBands();
  }

  /// Opens native Android system equalizer panel if available
  static Future<bool> openSystemEqualizer() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    if (_activeSessionId == null || _activeSessionId == 0) return false;
    try {
      final bool? success = await _channel.invokeMethod('openSystemEqualizer', {
        'sessionId': _activeSessionId,
      });
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Disposes listeners
  static void dispose() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _vocalAttenuation = 0.0;
    _sessionSub?.cancel();
    _sessionSub = null;
    if (_eqBandsListener != null) {
      SettingsManager.eqBandsNotifier.removeListener(_eqBandsListener!);
      _eqBandsListener = null;
    }
    if (_bassBoostListener != null) {
      SettingsManager.bassBoostNotifier.removeListener(_bassBoostListener!);
      _bassBoostListener = null;
    }
    if (_virtualizerListener != null) {
      SettingsManager.virtualizerNotifier.removeListener(_virtualizerListener!);
      _virtualizerListener = null;
    }
    try {
      _channel.invokeMethod('release');
    } catch (_) {}
  }
}
