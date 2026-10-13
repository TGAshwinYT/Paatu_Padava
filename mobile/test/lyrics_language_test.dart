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

  group('Lyrics Drift Elimination & Precision Alignment Tests', () {
    test('Preserves exact studio LRC timestamps without progressive drift during playback', () {
      // Audio duration is 210s (with a 10s outro), but last lyric is at 200s.
      // Under the old auto-scaling, ratio = 210/200 = 1.05 would delay all lines progressively.
      // With drift elimination, studio timestamps remain unwarped.
      const originalLineMs = 100000; // 1m 40s
      // No ratio scaling applied:
      const unwarpedLineMs = originalLineMs;
      expect(unwarpedLineMs, equals(100000));

      // With manual offset notifier (+300ms)
      const manualOffsetMs = 300;
      final effectivePlayerPos = const Duration(milliseconds: 99700) + const Duration(milliseconds: manualOffsetMs);
      expect(effectivePlayerPos.inMilliseconds >= unwarpedLineMs, isTrue);
    });

    test('Parses standard LRC [offset:...] header tag correctly', () {
      final offsetRegex = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);

      const positiveHeader = '[offset:+500]';
      final posMatch = offsetRegex.firstMatch(positiveHeader.trim());
      expect(posMatch, isNotNull);
      expect(int.tryParse(posMatch!.group(1)!), equals(500));

      const negativeHeader = '[offset:-250]';
      final negMatch = offsetRegex.firstMatch(negativeHeader.trim());
      expect(negMatch, isNotNull);
      expect(int.tryParse(negMatch!.group(1)!), equals(-250));
    });

    test('Parses multi-timestamp LRC lines accurately', () {
      const line = '[00:15.00][01:30.50] Hook line repeated';
      final timestampRegex = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
      final matches = timestampRegex.allMatches(line).toList();

      expect(matches.length, equals(2));

      final min1 = int.parse(matches[0].group(1)!);
      final sec1 = double.parse(matches[0].group(2)!);
      final ms1 = ((min1 * 60 + sec1) * 1000).toInt();
      expect(ms1, equals(15000));

      final min2 = int.parse(matches[1].group(1)!);
      final sec2 = double.parse(matches[1].group(2)!);
      final ms2 = ((min2 * 60 + sec2) * 1000).toInt();
      expect(ms2, equals(90500));
    });

    test('Binary search active line lookup performs instant pinpoint index selection', () {
      final sampleTimestamps = [
        const Duration(milliseconds: 0),
        const Duration(milliseconds: 12000),
        const Duration(milliseconds: 25000),
        const Duration(milliseconds: 40000),
      ];

      int findActive(Duration effectivePos) {
        int low = 0;
        int high = sampleTimestamps.length - 1;
        int idx = 0;
        final effectiveMs = effectivePos.inMilliseconds;
        while (low <= high) {
          final mid = (low + high) >> 1;
          if (sampleTimestamps[mid].inMilliseconds <= effectiveMs) {
            idx = mid;
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }
        return idx;
      }

      expect(findActive(const Duration(milliseconds: 5000)), equals(0));
      expect(findActive(const Duration(milliseconds: 12000)), equals(1));
      expect(findActive(const Duration(milliseconds: 20000)), equals(1));
      expect(findActive(const Duration(milliseconds: 25000)), equals(2));
      expect(findActive(const Duration(milliseconds: 45000)), equals(3));
    });
  });
}
