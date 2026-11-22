import '../../models/song.dart';
import '../../logic/search_query_planner.dart';
import '../../logic/lyrics/indic_romanizer.dart';
import '../fuzzy_search_service.dart';
import 'search_models.dart';
import 'search_filter_engine.dart';

/// Handles phonetic query expansion, multi-language query intent detection,
/// Indic script transliteration, and entity/attribute filtering for search results.
class QueryNormalizer {
  static final RegExp dialogueRegex = RegExp(
    r'\b(dialogues?|punch\s*dialogues?|mass\s*dialogues?|movie\s*scenes?|comedy\s*scenes?|audio\s*scenes?|dialogue\s*mix|scenes?|ringtones?|bgm\s*ringtones?)\b',
    caseSensitive: false,
  );

  static final RegExp arabicScriptRegex = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]',
  );

  static final RegExp knownIndianArtistsRegex = RegExp(
    r'\b(anirudh|rahman|yuvan|harris|santhosh|hiphop|ilaiyaraaja|sid\s*sriram|pradeep|spb|jen\s*martin|hesham|dhanush|karthik|shreya|jonita|chinmayi|vijay|ajith|surya|rajini|kamal|nani|keerthy)\b',
    caseSensitive: false,
  );

  static final RegExp _fromMovieBaseRegex = RegExp(
    r'[\(\[\-]\s*(?:from|ost|movie|soundtrack)\s*[\":\s]*',
    caseSensitive: false,
  );

  static const List<String> knownLanguages = [
    'tamil', 'telugu', 'hindi', 'english', 'malayalam',
    'kannada', 'punjabi', 'marathi', 'bengali',
  ];

  static const Map<String, String> tanglishIndex = {
    'mesaya muruku': 'Meesaya Murukku', 'meesaya muruku': 'Meesaya Murukku',
    'mesaya murukku': 'Meesaya Murukku', 'oorum blood': 'Oorum Blood',
    'oorum raththam': 'Oorum Blood', 'puthu mazha': 'Puthu Mazha',
    'pudhu mazha': 'Puthu Mazha', 'pudhumazha': 'Puthu Mazha',
    'puthumazha': 'Puthu Mazha', 'vaathi coming': 'Vaathi Coming',
    'vathi coming': 'Vaathi Coming', 'rowdy bby': 'Rowdy Baby',
    'rowdy baby': 'Rowdy Baby', 'alaporan tamizhan': 'Aalaporaan Thamizhan',
    'aalaporan': 'Aalaporaan Thamizhan', 'arabic kuthu': 'Arabic Kuthu',
    'arabik kuthu': 'Arabic Kuthu',
  };

  static bool isWordChar(int code) {
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }

  /// Expands common South Indian, Tanglish, and phonetically variant queries
  static String expandPhoneticQuery(String query) {
    var text = query.trim().toLowerCase();
    if (text.isEmpty) return query;

    // 0. Automatic Indic Script Transliteration (Tamil, Hindi, Telugu, Malayalam, Kannada)
    if (IndicRomanizer.hasIndicScript(text)) {
      final roman = IndicRomanizer.romanize(text).trim();
      if (roman.isNotEmpty) return roman;
    }

    if (tanglishIndex.containsKey(text)) {
      return tanglishIndex[text]!;
    }

    // Common phonetic swaps
    text = text.replaceAll('aniruth', 'anirudh')
               .replaceAll('ar rehman', 'ar rahman')
               .replaceAll('rehman', 'rahman')
               .replaceAll('yuvan shanker', 'yuvan shankar')
               .replaceAll('ilayaraja', 'ilaiyaraaja')
               .replaceAll('ilayaraaja', 'ilaiyaraaja')
               .replaceAll('hukkum', 'hukum')
               .replaceAll('hukm', 'hukum')
               .replaceAll('nerupuda', 'neruppu da')
               .replaceAll('kadaippoma', 'kadhaippoma')
               .replaceAll('waseegara', 'vaseegara')
               .replaceAll('vasikara', 'vaseegara')
               .replaceAll('mesaya muruku', 'meesaya murukku')
               .replaceAll('oorum raththam', 'oorum blood')
               .replaceAll('oorum ratham', 'oorum blood');

    return text;
  }

  /// Generates multi-language universal phonetic variants for Romanized search queries.
  static List<String> generateUniversalPhoneticVariants(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.length < 3) return const [];

    final variants = <String>{};

    // 1. Check BK-Tree / Fuzzy dictionary for closest known entry within edit distance <= 1
    final correction = FuzzySearchService.findCorrection(clean);
    if (correction != null && correction.corrected.toLowerCase() != clean) {
      variants.add(correction.corrected.toLowerCase());
    }

    // 2. Vowel substitutions
    if (clean.contains('ar') || clean.contains('er')) {
      variants.add(clean.replaceAll('ar', 'er'));
      variants.add(clean.replaceAll('er', 'ar'));
    }
    if (clean.contains('al') || clean.contains('el')) {
      variants.add(clean.replaceAll('al', 'el'));
      variants.add(clean.replaceAll('el', 'al'));
    }
    if (clean.contains('a') && !clean.contains('e')) {
      variants.add(clean.replaceFirst('a', 'e'));
    } else if (clean.contains('e') && !clean.contains('a')) {
      variants.add(clean.replaceFirst('e', 'a'));
    }

    if (clean.contains('ee')) {
      variants.add(clean.replaceAll('ee', 'i'));
    } else if (clean.contains('i')) {
      variants.add(clean.replaceAll('i', 'ee'));
    }

    if (clean.contains('oo')) {
      variants.add(clean.replaceAll('oo', 'u'));
    } else if (clean.contains('u')) {
      variants.add(clean.replaceAll('u', 'oo'));
    }

    if (clean.contains('ai')) {
      variants.add(clean.replaceAll('ai', 'ay'));
    } else if (clean.contains('ay')) {
      variants.add(clean.replaceAll('ay', 'ai'));
    }

    if (clean.contains('au')) {
      variants.add(clean.replaceAll('au', 'ou'));
    } else if (clean.contains('ou')) {
      variants.add(clean.replaceAll('ou', 'au'));
    }

    // 3. Consonant normalizations
    if (clean.contains('w')) {
      variants.add(clean.replaceAll('w', 'v'));
    } else if (clean.contains('v')) {
      variants.add(clean.replaceAll('v', 'w'));
    }

    // Geminate collapse (e.g. "neruppu" -> "nerupu", "kutty" -> "kuty")
    final collapsed = clean.replaceAllMapped(RegExp(r'([b-df-hj-np-tv-z])\1'), (m) => m[1]!);
    if (collapsed != clean) {
      variants.add(collapsed);
    }

    // Dental / retroflex aspirates (e.g. "aniruth" -> "anirudh")
    if (clean.endsWith('uth')) {
      variants.add('${clean.substring(0, clean.length - 3)}udh');
    }

    // Indic Script romanization variant
    if (IndicRomanizer.hasIndicScript(clean)) {
      final roman = IndicRomanizer.romanize(clean).trim().toLowerCase();
      if (roman.isNotEmpty && roman != clean) variants.add(roman);
    }

    // South Indian allophone folding (zh <-> l, th <-> dh, ph <-> f)
    if (clean.contains('zh')) variants.add(clean.replaceAll('zh', 'l'));
    if (clean.contains('th')) variants.add(clean.replaceAll('th', 'dh'));
    if (clean.contains('dh')) variants.add(clean.replaceAll('dh', 'th'));
    if (clean.contains('ph')) variants.add(clean.replaceAll('ph', 'f'));
    if (clean.contains('f')) variants.add(clean.replaceAll('f', 'ph'));

    // Geminate consonant expansion
    for (final ch in const ['k', 'p', 't', 'l', 'm', 'n', 'r']) {
      final medialRegex = RegExp('([aeiou])$ch([aeiou])');
      if (medialRegex.hasMatch(clean) && !clean.contains('$ch$ch')) {
        variants.add(clean.replaceAllMapped(medialRegex, (m) => '${m[1]}$ch$ch${m[2]}'));
      }
    }

    variants.remove(clean);
    return variants.where((v) => v != clean && v.length >= 3).toList();
  }

  /// Returns true if an album title or song.album matches a film entity query
  static bool isAlbumOrMovieEntityMatch(String title, String query) {
    final t = title.toLowerCase().trim();
    final q = query.toLowerCase().trim();
    if (q.isEmpty || t.isEmpty) return false;
    if (t == q) return true;

    final baseT = t.contains(' - ') ? t.split(' - ').first.trim() : t;
    if (baseT == q) return true;
    if (t.startsWith(q) || baseT.startsWith(q)) return true;

    // Check "(From <movie>)", "(From \"<movie>\")", "[From <movie>]", "From <movie>"
    for (final m in _fromMovieBaseRegex.allMatches(t)) {
      if (t.startsWith(q, m.end)) return true;
    }

    // Direct containment with word boundaries for queries >= 2 chars
    if (q.length >= 2 && t.contains(q)) {
      var start = 0;
      final qLen = q.length;
      final tLen = t.length;
      while (true) {
        final idx = t.indexOf(q, start);
        if (idx == -1) break;
        final startBoundary = idx == 0 || !isWordChar(t.codeUnitAt(idx - 1));
        final endBoundary = (idx + qLen == tLen) || !isWordChar(t.codeUnitAt(idx + qLen));
        if (startBoundary && endBoundary) return true;
        start = idx + 1;
      }
    }

    return false;
  }

  /// Strictly filters search artists by language and placeholder images
  static List<Map<String, dynamic>> filterArtistsByLanguage(
    List<Map<String, dynamic>> artists, {
    String? language,
    required String query,
  }) => SearchFilterEngine.filterArtistsByLanguage(artists, language: language, query: query);

  /// Strictly filters out single-song releases, fake albums, and unrelated compilations
  static List<Map<String, dynamic>> filterGenuineAlbums(
    List<Map<String, dynamic>> rawAlbums, {
    String? query,
    String? preferredLanguage,
    List<String>? preferredLanguages,
  }) => SearchFilterEngine.filterGenuineAlbums(rawAlbums, query: query, preferredLanguage: preferredLanguage, preferredLanguages: preferredLanguages);

  /// Filters playlists to ensure query relevance and language alignment
  static List<Map<String, dynamic>> filterPlaylistsByRelevanceAndLanguage(
    List<Map<String, dynamic>> rawPlaylists, {
    required String query,
    String? language,
  }) => SearchFilterEngine.filterPlaylistsByRelevanceAndLanguage(rawPlaylists, query: query, language: language);

  /// Dynamically extracts and synthesizes clean movie and soundtrack albums from a list of songs
  static List<Map<String, dynamic>> extractAlbumsFromSongList(
    List<Song> songs, {
    String? query,
    List<Map<String, dynamic>>? existingAlbums,
    List<String>? preferredLanguages,
  }) => SearchFilterEngine.extractAlbumsFromSongList(songs, query: query, existingAlbums: existingAlbums, preferredLanguages: preferredLanguages);

  /// Understands user query: detects script, explicit language override, and Tanglish transliteration
  static QueryIntent understandQuery(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const QueryIntent(rawQuery: '', cleanQuery: '', transliteratedQuery: '');
    }

    String? detectedScript;
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(trimmed)) {
      detectedScript = 'tamil';
    } else if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(trimmed)) {
      detectedScript = 'telugu';
    } else if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(trimmed)) {
      detectedScript = 'malayalam';
    } else if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(trimmed)) {
      detectedScript = 'kannada';
    } else if (RegExp(r'[\u0900-\u097F]').hasMatch(trimmed)) {
      detectedScript = 'devanagari';
    } else {
      detectedScript = 'latin';
    }

    String clean = trimmed;
    String? explicitLang;
    final lower = trimmed.toLowerCase();

    for (final lang in knownLanguages) {
      final langPattern = RegExp('\\b$lang\\b', caseSensitive: false);
      if (langPattern.hasMatch(lower)) {
        final isTitleEntity = lower == 'hindi medium' || lower.startsWith('hindi medium ') || lower.endsWith(' hindi medium') ||
            lower == 'english vinglish' || lower.startsWith('english vinglish ') || lower.endsWith(' english vinglish');
        if (isTitleEntity) {
          explicitLang = null;
          clean = trimmed;
          break;
        }

        final stripped = clean.replaceAll(langPattern, '').replaceAll(RegExp(r'\s+'), ' ').trim();
        explicitLang = lang[0].toUpperCase() + lang.substring(1);
        clean = stripped.isEmpty ? trimmed : stripped;
        break;
      }
    }

    if (clean.isEmpty) clean = trimmed;

    if (explicitLang == null) {
      if (clean.contains('मराठी')) {
        explicitLang = 'Marathi';
      } else if (clean.contains('हिंदी') || clean.contains('हिन्दी')) {
        explicitLang = 'Hindi';
      } else if (clean.contains('தமிழ்')) {
        explicitLang = 'Tamil';
      } else if (clean.contains('తెలుగు')) {
        explicitLang = 'Telugu';
      } else if (clean.contains('മലയാളം')) {
        explicitLang = 'Malayalam';
      } else if (clean.contains('ಕನ್ನಡ')) {
        explicitLang = 'Kannada';
      }
    }

    final cleanLower = clean.toLowerCase();
    String transliterated = clean;
    String? didYouMean;

    if (IndicRomanizer.hasIndicScript(clean)) {
      final roman = IndicRomanizer.romanize(clean).trim();
      if (roman.isNotEmpty && roman.toLowerCase() != cleanLower) {
        transliterated = roman;
      }
      if (explicitLang == null) {
        final detected = IndicRomanizer.detectScript(clean);
        if (detected != 'latin' && detected != 'devanagari') {
          final lang = IndicRomanizer.scriptToLanguage(detected);
          explicitLang = lang[0].toUpperCase() + lang.substring(1);
        }
      }
    } else if (tanglishIndex.containsKey(cleanLower)) {
      transliterated = tanglishIndex[cleanLower]!;
      didYouMean = transliterated;
    } else {
      for (final entry in tanglishIndex.entries) {
        if (cleanLower.contains(entry.key)) {
          transliterated = cleanLower.replaceAll(entry.key, entry.value);
          didYouMean = transliterated;
          break;
        }
      }
    }

    if (didYouMean == null && !IndicRomanizer.hasIndicScript(clean)) {
      final typoOrTanglish = FuzzySearchService.findCorrection(cleanLower);
      if (typoOrTanglish != null && typoOrTanglish.corrected.toLowerCase() != cleanLower) {
        transliterated = typoOrTanglish.corrected;
        didYouMean = typoOrTanglish.corrected;
      }
    }

    if (didYouMean == null) {
      final phoneticExpanded = expandPhoneticQuery(cleanLower);
      if (phoneticExpanded.toLowerCase() != cleanLower) {
        transliterated = phoneticExpanded;
        if (!IndicRomanizer.hasIndicScript(clean)) {
          didYouMean = phoneticExpanded;
        }
      }
    }

    String? universalPhonetic;
    final phoneticVariants = generateUniversalPhoneticVariants(cleanLower);
    if (phoneticVariants.isNotEmpty) {
      universalPhonetic = phoneticVariants.firstWhere(
        (v) => FuzzySearchService.containsCandidate(v),
        orElse: () => '',
      );
      if (universalPhonetic.isEmpty) {
        universalPhonetic = null;
      }
    }

    if (transliterated.toLowerCase() == cleanLower && universalPhonetic != null) {
      transliterated = universalPhonetic;
    }

    if (didYouMean == null && cleanLower != transliterated.toLowerCase() && !IndicRomanizer.hasIndicScript(clean)) {
      didYouMean = transliterated;
    }

    final isRemix = lower.contains('remix') || lower.contains('lofi') || lower.contains('slowed');
    final core = SearchQueryPlanner.extractCoreSubject(clean);

    return QueryIntent(
      rawQuery: trimmed,
      cleanQuery: clean,
      coreSubject: core,
      detectedScript: detectedScript,
      explicitLanguage: explicitLang,
      transliteratedQuery: transliterated,
      isRemixIntent: isRemix,
      didYouMeanSuggestion: didYouMean,
      universalPhoneticVariant: universalPhonetic,
    );
  }
}
