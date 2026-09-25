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

  /// Initializes equalizer service and binds to the player's Android Audio Session ID
  static void bindToPlayerSession(Stream<int?> sessionIdStream) {
    _sessionSub?.cancel();
    _sessionSub = sessionIdStream.listen((sessionId) {
      if (sessionId != null && sessionId != 0 && sessionId != _activeSessionId) {
        _activeSessionId = sessionId;
        setAudioSessionId(sessionId);
      }
    });

    // Listen to SettingsManager band changes and propagate to native equalizer
    SettingsManager.eqBandsNotifier.addListener(() {
      applyCurrentBands();
    });
  }

  /// Sets the native AudioSessionId
  static Future<void> setAudioSessionId(int sessionId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _activeSessionId = sessionId;
      await _channel.invokeMethod('setAudioSessionId', {'sessionId': sessionId});
      _isBound = true;
      debugPrint('[EqualizerService] Successfully bound to Android AudioSession: $sessionId');
      // Apply existing saved bands immediately
      await applyCurrentBands();
    } catch (e) {
      debugPrint('[EqualizerService] setAudioSessionId error: $e');
    }
  }

  /// Converts dB gains (-10.0 to +10.0 dB) to millibels (-1000 to +1000 mB) and sends to native
  static Future<void> applyCurrentBands() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final bands = SettingsManager.eqBands;
      // Convert dB to millibels (1 dB = 100 mB)
      final millibels = bands.map((dB) => (dB * 100).round()).toList();
      await _channel.invokeMethod('setAllBands', {'levels': millibels});
    } catch (e) {
      debugPrint('[EqualizerService] applyCurrentBands error: $e');
    }
  }

  /// Sets a single band gain
  static Future<void> setBandLevel(int bandIndex, double gainDb) async {
    SettingsManager.setEqBand(bandIndex, gainDb);
    if (defaultTargetPlatform != TargetPlatform.android) return;
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
    try {
      final bool? success = await _channel.invokeMethod('openSystemEqualizer', {
        'sessionId': _activeSessionId ?? 0,
      });
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Disposes listeners
  static void dispose() {
    _sessionSub?.cancel();
    try {
      _channel.invokeMethod('release');
    } catch (_) {}
  }
}
