import 'dart:collection';
import 'package:html_unescape/html_unescape.dart';
import '../core/dsa/trigram_index.dart';
import '../domain/models/track_entity.dart';

/// Represents a song match identified via lyrics search.
class LyricSearchResult {
  final String songId;
  final String matchingSnippet;
  final double score;

  const LyricSearchResult({
    required this.songId,
    required this.matchingSnippet,
    required this.score,
  });

  @override
  String toString() => 'LyricSearchResult(songId: $songId, score: $score, snippet: "$matchingSnippet")';
}

/// High-Performance On-Device Inverted Lyrics Search Index.
///
/// Enables Apple Music & Spotify-style "Search by Lyrics" where a user remembers
/// a catchy line or hook rather than the track's official title.
///
/// Architecture:
/// 1. Token Inverted Index: Maps normalized word stems and 3-grams to matching track IDs.
/// 2. Line Snippet Index: Stores raw parsed lyrics lines per track to extract clean snippets.
/// 3. Jaccard & Token Match Scoring: Accurately identifies the closest matching verse.
class LyricsSearchService {
  static final LyricsSearchService instance = LyricsSearchService._internal();
  LyricsSearchService._internal();

  static final HtmlUnescape _unescape = HtmlUnescape();

  // Inverted index: normalized token -> set of song IDs
  final Map<String, Set<String>> _tokenPostings = HashMap<String, Set<String>>();

  // Track lines store: songId -> list of clean lyric lines
  final Map<String, List<String>> _trackLines = HashMap<String, List<String>>();

  // Cache of indexed songs
  final Map<String, TrackEntity> _indexedSongs = HashMap<String, TrackEntity>();

  int get indexedCount => _indexedSongs.length;
  bool get isEmpty => _indexedSongs.isEmpty;

  /// Indexes raw LRC or plain-text lyrics for a [song].
  void indexLyrics(TrackEntity song, String rawLyrics) {
    if (song.id.isEmpty || rawLyrics.trim().isEmpty) return;

    final unescaped = _unescape.convert(rawLyrics);
    final rawLines = unescaped.split(RegExp(r'[\r\n]+'));

    final List<String> cleanLines = [];
    final Set<String> songTokens = <String>{};

    for (var line in rawLines) {
      // Strip LRC timestamps like [01:23.45]
      final stripped = line.replaceAll(RegExp(r'\[\d{2}:\d{2}(?:\.\d{2,3})?\]'), '').trim();
      if (stripped.isEmpty || stripped.startsWith('//') || stripped.length < 3) continue;

      cleanLines.add(stripped);

      // Extract words
      final words = stripped
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 2);

      for (final w in words) {
        songTokens.add(w);
      }
    }

    if (cleanLines.isEmpty) return;

    _indexedSongs[song.id] = song;
    _trackLines[song.id] = cleanLines;

    // Add to inverted index postings
    for (final token in songTokens) {
      _tokenPostings.putIfAbsent(token, () => <String>{}).add(song.id);
    }
  }

  /// Searches indexed lyrics for matching query tokens.
  /// Returns ranked [LyricSearchResult] candidates with contextual snippets.
  List<LyricSearchResult> searchLyrics(
    String query, {
    double minSimilarity = 0.35,
    int limit = 5,
  }) {
    final clean = query.trim().toLowerCase();
    if (clean.length < 3 || _tokenPostings.isEmpty) return const [];

    final queryWords = clean
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .toList();

    if (queryWords.isEmpty) return const [];

    // 1. Gather candidate songs that contain any query word
    final Map<String, int> candidateHits = <String, int>{};
    for (final word in queryWords) {
      final hits = _tokenPostings[word];
      if (hits != null) {
        for (final songId in hits) {
          candidateHits[songId] = (candidateHits[songId] ?? 0) + 1;
        }
      }
    }

    final List<LyricSearchResult> results = [];

    // 2. Score candidate lines within each candidate song
    for (final entry in candidateHits.entries) {
      final songId = entry.key;
      final lines = _trackLines[songId];
      if (lines == null || lines.isEmpty) continue;

      String bestSnippet = '';
      double bestScore = 0.0;

      for (final line in lines) {
        final lineLower = line.toLowerCase();

        // Exact substring match gives top score
        if (lineLower.contains(clean)) {
          bestScore = 1.0;
          bestSnippet = line;
          break;
        }

        // Compute tri-gram Jaccard similarity between query and lyric line
        final score = TrigramIndex.jaccard(clean, lineLower);
        if (score > bestScore) {
          bestScore = score;
          bestSnippet = line;
        }
      }

      if (bestScore >= minSimilarity) {
        results.add(
          LyricSearchResult(
            songId: songId,
            matchingSnippet: bestSnippet,
            score: bestScore,
          ),
        );
      }
    }

    // 3. Sort descending by score
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  /// Retrieves the track entity for an indexed song.
  TrackEntity? getSong(String songId) => _indexedSongs[songId];

  /// Clears the lyrics search index.
  void clear() {
    _tokenPostings.clear();
    _trackLines.clear();
    _indexedSongs.clear();
  }
}
