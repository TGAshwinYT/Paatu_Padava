import 'dart:math' as math;

/// Represents a spelling suggestion returned by [SymSpell].
class SymSpellResult {
  final String term;
  final int distance;
  final int count;

  const SymSpellResult({
    required this.term,
    required this.distance,
    required this.count,
  });

  @override
  String toString() => 'SymSpellResult(term: "$term", distance: $distance, count: $count)';
}

/// High-Performance Symmetric Delete (SymSpell) Spelling Correction Algorithm.
///
/// 1,000x faster than traditional Levenshtein / BK-Tree traversals:
/// Instead of generating all insertions/transpositions/substitutions dynamically at query time,
/// SymSpell pre-computes only *deletion* variants of dictionary terms up to [maxEditDistance].
///
/// At query time, deletions of the input word are looked up in O(1) hash maps.
/// Edit distance is only computed against candidate hits that share deletion hashes.
class SymSpell {
  final int maxEditDistance;
  final int prefixLength;

  final Map<String, Set<String>> _deletes = <String, Set<String>>{};
  final Map<String, int> _words = <String, int>{};

  SymSpell({
    this.maxEditDistance = 2,
    this.prefixLength = 7,
  });

  int get wordCount => _words.length;
  bool get isEmpty => _words.isEmpty;

  /// Inserts a dictionary word with an optional frequency count.
  void insert(String word, {int count = 1}) {
    final clean = _normalize(word);
    if (clean.isEmpty) return;

    final existingCount = _words[clean] ?? 0;
    _words[clean] = existingCount + count;

    // Generate deletion keys for this word
    final deletes = _getDeletes(clean, maxEditDistance, prefixLength);
    for (final del in deletes) {
      _deletes.putIfAbsent(del, () => <String>{}).add(clean);
    }
  }

  /// Looks up spelling suggestions for [input] within [maxDistance].
  /// Returns suggestions sorted by ascending distance, then descending frequency.
  List<SymSpellResult> lookup(
    String input, {
    int? maxDistance,
    int limit = 5,
  }) {
    final clean = _normalize(input);
    if (clean.isEmpty) return const [];

    final maxDist = maxDistance ?? maxEditDistance;
    final List<SymSpellResult> suggestions = [];
    final Set<String> considered = <String>{};

    // 1. Exact match check (O(1))
    if (_words.containsKey(clean)) {
      suggestions.add(
        SymSpellResult(term: clean, distance: 0, count: _words[clean]!),
      );
      if (maxDist == 0) return suggestions;
    }

    considered.add(clean);

    // 2. Query deletion generation
    final queryDeletes = _getDeletes(clean, maxDist, prefixLength);

    for (final del in queryDeletes) {
      final candidates = _deletes[del];
      if (candidates == null) continue;

      for (final candidate in candidates) {
        if (!considered.add(candidate)) continue;

        // Skip candidates whose length difference exceeds maxDist
        if ((candidate.length - clean.length).abs() > maxDist) continue;

        final distance = damerauLevenshtein(clean, candidate);
        if (distance <= maxDist) {
          suggestions.add(
            SymSpellResult(
              term: candidate,
              distance: distance,
              count: _words[candidate] ?? 1,
            ),
          );
        }
      }
    }

    // 3. Sort: ascending distance, then descending frequency
    suggestions.sort((a, b) {
      if (a.distance != b.distance) {
        return a.distance.compareTo(b.distance);
      }
      return b.count.compareTo(a.count);
    });

    return suggestions.take(limit).toList();
  }

  /// Generates all unique deletion variants of [word] up to [maxDistance].
  Set<String> _getDeletes(String word, int maxDistance, int prefLen) {
    final Set<String> deletes = <String>{};
    final target = word.length > prefLen ? word.substring(0, prefLen) : word;
    deletes.add(target);

    _recurseDeletes(target, 0, maxDistance, deletes);
    return deletes;
  }

  void _recurseDeletes(String word, int currentDistance, int maxDist, Set<String> results) {
    if (currentDistance >= maxDist || word.length <= 1) return;

    for (int i = 0; i < word.length; i++) {
      final del = word.substring(0, i) + word.substring(i + 1);
      if (results.add(del)) {
        _recurseDeletes(del, currentDistance + 1, maxDist, results);
      }
    }
  }

  static String _normalize(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Optimal Damerau-Levenshtein distance supporting transposition, insertion, deletion, and substitution.
  static int damerauLevenshtein(String source, String target) {
    final int m = source.length;
    final int n = target.length;
    if (m == 0) return n;
    if (n == 0) return m;

    final List<List<int>> d = List.generate(
      m + 1,
      (_) => List<int>.filled(n + 1, 0),
    );

    for (int i = 0; i <= m; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= n; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        final int cost = source[i - 1] == target[j - 1] ? 0 : 1;
        d[i][j] = math.min(
          d[i - 1][j] + 1, // deletion
          math.min(
            d[i][j - 1] + 1, // insertion
            d[i - 1][j - 1] + cost, // substitution
          ),
        );

        // Transposition
        if (i > 1 &&
            j > 1 &&
            source[i - 1] == target[j - 2] &&
            source[i - 2] == target[j - 1]) {
          d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 1);
        }
      }
    }

    return d[m][n];
  }

  void clear() {
    _deletes.clear();
    _words.clear();
  }
}
