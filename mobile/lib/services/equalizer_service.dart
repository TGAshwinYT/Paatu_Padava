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
  static void bindToPlayerSession(Stream<int?> sessionIdStream) {
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
      await applyCurrentBands();
      await applyBassBoost();
      await applyVirtualizer();
    } catch (e) {
      debugPrint('[EqualizerService] setAudioSessionId error: $e');
    }
  }

  /// Converts dB gains (-10.0 to +10.0 dB) to millibels (-1000 to +1000 mB) and sends to native
  static Future<void> applyCurrentBands() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final bands = SettingsManager.eqBands;
      // Convert dB to millibels (1 dB = 100 mB)
      final millibels = bands.map((dB) => (dB * 100).round()).toList();
      await _channel.invokeMethod('setAllBands', {'levels': millibels});
    } catch (e) {
      debugPrint('[EqualizerService] applyCurrentBands error: $e');
    }
  }

  /// Sends bass boost strength (0 to 1000) to native DSP
  static Future<void> applyBassBoost() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final strength = (SettingsManager.bassBoost * 1000).round();
      await _channel.invokeMethod('setBassBoostStrength', {'strength': strength});
    } catch (e) {
      debugPrint('[EqualizerService] applyBassBoost error: $e');
    }
  }

  /// Sends virtualizer strength (0 to 1000) to native DSP
  static Future<void> applyVirtualizer() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final strength = (SettingsManager.virtualizer * 1000).round();
      await _channel.invokeMethod('setVirtualizerStrength', {'strength': strength});
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
