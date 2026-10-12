import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/domain/models/lyrics_state.dart';
import 'package:paatu_padava_mobile/logic/lyrics/indic_romanizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IndicRomanizer Tests', () {
    test('Detects Indic scripts correctly', () {
      expect(IndicRomanizer.detectScript('கண்மணி அன்போடு காதலன்'), equals('tamil'));
      expect(IndicRomanizer.detectScript('तुम ही हो'), equals('devanagari'));
      expect(IndicRomanizer.detectScript('సామజవరగమన'), equals('telugu'));
      expect(IndicRomanizer.detectScript('മനസ്സിലായോ'), equals('malayalam'));
      expect(IndicRomanizer.detectScript('ಬೆಳಗೆದ್ದು ಯಾರ ಮುಖವ'), equals('kannada'));
      expect(IndicRomanizer.detectScript('Shape of You'), equals('latin'));
    });

    test('Identifies whether text contains transliterable Indic script', () {
      expect(IndicRomanizer.hasIndicScript('கண்மணி'), isTrue);
      expect(IndicRomanizer.hasIndicScript('Just an English song'), isFalse);
      expect(IndicRomanizer.hasIndicScript('[00:10.00] English with தமிழ் mixed'), isTrue);
    });

    test('Transliterates Tamil lyrics preserving exact timestamps', () {
      const rawLrc = '''
[00:15.50] கண்மணி அன்போடு காதலன்
[00:20.10] நான் நான் எழுதும் கடிதமே
''';

      final romanized = IndicRomanizer.romanizeLyrics(rawLrc);
      final lines = romanized.trim().split('\n');

      expect(lines.length, equals(2));
      expect(lines[0].startsWith('[00:15.50]'), isTrue);
      expect(lines[1].startsWith('[00:20.10]'), isTrue);

      // Verify Tamil letters are converted to Latin phonetics
      expect(lines[0].toLowerCase().contains('kanmani'), isTrue);
      expect(lines[1].toLowerCase().contains('naan'), isTrue);
      // Verify no untransliterated Tamil runes remain
      expect(RegExp(r'[\u0B80-\u0BFF]').hasMatch(lines[0]), isFalse);
      expect(RegExp(r'[\u0B80-\u0BFF]').hasMatch(lines[1]), isFalse);
    });

    test('Transliterates Hindi / Devanagari lyrics preserving timestamps', () {
      const rawLrc = '''
[01:05.00] तुम ही हो अब तुम ही हो
[01:10.50] मेरी आशिकी अब तुम ही हो
''';

      final romanized = IndicRomanizer.romanizeLyrics(rawLrc);
      final lines = romanized.trim().split('\n');

      expect(lines.length, equals(2));
      expect(lines[0].startsWith('[01:05.00]'), isTrue);
      expect(lines[1].startsWith('[01:10.50]'), isTrue);

      expect(lines[0].toLowerCase().contains('tum'), isTrue);
      expect(RegExp(r'[\u0900-\u097F]').hasMatch(lines[0]), isFalse);
    });

    test('Transliterates Telugu lyrics preserving timestamps', () {
      const rawLrc = '[00:30.00] నీ చూపులే నా ఊపిరి';
      final romanized = IndicRomanizer.romanizeLyrics(rawLrc);

      expect(romanized.startsWith('[00:30.00]'), isTrue);
      expect(RegExp(r'[\u0C00-\u0C7F]').hasMatch(romanized), isFalse);
    });

    test('Preserves English lyrics without changes', () {
      const englishLrc = '''
[00:12.00] I'm in love with the shape of you
[00:15.00] We push and pull like a magnet do
''';

      final romanized = IndicRomanizer.romanizeLyrics(englishLrc);
      expect(romanized, equals(englishLrc));
    });

    test('Handles mixed Indic and English lyrics cleanly', () {
      const mixedLrc = '[02:15.00] Yeah baby என் sweetheart நீ தான்';
      final romanized = IndicRomanizer.romanizeLyrics(mixedLrc);

      expect(romanized.startsWith('[02:15.00]'), isTrue);
      expect(romanized.contains('Yeah baby'), isTrue);
      expect(romanized.contains('sweetheart'), isTrue);
      expect(RegExp(r'[\u0B80-\u0BFF]').hasMatch(romanized), isFalse);
    });
  });

  group('DualLyrics Model Tests', () {
    test('Correctly identifies multiple variants between native and English', () {
      const nativeLyrics = '[00:10.00] கண்மணி அன்போடு';
      const englishLyrics = '[00:10.00] Kanmani anbodu';

      const dual = DualLyrics(
        defaultLyrics: nativeLyrics,
        englishLyrics: englishLyrics,
        detectedScript: 'tamil',
        isSynced: true,
      );

      expect(dual.hasMultipleVariants, isTrue);
      expect(dual.getLyricsForLanguage(LyricsLanguage.defaultLang), equals(nativeLyrics));
      expect(dual.getLyricsForLanguage(LyricsLanguage.english), equals(englishLyrics));
    });

    test('Identifies mono-variant English songs without redundant switching', () {
      const english = '[00:10.00] Yesterday, all my troubles seemed so far away';
      const dual = DualLyrics(
        defaultLyrics: english,
        englishLyrics: english,
        detectedScript: 'latin',
        isSynced: true,
      );

      expect(dual.hasMultipleVariants, isFalse);
      expect(dual.getLyricsForLanguage(LyricsLanguage.defaultLang), equals(english));
      expect(dual.getLyricsForLanguage(LyricsLanguage.english), equals(english));
    });

    test('LyricsState retains DualLyrics container', () {
      const dual = DualLyrics(
        defaultLyrics: 'பாடல் வரிகள்',
        englishLyrics: 'Paadal varigal',
        detectedScript: 'tamil',
      );

      final state = LyricsState.loaded('பாடல் வரிகள்', dualLyrics: dual);
      expect(state.hasLyrics, isTrue);
      expect(state.dualLyrics, isNotNull);
      expect(state.dualLyrics!.englishLyrics, equals('Paadal varigal'));
    });
  });

  group('Lyrics Duration-Scaling Multiplier & Alignment Tests', () {
    test('Calculates and scales timestamps when ratio R is within 0.95 to 1.05', () {
      const trackDuration = Duration(milliseconds: 204000); // 3m 24s
      const lastLyricTs = Duration(milliseconds: 200000);   // 3m 20s
      final ratio = trackDuration.inMilliseconds / lastLyricTs.inMilliseconds; // 1.02
      expect(ratio >= 0.95 && ratio <= 1.05, isTrue);

      const originalLineMs = 100000; // 100.0s
      final scaledLineMs = (originalLineMs * ratio).round(); // 102.0s
      expect(scaledLineMs, equals(102000));

      // With +500ms pill offset:
      const manualOffsetMs = 500;
      final effectivePlayerPos = const Duration(milliseconds: 101600) + const Duration(milliseconds: manualOffsetMs);
      expect(effectivePlayerPos.inMilliseconds >= scaledLineMs, isTrue);
    });

    test('Leaves timestamps unchanged when ratio R is outside 0.95 to 1.05 boundary', () {
      const shortTrackDuration = Duration(milliseconds: 150000); // 2m 30s
      const lastLyricTs = Duration(milliseconds: 200000);        // 3m 20s
      final ratio = shortTrackDuration.inMilliseconds / lastLyricTs.inMilliseconds; // 0.75
      expect(ratio >= 0.95 && ratio <= 1.05, isFalse);

      const originalLineMs = 100000;
      final effectiveLineMs = (ratio >= 0.95 && ratio <= 1.05)
          ? (originalLineMs * ratio).round()
          : originalLineMs;
      expect(effectiveLineMs, equals(originalLineMs));
    });
  });
}
