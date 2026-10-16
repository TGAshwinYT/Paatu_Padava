import 'dart:math';

/// High-Performance O(N) Reversible Fisher-Yates Shuffle Manager.
///
/// Solves the three classical audio playback shuffle problems:
/// 1. True Uniformity: Implements the Knuth / Fisher-Yates algorithm
///    guaranteeing unbiased 1/N! permutation distribution.
/// 2. Bidirectional History Stack: Maintains a deterministic two-way navigation
///    stack so "Previous" always retraces the exact played sequence rather than
///    randomly jumping.
/// 3. Zero-Loss Reversibility: Preserves original un-shuffled playlist sequence
///    so toggling shuffle ON and OFF anchors the active track back to its original
///    album/playlist position seamlessly.
class ReversibleShuffleManager<T> {
  final List<T> _originalSequence = [];
  final List<int> _shuffledIndices = [];
  final List<int> _historyStack = [];
  int _historyCursor = -1;
  int _currentShuffledIndex = -1;
  bool _isShuffleActive = false;
  final Random _random;

  ReversibleShuffleManager({Random? random}) : _random = random ?? Random();

  bool get isShuffleActive => _isShuffleActive;
  int get length => _originalSequence.length;
  bool get isEmpty => _originalSequence.isEmpty;
  bool get isNotEmpty => _originalSequence.isNotEmpty;
  int get currentShuffledIndex => _currentShuffledIndex;

  /// Returns the current active item, or null if sequence is empty.
  T? get currentItem {
    if (_originalSequence.isEmpty) return null;
    if (_isShuffleActive) {
      if (_currentShuffledIndex >= 0 && _currentShuffledIndex < _shuffledIndices.length) {
        return _originalSequence[_shuffledIndices[_currentShuffledIndex]];
      }
      return null;
    } else {
      if (_currentShuffledIndex >= 0 && _currentShuffledIndex < _originalSequence.length) {
        return _originalSequence[_currentShuffledIndex];
      }
      return null;
    }
  }

  /// Sets or replaces the base playlist context sequence.
  void setSequence(List<T> items, {int initialIndex = 0}) {
    _originalSequence.clear();
    _originalSequence.addAll(items);
    _shuffledIndices.clear();
    _historyStack.clear();
    _historyCursor = -1;

    final safeIdx = items.isEmpty ? -1 : initialIndex.clamp(0, items.length - 1);
    _currentShuffledIndex = safeIdx;

    if (_isShuffleActive && items.isNotEmpty) {
      _generateFisherYatesPermutation(anchorOriginalIndex: safeIdx);
    }
  }

  /// Toggles shuffle state on or off while strictly preserving the active item.
  void setShuffleEnabled(bool enable, {int? activeOriginalIndex}) {
    if (_isShuffleActive == enable) return;
    if (_originalSequence.isEmpty) {
      _isShuffleActive = enable;
      return;
    }

    if (enable) {
      _isShuffleActive = true;
      final anchorIdx = activeOriginalIndex ??
          (_currentShuffledIndex >= 0 ? _currentShuffledIndex : 0);
      _generateFisherYatesPermutation(anchorOriginalIndex: anchorIdx);
      _currentShuffledIndex = 0; // Pinned anchor is at index 0
      _historyStack.clear();
      _historyStack.add(anchorIdx);
      _historyCursor = 0;
    } else {
      _isShuffleActive = false;
      // Map active shuffled track back to original sequence index
      if (_currentShuffledIndex >= 0 && _currentShuffledIndex < _shuffledIndices.length) {
        final restoredRawIndex = _shuffledIndices[_currentShuffledIndex];
        _currentShuffledIndex = restoredRawIndex;
      }
      _shuffledIndices.clear();
      _historyStack.clear();
      _historyCursor = -1;
    }
  }

  /// Executes Knuth / Fisher-Yates uniform shuffle in O(N) time,
  /// pinning [anchorOriginalIndex] to position 0.
  void _generateFisherYatesPermutation({required int anchorOriginalIndex}) {
    final n = _originalSequence.length;
    final remainingIndices = <int>[];

    for (int i = 0; i < n; i++) {
      if (i != anchorOriginalIndex) {
        remainingIndices.add(i);
      }
    }

    // Modern Fisher-Yates Shuffle on remaining indices
    for (int i = remainingIndices.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = remainingIndices[i];
      remainingIndices[i] = remainingIndices[j];
      remainingIndices[j] = temp;
    }

    _shuffledIndices.clear();
    if (anchorOriginalIndex >= 0 && anchorOriginalIndex < n) {
      _shuffledIndices.add(anchorOriginalIndex); // Pin active track to 0
    }
    _shuffledIndices.addAll(remainingIndices);
  }

  /// Advances to the next track. Returns next item, or null if EOF reached.
  T? next() {
    if (_originalSequence.isEmpty) return null;

    if (_isShuffleActive) {
      // Check if we can traverse forward in history stack
      if (_historyCursor + 1 < _historyStack.length) {
        _historyCursor++;
        final origIdx = _historyStack[_historyCursor];
        _currentShuffledIndex = _shuffledIndices.indexOf(origIdx);
        return _originalSequence[origIdx];
      }

      // Otherwise advance to next in shuffled order
      if (_currentShuffledIndex + 1 < _shuffledIndices.length) {
        _currentShuffledIndex++;
        final origIdx = _shuffledIndices[_currentShuffledIndex];
        _historyStack.add(origIdx);
        _historyCursor = _historyStack.length - 1;
        return _originalSequence[origIdx];
      }
      return null;
    } else {
      if (_currentShuffledIndex + 1 < _originalSequence.length) {
        _currentShuffledIndex++;
        return _originalSequence[_currentShuffledIndex];
      }
      return null;
    }
  }

  /// Rewinds to the previous track along the bidirectional history stack.
  T? previous() {
    if (_originalSequence.isEmpty) return null;

    if (_isShuffleActive) {
      if (_historyCursor > 0) {
        _historyCursor--;
        final origIdx = _historyStack[_historyCursor];
        _currentShuffledIndex = _shuffledIndices.indexOf(origIdx);
        return _originalSequence[origIdx];
      }
      return null;
    } else {
      if (_currentShuffledIndex > 0) {
        _currentShuffledIndex--;
        return _originalSequence[_currentShuffledIndex];
      }
      return null;
    }
  }

  /// Current permutation indices (for inspection / tests)
  List<int> get shuffledIndices => List.unmodifiable(_shuffledIndices);

  /// Original sequence items
  List<T> get originalSequence => List.unmodifiable(_originalSequence);

  /// History stack items
  List<int> get historyStack => List.unmodifiable(_historyStack);

  /// Clears all sequences and history.
  void clear() {
    _originalSequence.clear();
    _shuffledIndices.clear();
    _historyStack.clear();
    _historyCursor = -1;
    _currentShuffledIndex = -1;
    _isShuffleActive = false;
  }
}
