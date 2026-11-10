import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:html_unescape/html_unescape.dart';
import '../domain/models/lyrics_state.dart';
import '../logic/lyrics/indic_romanizer.dart';
import '../models/song.dart';
import 'app_logger.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';

/// Represents a single word in a synchronized lyric line with start and end timestamps.
class LyricWord {
  final String text;
  final String? romanizedText;
  final Duration start;
  final Duration end;

  const LyricWord({
    required this.text,
    this.romanizedText,
    required this.start,
    required this.end,
  });

  /// Calculates the 0.0 - 1.0 progress of this word for a given audio position.
  double progressAt(Duration position) {
    if (position <= start) return 0.0;
    if (position >= end) return 1.0;
    final total = end.inMilliseconds - start.inMilliseconds;
    if (total <= 0) return 1.0;
    final elapsed = position.inMilliseconds - start.inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}

/// Single parsed lyric line with timestamps, words, and optional romanized text.
class LyricLine {
  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;
  final String? romanizedText;
  final bool isBgm;
  final List<LyricWord> words;

  const LyricLine({
    required this.timestamp,
    this.endTimestamp,
    required this.text,
    this.romanizedText,
    this.isBgm = false,
    this.words = const [],
  });
}

/// Direct on-device Lyrics client communicating directly with LRCLIB & JioSaavn.
/// Bypasses backend server completely, provides 0ms memory & Hive caching,
/// duration-scored LRC selection, and auto-timed progressive plain lyrics.
class LyricsClient {
  static final LyricsClient instance = LyricsClient._internal();
  LyricsClient._internal();

  static final HtmlUnescape _unescape = HtmlUnescape();
  static const String _userAgent = 'PaatuPadava/1.0 (Flutter)';
  static const String _boxName = 'lyrics_cache';
  static const int _maxMemoryCacheSize = 100;

  final Map<String, LyricsState> _memoryCache = {};
  final Map<String, List<Map<String, dynamic>>> _candidatesCache = {};

  /// Exposes memory cache for test verification
  @visibleForTesting
  Map<String, LyricsState> get memoryCache => _memoryCache;

  /// Exposes candidates cache for test verification
  @visibleForTesting
  Map<String, List<Map<String, dynamic>>> get candidatesCache => _candidatesCache;

  Future<Box?> _getBox() async {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        return Hive.box(_boxName);
      }
      return await Hive.openBox(_boxName);
    } catch (_) {
      return null;
    }
  }

  // ================= 1. Title & Artist Sanitization ================= //

  /// Cleans song titles by stripping extraneous tags, video markers, and parenthetical metadata.
  static String sanitizeTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';
    var t = _unescape.convert(Song.sanitize(rawTitle));

    // 1. Strip leading channel/artist handles (e.g. "@SaiAbhyankkar - ")
    t = t.replaceAll(RegExp(r'^@[a-zA-Z0-9_.]+\s*[-:|~–—]?\s*'), '');

    // 2. Strip leading track numbers like "01 - ", "02. ", "1. "
    t = t.replaceAll(RegExp(r'^\d{1,3}[\s.\-_:]+\s*'), '');

    // 3. Strip web domain tags: [Masstamilan], [SongsLover], [Starmusiq], etc.
    t = t.replaceAll(
      RegExp(r'\[\s*(?:masstamilan|starmusiq|isaimini|senlyrics|123musiq|songslover|tamildada|mp3paw)[^\]]*\]', caseSensitive: false),
      '',
    );

    // 4. Strip pipe '|' and anything after it
    t = t.replaceAll(RegExp(r'\|.*$'), '');

    // 5. Strip "- From ..." or " - From Movie"
    t = t.replaceAll(RegExp(r'\s*-\s*from\b.*$', caseSensitive: false), '');

    // 6. Strip parenthetical/bracketed "From ..." markers: (From "Movie"), [From Movie]
    t = t.replaceAll(
      RegExp(r'\s*[\(\[][Ff]rom\s+["\u201c\u201d\u2018\u2019]?[^)\u201d\]]+["\u201c\u201d\u2018\u2019]?[\)\]]'),
      '',
    );

    // 7. Strip language indicators in parentheses/brackets: (Tamil), (Telugu), [Hindi], etc.
    t = t.replaceAll(
      RegExp(r'\s*[\(\[](?:tamil|telugu|hindi|malayalam|kannada|bengali|marathi|punjabi|english|bhojpuri|gujarati)[\)\]]', caseSensitive: false),
      '',
    );

    // 8. Strip audio effect tags: (Slowed + Reverb), (8D Audio), (Lofi), etc.
    t = t.replaceAll(
      RegExp(r'\s*[\(\[](?:slowed(?:\s*[\+&]\s*reverb)?|reverb|bass\s*boosted|8d\s*audio|lo-?fi|sped\s*up|speed\s*up)[\)\]]', caseSensitive: false),
      '',
    );

    // 9. Strip official video, audio, lyrical, ost, soundtrack, remaster markers
    t = t.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:official|audio|video|lyric|lyrical|soundtrack|ost|theme|score|remaster|full\s*song|visuali[sz]er|motion\s*poster|teaser|trailer|color\s*coded)[\)\]]', caseSensitive: false),
      '',
    );

    // 10. Strip featured artists in brackets/parentheses: (feat. Sid Sriram), [ft. Anirudh]
    t = t.replaceAll(
      RegExp(r'\s*[\(\[](?:feat\.?|ft\.?|featuring)\s+[^)\]]+[\)\]]', caseSensitive: false),
      '',
    );

    // 11. Strip standalone video/audio keywords
    t = t.replaceAll(
      RegExp(r'\b(lyrical|video song|audio song|full song|4k|8k|hd|uhd|1080p|720p|remastered|lyrics? video|promo|visuali[sz]er)\b', caseSensitive: false),
      '',
    );

    // 12. Strip lingering square brackets content
    t = t.replaceAll(RegExp(r'\[[^\]]*\]'), '');

    // 13. Strip trailing feat / ft clause at end of title: "Song Name ft. Artist"
    t = t.replaceAll(RegExp(r'\s+\b(?:feat\.?|ft\.?|featuring)\b\s+.*$', caseSensitive: false), '');

    // 14. Strip trailing release metadata: " - Remastered 2021", " - Radio Edit", " - Live at ..."
    t = t.replaceAll(RegExp(r'\s*-\s*(?:remaster(?:ed)?(?:\s*\d{4})?|radio edit|deluxe(?:\s*edition)?|live(?:\s*at\b.*)?|mono|stereo)\b.*$', caseSensitive: false), '');

    // 15. Clean stray parentheses
    t = t.replaceAll(RegExp(r'[\(\)]'), ' ');

    // 16. Strip leading and trailing punctuation (hyphens, dashes, colons, slashes, pipes, tildes, commas)
    t = t.replaceAll(RegExp(r'^[\s\-–—:~|/,.\+]+|[\s\-–—:~|/,.\+]+$'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// Generates a prioritized, deduplicated list of candidate title variations
  /// to maximize hit rate on lyrics providers (LRCLIB, JioSaavn, YouTube Captions).
  /// Correctly handles:
  /// - YouTube "Movie - Song" or "Artist - Song" patterns (e.g. "Leo - Badass" -> "Badass", "Leo - Badass")
  /// - Subtitles & alternate song names (e.g. "Hukum - Thalaivar Alappara" -> "Hukum", "Thalaivar Alappara")
  /// - Artist/Album prefix de-duplication
  static List<String> generateTitleCandidates(String rawTitle, {String? artist, String? album}) {
    final cleanBase = sanitizeTitle(rawTitle);
    if (cleanBase.isEmpty) return const [];

    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String s) {
      final trimmed = s.replaceAll(RegExp(r'^[\s\-–—:~|/,.\+]+|[\s\-–—:~|/,.\+]+$'), '').trim();
      if (trimmed.length >= 2 && seen.add(trimmed.toLowerCase())) {
        candidates.add(trimmed);
      }
    }

    final cleanArtist = (artist != null && artist.isNotEmpty) ? sanitizeArtist(artist).toLowerCase() : '';
    final cleanAlbum = (album != null && album.isNotEmpty && album.toLowerCase() != 'unknown album') ? sanitizeTitle(album).toLowerCase() : '';

    // Check if raw title has trailing/enclosed parenthetical or bracketed notes (e.g. "(Spider-Man: ...)", "(From Movie)")
    // and extract the core title before the brackets
    final preBracket = rawTitle.split(RegExp(r'[\(\[\{]')).first.trim();
    final cleanPre = sanitizeTitle(preBracket);
    final preSeparatorMatch = RegExp(r'\s*([-–—:~])\s*').firstMatch(cleanPre);
    if (preSeparatorMatch != null) {
      final pA = cleanPre.substring(0, preSeparatorMatch.start).trim();
      final pB = cleanPre.substring(preSeparatorMatch.end).trim();
      if (cleanArtist.isNotEmpty && (cleanArtist.contains(pA.toLowerCase()) || pA.toLowerCase().contains(cleanArtist))) {
        addCandidate(pB);
      } else if (cleanArtist.isNotEmpty && (cleanArtist.contains(pB.toLowerCase()) || pB.toLowerCase().contains(cleanArtist))) {
        addCandidate(pA);
      } else if (cleanAlbum.isNotEmpty && (cleanAlbum == pA.toLowerCase() || cleanAlbum.contains(pA.toLowerCase()))) {
        addCandidate(pB);
      } else {
        addCandidate(pB);
        addCandidate(pA);
      }
    } else if (cleanPre.isNotEmpty && cleanPre != cleanBase) {
      addCandidate(cleanPre);
    }

    // Check if cleanBase has a hyphen/dash/colon separator (e.g. "Movie - Song" or "Artist - Song")
    final separatorMatch = RegExp(r'\s*([-–—:~])\s*').firstMatch(cleanBase);
    if (separatorMatch != null) {
      final idx = separatorMatch.start;
      final endIdx = separatorMatch.end;
      final partA = cleanBase.substring(0, idx).trim();
      final partB = cleanBase.substring(endIdx).trim();

      if (partA.isNotEmpty && partB.isNotEmpty) {
        final lowerA = partA.toLowerCase();
        final lowerB = partB.toLowerCase();

        // 1. If partA is the artist -> partB is 100% the track title (e.g. "Anirudh - Hukum")
        if (cleanArtist.isNotEmpty && (cleanArtist.contains(lowerA) || lowerA.contains(cleanArtist))) {
          addCandidate(partB);
          addCandidate(cleanBase);
        }
        // 2. If partB is the artist -> partA is the track title (e.g. "Katchi Sera - Sai Abhyankkar")
        else if (cleanArtist.isNotEmpty && (cleanArtist.contains(lowerB) || lowerB.contains(cleanArtist))) {
          addCandidate(partA);
          addCandidate(cleanBase);
        }
        // 3. If partA matches the album/movie -> partB is the song title (e.g. "Leo - Badass", "Jailer - Hukum")
        else if (cleanAlbum.isNotEmpty && (cleanAlbum == lowerA || cleanAlbum.contains(lowerA))) {
          addCandidate(partB);
          addCandidate(cleanBase);
        }
        // 4. Default: Indian/YouTube tracks overwhelmingly use "Movie - Song" (e.g. "Leo - Badass"),
        // so prioritize partB, then full cleanBase, then partA
        else {
          addCandidate(partB);
          addCandidate(cleanBase);
          addCandidate(partA);
        }
      }
    }

    // Always ensure cleanBase is in candidates
    addCandidate(cleanBase);

    // If title starts with the artist name, strip artist prefix
    if (cleanArtist.isNotEmpty && cleanBase.toLowerCase().startsWith(cleanArtist)) {
      final stripped = cleanBase.substring(cleanArtist.length).trim();
      addCandidate(stripped);
    }

    // If title starts with album name, strip album prefix
    if (cleanAlbum.isNotEmpty && cleanBase.toLowerCase().startsWith(cleanAlbum)) {
      final stripped = cleanBase.substring(cleanAlbum.length).trim();
      addCandidate(stripped);
    }

    return candidates;
  }

  /// Cleans artist metadata by extracting primary artist and stripping record labels & metric tags.
  static String sanitizeArtist(String rawArtist) {
    if (rawArtist.isEmpty) return '';
    var a = _unescape.convert(Song.sanitize(rawArtist));

    // Strip record labels
    a = a.replaceAll(
      RegExp(r'\b(sony\s*music.*|think\s*music.*|zee\s*music.*|t-series.*|aditya\s*music.*|lahari\s*music.*|speed\s*records.*|saregama.*|tips\s*official.*|yrf.*|vevo.*)\b', caseSensitive: false),
      '',
    );

    // Strip metric text ("10M views", "Topic", "Official")
    a = a.replaceAll(
      RegExp(r'\b(\d+[\d,.]*\s*(?:views|subscribers|plays)|topic|official)\b', caseSensitive: false),
      '',
    );

    // Clean artifacts like double commas ", ,"
    a = a.replaceAll(RegExp(r',(\s*,)+'), ',');

    // Extract primary genuine artist
    final parts = a.split(RegExp(r'[,&/|]|(?:\s+feat\.?|\s+ft\.)', caseSensitive: false));
    var primary = parts.isNotEmpty ? parts.first.trim() : a.trim();
    primary = primary.replaceAll(RegExp(r'^[^\w\s\u0B80-\u0BFF\u0C00-\u0C7F\u0900-\u097F]+|[^\w\s\u0B80-\u0BFF\u0C00-\u0C7F\u0900-\u097F]+$'), '').trim();
    return primary.isNotEmpty ? primary : Song.sanitize(rawArtist);
  }

  // ================= 2. LRC Parser & Plain-Text Auto-Timer ================= //

  /// Checks if a string has LRC timestamp formatting: [mm:ss.xx]
  static bool isLrc(String text) {
    return RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]').hasMatch(text);
  }

  /// Converts plain text lyrics into auto-timed synchronized LRC format by evenly
  /// assigning progressive timestamps across the track body (5% intro, 10% outro margin).
  static String plainLyricsToAutoTimedLrc(String plainLyrics, int durationSeconds) {
    final rawLines = plainLyrics
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (rawLines.isEmpty) return '';

    final totalDurationMs = (durationSeconds > 0 ? durationSeconds : 180) * 1000;
    final introMs = (totalDurationMs * 0.05).toInt(); // 5% intro
    final outroMs = (totalDurationMs * 0.10).toInt(); // 10% outro
    final bodyDurationMs = math.max(1000, totalDurationMs - introMs - outroMs);

    final buffer = StringBuffer();
    for (int i = 0; i < rawLines.length; i++) {
      final lineMs = introMs + ((i * bodyDurationMs) ~/ rawLines.length);
      final min = lineMs ~/ 60000;
      final sec = (lineMs % 60000) ~/ 1000;
      final hundredths = (lineMs % 1000) ~/ 10;
      final minStr = min.toString().padLeft(2, '0');
      final secStr = sec.toString().padLeft(2, '0');
      final msStr = hundredths.toString().padLeft(2, '0');
      buffer.writeln('[$minStr:$secStr.$msStr] ${rawLines[i]}');
    }
    return buffer.toString().trim();
  }

  /// Allocates words across the line duration using Phonetic Length & Vowel weighting.
  static List<LyricWord> allocateWordsForLine(
    String text,
    String? romanizedText,
    Duration start,
    Duration end,
  ) {
    if (text.trim().isEmpty) return const [];

    final rawWords = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (rawWords.isEmpty) return const [];

    final rawRomWords = (romanizedText != null && romanizedText.trim().isNotEmpty)
        ? romanizedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList()
        : null;

    final totalDurationMs = (end - start).inMilliseconds;
    // Cap singing duration so long gaps don't cause unrealistically slow word sweeps
    final maxReasonableDuration = math.max(1500, rawWords.length * 750);
    final effectiveDurationMs = totalDurationMs > 0
        ? math.min(totalDurationMs, maxReasonableDuration)
        : rawWords.length * 400;

    // Calculate phonetic weights (character count + vowel multiplier)
    final weights = <double>[];
    for (int i = 0; i < rawWords.length; i++) {
      final w = rawWords[i];
      // Count vowels (Latin aeiou + Indic vowel diacritics)
      final vowelMatches = RegExp(r'[aeiouAEIOU\u0BBE-\u0BCD\u0C3E-\u0C4D\u093E-\u094D\u0D3E-\u0D4D]').allMatches(w).length;
      double weight = math.max(1.0, w.length.toDouble() + (vowelMatches * 1.5));
      // Phrase-final elongated note bonus for lines with 2+ words
      if (i == rawWords.length - 1 && rawWords.length >= 2) {
        weight *= 1.25;
      }
      weights.add(weight);
    }

    final totalWeight = weights.fold<double>(0.0, (sum, w) => sum + w);
    final result = <LyricWord>[];

    int currentMs = start.inMilliseconds;
    for (int i = 0; i < rawWords.length; i++) {
      final fraction = totalWeight > 0 ? (weights[i] / totalWeight) : (1.0 / rawWords.length);
      final wordDurationMs = math.max(120, (effectiveDurationMs * fraction).round());
      final wordStart = Duration(milliseconds: currentMs);
      final wordEnd = Duration(milliseconds: currentMs + wordDurationMs);

      final romWord = (rawRomWords != null && i < rawRomWords.length) ? rawRomWords[i] : null;

      result.add(LyricWord(
        text: rawWords[i],
        romanizedText: romWord,
        start: wordStart,
        end: wordEnd,
      ));

      currentMs += wordDurationMs;
    }

    return result;
  }

  /// Parses raw LRC string into sorted [LyricLine]s with [IndicRomanizer] support
  /// and dynamic BGM instrumental gap detection for Intro, Interludes, and Outro (>6s pauses).
  /// CRITICAL: Zero timestamp stretching/skew multipliers are applied!
  static List<LyricLine> parseLrc(String rawLyrics, {int? durationSeconds}) {
    if (rawLyrics.trim().isEmpty) return [];

    final timestampRegex = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
    final rawLines = rawLyrics.split('\n');

    // Parse [offset:+500] / [offset:-200] header tag if present
    final offsetRegex = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
    int headerOffsetMs = 0;
    for (final line in rawLines) {
      final m = offsetRegex.firstMatch(line.trim());
      if (m != null) {
        headerOffsetMs = int.tryParse(m.group(1)!) ?? 0;
        break;
      }
    }

    final List<LyricLine> parsed = [];

    for (final line in rawLines) {
      final matches = timestampRegex.allMatches(line);
      if (matches.isNotEmpty) {
        final text = Song.sanitize(line.replaceAll(timestampRegex, '').trim());
        if (text.isEmpty) continue;
        final romanized = IndicRomanizer.hasIndicScript(text) ? IndicRomanizer.romanize(text) : null;

        for (final m in matches) {
          final min = int.tryParse(m.group(1)!) ?? 0;
          final sec = double.tryParse(m.group(2)!) ?? 0.0;
          final rawMs = ((min * 60 + sec) * 1000).toInt();
          final effectiveMs = math.max(0, rawMs + headerOffsetMs);
          parsed.add(LyricLine(
            timestamp: Duration(milliseconds: effectiveMs),
            text: text,
            romanizedText: romanized,
            isBgm: false,
          ));
        }
      }
    }

    parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (parsed.isEmpty) return [];

    final List<LyricLine> result = [];

    // 1. Intro instrumental pause > 6s
    if (parsed.first.timestamp > const Duration(seconds: 6)) {
      result.add(LyricLine(
        timestamp: Duration.zero,
        endTimestamp: parsed.first.timestamp,
        text: '• • • ♪',
        isBgm: true,
      ));
    }

    // 2. Verse lines and middle instrumental interludes
    for (int i = 0; i < parsed.length; i++) {
      final current = parsed[i];
      Duration effectiveEnd;
      if (i < parsed.length - 1) {
        effectiveEnd = parsed[i + 1].timestamp;
      } else if (durationSeconds != null && durationSeconds > 0) {
        effectiveEnd = Duration(seconds: durationSeconds);
      } else {
        effectiveEnd = current.timestamp + const Duration(seconds: 4);
      }

      final words = allocateWordsForLine(
        current.text,
        current.romanizedText,
        current.timestamp,
        effectiveEnd,
      );

      final lineWithWords = LyricLine(
        timestamp: current.timestamp,
        endTimestamp: effectiveEnd,
        text: current.text,
        romanizedText: current.romanizedText,
        isBgm: false,
        words: words,
      );

      result.add(lineWithWords);

      if (i < parsed.length - 1) {
        final next = parsed[i + 1];
        final gap = next.timestamp - current.timestamp;

        if (gap > const Duration(seconds: 6)) {
          final vocalMs = math.min(2500, (gap.inMilliseconds ~/ 3));
          final bgmStart = current.timestamp + Duration(milliseconds: vocalMs);
          result.add(LyricLine(
            timestamp: bgmStart,
            endTimestamp: next.timestamp,
            text: '• • • ♪',
            isBgm: true,
          ));
        }
      }
    }

    // 3. Outro instrumental pause at the end of the song (>6s remaining after last vocal)
    if (durationSeconds != null && durationSeconds > 0 && parsed.isNotEmpty) {
      final totalDuration = Duration(seconds: durationSeconds);
      final lastLyric = parsed.last;
      final remaining = totalDuration - lastLyric.timestamp;

      if (remaining > const Duration(seconds: 6)) {
        // Allow ~3 seconds for the last sung syllable to fade out before lighting up BGM
        final vocalMs = math.min(3000, remaining.inMilliseconds ~/ 3);
        final bgmStart = lastLyric.timestamp + Duration(milliseconds: vocalMs);
        if (bgmStart < totalDuration) {
          result.add(LyricLine(
            timestamp: bgmStart,
            endTimestamp: totalDuration,
            text: '• • • ♪',
            isBgm: true,
          ));
        }
      }
    }

    return result;
  }

  /// Builds a [DualLyrics] model pre-computing romanized English lyrics via [IndicRomanizer].
  static DualLyrics buildDualLyrics(String lrc) {
    final isSynced = isLrc(lrc);
    final script = IndicRomanizer.detectScript(lrc);
    if (IndicRomanizer.hasIndicScript(lrc)) {
      final romanized = IndicRomanizer.romanizeLyrics(lrc);
      return DualLyrics(
        defaultLyrics: lrc,
        englishLyrics: romanized,
        detectedScript: script,
        isSynced: isSynced,
      );
    } else {
      return DualLyrics(
        defaultLyrics: lrc,
        englishLyrics: lrc,
        detectedScript: 'latin',
        isSynced: isSynced,
      );
    }
  }

  // ================= 3. Direct Fetch & Duration-Scoring ================= //

  /// Fetches lyrics with 0ms memory & Hive cache checking, querying LRCLIB directly with
  /// duration-scored candidate selection and JioSaavn fallback.
  Future<LyricsState> fetchLyrics({
    required String trackId,
    required String title,
    required String artist,
    String? album,
    int durationSeconds = 0,
  }) async {
    // 1. In-memory LRU cache check (0ms)
    final cachedMem = _memoryCache[trackId];
    if (cachedMem != null && cachedMem.status == LyricsStatus.loaded) {
      return cachedMem;
    }

    // 2. Persistent Hive storage check (0ms)
    final box = await _getBox();
    if (box != null) {
      final rawData = box.get('lyrics_$trackId');
      if (rawData is Map) {
        final lrc = rawData['lyrics']?.toString();
        if (lrc != null && lrc.trim().isNotEmpty) {
          final dual = DualLyrics(
            defaultLyrics: rawData['defaultLyrics']?.toString() ?? lrc,
            englishLyrics: rawData['englishLyrics']?.toString() ?? lrc,
            detectedScript: rawData['detectedScript']?.toString() ?? 'latin',
            isSynced: rawData['isSynced'] as bool? ?? isLrc(lrc),
          );
          final state = LyricsState.loaded(lrc, dualLyrics: dual);
          _putMemoryCache(trackId, state);
          return state;
        }
      }
    }

    final titleCandidates = generateTitleCandidates(title, artist: artist, album: album);
    final primaryArtist = sanitizeArtist(artist);

    AppLogger.log(
      'LyricsClient',
      'Fetching lyrics on-device for "$title" (dur: ${durationSeconds}s). Candidates: $titleCandidates, Artist: "$primaryArtist"',
    );

    List<Map<String, dynamic>> allCandidates = [];

    // Step 1: Specific track_name and artist_name search across generated title candidates
    for (final cand in titleCandidates.take(3)) {
      try {
        final uri1 = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
          'track_name': cand,
          if (primaryArtist.isNotEmpty) 'artist_name': primaryArtist,
        });
        final res1 = await http.get(uri1, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 3));
        if (res1.statusCode == 200) {
          final List data = json.decode(res1.body);
          final valid = data.whereType<Map<String, dynamic>>().toList();
          allCandidates.addAll(valid);

          // Check if we immediately found a synced lyrics candidate with matching duration
          final syncedMatches = valid.where((c) => (c['syncedLyrics'] as String?)?.trim().isNotEmpty == true).toList();
          if (syncedMatches.isNotEmpty) {
            if (durationSeconds > 0) {
              syncedMatches.sort((a, b) {
                final durA = ((a['duration'] as num?)?.toInt() ?? 0);
                final durB = ((b['duration'] as num?)?.toInt() ?? 0);
                return (durA - durationSeconds).abs().compareTo((durB - durationSeconds).abs());
              });
              final bestDiff = (((syncedMatches.first['duration'] as num?)?.toInt() ?? 0) - durationSeconds).abs();
              // If within 10 seconds tolerance, accept immediately!
              if (bestDiff <= 10) {
                final best = syncedMatches.first;
                final rawLrc = best['syncedLyrics'] as String;
                final dual = buildDualLyrics(rawLrc);
                final state = LyricsState.loaded(rawLrc, dualLyrics: dual);
                _putMemoryCache(trackId, state);
                _savePersistentCache(trackId, rawLrc, dual);
                AppLogger.log('LyricsClient', 'Instant synced LRC hit for "$title" using candidate "$cand" (diff: ${bestDiff}s)');
                return state;
              }
            } else {
              final best = syncedMatches.first;
              final rawLrc = best['syncedLyrics'] as String;
              final dual = buildDualLyrics(rawLrc);
              final state = LyricsState.loaded(rawLrc, dualLyrics: dual);
              _putMemoryCache(trackId, state);
              _savePersistentCache(trackId, rawLrc, dual);
              return state;
            }
          }
        }

        // Tier 1.5: If artist-constrained search yielded nothing, try track_name alone
        if (allCandidates.isEmpty && primaryArtist.isNotEmpty) {
          try {
            final uriAlt = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
              'track_name': cand,
            });
            final resAlt = await http.get(uriAlt, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 3));
            if (resAlt.statusCode == 200) {
              final List dataAlt = json.decode(resAlt.body);
              allCandidates.addAll(dataAlt.whereType<Map<String, dynamic>>());
            }
          } catch (_) {}
        }
      } catch (e) {
        AppLogger.log('LyricsClient', 'LRCLIB Step 1 search notice for "$cand": $e');
      }
    }

    // Step 2: Fallback query search across candidates if no synced lyrics found yet
    final hasSynced = allCandidates.any((c) => (c['syncedLyrics'] as String?)?.trim().isNotEmpty == true);
    if (!hasSynced) {
      for (final cand in titleCandidates.take(2)) {
        try {
          final uri2 = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
            'q': '$cand $primaryArtist'.trim(),
          });
          final res2 = await http.get(uri2, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 3));
          if (res2.statusCode == 200) {
            final List data = json.decode(res2.body);
            allCandidates.addAll(data.whereType<Map<String, dynamic>>());
          }
        } catch (e) {
          AppLogger.log('LyricsClient', 'LRCLIB Step 2 query notice for "$cand": $e');
        }

        // Title-only fuzzy search
        try {
          final uri3 = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
            'q': cand,
          });
          final res3 = await http.get(uri3, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 3));
          if (res3.statusCode == 200) {
            final List data = json.decode(res3.body);
            allCandidates.addAll(data.whereType<Map<String, dynamic>>());
          }
        } catch (_) {}
      }
    }

    // Cache candidates for duration re-selection
    _candidatesCache[trackId] = allCandidates;

    // DURATION-SCORED CANDIDATE SELECTION FROM ACCUMULATED LRCLIB POOL
    final syncedCandidates = allCandidates
        .where((c) => (c['syncedLyrics'] as String?)?.trim().isNotEmpty == true)
        .toList();

    if (syncedCandidates.isNotEmpty) {
      if (durationSeconds > 0) {
        syncedCandidates.sort((a, b) {
          final durA = ((a['duration'] as num?)?.toInt() ?? 0);
          final durB = ((b['duration'] as num?)?.toInt() ?? 0);
          return (durA - durationSeconds).abs().compareTo((durB - durationSeconds).abs());
        });
      }
      final best = syncedCandidates.first;
      final rawLrc = best['syncedLyrics'] as String;
      final dual = buildDualLyrics(rawLrc);
      final state = LyricsState.loaded(rawLrc, dualLyrics: dual);
      _putMemoryCache(trackId, state);
      _savePersistentCache(trackId, rawLrc, dual);
      AppLogger.log('LyricsClient', 'Resolved synced LRC for "$title" (best diff: ${durationSeconds > 0 ? (((best['duration'] as num?)?.toInt() ?? 0) - durationSeconds).abs() : 0}s)');
      return state;
    }

    // Step 3: Direct JioSaavn Fallback for regional tracks (Tamil, Telugu, Hindi, etc.)
    for (final cand in titleCandidates.take(2)) {
      try {
        String? saavnId = (trackId.isNotEmpty && trackId.length != 11) ? trackId : null;
        if (saavnId == null) {
          var searchSongs = await SaavnClient.search('$cand $primaryArtist', limit: 2);
          if (searchSongs.isEmpty) {
            searchSongs = await SaavnClient.search(cand, limit: 2);
          }
          if (searchSongs.isNotEmpty) {
            saavnId = searchSongs.first.id;
          }
        }

        if (saavnId != null && saavnId.isNotEmpty) {
          final saavnUri = Uri.parse('https://www.jiosaavn.com/api.php').replace(queryParameters: {
            '__call': 'lyrics.getLyrics',
            '_format': 'json',
            '_marker': '0',
            'api_version': '4',
            'ctx': 'web6dot0',
            'lyrics_id': saavnId,
          });

          final saavnRes = await http.get(saavnUri).timeout(const Duration(seconds: 3));
          if (saavnRes.statusCode == 200) {
            final data = json.decode(saavnRes.body);
            final lyrics = data['lyrics']?.toString();
            if (lyrics != null && lyrics.trim().isNotEmpty) {
              final cleanPlain = _unescape
                  .convert(lyrics.replaceAll('<br>', '\n').replaceAll('<br/>', '\n'))
                  .trim();
              final autoTimedLrc = isLrc(cleanPlain)
                  ? cleanPlain
                  : plainLyricsToAutoTimedLrc(cleanPlain, durationSeconds);
              final dual = buildDualLyrics(autoTimedLrc);
              final state = LyricsState.loaded(autoTimedLrc, dualLyrics: dual);
              _putMemoryCache(trackId, state);
              _savePersistentCache(trackId, autoTimedLrc, dual);
              AppLogger.log('LyricsClient', 'Resolved JioSaavn plain lyrics for "$title" using candidate "$cand" into auto-timed LRC');
              return state;
            }
          }
        }
      } catch (e) {
        AppLogger.log('LyricsClient', 'JioSaavn lyrics fallback notice for "$cand": $e');
      }
    }

    // Step 4: YouTube Closed Captions / Timed Subtitles Fallback
    String? targetYtId = trackId.length == 11 ? trackId : null;
    if (targetYtId == null) {
      try {
        final ytMatches = await YouTubeClient.search('$title $primaryArtist', limit: 1);
        if (ytMatches.isNotEmpty && ytMatches.first.id.length == 11) {
          targetYtId = ytMatches.first.id;
        }
      } catch (_) {}
    }

    if (targetYtId != null) {
      try {
        final ytCaptionsLrc = await YouTubeClient.fetchVideoCaptions(targetYtId);
        if (ytCaptionsLrc != null && ytCaptionsLrc.trim().isNotEmpty) {
          final dual = buildDualLyrics(ytCaptionsLrc);
          final state = LyricsState.loaded(ytCaptionsLrc, dualLyrics: dual);
          _putMemoryCache(trackId, state);
          _savePersistentCache(trackId, ytCaptionsLrc, dual);
          AppLogger.log('LyricsClient', 'Resolved YouTube closed captions for "$title" (video: $targetYtId)');
          return state;
        }
      } catch (e) {
        AppLogger.log('LyricsClient', 'YouTube captions fallback notice: $e');
      }
    }

    // Step 5: If only plain text lyrics available from LRCLIB
    final plainCandidates = allCandidates
        .where((c) => (c['plainLyrics'] as String?)?.trim().isNotEmpty == true)
        .toList();

    if (plainCandidates.isNotEmpty) {
      if (durationSeconds > 0) {
        plainCandidates.sort((a, b) {
          final durA = ((a['duration'] as num?)?.toInt() ?? 0);
          final durB = ((b['duration'] as num?)?.toInt() ?? 0);
          return (durA - durationSeconds).abs().compareTo((durB - durationSeconds).abs());
        });
      }
      final bestPlain = plainCandidates.first['plainLyrics'] as String;
      final autoTimedLrc = plainLyricsToAutoTimedLrc(bestPlain, durationSeconds);
      final dual = buildDualLyrics(autoTimedLrc);
      final state = LyricsState.loaded(autoTimedLrc, dualLyrics: dual);
      _putMemoryCache(trackId, state);
      _savePersistentCache(trackId, autoTimedLrc, dual);
      AppLogger.log('LyricsClient', 'Resolved plain lyrics for "$title" into auto-timed LRC');
      return state;
    }

    const notFoundState = LyricsState.notFound();
    _putMemoryCache(trackId, notFoundState);
    return notFoundState;
  }

  /// Automatically re-selects candidate if the audio player's actual duration becomes
  /// known after playback starts and differs by > 4 seconds.
  Future<LyricsState?> reselectForActualDuration({
    required String trackId,
    required int actualDurationSeconds,
  }) async {
    final candidates = _candidatesCache[trackId];
    if (candidates == null || candidates.isEmpty) return null;

    final syncedCandidates = candidates
        .where((c) => (c['syncedLyrics'] as String?)?.trim().isNotEmpty == true)
        .toList();

    if (syncedCandidates.isEmpty) return null;

    syncedCandidates.sort((a, b) {
      final durA = ((a['duration'] as num?)?.toInt() ?? 0);
      final durB = ((b['duration'] as num?)?.toInt() ?? 0);
      return (durA - actualDurationSeconds).abs().compareTo((durB - actualDurationSeconds).abs());
    });

    final best = syncedCandidates.first;
    final rawLrc = best['syncedLyrics'] as String;
    final current = _memoryCache[trackId];

    // If candidate text is different, update state
    if (current?.lyrics != rawLrc) {
      final dual = buildDualLyrics(rawLrc);
      final newState = LyricsState.loaded(rawLrc, dualLyrics: dual);
      _putMemoryCache(trackId, newState);
      _savePersistentCache(trackId, rawLrc, dual);
      AppLogger.log('LyricsClient', 'Reselected best-matching candidate for $trackId at duration ${actualDurationSeconds}s');
      return newState;
    }
    return null;
  }

  void _putMemoryCache(String trackId, LyricsState state) {
    if (_memoryCache.length >= _maxMemoryCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[trackId] = state;
  }

  Future<void> _savePersistentCache(String trackId, String lrc, DualLyrics dual) async {
    try {
      final box = await _getBox();
      if (box != null) {
        await box.put('lyrics_$trackId', {
          'status': 'loaded',
          'lyrics': lrc,
          'defaultLyrics': dual.defaultLyrics,
          'englishLyrics': dual.englishLyrics,
          'detectedScript': dual.detectedScript,
          'isSynced': dual.isSynced,
        });
      }
    } catch (_) {}
  }

  /// Clears in-memory and persistent cache
  Future<void> clearCache() async {
    _memoryCache.clear();
    _candidatesCache.clear();
    try {
      final box = await _getBox();
      await box?.clear();
    } catch (_) {}
  }

  /// Retrieves user-adjusted lyrics sync offset (in milliseconds) for a given track.
  Future<int> getLyricsOffset(String trackId) async {
    try {
      final box = await _getBox();
      if (box != null) {
        return (box.get('offset_$trackId') as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// Persists user-adjusted lyrics sync offset (in milliseconds) for a given track.
  Future<void> saveLyricsOffset(String trackId, int offsetMs) async {
    try {
      final box = await _getBox();
      if (box != null) {
        if (offsetMs == 0) {
          await box.delete('offset_$trackId');
        } else {
          await box.put('offset_$trackId', offsetMs);
        }
      }
    } catch (_) {}
  }

  /// Searches and resolves an authentic official studio karaoke or instrumental version
  /// of the target song from YouTube/Saavn, matching duration within tolerance.
  Future<Song?> resolveStudioKaraoke(Song song) async {
    final cleanTitle = sanitizeTitle(song.title);
    if (cleanTitle.isEmpty) return null;

    final primaryArtist = sanitizeArtist(song.artist);
    final queries = [
      '$cleanTitle Karaoke',
      '$cleanTitle Instrumental',
      if (primaryArtist.isNotEmpty) '$cleanTitle $primaryArtist Karaoke',
    ];

    for (final q in queries) {
      try {
        final results = await YouTubeClient.search(q, limit: 5);
        for (final candidate in results) {
          final titleLower = candidate.title.toLowerCase();

          // Invariant 1: Must contain karaoke or instrumental in the title
          final isKaraokeMarker = titleLower.contains('karaoke') ||
              titleLower.contains('instrumental') ||
              titleLower.contains('bgm');
          if (!isKaraokeMarker) continue;

          // Invariant 2: Must NOT be an amateur cover or tutorial
          final isBlacklisted = titleLower.contains('vocal cover') ||
              titleLower.contains('cover by') ||
              titleLower.contains('female cover') ||
              titleLower.contains('male cover') ||
              titleLower.contains('piano tutorial') ||
              titleLower.contains('guitar tutorial') ||
              titleLower.contains('remix') ||
              titleLower.contains('speed up') ||
              titleLower.contains('slowed');
          if (isBlacklisted) continue;

          // Invariant 3: Duration check within +/- 6 seconds if duration is known
          if (song.duration > 0 && candidate.duration > 0) {
            final diff = (candidate.duration - song.duration).abs();
            if (diff > 6) continue;
          }

          AppLogger.log('LyricsClient', 'Found studio karaoke candidate for "${song.title}": "${candidate.title}" (id: ${candidate.id})');
          return candidate;
        }
      } catch (e) {
        AppLogger.log('LyricsClient', 'Studio karaoke lookup notice for "$q": $e');
      }
    }
    return null;
  }
}
