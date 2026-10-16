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

  /// Converts dB gains (-10.0 to +10.0 dB) to millibels (-1000 to +1000 mB) and sends to native
  /// Incorporates acoustic frequency enhancement so Bass Boost & 3D Spatial are audible on all outputs
  static Future<void> applyCurrentBands() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final baseBands = SettingsManager.eqBands;
      final bassBoostRatio = SettingsManager.bassBoost; // 0.0 to 1.0
      final virtualizerRatio = SettingsManager.virtualizer; // 0.0 to 1.0

      // Combined acoustic curve:
      // Band 0 (60 Hz Sub-bass): +0 to +5 dB proportional to Bass Boost
      // Band 1 (230 Hz Punch): +0 to +3 dB proportional to Bass Boost
      // Band 3 (3.6 kHz Presence): +0 to +2.5 dB proportional to 3D Spatial
      // Band 4 (14 kHz Air/Treble): +0 to +3.5 dB proportional to 3D Spatial
      final effectiveBands = List<double>.from(baseBands);
      if (effectiveBands.length >= 5) {
        effectiveBands[0] = (effectiveBands[0] + (bassBoostRatio * 5.0)).clamp(-10.0, 10.0);
        effectiveBands[1] = (effectiveBands[1] + (bassBoostRatio * 3.0)).clamp(-10.0, 10.0);
        effectiveBands[3] = (effectiveBands[3] + (virtualizerRatio * 2.5)).clamp(-10.0, 10.0);
        effectiveBands[4] = (effectiveBands[4] + (virtualizerRatio * 3.5)).clamp(-10.0, 10.0);
      }

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
