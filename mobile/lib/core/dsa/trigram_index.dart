import 'dart:math' as math;

/// Represents a match result returned by [TrigramIndex].
class TrigramMatch<T> {
  final String term;
  final T? payload;
  final double similarity;

  const TrigramMatch({
    required this.term,
    this.payload,
    required this.similarity,
  });

  @override
  String toString() => 'TrigramMatch(term: "$term", similarity: ${(similarity * 100).toStringAsFixed(1)}%)';
}

/// High-Performance Character 3-Gram (Tri-Gram) Inverted Index for Tanglish & Regional Phonetic Search.
///
/// Regional Indian music queries (Tamil, Telugu, Hindi) typed in English characters often have
/// diverse phonetic spellings (e.g. "kannadi" vs "kannaadi", "vaathi" vs "vathi", "aaradhya" vs "aradhya").
///
/// Mathematical Principles:
/// 1. Tri-gram decomposition: Slices string into sliding windows of length 3:
///    "kannaadi" -> {"$$k", "$ka", "kan", "ann", "nna", "naa", "aad", "adi", "di$"}
/// 2. Jaccard Similarity Coefficient:
///    J(A, B) = |A ∩ B| / |A ∪ B|
/// 3. Inverted Postings List:
///    Maps each 3-gram to candidate term entries. When querying, only terms sharing at least
///    one 3-gram are evaluated, achieving O(1) candidate pruning before computing Jaccard score.
class TrigramIndex<T> {
  final Map<String, Set<int>> _postings = <String, Set<int>>{};
  final List<String> _terms = <String>[];
  final List<T?> _payloads = <T?>[];
  final List<Set<String>> _termTrigrams = <Set<String>>[];

  int get size => _terms.length;
  bool get isEmpty => _terms.isEmpty;
  bool get isNotEmpty => _terms.isNotEmpty;

  /// Extracts sliding 3-character n-grams with edge boundary padding.
  static Set<String> extractTrigrams(String text) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.isEmpty) return const {};

    final padded = '$$clean\$';
    final Set<String> ngrams = <String>{};
    for (int i = 0; i <= padded.length - 3; i++) {
      ngrams.add(padded.substring(i, i + 3));
    }
    return ngrams;
  }

  /// Calculates the Jaccard similarity coefficient between two strings based on tri-grams.
  static double jaccard(String a, String b) {
    if (a.toLowerCase() == b.toLowerCase()) return 1.0;
    final triA = extractTrigrams(a);
    final triB = extractTrigrams(b);
    if (triA.isEmpty || triB.isEmpty) return 0.0;

    int intersection = 0;
    for (final gram in triA) {
      if (triB.contains(gram)) intersection++;
    }

    final union = triA.length + triB.length - intersection;
    return union > 0 ? intersection / union : 0.0;
  }

  /// Inserts a term with an optional payload into the inverted tri-gram index.
  void insert(String term, {T? payload}) {
    final clean = term.trim();
    if (clean.isEmpty) return;

    final termIndex = _terms.length;
    _terms.add(clean);
    _payloads.add(payload);

    final trigrams = extractTrigrams(clean);
    _termTrigrams.add(trigrams);

    for (final gram in trigrams) {
      _postings.putIfAbsent(gram, () => <int>{}).add(termIndex);
    }
  }

  /// Searches the index for candidates matching [query] with similarity >= [threshold].
  /// Returns matches sorted by descending Jaccard similarity.
  List<TrigramMatch<T>> search(
    String query, {
    double threshold = 0.30,
    int limit = 10,
  }) {
    final clean = query.trim();
    if (clean.isEmpty || _terms.isEmpty) return const [];

    final queryGrams = extractTrigrams(clean);
    if (queryGrams.isEmpty) return const [];

    // 1. Accumulate candidate document frequencies via postings list
    final Map<int, int> intersectionCounts = <int, int>{};
    for (final gram in queryGrams) {
      final postings = _postings[gram];
      if (postings != null) {
        for (final docId in postings) {
          intersectionCounts[docId] = (intersectionCounts[docId] ?? 0) + 1;
        }
      }
    }

    if (intersectionCounts.isEmpty) return const [];

    // 2. Score candidates using Jaccard index
    final List<TrigramMatch<T>> matches = [];
    final int queryGramCount = queryGrams.length;

    for (final entry in intersectionCounts.entries) {
      final docId = entry.key;
      final intersection = entry.value;
      final docGramCount = _termTrigrams[docId].length;
      final union = queryGramCount + docGramCount - intersection;
      final similarity = union > 0 ? intersection / union : 0.0;

      if (similarity >= threshold) {
        matches.add(
          TrigramMatch<T>(
            term: _terms[docId],
            payload: _payloads[docId],
            similarity: similarity,
          ),
        );
      }
    }

    // 3. Sort descending by similarity
    matches.sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches.take(limit).toList();
  }

  /// Clears all entries from the index.
  void clear() {
    _postings.clear();
    _terms.clear();
    _payloads.clear();
    _termTrigrams.clear();
  }
}
