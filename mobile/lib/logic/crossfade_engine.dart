import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/settings_manager.dart';
import 'beat_match_engine.dart';

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

/// Studio-grade Audio Crossfade & DJ Automix Engine.
///
/// Coordinates smooth transitions between outgoing and incoming audio sources
/// using equal-power trigonometric curves and tempo-aligned beat-matching.
class CrossfadeEngine {
  final AudioPlayer primaryPlayer;
  AudioPlayer? _secondaryPlayer;
  final CrossfadeState _state = CrossfadeState.idle;
  Timer? _fadeTimer;
  Timer? _tempoRampTimer;

  BeatMatchPlan? _activeBeatMatchPlan;
  BeatMatchPlan? get activeBeatMatchPlan => _activeBeatMatchPlan;

  final ValueNotifier<CrossfadeState> stateNotifier =
      ValueNotifier<CrossfadeState>(CrossfadeState.idle);

  CrossfadeEngine({required this.primaryPlayer});

  CrossfadeState get state => _state;
  bool get isCrossfading => _state == CrossfadeState.crossfading;

  /// Prepares an intelligent Automix transition plan before reaching track end.
  void prepareTransition({
    required Song outgoing,
    required Song? incoming,
  }) {
    if (!SettingsManager.isBeatMatchEnabled) {
      _activeBeatMatchPlan = null;
      return;
    }

    _activeBeatMatchPlan = BeatMatchEngine.planTransition(
      outgoing: outgoing,
      incoming: incoming,
      phraseBeats: SettingsManager.transitionPhraseBeats,
    );
  }

  /// Executes an equal-power or beat-matched fade-out as track approaches end.
  void applyEqualPowerFadeOut({
    required Duration position,
    required Duration duration,
    required double baseTargetVolume,
  }) {
    final crossfadeSec = SettingsManager.crossfadeSeconds;
    final plan = _activeBeatMatchPlan;

    // Determine transition window
    final effectiveTransitionMs = (plan != null && SettingsManager.isBeatMatchEnabled)
        ? plan.transitionDurationMs
        : (crossfadeSec * 1000);

    if (effectiveTransitionMs <= 0) return;

    final remaining = duration - position;
    if (remaining.inMilliseconds > effectiveTransitionMs || remaining.inMilliseconds < 150) {
      return;
    }

    // Normalized progress from 0.0 (crossfade start) to 1.0 (track end)
    final progress = 1.0 - (remaining.inMilliseconds / effectiveTransitionMs.toDouble()).clamp(0.0, 1.0);

    // Apply subtle tempo stretch on outgoing track if beat-matching
    if (plan != null && plan.hasTempoAdjustment && plan.speedMultiplierA != 1.0) {
      try {
        if ((primaryPlayer.speed - plan.speedMultiplierA).abs() > 0.005) {
          primaryPlayer.setSpeed(plan.speedMultiplierA);
        }
      } catch (_) {}
    }

    final (outgoingVolRatio, _) = plan != null
        ? BeatMatchEngine.calculateAutomixCurve(progress)
        : EqualPowerCurve.calculate(progress);

    final effectiveVol = (baseTargetVolume * outgoingVolRatio).clamp(0.0, 1.0);

    try {
      primaryPlayer.setVolume(effectiveVol);
    } catch (_) {}
  }

  /// Handles incoming track initialization with tempo matching and smooth recovery ramp.
  Future<void> onIncomingTrackStarted(AudioPlayer player) async {
    final plan = _activeBeatMatchPlan;
    if (plan != null && plan.hasTempoAdjustment && plan.speedMultiplierB != 1.0) {
      try {
        await player.setSpeed(plan.speedMultiplierB);
      } catch (_) {}

      // Smoothly ramp speed back to natural 1.0x over 3.0s after crossfade handoff
      smoothRampSpeed(player, targetSpeed: 1.0, durationMs: 3000);
    }
  }

  /// Smoothly restores playback speed to [targetSpeed] using 100ms micro-increments.
  void smoothRampSpeed(
    AudioPlayer player, {
    double targetSpeed = 1.0,
    int durationMs = 3000,
  }) {
    _tempoRampTimer?.cancel();
    final startSpeed = player.speed;
    if ((startSpeed - targetSpeed).abs() < 0.005) {
      try {
        player.setSpeed(targetSpeed);
      } catch (_) {}
      return;
    }

    const intervalMs = 100;
    final totalSteps = (durationMs / intervalMs).round().clamp(5, 30);
    int currentStep = 0;

    _tempoRampTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      currentStep++;
      final t = (currentStep / totalSteps).clamp(0.0, 1.0);
      final currentSpeed = startSpeed + (targetSpeed - startSpeed) * t;

      try {
        player.setSpeed(double.parse(currentSpeed.toStringAsFixed(4)));
      } catch (_) {}

      if (currentStep >= totalSteps) {
        timer.cancel();
        try {
          player.setSpeed(targetSpeed);
        } catch (_) {}
      }
    });
  }

  /// Smoothly fades a player's volume from its current level to [targetVolume]
  /// over [durationMs] using high-frequency 40ms sinusoidal steps.
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

  void reset() {
    _fadeTimer?.cancel();
    _tempoRampTimer?.cancel();
    _activeBeatMatchPlan = null;
    try {
      primaryPlayer.setSpeed(1.0);
    } catch (_) {}
  }

  void dispose() {
    _fadeTimer?.cancel();
    _tempoRampTimer?.cancel();
    _secondaryPlayer?.dispose();
    _secondaryPlayer = null;
    stateNotifier.dispose();
  }
}
