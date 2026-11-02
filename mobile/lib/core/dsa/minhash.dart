import 'dart:math' as math;

/// Represents a compact 64-dimensional MinHash sketch signature.
///
/// Enables O(1) constant-time Jaccard similarity estimation between
/// song metadata, lyrics, and cross-provider audio entities.
class MinHashSignature {
  final List<int> values;

  const MinHashSignature(this.values);

  /// Computes the estimated Jaccard similarity between this signature and [other].
  ///
  /// Mathematical foundation:
  /// Pr[h_min(A) == h_min(B)] = Jaccard(A, B) = |A ∩ B| / |A ∪ B|
  double similarity(MinHashSignature other) {
    if (values.isEmpty || other.values.isEmpty) return 0.0;
    final int len = math.min(values.length, other.values.length);
    if (len == 0) return 0.0;

    int matches = 0;
    for (int i = 0; i < len; i++) {
      if (values[i] == other.values[i]) {
        matches++;
      }
    }
    return matches / len;
  }

  /// Determines whether two signatures are near-duplicates above [threshold].
  bool isDuplicate(MinHashSignature other, {double threshold = 0.80}) {
    return similarity(other) >= threshold;
  }

  @override
  String toString() => 'MinHashSignature(dims: ${values.length})';
}

/// MinHash Sketch Generator using 64 Universal Hash Permutations.
///
/// Used for O(1) near-duplicate detection and cross-provider deduplication
/// (e.g. JioSaavn vs YouTube music tracks) without expensive string metric calculations.
class MinHash {
  /// Default number of permutation hash functions (64 provides ~12.5% std error, optimal for mobile).
  static const int defaultDimensions = 64;

  /// Large Mersenne Prime 2^31 - 1
  static const int _prime = 2147483647;

  final int dimensions;
  final List<int> _aCoefficients;
  final List<int> _bCoefficients;

  /// Creates a MinHash instance with deterministically generated hash coefficients.
  MinHash({this.dimensions = defaultDimensions})
      : _aCoefficients = List<int>.filled(dimensions, 0),
        _bCoefficients = List<int>.filled(dimensions, 0) {
    // Deterministic linear congruential generator for reproducible universal hashing
    int seed = 42;
    for (int i = 0; i < dimensions; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      int a = seed % (_prime - 1) + 1;
      if (a.isEven) a++; // Ensure non-zero and odd

      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      int b = seed % _prime;

      _aCoefficients[i] = a;
      _bCoefficients[i] = b;
    }
  }

  static final MinHash instance = MinHash();

  /// Hashes a string token into a 32-bit positive integer using FNV-1a.
  static int hashToken(String token) {
    int hash = 0x811c9dc5;
    final units = token.codeUnits;
    for (int i = 0; i < units.length; i++) {
      hash ^= units[i];
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// Extracts character n-gram shingles from text for robust regional phonetic tolerance.
  static Set<String> extractShingles(String text, {int shingleSize = 3}) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.isEmpty) return const {};
    if (clean.length <= shingleSize) return {clean};

    final padded = '__${clean}__';
    final Set<String> shingles = <String>{};
    for (int i = 0; i <= padded.length - shingleSize; i++) {
      shingles.add(padded.substring(i, i + shingleSize));
    }
    return shingles;
  }

  /// Computes a [MinHashSignature] from a collection of raw string tokens or shingles.
  MinHashSignature computeFromTokens(Iterable<String> tokens) {
    if (tokens.isEmpty) {
      return MinHashSignature(List<int>.filled(dimensions, 0));
    }

    final tokenHashes = tokens.map(hashToken).toList(growable: false);
    final List<int> minValues = List<int>.filled(dimensions, _prime);

    for (final h in tokenHashes) {
      for (int i = 0; i < dimensions; i++) {
        // Universal Hash Function: h_i(x) = (a * x + b) % prime
        final int val = ((_aCoefficients[i] * h + _bCoefficients[i]) & 0x7FFFFFFF) % _prime;
        if (val < minValues[i]) {
          minValues[i] = val;
        }
      }
    }

    return MinHashSignature(minValues);
  }

  /// Computes a [MinHashSignature] from raw text by decomposing into character shingles.
  MinHashSignature computeFromText(String text, {int shingleSize = 3}) {
    final shingles = extractShingles(text, shingleSize: shingleSize);
    return computeFromTokens(shingles);
  }

  /// Computes a unified track signature from title, artist, and optional album.
  ///
  /// Combines 3-gram character shingles of title, word tokens of artists, and clean album name
  /// to form an invariant identity fingerprint for cross-provider matching.
  MinHashSignature computeTrackSignature({
    required String title,
    required String artist,
    String? album,
  }) {
    final tokens = <String>{};
    tokens.addAll(extractShingles(title, shingleSize: 3));

    // Artist words (e.g. "Anirudh", "A.R. Rahman")
    final artistClean = artist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    for (final word in artistClean.split(RegExp(r'\s+'))) {
      if (word.length >= 2) tokens.add('art_$word');
    }

    if (album != null && album.isNotEmpty) {
      tokens.addAll(extractShingles(album, shingleSize: 3));
    }

    return computeFromTokens(tokens);
  }
}
