import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/equalizer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Acoustic Vocal Attenuation Formant Notch Filtering Tests', () {
    test('Flat bands with 0.0 vocal attenuation remain unmodified', () {
      final base = [0.0, 0.0, 0.0, 0.0, 0.0];
      final result = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 0.0,
        virtualizer: 0.0,
        vocalAttenuation: 0.0,
      );

      expect(result, equals([0.0, 0.0, 0.0, 0.0, 0.0]));
    });

    test('Full vocal attenuation (1.0) scoops vocal formants and boosts rhythm foundation', () {
      final base = [0.0, 0.0, 0.0, 0.0, 0.0];
      final result = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 0.0,
        virtualizer: 0.0,
        vocalAttenuation: 1.0,
      );

      // Band 0 (60 Hz Sub-bass): +3.5 dB
      expect(result[0], closeTo(3.5, 0.001));
      // Band 1 (230 Hz Lower chest resonance): -2.0 dB
      expect(result[1], closeTo(-2.0, 0.001));
      // Band 2 (910 Hz Core vocal vowel formant): -8.0 dB
      expect(result[2], closeTo(-8.0, 0.001));
      // Band 3 (3.6 kHz Presence & singer's formant): -5.0 dB
      expect(result[3], closeTo(-5.0, 0.001));
      // Band 4 (14 kHz Air & cymbals): +2.5 dB
      expect(result[4], closeTo(2.5, 0.001));
    });

    test('Half vocal attenuation (0.5) applies proportional intermediate notch', () {
      final base = [0.0, 0.0, 0.0, 0.0, 0.0];
      final result = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 0.0,
        virtualizer: 0.0,
        vocalAttenuation: 0.5,
      );

      // Band 0: +1.75 dB
      expect(result[0], closeTo(1.75, 0.001));
      // Band 1: -1.0 dB
      expect(result[1], closeTo(-1.0, 0.001));
      // Band 2: -4.0 dB
      expect(result[2], closeTo(-4.0, 0.001));
      // Band 3: -2.5 dB
      expect(result[3], closeTo(-2.5, 0.001));
      // Band 4: +1.25 dB
      expect(result[4], closeTo(1.25, 0.001));
    });

    test('Effective bands strictly clamp within [-10.0, 10.0] dB with extreme values', () {
      final base = [8.0, -8.0, -9.0, 9.0, 7.0];
      final result = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 1.0,
        virtualizer: 1.0,
        vocalAttenuation: 1.0,
      );

      for (final band in result) {
        expect(band >= -10.0 && band <= 10.0, isTrue, reason: 'Band $band out of [-10, 10] range');
      }
      expect(result[0], equals(10.0)); // 8 + 5 = 13 -> clamped to 10
      expect(result[2], equals(-10.0)); // -9 - 12 = -21 -> clamped to -10
    });
  });
}
