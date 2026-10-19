import 'dart:math';

/// Pure algorithmic utility for non-destructive shuffle permutations.
/// Keeps the active track pinned at index 0 and guarantees deterministic un-shuffle.
class SmartShufflePermutator {
  final Random _rng;

  SmartShufflePermutator({Random? rng}) : _rng = rng ?? Random();

  /// Generates a Knuth/Fisher-Yates permutation list of length [totalLength],
  /// placing [activeRawIndex] at position 0 and uniformly randomizing the remainder.
  List<int> generateShuffleTable({
    required int totalLength,
    required int activeRawIndex,
  }) {
    if (totalLength <= 0) return const [];
    if (totalLength == 1) return const [0];

    final clampedActive = activeRawIndex.clamp(0, totalLength - 1);
    final List<int> remainder = [];
    for (int i = 0; i < totalLength; i++) {
      if (i != clampedActive) remainder.add(i);
    }

    for (int i = remainder.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final temp = remainder[i];
      remainder[i] = remainder[j];
      remainder[j] = temp;
    }

    return [clampedActive, ...remainder];
  }

  /// Maps a permuted index back to the underlying raw context queue index.
  int restoreRawIndex({
    required List<int> permutationTable,
    required int currentPermutedIndex,
    int fallbackIndex = 0,
  }) {
    if (permutationTable.isEmpty) return fallbackIndex;
    if (currentPermutedIndex >= 0 && currentPermutedIndex < permutationTable.length) {
      return permutationTable[currentPermutedIndex];
    }
    return fallbackIndex;
  }
}
