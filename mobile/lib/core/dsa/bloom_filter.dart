import 'dart:math' as math;
import 'dart:typed_data';

/// High-Performance O(1) Space-Efficient Probabilistic Bloom Filter.
///
/// Uses a compact Uint32 bit-array and the Kirsch-Mitzenmacher double-hashing
/// technique to simulate k independent hash functions:
///   g_i(x) = (h1(x) + i * h2(x)) mod m
///
/// Properties:
/// - Zero False Negatives: If contains(item) == false, the item is 100% GUARANTEED
///   not in the set (eliminates unnecessary disk/SQLite queries).
/// - Configurable False Positive rate (p <= 0.01 by default).
/// - Time Complexity: O(k) = O(1) for both insertion and lookup.
/// - Space Complexity: Sub-kilobyte footprint for thousands of items.
class BloomFilter {
  final int expectedElements;
  final double falsePositiveProbability;

  late final int _bitSize; // m
  late final int _numHashFunctions; // k
  late final Uint32List _bitArray;
  int _insertedCount = 0;

  BloomFilter({
    this.expectedElements = 1000,
    this.falsePositiveProbability = 0.01,
  }) {
    final n = math.max(1, expectedElements);
    final p = falsePositiveProbability.clamp(0.0001, 0.5);

    // Optimal bit size: m = - (n * ln(p)) / (ln(2)^2)
    final m = (-1.0 * n * math.log(p) / (math.ln2 * math.ln2)).ceil();
    _bitSize = math.max(32, m);

    // Optimal hash function count: k = (m / n) * ln(2)
    final k = ((_bitSize / n) * math.ln2).round();
    _numHashFunctions = math.max(1, k);

    // Size in 32-bit words
    final wordCount = (_bitSize + 31) ~/ 32;
    _bitArray = Uint32List(wordCount);
  }

  int get bitSize => _bitSize;
  int get numHashFunctions => _numHashFunctions;
  int get insertedCount => _insertedCount;

  /// Returns current theoretical false-positive probability based on inserted items:
  /// p = (1 - e^(-k * n / m))^k
  double get currentEstimatedFalsePositiveProbability {
    if (_insertedCount == 0) return 0.0;
    final expVal = math.exp(-1.0 * _numHashFunctions * _insertedCount / _bitSize);
    return math.pow(1.0 - expVal, _numHashFunctions).toDouble();
  }

  /// Adds a string item into the Bloom Filter in O(1) time.
  void add(String item) {
    final hashes = _computeDualHashes(item);
    final h1 = hashes[0];
    final h2 = hashes[1];

    for (int i = 0; i < _numHashFunctions; i++) {
      final bitIndex = (h1 + i * h2).abs() % _bitSize;
      _setBit(bitIndex);
    }
    _insertedCount++;
  }

  /// Bulk adds multiple items into the filter.
  void addAll(Iterable<String> items) {
    for (final item in items) {
      add(item);
    }
  }

  /// Tests whether [item] may have been added to the filter in O(1) time.
  /// - Returns false: Guaranteed that [item] is NOT present.
  /// - Returns true: High probability that [item] is present (false positive rate <= p).
  bool contains(String item) {
    final hashes = _computeDualHashes(item);
    final h1 = hashes[0];
    final h2 = hashes[1];

    for (int i = 0; i < _numHashFunctions; i++) {
      final bitIndex = (h1 + i * h2).abs() % _bitSize;
      if (!_getBit(bitIndex)) {
        return false; // Definite absence!
      }
    }
    return true; // Probable presence!
  }

  /// Resets the Bloom Filter bit-array to empty.
  void clear() {
    _bitArray.fillRange(0, _bitArray.length, 0);
    _insertedCount = 0;
  }

  void _setBit(int bitIndex) {
    final wordIndex = bitIndex >> 5; // bitIndex / 32
    final bitOffset = bitIndex & 31; // bitIndex % 32
    _bitArray[wordIndex] |= (1 << bitOffset);
  }

  bool _getBit(int bitIndex) {
    final wordIndex = bitIndex >> 5;
    final bitOffset = bitIndex & 31;
    return (_bitArray[wordIndex] & (1 << bitOffset)) != 0;
  }

  /// Generates two distinct 32-bit hashes for string [item]:
  /// - h1: 32-bit Fowler-Noll-Vo (FNV-1a) hash
  /// - h2: DJB2 / Murmur-inspired variant
  static List<int> _computeDualHashes(String item) {
    int h1 = 0x811c9dc5; // 32-bit FNV offset basis
    int h2 = 5381; // DJB2 seed

    for (int i = 0; i < item.length; i++) {
      final code = item.codeUnitAt(i);

      // FNV-1a
      h1 ^= code;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;

      // DJB2 with bit-mixing
      h2 = (((h2 << 5) + h2) ^ code) & 0xFFFFFFFF;
    }

    // Force signed 32-bit integer normalization
    if (h1 >= 0x80000000) h1 -= 0x100000000;
    if (h2 >= 0x80000000) h2 -= 0x100000000;

    return [h1, h2];
  }
}
