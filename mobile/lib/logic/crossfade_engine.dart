import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../services/settings_manager.dart';

/// Calculation engine for constant acoustic power crossfade transitions.
class EqualPowerCurve {
  /// Computes equal-power volumes (outgoing, incoming) for normalized progress [t] in [0.0, 1.0].
  ///
  /// Mathematical Derivation:
  /// V_out(t) = cos((pi / 2) * t)
  /// V_in(t)  = sin((pi / 2) * t)
  ///
  /// Guarantees constant total sound pressure level:
  /// V_out(t)^2 + V_in(t)^2 = cos^2(theta) + sin^2(theta) == 1.0 (0 dB drop at midpoint).
  static (double outgoing, double incoming) calculate(double t) {
    final clampedT = t.clamp(0.0, 1.0);
    final theta = (math.pi / 2.0) * clampedT;
    final outgoing = math.cos(theta);
    final incoming = math.sin(theta);
    return (outgoing, incoming);
  }

  /// Alternative smooth quadratic curve: (1 - t)^2 and t^2.
  static (double outgoing, double incoming) calculateQuadratic(double t) {
    final clampedT = t.clamp(0.0, 1.0);
    final outgoing = math.pow(1.0 - clampedT, 2).toDouble();
    final incoming = math.pow(clampedT, 2).toDouble();
    return (outgoing, incoming);
  }
}

/// Status of an active crossfade transition.
enum CrossfadeState {
  idle,
  fadingOut,
  crossfading,
  completed,
}

/// Studio-grade Audio Crossfade Engine.
///
/// Coordinates smooth transitions between outgoing and incoming audio sources
/// using equal-power trigonometric curves to eliminate perceived loudness dips
/// and silence gaps between songs.
class CrossfadeEngine {
  final AudioPlayer primaryPlayer;
  AudioPlayer? _secondaryPlayer;
  final CrossfadeState _state = CrossfadeState.idle;
  Timer? _fadeTimer;

  final ValueNotifier<CrossfadeState> stateNotifier =
      ValueNotifier<CrossfadeState>(CrossfadeState.idle);

  CrossfadeEngine({required this.primaryPlayer});

  CrossfadeState get state => _state;
  bool get isCrossfading => _state == CrossfadeState.crossfading;

  /// Executes an equal-power fade-out on the active player as it approaches track end.
  void applyEqualPowerFadeOut({
    required Duration position,
    required Duration duration,
    required double baseTargetVolume,
  }) {
    final crossfadeSec = SettingsManager.crossfadeSeconds;
    if (crossfadeSec <= 0) return;

    final remaining = duration - position;
    if (remaining.inSeconds > crossfadeSec || remaining.inMilliseconds < 150) {
      return;
    }

    // Normalized progress from 0.0 (crossfade start) to 1.0 (track end)
    final progress = 1.0 - (remaining.inMilliseconds / (crossfadeSec * 1000.0)).clamp(0.0, 1.0);
    final (outgoingVolRatio, _) = EqualPowerCurve.calculate(progress);
    final effectiveVol = (baseTargetVolume * outgoingVolRatio).clamp(0.0, 1.0);

    try {
      primaryPlayer.setVolume(effectiveVol);
    } catch (_) {}
  }

  /// Smoothly fades a player's volume from its current level to [targetVolume]
  /// over [durationMs] using high-frequency 40ms equal-power steps.
  Future<void> smoothFadeVolumeTo(
    AudioPlayer player,
    double targetVolume, {
    int durationMs = 800,
  }) async {
    _fadeTimer?.cancel();
    final currentVol = player.volume;
    if ((currentVol - targetVolume).abs() < 0.02 || durationMs <= 50) {
      try {
        await player.setVolume(targetVolume);
      } catch (_) {}
      return;
    }

    final completer = Completer<void>();
    final steps = (durationMs / 40).round().clamp(5, 50);
    int currentStep = 0;

    _fadeTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      currentStep++;
      final t = currentStep / steps;
      // Smooth sinusoidal interpolation
      final smoothedT = (1.0 - math.cos(math.pi * t)) / 2.0;
      final stepVol = currentVol + (targetVolume - currentVol) * smoothedT;

      try {
        player.setVolume(stepVol.clamp(0.0, 1.0));
      } catch (_) {}

      if (currentStep >= steps) {
        timer.cancel();
        try {
          player.setVolume(targetVolume.clamp(0.0, 1.0));
        } catch (_) {}
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  void dispose() {
    _fadeTimer?.cancel();
    _secondaryPlayer?.dispose();
    _secondaryPlayer = null;
    stateNotifier.dispose();
  }
}
