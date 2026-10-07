/// High-performance, offline, deterministic Indic-to-English (Romanized)
/// transliterator tailored for music lyrics and synchronized LRC files.
///
/// Preserves exact `[mm:ss.xx]` timing timestamps, symbols, and formatting,
/// transforming native Brahmic scripts (Tamil, Hindi/Devanagari, Telugu,
/// Malayalam, Kannada) into natural, singable Latin phonetics.
class IndicRomanizer {
  IndicRomanizer._();

  // LRC timestamp extractor: matches [00:12.34] or [00:12] or multiple stamps
  static final RegExp _timestampPattern = RegExp(r'^(\[\d{2}:\d{2}(?:\.\d+)?\])+');

  // Script detection patterns
  static final RegExp _tamilPattern = RegExp(r'[\u0B80-\u0BFF]');
  static final RegExp _devanagariPattern = RegExp(r'[\u0900-\u097F]');
  static final RegExp _teluguPattern = RegExp(r'[\u0C00-\u0C7F]');
  static final RegExp _malayalamPattern = RegExp(r'[\u0D00-\u0D7F]');
  static final RegExp _kannadaPattern = RegExp(r'[\u0C80-\u0CFF]');

  /// Detects the dominant non-Latin script of the input lyrics
  static String detectScript(String text) {
    if (_tamilPattern.hasMatch(text)) return 'tamil';
    if (_devanagariPattern.hasMatch(text)) return 'devanagari';
    if (_teluguPattern.hasMatch(text)) return 'telugu';
    if (_malayalamPattern.hasMatch(text)) return 'malayalam';
    if (_kannadaPattern.hasMatch(text)) return 'kannada';
    return 'latin';
  }

  /// Whether the lyrics contain an Indic script that can be romanized
  static bool hasIndicScript(String text) {
    return _tamilPattern.hasMatch(text) ||
        _devanagariPattern.hasMatch(text) ||
        _teluguPattern.hasMatch(text) ||
        _malayalamPattern.hasMatch(text) ||
        _kannadaPattern.hasMatch(text);
  }

  /// Transliterates full lyrics (synced LRC or plain text) into Romanized English.
  /// Line-by-line timestamps (`[mm:ss.xx]`) are preserved verbatim.
  static String romanizeLyrics(String lyrics) {
    if (lyrics.trim().isEmpty) return lyrics;
    if (!hasIndicScript(lyrics)) return lyrics;

    final lines = lyrics.split('\n');
    final buffer = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = _timestampPattern.firstMatch(line);

      if (match != null) {
        final timestamps = match.group(0)!;
        final content = line.substring(timestamps.length);
        final romanizedContent = _romanizeLine(content);
        buffer.write(timestamps);
        buffer.write(romanizedContent);
      } else {
        buffer.write(_romanizeLine(line));
      }

      if (i < lines.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Converts a single line of mixed text to Romanized Latin
  static String _romanizeLine(String line) {
    if (line.isEmpty) return line;
    final runes = line.runes.toList();
    final out = StringBuffer();

    int i = 0;
    while (i < runes.length) {
      final code = runes[i];

      // Tamil Block (0x0B80 - 0x0BFF)
      if (code >= 0x0B80 && code <= 0x0BFF) {
        i = _transliterateTamil(runes, i, out);
      }
      // Devanagari Block (0x0900 - 0x097F)
      else if (code >= 0x0900 && code <= 0x097F) {
        i = _transliterateDevanagari(runes, i, out);
      }
      // Telugu Block (0x0C00 - 0x0C7F)
      else if (code >= 0x0C00 && code <= 0x0C7F) {
        i = _transliterateTelugu(runes, i, out);
      }
      // Malayalam Block (0x0D00 - 0x0D7F)
      else if (code >= 0x0D00 && code <= 0x0D7F) {
        i = _transliterateMalayalam(runes, i, out);
      }
      // Kannada Block (0x0C80 - 0x0CFF)
      else if (code >= 0x0C80 && code <= 0x0CFF) {
        i = _transliterateKannada(runes, i, out);
      }
      // Non-Indic characters (Latin, numbers, symbols, spaces, punctuation)
      else {
        out.writeCharCode(code);
        i++;
      }
    }

    return out.toString();
  }

  // =========================================================================
  // 1. TAMIL TRANSLITERATION (தமிழ்)
  // =========================================================================

  static final Map<int, String> _tamilIndependentVowels = {
    0x0B85: 'a',
    0x0B86: 'aa',
    0x0B87: 'i',
    0x0B88: 'ee',
    0x0B89: 'u',
    0x0B8A: 'oo',
    0x0B8E: 'e',
    0x0B8F: 'ae',
    0x0B90: 'ai',
    0x0B92: 'o',
    0x0B93: 'oa',
    0x0B94: 'au',
    0x0B83: 'kh', // ஆய்த எழுத்து ஃ
  };

  static final Map<int, String> _tamilConsonants = {
    0x0B95: 'k',  // க
    0x0B99: 'ng', // ங
    0x0B9A: 'ch', // ச
    0x0B9C: 'j',  // ஜ
    0x0B9E: 'ny', // ஞ
    0x0B9F: 't',  // ட
    0x0BA3: 'n',  // ண
    0x0BA4: 'th', // த
    0x0BA8: 'n',  // ந
    0x0BA9: 'n',  // ன
    0x0BAA: 'p',  // ப
    0x0BAE: 'm',  // ம
    0x0BAF: 'y',  // ய
    0x0BB0: 'r',  // ர
    0x0BB1: 'r',  // ற
    0x0BB2: 'l',  // ல
    0x0BB3: 'l',  // ள
    0x0BB4: 'zh', // ழ
    0x0BB5: 'v',  // வ
    0x0BB6: 'sh', // ஶ
    0x0BB7: 'sh', // ஷ
    0x0BB8: 's',  // ஸ
    0x0BB9: 'h',  // ஹ
  };

  static final Map<int, String> _tamilVowelSigns = {
    0x0BBE: 'aa', // ா
    0x0BBF: 'i',  // ி
    0x0BC0: 'ee', // ீ
    0x0BC1: 'u',  // ு
    0x0BC2: 'oo', // ூ
    0x0BC6: 'e',  // ெ
    0x0BC7: 'ae', // ே
    0x0BC8: 'ai', // ை
    0x0BCA: 'o',  // ொ
    0x0BCB: 'oa', // ோ
    0x0BCC: 'au', // ௌ
  };

  static int _transliterateTamil(List<int> runes, int index, StringBuffer out) {
    final code = runes[index];

    // Independent Vowel
    if (_tamilIndependentVowels.containsKey(code)) {
      out.write(_tamilIndependentVowels[code]);
      return index + 1;
    }

    // Consonant
    if (_tamilConsonants.containsKey(code)) {
      final base = _tamilConsonants[code]!;

      // Check next rune for combining marks (Pulli or Vowel Sign)
      if (index + 1 < runes.length) {
        final nextCode = runes[index + 1];

        // Pulli (Virama 0x0BCD): suppresses inherent 'a'
        if (nextCode == 0x0BCD) {
          out.write(base);
          return index + 2;
        }

        // Vowel sign (Matra)
        if (_tamilVowelSigns.containsKey(nextCode)) {
          out.write(base);
          out.write(_tamilVowelSigns[nextCode]);
          return index + 2;
        }
      }

      // Default inherent vowel 'a'
      out.write('${base}a');
      return index + 1;
    }

    // Standalone vowel sign or pulli without consonant
    if (_tamilVowelSigns.containsKey(code)) {
      out.write(_tamilVowelSigns[code]);
      return index + 1;
    }

    if (code == 0x0BCD) {
      return index + 1; // skip orphan pulli
    }

    out.writeCharCode(code);
    return index + 1;
  }

  // =========================================================================
  // 2. DEVANAGARI TRANSLITERATION (हिन्दी / मराठी)
  // =========================================================================

  static final Map<int, String> _devanagariIndependentVowels = {
    0x0905: 'a',
    0x0906: 'aa',
    0x0907: 'i',
    0x0908: 'ee',
    0x0909: 'u',
    0x090A: 'oo',
    0x090B: 'ri',
    0x090F: 'e',
    0x0910: 'ai',
    0x0913: 'o',
    0x0914: 'au',
    0x0902: 'n', // Anusvara
    0x0901: 'n', // Chandrabindu
    0x0903: 'h', // Visarga
  };

  static final Map<int, String> _devanagariConsonants = {
    0x0915: 'k',  0x0916: 'kh', 0x0917: 'g',  0x0918: 'gh', 0x0919: 'ng',
    0x091A: 'ch', 0x091B: 'chh', 0x091C: 'j',  0x091D: 'jh', 0x091E: 'ny',
    0x091F: 't',  0x0920: 'th', 0x0921: 'd',  0x0922: 'dh', 0x0923: 'n',
    0x0924: 't',  0x0925: 'th', 0x0926: 'd',  0x0927: 'dh', 0x0928: 'n',
    0x092A: 'p',  0x092B: 'ph', 0x092C: 'b',  0x092D: 'bh', 0x092E: 'm',
    0x092F: 'y',  0x0930: 'r',  0x0932: 'l',  0x0935: 'v',
    0x0936: 'sh', 0x0937: 'sh', 0x0938: 's',  0x0939: 'h',
    0x0958: 'q',  0x0959: 'kh', 0x095A: 'gh', 0x095B: 'z',  0x095C: 'r',
    0x095D: 'rh', 0x095E: 'f',
  };

  static final Map<int, String> _devanagariVowelSigns = {
    0x093E: 'aa',
    0x093F: 'i',
    0x0940: 'ee',
    0x0941: 'u',
    0x0942: 'oo',
    0x0943: 'ri',
    0x0947: 'e',
    0x0948: 'ai',
    0x094B: 'o',
    0x094C: 'au',
    0x0902: 'n',
    0x0903: 'h',
  };

  static int _transliterateDevanagari(List<int> runes, int index, StringBuffer out) {
    final code = runes[index];

    if (_devanagariIndependentVowels.containsKey(code)) {
      out.write(_devanagariIndependentVowels[code]);
      return index + 1;
    }

    if (_devanagariConsonants.containsKey(code)) {
      final base = _devanagariConsonants[code]!;

      if (index + 1 < runes.length) {
        final nextCode = runes[index + 1];

        // Halant (0x094D): cancels inherent vowel
        if (nextCode == 0x094D) {
          out.write(base);
          return index + 2;
        }

        // Matra
        if (_devanagariVowelSigns.containsKey(nextCode)) {
          out.write(base);
          out.write(_devanagariVowelSigns[nextCode]);
          return index + 2;
        }
      }

      // Inherent vowel
      out.write('${base}a');
      return index + 1;
    }

    if (_devanagariVowelSigns.containsKey(code)) {
      out.write(_devanagariVowelSigns[code]);
      return index + 1;
    }

    if (code == 0x094D) return index + 1;

    out.writeCharCode(code);
    return index + 1;
  }

  // =========================================================================
  // 3. TELUGU TRANSLITERATION (తెలుగు)
  // =========================================================================

  static final Map<int, String> _teluguIndependentVowels = {
    0x0C05: 'a', 0x0C06: 'aa', 0x0C07: 'i', 0x0C08: 'ee', 0x0C09: 'u',
    0x0C0A: 'oo', 0x0C0E: 'e', 0x0C0F: 'ae', 0x0C10: 'ai', 0x0C12: 'o',
    0x0C13: 'oa', 0x0C14: 'au', 0x0C02: 'm',
  };

  static final Map<int, String> _teluguConsonants = {
    0x0C15: 'k', 0x0C16: 'kh', 0x0C17: 'g', 0x0C18: 'gh', 0x0C19: 'ng',
    0x0C1A: 'ch', 0x0C1B: 'chh', 0x0C1C: 'j', 0x0C1D: 'jh', 0x0C1E: 'ny',
    0x0C1F: 't', 0x0C20: 'th', 0x0C21: 'd', 0x0C22: 'dh', 0x0C23: 'n',
    0x0C24: 'th', 0x0C25: 'th', 0x0C26: 'd', 0x0C27: 'dh', 0x0C28: 'n',
    0x0C2A: 'p', 0x0C2B: 'ph', 0x0C2C: 'b', 0x0C2D: 'bh', 0x0C2E: 'm',
    0x0C2F: 'y', 0x0C30: 'r', 0x0C31: 'r', 0x0C32: 'l', 0x0C33: 'l',
    0x0C35: 'v', 0x0C36: 'sh', 0x0C37: 'sh', 0x0C38: 's', 0x0C39: 'h',
  };

  static final Map<int, String> _teluguVowelSigns = {
    0x0C3E: 'aa', 0x0C3F: 'i', 0x0C40: 'ee', 0x0C41: 'u', 0x0C42: 'oo',
    0x0C46: 'e', 0x0C47: 'ae', 0x0C48: 'ai', 0x0C4A: 'o', 0x0C4B: 'oa',
    0x0C4C: 'au', 0x0C02: 'm',
  };

  static int _transliterateTelugu(List<int> runes, int index, StringBuffer out) {
    final code = runes[index];

    if (_teluguIndependentVowels.containsKey(code)) {
      out.write(_teluguIndependentVowels[code]);
      return index + 1;
    }

    if (_teluguConsonants.containsKey(code)) {
      final base = _teluguConsonants[code]!;

      if (index + 1 < runes.length) {
        final nextCode = runes[index + 1];

        // Halant (0x0C4D): virama
        if (nextCode == 0x0C4D) {
          out.write(base);
          return index + 2;
        }

        if (_teluguVowelSigns.containsKey(nextCode)) {
          out.write(base);
          out.write(_teluguVowelSigns[nextCode]);
          return index + 2;
        }
      }

      out.write('${base}a');
      return index + 1;
    }

    if (_teluguVowelSigns.containsKey(code)) {
      out.write(_teluguVowelSigns[code]);
      return index + 1;
    }

    if (code == 0x0C4D) return index + 1;

    out.writeCharCode(code);
    return index + 1;
  }

  // =========================================================================
  // 4. MALAYALAM TRANSLITERATION (മലയാളം)
  // =========================================================================

  static final Map<int, String> _malayalamIndependentVowels = {
    0x0D05: 'a', 0x0D06: 'aa', 0x0D07: 'i', 0x0D08: 'ee', 0x0D09: 'u',
    0x0D0A: 'oo', 0x0D0E: 'e', 0x0D0F: 'ae', 0x0D10: 'ai', 0x0D12: 'o',
    0x0D13: 'oa', 0x0D14: 'au', 0x0D02: 'm',
  };

  static final Map<int, String> _malayalamConsonants = {
    0x0D15: 'k', 0x0D16: 'kh', 0x0D17: 'g', 0x0D18: 'gh', 0x0D19: 'ng',
    0x0D1A: 'ch', 0x0D1B: 'chh', 0x0D1C: 'j', 0x0D1D: 'jh', 0x0D1E: 'ny',
    0x0D1F: 't', 0x0D20: 'th', 0x0D21: 'd', 0x0D22: 'dh', 0x0D23: 'n',
    0x0D24: 'th', 0x0D25: 'th', 0x0D26: 'd', 0x0D27: 'dh', 0x0D28: 'n',
    0x0D2A: 'p', 0x0D2B: 'ph', 0x0D2C: 'b', 0x0D2D: 'bh', 0x0D2E: 'm',
    0x0D2F: 'y', 0x0D30: 'r', 0x0D31: 'r', 0x0D32: 'l', 0x0D33: 'l',
    0x0D34: 'zh', 0x0D35: 'v', 0x0D36: 'sh', 0x0D37: 'sh', 0x0D38: 's', 0x0D39: 'h',
    // Chillu letters
    0x0D7A: 'n', 0x0D7B: 'n', 0x0D7C: 'r', 0x0D7D: 'l', 0x0D7E: 'l', 0x0D7F: 'k',
  };

  static final Map<int, String> _malayalamVowelSigns = {
    0x0D3E: 'aa', 0x0D3F: 'i', 0x0D40: 'ee', 0x0D41: 'u', 0x0D42: 'oo',
    0x0D46: 'e', 0x0D47: 'ae', 0x0D48: 'ai', 0x0D4A: 'o', 0x0D4B: 'oa',
    0x0D4C: 'au', 0x0D02: 'm',
  };

  static int _transliterateMalayalam(List<int> runes, int index, StringBuffer out) {
    final code = runes[index];

    if (_malayalamIndependentVowels.containsKey(code)) {
      out.write(_malayalamIndependentVowels[code]);
      return index + 1;
    }

    if (_malayalamConsonants.containsKey(code)) {
      final base = _malayalamConsonants[code]!;

      // Chillu characters are pure consonants without inherent 'a'
      if (code >= 0x0D7A && code <= 0x0D7F) {
        out.write(base);
        return index + 1;
      }

      if (index + 1 < runes.length) {
        final nextCode = runes[index + 1];

        // Chandrakkala (virama 0x0D4D)
        if (nextCode == 0x0D4D) {
          out.write(base);
          return index + 2;
        }

        if (_malayalamVowelSigns.containsKey(nextCode)) {
          out.write(base);
          out.write(_malayalamVowelSigns[nextCode]);
          return index + 2;
        }
      }

      out.write('${base}a');
      return index + 1;
    }

    if (_malayalamVowelSigns.containsKey(code)) {
      out.write(_malayalamVowelSigns[code]);
      return index + 1;
    }

    if (code == 0x0D4D) return index + 1;

    out.writeCharCode(code);
    return index + 1;
  }

  // =========================================================================
  // 5. KANNADA TRANSLITERATION (ಕನ್ನಡ)
  // =========================================================================

  static final Map<int, String> _kannadaIndependentVowels = {
    0x0C85: 'a', 0x0C86: 'aa', 0x0C87: 'i', 0x0C88: 'ee', 0x0C89: 'u',
    0x0C8A: 'oo', 0x0C8E: 'e', 0x0C8F: 'ae', 0x0C90: 'ai', 0x0C92: 'o',
    0x0C93: 'oa', 0x0C94: 'au', 0x0C82: 'm',
  };

  static final Map<int, String> _kannadaConsonants = {
    0x0C95: 'k', 0x0C96: 'kh', 0x0C97: 'g', 0x0C98: 'gh', 0x0C99: 'ng',
    0x0C9A: 'ch', 0x0C9B: 'chh', 0x0C9C: 'j', 0x0C9D: 'jh', 0x0C9E: 'ny',
    0x0C9F: 't', 0x0CA0: 'th', 0x0CA1: 'd', 0x0CA2: 'dh', 0x0CA3: 'n',
    0x0CA4: 'th', 0x0CA5: 'th', 0x0CA6: 'd', 0x0CA7: 'dh', 0x0CA8: 'n',
    0x0CAA: 'p', 0x0CAB: 'ph', 0x0CAC: 'b', 0x0CAD: 'bh', 0x0CAE: 'm',
    0x0CAF: 'y', 0x0CB0: 'r', 0x0CB1: 'r', 0x0CB2: 'l', 0x0CB3: 'l',
    0x0CB5: 'v', 0x0CB6: 'sh', 0x0CB7: 'sh', 0x0CB8: 's', 0x0CB9: 'h',
  };

  static final Map<int, String> _kannadaVowelSigns = {
    0x0CBE: 'aa', 0x0CBF: 'i', 0x0CC0: 'ee', 0x0CC1: 'u', 0x0CC2: 'oo',
    0x0CC6: 'e', 0x0CC7: 'ae', 0x0CC8: 'ai', 0x0CCA: 'o', 0x0CCB: 'oa',
    0x0CCC: 'au', 0x0C82: 'm',
  };

  static int _transliterateKannada(List<int> runes, int index, StringBuffer out) {
    final code = runes[index];

    if (_kannadaIndependentVowels.containsKey(code)) {
      out.write(_kannadaIndependentVowels[code]);
      return index + 1;
    }

    if (_kannadaConsonants.containsKey(code)) {
      final base = _kannadaConsonants[code]!;

      if (index + 1 < runes.length) {
        final nextCode = runes[index + 1];

        // Virama (0x0CCD)
        if (nextCode == 0x0CCD) {
          out.write(base);
          return index + 2;
        }

        if (_kannadaVowelSigns.containsKey(nextCode)) {
          out.write(base);
          out.write(_kannadaVowelSigns[nextCode]);
          return index + 2;
        }
      }

      out.write('${base}a');
      return index + 1;
    }

    if (_kannadaVowelSigns.containsKey(code)) {
      out.write(_kannadaVowelSigns[code]);
      return index + 1;
    }

    if (code == 0x0CCD) return index + 1;

    out.writeCharCode(code);
    return index + 1;
  }
}
