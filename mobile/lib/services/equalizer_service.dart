import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../platform/audio_platform.dart';
import 'settings_manager.dart';

import 'package:paatu_padava_mobile/services/app_logger.dart';

class EqualizerService {
  static const MethodChannel _channel = MethodChannel('com.tamilgaming.paatupadava/equalizer');

  static int? _activeSessionId;
  static StreamSubscription<int?>? _sessionSub;
  static bool _isBound = false;
  static bool _isDspAvailable = false;
  static int _hardwareBandCount = 5;

  static int? get activeSessionId => _activeSessionId;
  static bool get isBound => _isBound;
  static bool get isDspAvailable => _isDspAvailable;
  static int get hardwareBandCount => _hardwareBandCount;
  static final ValueNotifier<bool> isDspActiveNotifier = ValueNotifier<bool>(false);

  static double _vocalAttenuation = 0.0;
  static double get vocalAttenuation => _vocalAttenuation;
  static Timer? _throttleTimer;
  static Timer? _vocalIpcThrottleTimer;
  static double? _pendingVocalDspValue;

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

  static int? _lastBoundSessionId;

  /// Sets the native AudioSessionId
  static Future<void> setAudioSessionId(int? sessionId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (sessionId == null || sessionId == 0) {
      _activeSessionId = null;
      _lastBoundSessionId = null;
      _isBound = false;
      return;
    }
    if (_lastBoundSessionId == sessionId && _isBound) return;
    _lastBoundSessionId = sessionId;

    try {
      _activeSessionId = sessionId;
      await _channel.invokeMethod('setAudioSessionId', {'sessionId': sessionId});
      _isBound = true;
      final results = await Future.wait([
        AudioPlatform.getDspStatus(),
        AudioPlatform.getBandCount(),
      ]);
      final dspStatus = results[0] as Map<String, dynamic>;
      _isDspAvailable = dspStatus['attached'] == true;
      _hardwareBandCount = results[1] as int;
      debugPrint('[EqualizerService] Bound to Android AudioSession: $sessionId (DSP: $_isDspAvailable, bands: $_hardwareBandCount)');

      if (_isDspAvailable && _vocalAttenuation > 0.0) {
        await AudioPlatform.setVocalCancellation(_vocalAttenuation);
        isDspActiveNotifier.value = true;
      }

      final isNeutral = SettingsManager.bassBoost == 0.0 &&
          SettingsManager.virtualizer == 0.0 &&
          _vocalAttenuation == 0.0 &&
          SettingsManager.eqBands.every((b) => b == 0.0);

      if (!isNeutral) {
        await Future.wait([
          if (SettingsManager.bassBoost > 0.0)
            _channel.invokeMethod('setBassBoostStrength', {'strength': (SettingsManager.bassBoost * 1000).round()}),
          if (SettingsManager.virtualizer > 0.0)
            _channel.invokeMethod('setVirtualizerStrength', {'strength': (SettingsManager.virtualizer * 1000).round()}),
          applyCurrentBands(),
        ]);
      }
    } catch (e) {
      debugPrint('[EqualizerService] setAudioSessionId error: $e');
    }
  }

  static const List<double> referenceFrequencies = [60.0, 230.0, 910.0, 3600.0, 14000.0];

  /// Interpolates a source band gain curve (e.g. 5-band reference) onto N hardware bands
  /// using logarithmic frequency interpolation across the audio spectrum.
  static List<double> interpolateBands(List<double> sourceBands, int targetCount) {
    if (sourceBands.isEmpty) return List.filled(targetCount > 0 ? targetCount : 0, 0.0);
    if (targetCount <= 0) return const [];
    if (sourceBands.length == targetCount) return List<double>.from(sourceBands);
    if (sourceBands.length == 1) return List.filled(targetCount, sourceBands.first);

    final logRef = referenceFrequencies.map((f) => math.log(f) / math.ln10).toList();
    final minLog = logRef.first;
    final maxLog = logRef.last;

    final result = List<double>.filled(targetCount, 0.0);
    for (int i = 0; i < targetCount; i++) {
      final targetLog = targetCount == 1
          ? minLog
          : minLog + (i / (targetCount - 1)) * (maxLog - minLog);

      if (targetLog <= logRef.first) {
        result[i] = sourceBands.first;
      } else if (targetLog >= logRef.last) {
        result[i] = sourceBands.last;
      } else {
        int seg = 0;
        for (int s = 0; s < logRef.length - 1; s++) {
          if (targetLog <= logRef[s + 1]) {
            seg = s;
            break;
          }
        }
        final fraction = (targetLog - logRef[seg]) / (logRef[seg + 1] - logRef[seg]);
        final gainA = seg < sourceBands.length ? sourceBands[seg] : sourceBands.last;
        final gainB = (seg + 1) < sourceBands.length ? sourceBands[seg + 1] : sourceBands.last;
        result[i] = gainA + fraction * (gainB - gainA);
      }
    }
    return result;
  }

  /// Calculates effective acoustic frequency bands (-10.0 to +10.0 dB) incorporating
  /// baseline EQ, bass boost (+0..5 dB), 3D virtualizer, and vocal notch filtering.
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

      // 3. Real-time vocal formant notch attenuation with dynamic loudness compensation
      if (vocalAttenuation > 0.0) {
        final clampedVocal = vocalAttenuation.clamp(0.0, 1.0);
        // Band 2 (~910 Hz): Core vocal formant notch
        effectiveBands[2] = (effectiveBands[2] - (clampedVocal * 8.0)).clamp(-10.0, 10.0);
        // Band 3 (~3.6 kHz): Vocal presence and consonant friction notch
        effectiveBands[3] = (effectiveBands[3] - (clampedVocal * 5.0)).clamp(-10.0, 10.0);
        // Band 1 (~230 Hz): Lower chest resonance attenuation (subtle to preserve rhythm chords)
        effectiveBands[1] = (effectiveBands[1] - (clampedVocal * 2.0)).clamp(-10.0, 10.0);
        // Band 0 (~60 Hz): Sub-bass / kick compensation to maintain rhythm power
        effectiveBands[0] = (effectiveBands[0] + (clampedVocal * 3.5)).clamp(-10.0, 10.0);
        // Band 4 (~14 kHz): Air & shimmer preservation
        effectiveBands[4] = (effectiveBands[4] + (clampedVocal * 2.5)).clamp(-10.0, 10.0);
      }
    }
    return effectiveBands;
  }

  /// Refreshes DSP availability and re-applies vocal cancellation if active.
  static Future<bool> refreshDspStatus() async {
    final status = await AudioPlatform.getDspStatus();
    _isDspAvailable = status['attached'] == true;
    if (_isDspAvailable && _vocalAttenuation > 0.0) {
      await AudioPlatform.setVocalCancellation(_vocalAttenuation);
      isDspActiveNotifier.value = true;
    } else {
      isDspActiveNotifier.value = false;
    }
    return _isDspAvailable;
  }

  /// Sets the vocal attenuation factor (0.0 = full vocals, 1.0 = full karaoke / vocal suppression).
  /// If native DSP center-channel cancellation is available, routes directly to AudioPlatform
  /// with 30ms throttling and trailing send, preserving clean baseline graphic EQ.
  /// Otherwise, falls back to graphic EQ formant notch attenuation.
  static Future<void> setVocalAttenuation(double factor) async {
    final clamped = factor.clamp(0.0, 1.0);
    _vocalAttenuation = clamped;

    if (_isDspAvailable) {
      isDspActiveNotifier.value = clamped > 0.0;
      if (clamped == 0.0 || clamped == 1.0) {
        _vocalIpcThrottleTimer?.cancel();
        _vocalIpcThrottleTimer = null;
        _pendingVocalDspValue = null;
        await AudioPlatform.setVocalCancellation(clamped);
        return;
      }
      _pendingVocalDspValue = clamped;
      if (_vocalIpcThrottleTimer?.isActive == true) return;
      _vocalIpcThrottleTimer = Timer(const Duration(milliseconds: 30), () {
        final val = _pendingVocalDspValue ?? clamped;
        _pendingVocalDspValue = null;
        AudioPlatform.setVocalCancellation(val);
      });
      return;
    }

    await refreshDspStatus();
    if (_isDspAvailable) {
      isDspActiveNotifier.value = clamped > 0.0;
      await AudioPlatform.setVocalCancellation(clamped);
      return;
    }

    isDspActiveNotifier.value = false;
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

  /// Converts dB gains (-10.0 to +10.0 dB) to millibels (-1000 to +1000 mB) and sends to native.
  /// When native DSP is active, preserves clean baseline EQ without artificial mid scoops.
  static Future<void> applyCurrentBands() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_activeSessionId == null || _activeSessionId == 0) return;
    try {
      final baseBands = SettingsManager.eqBands;
      final isDsp = isDspActiveNotifier.value;
      final bassBoostRatio = isDsp
          ? SettingsManager.bassBoost
          : (SettingsManager.bassBoost + (_vocalAttenuation * 0.25)).clamp(0.0, 1.0);
      final virtualizerRatio = isDsp
          ? SettingsManager.virtualizer
          : (SettingsManager.virtualizer + (_vocalAttenuation * 0.40)).clamp(0.0, 1.0);
      final effectiveVocalAttenuation = isDsp ? 0.0 : _vocalAttenuation;

      final effectiveBands = calculateEffectiveBands(
        baseBands: baseBands,
        bassBoost: bassBoostRatio,
        virtualizer: virtualizerRatio,
        vocalAttenuation: effectiveVocalAttenuation,
      );

      // Logarithmically interpolate effective bands to hardware band count
      final interpolated = interpolateBands(effectiveBands, _hardwareBandCount);
      // Convert dB to millibels (1 dB = 100 mB)
      final targetBands = interpolated.map((dB) => (dB * 100).round()).toList();
      await _channel.invokeMethod('setAllBands', {'levels': targetBands});
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
    _vocalIpcThrottleTimer?.cancel();
    _vocalIpcThrottleTimer = null;
    _pendingVocalDspValue = null;
    _vocalAttenuation = 0.0;
    _isDspAvailable = false;
    isDspActiveNotifier.value = false;
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
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        _channel.invokeMethod('release').catchError((_) => null);
      } catch (e) {
      AppLogger.debug('EqualizerService', 'Handled exception: $e');
    }
    }
  }
}
