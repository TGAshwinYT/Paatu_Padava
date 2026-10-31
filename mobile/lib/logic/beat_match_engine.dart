import 'dart:math' as math;
import '../models/song.dart';

/// Musical transition parameters for seamless DJ Automix.
class BeatMatchPlan {
  final double outgoingBpm;
  final double incomingBpm;
  final double matchedBpm;
  final double speedMultiplierA; // Outgoing track speed adjustment (clamped ±3%)
  final double speedMultiplierB; // Incoming track speed adjustment (clamped ±3%)
  final int transitionDurationMs; // Musical phrase-quantized duration
  final bool isHarmonicallyAligned;
  final int phraseBeats;

  const BeatMatchPlan({
    required this.outgoingBpm,
    required this.incomingBpm,
    required this.matchedBpm,
    required this.speedMultiplierA,
    required this.speedMultiplierB,
    required this.transitionDurationMs,
    required this.isHarmonicallyAligned,
    required this.phraseBeats,
  });

  /// 1.0 means no tempo modification was necessary
  bool get hasTempoAdjustment =>
      (speedMultiplierA - 1.0).abs() > 0.002 || (speedMultiplierB - 1.0).abs() > 0.002;
}

/// Estimates tempo (BPM) and computes harmonic beat-matched transitions.
class BeatMatchEngine {
  /// Maximum allowable tempo stretch during transitions (±3.0%)
  static const double maxTempoStretch = 0.03;

  /// Estimates or derives BPM for a track.
  /// Uses audio metadata if available, title/genre analysis, and a deterministic hash bucket fallback.
  static double estimateBpm(Song song) {
    final title = song.title.toLowerCase();
    final album = song.album.toLowerCase();
    final combined = '$title $album';

    // 1. Explicit BPM tags in title (e.g. "Song (128 BPM)")
    final bpmMatch = RegExp(r'\b(\d{2,3})\s*(?:bpm|tempo)\b', caseSensitive: false).firstMatch(combined);
    if (bpmMatch != null) {
      final parsed = double.tryParse(bpmMatch.group(1)!);
      if (parsed != null && parsed >= 60 && parsed <= 200) {
        return parsed;
      }
    }

    // 2. Slowed & Reverb / Lo-Fi / Chill / Acoustic (checked first to catch slowed remixes)
    if (combined.contains('slowed') ||
        combined.contains('lo-fi') ||
        combined.contains('lofi') ||
        combined.contains('chill') ||
        combined.contains('lullaby') ||
        combined.contains('unplugged')) {
      return 76.0;
    }

    // 3. High-energy Dance / Kuthu / EDM / Fast Beats
    if (combined.contains('kuthu') ||
        combined.contains('dappan') ||
        combined.contains('fast beat') ||
        combined.contains('dance') ||
        combined.contains('club mix') ||
        combined.contains('party')) {
      return 138.0;
    }

    // 4. Melodies / Romantic / Soulful
    if (combined.contains('melody') ||
        combined.contains('romantic') ||
        combined.contains('love') ||
        combined.contains('duet')) {
      return 94.0;
    }

    // 5. Deterministic hash-seeded fallback within natural pop tempo spectrum (95 - 130 BPM)
    // Guarantees consistent BPM across app reloads for the exact same track
    final seed = song.id.hashCode.abs();
    return 95.0 + (seed % 36).toDouble();
  }

  /// Calculates a beat-matched Automix plan between [outgoing] and [incoming].
  static BeatMatchPlan planTransition({
    required Song outgoing,
    required Song? incoming,
    int phraseBeats = 8,
  }) {
    final bpmA = estimateBpm(outgoing);

    if (incoming == null) {
      // Single track transition fallback (bar-quantized to outgoing BPM)
      final beatDurationMs = (60.0 / bpmA) * 1000.0;
      final durationMs = (phraseBeats * beatDurationMs).round().clamp(2000, 10000);
      return BeatMatchPlan(
        outgoingBpm: bpmA,
        incomingBpm: bpmA,
        matchedBpm: bpmA,
        speedMultiplierA: 1.0,
        speedMultiplierB: 1.0,
        transitionDurationMs: durationMs,
        isHarmonicallyAligned: true,
        phraseBeats: phraseBeats,
      );
    }

    final rawBpmB = estimateBpm(incoming);

    // Harmonic octave alignment: check if tracks are half-time / double-time relative to each other
    double effectiveBpmB = rawBpmB;
    if ((rawBpmB * 2.0 - bpmA).abs() < (rawBpmB - bpmA).abs()) {
      effectiveBpmB = rawBpmB * 2.0; // Half-time to normal (e.g. 70 -> 140 matching 138)
    } else if ((rawBpmB / 2.0 - bpmA).abs() < (rawBpmB - bpmA).abs()) {
      effectiveBpmB = rawBpmB / 2.0; // Double-time to normal (e.g. 140 -> 70 matching 74)
    }

    final diffRatio = (effectiveBpmB - bpmA).abs() / bpmA;

    // Harmonic tempo matching allowed if difference is within 6%
    if (diffRatio <= 0.06) {
      final targetBpm = (bpmA + effectiveBpmB) / 2.0;
      final rawSpeedA = targetBpm / bpmA;
      final rawSpeedB = targetBpm / effectiveBpmB;

      final clampedSpeedA = rawSpeedA.clamp(1.0 - maxTempoStretch, 1.0 + maxTempoStretch);
      final clampedSpeedB = rawSpeedB.clamp(1.0 - maxTempoStretch, 1.0 + maxTempoStretch);

      final beatDurationMs = (60.0 / targetBpm) * 1000.0;
      final durationMs = (phraseBeats * beatDurationMs).round().clamp(2500, 12000);

      return BeatMatchPlan(
        outgoingBpm: bpmA,
        incomingBpm: rawBpmB,
        matchedBpm: targetBpm,
        speedMultiplierA: double.parse(clampedSpeedA.toStringAsFixed(4)),
        speedMultiplierB: double.parse(clampedSpeedB.toStringAsFixed(4)),
        transitionDurationMs: durationMs,
        isHarmonicallyAligned: true,
        phraseBeats: phraseBeats,
      );
    }

    // Beyond 6% difference: do not pitch-shift to avoid audible warbling;
    // Quantize crossfade duration cleanly to outgoing track's musical bar boundary
    final beatDurationMs = (60.0 / bpmA) * 1000.0;
    final durationMs = (phraseBeats * beatDurationMs).round().clamp(2000, 10000);

    return BeatMatchPlan(
      outgoingBpm: bpmA,
      incomingBpm: rawBpmB,
      matchedBpm: bpmA,
      speedMultiplierA: 1.0,
      speedMultiplierB: 1.0,
      transitionDurationMs: durationMs,
      isHarmonicallyAligned: false,
      phraseBeats: phraseBeats,
    );
  }

  /// Calculates the asymmetric volume ratio during Automix.
  /// At t > 0.5, outgoing track undergoes an accelerated bass rolloff to avoid low-end mud.
  static (double outgoingVol, double incomingVol) calculateAutomixCurve(double t) {
    final clampedT = t.clamp(0.0, 1.0);
    final theta = (math.pi / 2.0) * clampedT;

    // Standard constant-power trigonometric base
    double outVol = math.cos(theta);
    double inVol = math.sin(theta);

    // DJ Bass Roll-Off: When incoming track drops in (t >= 0.5), accelerate outgoing volume attenuation
    if (clampedT > 0.5) {
      final rollOff = math.pow((1.0 - clampedT) / 0.5, 1.25).toDouble();
      outVol = math.min(outVol, rollOff);
    }

    return (outVol.clamp(0.0, 1.0), inVol.clamp(0.0, 1.0));
  }
}
