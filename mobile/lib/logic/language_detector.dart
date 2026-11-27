import '../data/catalog_artists_seed.dart';
import '../models/song.dart';
import '../services/settings_manager.dart';

/// Deterministic, on-device language inference and compatibility checks for
/// next-song recommendations (English, Tamil, Hindi, Telugu, Malayalam, Kannada, Punjabi).
class LanguageDetector {
  LanguageDetector._();

  static const Map<String, String> composerLanguageMap = {
    'a r rahman': 'tamil',
    'ar rahman': 'tamil',
    'anirudh': 'tamil',
    'anirudh ravichander': 'tamil',
    'yuvan': 'tamil',
    'yuvan shankar raja': 'tamil',
    'harris jayaraj': 'tamil',
    'ilaiyaraaja': 'tamil',
    'ilayaraja': 'tamil',
    'santhosh narayanan': 'tamil',
    'gv prakash': 'tamil',
    'gv prakash kumar': 'tamil',
    'g v prakash kumar': 'tamil',
    'd imman': 'tamil',
    'imman': 'tamil',
    'deva': 'tamil',
    'vidyasagar': 'tamil',
    'hiphop tamizha': 'tamil',
    'ghibran': 'tamil',
    'sam cs': 'tamil',
    'm s viswanathan': 'tamil',
    'kv mahadevan': 'tamil',
    'justin prabhakaran': 'tamil',
    'leon james': 'tamil',
    'dhibu ninan thomas': 'tamil',
    'sean roldan': 'tamil',
    'keeravaani': 'telugu',
    'm m keeravaani': 'telugu',
    'thaman': 'telugu',
    'thaman s': 'telugu',
    'devi sri prasad': 'telugu',
    'dsp': 'telugu',
    'pritam': 'hindi',
    'vishal shekhar': 'hindi',
    'ajay atul': 'hindi',
    'amit trivedi': 'hindi',
    'sachin jigar': 'hindi',
    'meet bros': 'hindi',
    'shankar ehsaan loy': 'hindi',
    'himesh reshammiya': 'hindi',
    'anu malik': 'hindi',
    'mithoon': 'hindi',
    'sushin shyam': 'malayalam',
    'shaan rahman': 'malayalam',
    'deepak dev': 'malayalam',
    'bijibal': 'malayalam',
    'jassie gift': 'malayalam',
    'jakes bejoy': 'malayalam',
    'hesham abdul wahab': 'malayalam',
  };

  static const Map<String, String> _regionalKeywords = {
    'bollywood': 'hindi',
    'kollywood': 'tamil',
    'tollywood': 'telugu',
    'mollywood': 'malayalam',
    'sandalwood': 'kannada',
    'punjabi': 'punjabi',
    'bhangra': 'punjabi',
  };

  static Map<String, Set<String>>? _artistLanguageIndex;

  static Map<String, Set<String>> get _artistLanguages {
    if (_artistLanguageIndex != null) return _artistLanguageIndex!;
    final map = <String, Set<String>>{};
    for (final entry in CatalogArtistsSeed.data) {
      final name = entry.name.trim().toLowerCase();
      final lang = normalizeLanguage(entry.language);
      if (name.isEmpty || lang == null) continue;
      map.putIfAbsent(name, () => <String>{}).add(lang);
    }
    _artistLanguageIndex = map;
    return map;
  }

  static String? normalizeLanguage(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim().toLowerCase();
    if (clean.isEmpty || clean == 'unknown' || clean == 'all') return null;
    if (clean == 'en' || clean.startsWith('eng')) return 'english';
    if (clean == 'ta' || clean.startsWith('tam')) return 'tamil';
    if (clean == 'hi' || clean == 'devanagari' || clean.startsWith('hin')) return 'hindi';
    if (clean == 'te' || clean.startsWith('tel')) return 'telugu';
    if (clean == 'ml' || clean.startsWith('mal')) return 'malayalam';
    if (clean == 'kn' || clean.startsWith('kan')) return 'kannada';
    if (clean == 'pa' || clean.startsWith('pun')) return 'punjabi';
    return clean;
  }

  static String? detectIndicScript(String text) {
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'tamil';
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hindi';
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return 'telugu';
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'malayalam';
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kannada';
    return null;
  }

  /// Infers the primary language of [song].
  /// Returns `'english'` for Latin-script tracks with no Indic script, artist,
  /// composer, or regional keyword match.
  static String inferSongLanguage(Song song, {bool fallbackToPreferred = false}) {
    final explicit = normalizeLanguage(song.language);
    if (explicit != null) return explicit;

    final combined = '${song.title} ${song.artist} ${song.album}';
    final scriptLang = detectIndicScript(combined);
    if (scriptLang != null) return scriptLang;

    final artistLower = song.artist.toLowerCase();
    for (final entry in _artistLanguages.entries) {
      if (artistLower.contains(entry.key)) {
        return entry.value.first;
      }
    }
    for (final entry in composerLanguageMap.entries) {
      if (artistLower.contains(entry.key)) return entry.value;
    }

    final lower = combined.toLowerCase();
    for (final entry in _regionalKeywords.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    if (RegExp(r'[a-zA-Z0-9]').hasMatch('${song.title}${song.artist}')) {
      return 'english';
    }
    if (fallbackToPreferred && SettingsManager.preferredLanguages.isNotEmpty) {
      return normalizeLanguage(SettingsManager.preferredLanguages.first) ?? 'english';
    }
    return 'english';
  }

  /// Returns `true` if [candidate] is compatible with [targetLang].
  static bool isLanguageCompatible(Song candidate, String targetLang) {
    final normTarget = normalizeLanguage(targetLang);
    if (normTarget == null) return true;

    final explicit = normalizeLanguage(candidate.language);
    if (explicit != null) return explicit == normTarget;

    final artistLower = candidate.artist.toLowerCase();
    for (final entry in _artistLanguages.entries) {
      if (artistLower.contains(entry.key)) {
        if (entry.value.contains(normTarget)) return true;
        if (normTarget == 'english' && !entry.value.contains('english')) return false;
        if (normTarget != 'english' && entry.value.contains('english') && entry.value.length == 1) {
          return false;
        }
      }
    }

    if (normTarget == 'english') {
      return inferSongLanguage(candidate) == 'english';
    }

    final detected = detectIndicScript('${candidate.title} ${candidate.artist}');
    if (detected != null && detected != normTarget) {
      return false;
    }
    return true;
  }
}
