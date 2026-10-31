import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/logic/beat_match_engine.dart';

void main() {
  group('BeatMatchEngine & DJ Automix Tests', () {
    test('1. BpmEstimator accurately derives tempo from title, tags, and genres', () {
      final explicitBpmSong = Song(
        id: 's_exp',
        title: 'Dance Rhythm (128 BPM)',
        artist: 'Producer',
        coverUrl: '',
      );
      expect(BeatMatchEngine.estimateBpm(explicitBpmSong), equals(128.0));

      final kuthuSong = Song(
        id: 's_kuthu',
        title: 'Vaathi Raid - High Energy Kuthu',
        artist: 'Anirudh',
        coverUrl: '',
      );
      expect(BeatMatchEngine.estimateBpm(kuthuSong), equals(138.0));

      final lofiSong = Song(
        id: 's_lofi',
        title: 'Arabic Kuthu - Slowed + Reverb (Lo-Fi Chill)',
        artist: 'Lofi Producer',
        coverUrl: '',
      );
      expect(BeatMatchEngine.estimateBpm(lofiSong), equals(76.0));

      final melodySong = Song(
        id: 's_mel',
        title: 'Vaseegara Romantic Melody',
        artist: 'Harris',
        coverUrl: '',
      );
      expect(BeatMatchEngine.estimateBpm(melodySong), equals(94.0));
    });

    test('2. BpmEstimator fallback is deterministic for the same song ID', () {
      final songA = Song(id: 'song_seed_123', title: 'Unknown Track', artist: 'Artist', coverUrl: '');
      final bpm1 = BeatMatchEngine.estimateBpm(songA);
      final bpm2 = BeatMatchEngine.estimateBpm(songA);
      expect(bpm1, equals(bpm2));
      expect(bpm1, greaterThanOrEqualTo(95.0));
      expect(bpm1, lessThanOrEqualTo(130.0));
    });

    test('3. Harmonic tempo alignment calculates speed adjustment within ±3% for blendable tempos', () {
      final songA = Song(
        id: 's_125',
        title: 'Club Track (125 BPM)',
        artist: 'DJ A',
        coverUrl: '',
      );
      final songB = Song(
        id: 's_128',
        title: 'Festival Track (128 BPM)',
        artist: 'DJ B',
        coverUrl: '',
      );

      final plan = BeatMatchEngine.planTransition(outgoing: songA, incoming: songB, phraseBeats: 8);

      expect(plan.isHarmonicallyAligned, isTrue);
      expect(plan.hasTempoAdjustment, isTrue);

      // Target BPM is average (126.5)
      expect(plan.matchedBpm, closeTo(126.5, 0.1));

      // Speed adjustments must stay within ±3% (0.97 - 1.03)
      expect(plan.speedMultiplierA, greaterThanOrEqualTo(0.97));
      expect(plan.speedMultiplierA, lessThanOrEqualTo(1.03));
      expect(plan.speedMultiplierB, greaterThanOrEqualTo(0.97));
      expect(plan.speedMultiplierB, lessThanOrEqualTo(1.03));

      // Song A speeds up slightly; Song B slows down slightly
      expect(plan.speedMultiplierA, greaterThan(1.0));
      expect(plan.speedMultiplierB, lessThan(1.0));

      // Bar-quantized duration for 8 beats at ~126.5 BPM: 8 * (60 / 126.5) * 1000 = ~3794ms
      expect(plan.transitionDurationMs, closeTo(3794, 50));
    });

    test('4. Detects half-time / double-time harmonic compatibility (e.g. 70 BPM vs 140 BPM)', () {
      final lofiSong = Song(
        id: 's_lofi_70',
        title: 'Chill Hop (70 BPM)',
        artist: 'Beats',
        coverUrl: '',
      );
      final fastSong = Song(
        id: 's_fast_140',
        title: 'Fast EDM (140 BPM)',
        artist: 'Producer',
        coverUrl: '',
      );

      final plan = BeatMatchEngine.planTransition(outgoing: lofiSong, incoming: fastSong, phraseBeats: 8);

      // 70 BPM doubled is 140 BPM -> harmonic match
      expect(plan.isHarmonicallyAligned, isTrue);
      expect(plan.speedMultiplierA, equals(1.0));
      expect(plan.speedMultiplierB, equals(1.0));
    });

    test('5. Tempos beyond 6% difference skip pitch/speed shift but preserve bar quantization', () {
      final slowBallad = Song(
        id: 's_slow',
        title: 'Sad Ballad (65 BPM)',
        artist: 'Singer',
        coverUrl: '',
      );
      final fastKuthu = Song(
        id: 's_kuthu',
        title: 'Fast Kuthu (138 BPM)',
        artist: 'Anirudh',
        coverUrl: '',
      );

      final plan = BeatMatchEngine.planTransition(outgoing: slowBallad, incoming: fastKuthu, phraseBeats: 8);

      // No audible warble
      expect(plan.isHarmonicallyAligned, isFalse);
      expect(plan.hasTempoAdjustment, isFalse);
      expect(plan.speedMultiplierA, equals(1.0));
      expect(plan.speedMultiplierB, equals(1.0));

      // Bar quantized to outgoing 65 BPM: 8 * (60 / 65) * 1000 = ~7384ms
      expect(plan.transitionDurationMs, closeTo(7384, 50));
    });

    test('6. calculateAutomixCurve accelerates low-end rolloff after midpoint', () {
      // At start (t = 0.0)
      final (out0, in0) = BeatMatchEngine.calculateAutomixCurve(0.0);
      expect(out0, equals(1.0));
      expect(in0, equals(0.0));

      // At midpoint (t = 0.5)
      final (outMid, inMid) = BeatMatchEngine.calculateAutomixCurve(0.5);
      expect(outMid, closeTo(0.707, 0.01));
      expect(inMid, closeTo(0.707, 0.01));

      // After midpoint (t = 0.8): bass rolloff accelerates attenuation
      final (outLate, inLate) = BeatMatchEngine.calculateAutomixCurve(0.8);
      expect(outLate, lessThan(0.35));
      expect(inLate, greaterThan(0.90));
    });
  });
}
