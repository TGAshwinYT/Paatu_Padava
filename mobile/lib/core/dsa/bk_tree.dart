import 'dart:math' as math;

/// Represents a fuzzy match result retrieved from the [BkTree].
class BkSearchResult<T> {
  final String term;
  final int distance;
  final T? payload;
  final double similarity;

  const BkSearchResult({
    required this.term,
    required this.distance,
    this.payload,
    required this.similarity,
  });

  @override
  String toString() =>
      'BkSearchResult(term: "$term", distance: $distance, similarity: ${(similarity * 100).toStringAsFixed(1)}%)';
}

/// Node in the Burkhard-Keller Metric Tree.
class BkNode<T> {
  final String term;
  final String normalizedTerm;
  T? payload;
  final Map<int, BkNode<T>> children = <int, BkNode<T>>{};

  BkNode(this.term, this.normalizedTerm, {this.payload});
}

/// Burkhard-Keller Tree (BK-Tree) metric tree data structure for lightning-fast
/// typo-tolerant fuzzy searching in O(log N) metric space.
///
/// Mathematical Metric Space Principles:
/// 1. Metric: Levenshtein distance d(x, y) satisfies:
///    - Identity: d(x, y) == 0 <=> x == y
///    - Symmetry: d(x, y) == d(y, x)
///    - Triangle Inequality: d(x, z) <= d(x, y) + d(y, z)
///
/// 2. Triangle Pruning:
///    When searching for words within edit distance k from query Q:
///    For any node U and child V at distance w = d(U, V):
///    |d(U, V) - d(U, Q)| <= d(V, Q) <= k
///    Therefore, only children with edge distance w in [d(U, Q) - k, d(U, Q) + k]
///    are explored. All other branches are mathematically guaranteed to have
///    distance > k and are pruned in O(1).
///
/// Time Complexity:
/// - Insertion: O(log N) average
/// - Fuzzy Query (distance <= 2): O(log N) average (compared to O(N * M) brute-force)
/// - Space: O(N) memory
class BkTree<T> {
  BkNode<T>? _root;
  int _size = 0;

  // Search Telemetry
  int _lastSearchNodesVisited = 0;
  int _lastSearchBranchesPruned = 0;

  int get size => _size;
  bool get isEmpty => _size == 0;
  bool get isNotEmpty => _size > 0;
  int get lastSearchNodesVisited => _lastSearchNodesVisited;
  int get lastSearchBranchesPruned => _lastSearchBranchesPruned;

  /// Inserts a term with an optional payload into the BK-tree in O(log N) time.
  void insert(String term, {T? payload}) {
    final normalized = _normalize(term);
    if (normalized.isEmpty) return;

    if (_root == null) {
      _root = BkNode<T>(term, normalized, payload: payload);
      _size++;
      return;
    }

    BkNode<T> current = _root!;
    while (true) {
      final distance = levenshteinDistance(current.normalizedTerm, normalized);
      if (distance == 0) {
        // Exact term match: update payload
        current.payload = payload;
        return;
      }

      final child = current.children[distance];
      if (child != null) {
        current = child;
      } else {
        current.children[distance] =
            BkNode<T>(term, normalized, payload: payload);
        _size++;
        return;
      }
    }
  }

  /// Bulk inserts an iterable of terms into the tree.
  void insertAll(Iterable<String> terms) {
    for (final term in terms) {
      insert(term);
    }
  }

  /// Searches for all terms within [maxDistance] Levenshtein edit distance in O(log N) average time.
  /// Results are sorted by edit distance ascending, then by similarity score descending.
  List<BkSearchResult<T>> search(
    String query, {
    int maxDistance = 2,
    int limit = 10,
  }) {
    final normalizedQuery = _normalize(query);
    if (_root == null || normalizedQuery.isEmpty || maxDistance < 0) {
      return const [];
    }

    _lastSearchNodesVisited = 0;
    _lastSearchBranchesPruned = 0;

    final results = <BkSearchResult<T>>[];
    final queue = <BkNode<T>>[_root!];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      _lastSearchNodesVisited++;

      final distance =
          levenshteinDistance(current.normalizedTerm, normalizedQuery);

      if (distance <= maxDistance) {
        final maxLen = math.max(
          current.normalizedTerm.length,
          normalizedQuery.length,
        );
        final similarity = maxLen > 0 ? (1.0 - (distance / maxLen)) : 1.0;

        results.add(
          BkSearchResult<T>(
            term: current.term,
            distance: distance,
            payload: current.payload,
            similarity: similarity,
          ),
        );
      }

      // Triangle inequality pruning window: [distance - maxDistance, distance + maxDistance]
      final minRange = distance - maxDistance;
      final maxRange = distance + maxDistance;

      for (final entry in current.children.entries) {
        final edgeDist = entry.key;
        if (edgeDist >= minRange && edgeDist <= maxRange) {
          queue.add(entry.value);
        } else {
          _lastSearchBranchesPruned++;
        }
      }
    }

    // Sort: lowest distance first, then highest similarity
    results.sort((a, b) {
      final distCmp = a.distance.compareTo(b.distance);
      if (distCmp != 0) return distCmp;
      return b.similarity.compareTo(a.similarity);
    });

    return results.take(limit).toList();
  }

  /// Finds the single closest match within [maxDistance], or returns null if none found.
  BkSearchResult<T>? findBestMatch(String query, {int maxDistance = 2}) {
    final matches = search(query, maxDistance: maxDistance, limit: 1);
    return matches.isNotEmpty ? matches.first : null;
  }

  /// Checks if the tree contains an exact match for [term].
  bool contains(String term) {
    final normalized = _normalize(term);
    if (_root == null || normalized.isEmpty) return false;

    BkNode<T>? current = _root;
    while (current != null) {
      final distance = levenshteinDistance(current.normalizedTerm, normalized);
      if (distance == 0) return true;
      current = current.children[distance];
    }
    return false;
  }

  /// Clears the tree and resets size and telemetry.
  void clear() {
    _root = null;
    _size = 0;
    _lastSearchNodesVisited = 0;
    _lastSearchBranchesPruned = 0;
  }

  static String _normalize(String s) => s.trim().toLowerCase();

  /// High-performance memory-optimized Levenshtein Distance calculation.
  ///
  /// Uses a 2-row rolling DP buffer to achieve O(min(N, M)) space complexity
  /// and terminates early if the minimum edit cost in a row exceeds [maxDistance].
  static int levenshteinDistance(String s1, String s2, {int? maxDistance}) {
    if (identical(s1, s2) || s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    // Quick length-based prune: |len1 - len2| > maxDistance
    final lenDiff = (s1.length - s2.length).abs();
    if (maxDistance != null && lenDiff > maxDistance) {
      return maxDistance + 1;
    }

    // Ensure s1 is the shorter string to minimize rolling buffer memory O(min(N, M))
    final a = s1.length <= s2.length ? s1 : s2;
    final b = s1.length <= s2.length ? s2 : s1;

    final m = a.length;
    final n = b.length;

    List<int> previousRow = List<int>.generate(m + 1, (i) => i);
    List<int> currentRow = List<int>.filled(m + 1, 0);

    for (int j = 1; j <= n; j++) {
      currentRow[0] = j;
      final charB = b.codeUnitAt(j - 1);
      int rowMin = currentRow[0];

      for (int i = 1; i <= m; i++) {
        final charA = a.codeUnitAt(i - 1);
        final cost = (charA == charB) ? 0 : 1;

        final insertion = currentRow[i - 1] + 1;
        final deletion = previousRow[i] + 1;
        final substitution = previousRow[i - 1] + cost;

        int minCost = insertion;
        if (deletion < minCost) minCost = deletion;
        if (substitution < minCost) minCost = substitution;

        currentRow[i] = minCost;
        if (minCost < rowMin) rowMin = minCost;
      }

      // Early exit if the minimum edit cost in this row already exceeds maxDistance
      if (maxDistance != null && rowMin > maxDistance) {
        return maxDistance + 1;
      }

      // Swap rows
      final temp = previousRow;
      previousRow = currentRow;
      currentRow = temp;
    }

    return previousRow[m];
  }
}
