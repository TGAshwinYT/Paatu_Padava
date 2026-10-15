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

/// Single parsed lyric line with timestamps and optional romanized text.
class LyricLine {
  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;
  final String? romanizedText;
  final bool isBgm;

  const LyricLine({
    required this.timestamp,
    this.endTimestamp,
    required this.text,
    this.romanizedText,
    this.isBgm = false,
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

    // Strip leading handles like "@SaiAbhyankkar - "
    t = t.replaceAll(RegExp(r'^@[a-zA-Z0-9_.]+\s*[-:|~–—]?\s*'), '');

    // Strip anything after pipe '|'
    t = t.replaceAll(RegExp(r'\|.*$'), '');

    // Strip "- From ..." or " - From Movie"
    t = t.replaceAll(RegExp(r'\s*-\s*from\b.*$', caseSensitive: false), '');

    // Strip parenthetical/bracketed "From ..." markers: (From "Movie"), [From Movie]
    t = t.replaceAll(
      RegExp(r'\s*[\(\[][Ff]rom\s+["\u201c\u201d\u2018\u2019]?[^)\u201d\]]+["\u201c\u201d\u2018\u2019]?[\)\]]'),
      '',
    );

    // Strip official video, audio, lyrical, ost, soundtrack, remaster markers
    t = t.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:official|audio|video|lyric|lyrical|soundtrack|ost|remaster|full\s*song)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // Strip standalone keywords like "Lyrical", "Video Song", "4K", "HD", etc.
    t = t.replaceAll(
      RegExp(r'\b(lyrical|video song|audio song|full song|4k|8k|hd|remastered|lyrics? video)\b', caseSensitive: false),
      '',
    );

    // Strip any lingering square brackets content
    t = t.replaceAll(RegExp(r'\[[^\]]*\]'), '');

    // Clean stray parentheses and collapse whitespace
    t = t.replaceAll(RegExp(r'[\(\)]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
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

  /// Parses raw LRC string into sorted [LyricLine]s with [IndicRomanizer] support
  /// and dynamic BGM instrumental gap detection (>6s pauses).
  /// CRITICAL: Zero timestamp stretching/skew multipliers are applied!
  static List<LyricLine> parseLrc(String rawLyrics) {
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

    // Intro instrumental pause > 6s
    if (parsed.first.timestamp > const Duration(seconds: 6)) {
      result.add(LyricLine(
        timestamp: Duration.zero,
        endTimestamp: parsed.first.timestamp,
        text: '• • • ♪',
        isBgm: true,
      ));
    }

    for (int i = 0; i < parsed.length; i++) {
      result.add(parsed[i]);

      if (i < parsed.length - 1) {
        final current = parsed[i];
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

    final cleanTitle = sanitizeTitle(title);
    final primaryArtist = sanitizeArtist(artist);

    AppLogger.log('LyricsClient', 'Fetching lyrics on-device: "$cleanTitle" by "$primaryArtist" (dur: ${durationSeconds}s)');

    List<Map<String, dynamic>> allCandidates = [];

    // Step 1: Specific track_name and artist_name search
    try {
      final uri1 = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
        'track_name': cleanTitle,
        'artist_name': primaryArtist,
      });
      final res1 = await http.get(uri1, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 3));
      if (res1.statusCode == 200) {
        final List data = json.decode(res1.body);
        allCandidates.addAll(data.whereType<Map<String, dynamic>>());
      }
    } catch (e) {
      AppLogger.log('LyricsClient', 'LRCLIB Step 1 search notice: $e');
    }

    // Step 2: Fallback query search if no synced lyrics found yet
    final hasSynced = allCandidates.any((c) => (c['syncedLyrics'] as String?)?.trim().isNotEmpty == true);
    if (!hasSynced) {
      try {
        final uri2 = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
          'q': '$cleanTitle $primaryArtist'.trim(),
        });
        final res2 = await http.get(uri2, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 3));
        if (res2.statusCode == 200) {
          final List data = json.decode(res2.body);
          allCandidates.addAll(data.whereType<Map<String, dynamic>>());
        }
      } catch (e) {
        AppLogger.log('LyricsClient', 'LRCLIB Step 2 query notice: $e');
      }

      // Step 2b: Fallback title-only query search
      final hasSyncedAfterStep2 = allCandidates.any((c) => (c['syncedLyrics'] as String?)?.trim().isNotEmpty == true);
      if (!hasSyncedAfterStep2 && cleanTitle.isNotEmpty) {
        try {
          final uri3 = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
            'q': cleanTitle,
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

    // DURATION-SCORED CANDIDATE SELECTION
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

    // If only plain text lyrics available from LRCLIB
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

    // Step 3: Direct JioSaavn Fallback for regional tracks
    try {
      String? saavnId = (trackId.isNotEmpty && trackId.length != 11) ? trackId : null;
      if (saavnId == null) {
        final searchSongs = await SaavnClient.search('$cleanTitle $primaryArtist', limit: 1);
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
            AppLogger.log('LyricsClient', 'Resolved JioSaavn plain lyrics for "$title" into auto-timed LRC');
            return state;
          }
        }
      }
    } catch (e) {
      AppLogger.log('LyricsClient', 'JioSaavn lyrics fallback notice: $e');
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
}
