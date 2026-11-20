import 'dart:math' as math;
import 'bk_tree.dart';

/// Represents an item matched against a query with its computed similarity score (0..100).
class ExtractedResult<T> {
  final T choice;
  final int score;

  const ExtractedResult({
    required this.choice,
    required this.score,
  });

  @override
  String toString() => 'ExtractedResult(choice: $choice, score: $score)';
}

/// Zero-dependency, memory-bounded String Similarity Algorithms in pure Dart.
///
/// Implements standard string distance metrics optimized with O(min(N, M)) rolling
/// buffers and set-based word tokenization:
/// - [ratio]: Levenshtein similarity ratio (0..100).
/// - [partialRatio]: Best-matching substring ratio.
/// - [tokenSetRatio]: Token-set Jaccard + Levenshtein permutation similarity.
/// - [weightedRatio]: Composite similarity weighted by query length and token overlap.
/// - [extractTop]: Bounded top-K similarity search across candidates.
class StringSimilarity {
  static final RegExp _wordSplitRegex = RegExp(r'[\s,._\-!?/\\&|:;()\[\]{}"]+');

  /// Computes the standard Levenshtein similarity ratio between [s1] and [s2] (0..100).
  static int ratio(String s1, String s2) {
    if (identical(s1, s2) || s1 == s2) return 100;
    if (s1.isEmpty || s2.isEmpty) return 0;

    final totalLen = s1.length + s2.length;
    final dist = BkTree.levenshteinDistance(s1, s2);
    final similarity = ((totalLen - dist) / totalLen) * 100;
    return similarity.clamp(0, 100).round();
  }

  /// Computes partial ratio by sliding the shorter string across windows of the longer string.
  static int partialRatio(String s1, String s2) {
    if (identical(s1, s2) || s1 == s2) return 100;
    if (s1.isEmpty || s2.isEmpty) return 0;

    final shorter = s1.length <= s2.length ? s1 : s2;
    final longer = s1.length <= s2.length ? s2 : s1;
    final m = shorter.length;

    if (longer.contains(shorter)) return 100;

    int maxScore = 0;
    for (int i = 0; i <= longer.length - m; i++) {
      final sub = longer.substring(i, i + m);
      final r = ratio(shorter, sub);
      if (r > maxScore) {
        maxScore = r;
        if (maxScore == 100) return 100;
      }
    }
    return maxScore;
  }

  /// Computes token set ratio: tokenizes both strings, computes token set intersection and
  /// remainders, and measures Levenshtein similarity across the reconstructed token segments.
  static int tokenSetRatio(String s1, String s2) {
    if (identical(s1, s2) || s1 == s2) return 100;
    if (s1.isEmpty || s2.isEmpty) return 0;

    final tokens1 = s1
        .toLowerCase()
        .split(_wordSplitRegex)
        .where((t) => t.isNotEmpty)
        .toSet();
    final tokens2 = s2
        .toLowerCase()
        .split(_wordSplitRegex)
        .where((t) => t.isNotEmpty)
        .toSet();

    if (tokens1.isEmpty || tokens2.isEmpty) return ratio(s1, s2);

    final intersection = tokens1.intersection(tokens2);
    final diff1 = tokens1.difference(tokens2);
    final diff2 = tokens2.difference(tokens1);

    final sortedIntersection = intersection.toList()..sort();
    final sortedDiff1 = diff1.toList()..sort();
    final sortedDiff2 = diff2.toList()..sort();

    final t0 = sortedIntersection.join(' ');
    final t1 = (sortedIntersection.followedBy(sortedDiff1)).join(' ');
    final t2 = (sortedIntersection.followedBy(sortedDiff2)).join(' ');

    if (t0.isNotEmpty && (diff1.isEmpty || diff2.isEmpty)) {
      return 100;
    }

    final score01 = ratio(t0, t1);
    final score02 = ratio(t0, t2);
    final score12 = ratio(t1, t2);

    return math.max(score01, math.max(score02, score12));
  }

  /// Computes a weighted composite ratio balancing standard ratio, partial ratio,
  /// and token set ratio.
  static int weightedRatio(String s1, String s2) {
    if (identical(s1, s2) || s1 == s2) return 100;
    if (s1.isEmpty || s2.isEmpty) return 0;

    final lenRatio = math.min(s1.length, s2.length) / math.max(s1.length, s2.length);
    final baseRatio = ratio(s1, s2);

    if (lenRatio > 0.8) {
      final tokenScore = tokenSetRatio(s1, s2);
      return math.max(baseRatio, tokenScore);
    }

    final partial = partialRatio(s1, s2);
    final tokenScore = tokenSetRatio(s1, s2);
    return math.max(baseRatio, math.max(partial, tokenScore));
  }

  /// Extracts top [limit] candidate choices matching [query] with score >= [cutoff].
  static List<ExtractedResult<T>> extractTop<T>({
    required String query,
    required List<T> choices,
    int limit = 5,
    int cutoff = 0,
    String Function(T)? getter,
  }) {
    if (choices.isEmpty) return const [];

    final results = <ExtractedResult<T>>[];
    for (final choice in choices) {
      final str = getter != null ? getter(choice) : choice.toString();
      final score = tokenSetRatio(query, str);
      if (score >= cutoff) {
        results.add(ExtractedResult(choice: choice, score: score));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }
}

// Global top-level convenience functions matching FuzzyWuzzy API signatures
int ratio(String s1, String s2) => StringSimilarity.ratio(s1, s2);
int partialRatio(String s1, String s2) => StringSimilarity.partialRatio(s1, s2);
int tokenSetRatio(String s1, String s2) => StringSimilarity.tokenSetRatio(s1, s2);
int weightedRatio(String s1, String s2) => StringSimilarity.weightedRatio(s1, s2);
List<ExtractedResult<T>> extractTop<T>({
  required String query,
  required List<T> choices,
  int limit = 5,
  int cutoff = 0,
  String Function(T)? getter,
}) =>
    StringSimilarity.extractTop<T>(
      query: query,
      choices: choices,
      limit: limit,
      cutoff: cutoff,
      getter: getter,
    );
