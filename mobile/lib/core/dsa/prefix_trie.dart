import 'dart:collection';

/// Represents a suggestion match from the [PrefixTrie].
class TrieMatch<T> {
  final String term;
  final T? payload;
  final int weight;

  const TrieMatch({
    required this.term,
    this.payload,
    this.weight = 0,
  });

  @override
  String toString() => 'TrieMatch($term, weight: $weight)';
}

/// Internal Node in the [PrefixTrie].
class TrieNode<T> {
  final Map<String, TrieNode<T>> children = HashMap<String, TrieNode<T>>();
  bool isEndOfWord = false;
  String? fullTerm;
  T? payload;
  int weight = 0;
}

/// High-Performance O(K) Prefix Trie (Retrieval Tree) for instantaneous search autocomplete.
/// 
/// Time Complexity:
/// - Insertion: O(K) where K is the term character length.
/// - Prefix Lookup: O(K + M) where K is prefix length and M is number of matching descendants.
/// - Memory: Compact character node tree with shared common prefixes.
class PrefixTrie<T> {
  final TrieNode<T> _root = TrieNode<T>();
  int _size = 0;

  int get size => _size;
  bool get isEmpty => _size == 0;
  bool get isNotEmpty => _size > 0;

  /// Inserts a term with an optional payload and ranking weight into the Trie in O(K) time.
  void insert(String term, {T? payload, int weight = 0}) {
    final normalized = _normalize(term);
    if (normalized.isEmpty) return;

    TrieNode<T> current = _root;
    for (int i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      current = current.children.putIfAbsent(char, () => TrieNode<T>());
    }

    if (!current.isEndOfWord) {
      _size++;
      current.isEndOfWord = true;
    }
    current.fullTerm = term; // Store original case representation
    current.payload = payload;
    current.weight = weight;
  }

  /// Bulk insert of terms.
  void insertAll(Iterable<String> terms, {int defaultWeight = 0}) {
    for (final term in terms) {
      insert(term, weight: defaultWeight);
    }
  }

  /// Finds all terms matching the given [prefix] in O(K + M) time.
  /// Results are ordered by descending weight, capped at [limit].
  List<TrieMatch<T>> findByPrefix(String prefix, {int limit = 10}) {
    final normalized = _normalize(prefix);
    if (normalized.isEmpty) return const [];

    TrieNode<T> current = _root;
    for (int i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      final next = current.children[char];
      if (next == null) {
        return const []; // Prefix does not exist in Trie
      }
      current = next;
    }

    // Traverse subtree using BFS to collect candidates
    final matches = <TrieMatch<T>>[];
    final queue = Queue<TrieNode<T>>()..add(current);

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      if (node.isEndOfWord && node.fullTerm != null) {
        matches.add(TrieMatch<T>(
          term: node.fullTerm!,
          payload: node.payload,
          weight: node.weight,
        ));
      }
      queue.addAll(node.children.values);
    }

    // Sort by descending weight
    matches.sort((a, b) => b.weight.compareTo(a.weight));

    if (matches.length > limit) {
      return matches.sublist(0, limit);
    }
    return matches;
  }

  /// Fast O(K) exact membership test.
  bool contains(String term) {
    final normalized = _normalize(term);
    if (normalized.isEmpty) return false;

    TrieNode<T> current = _root;
    for (int i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      final next = current.children[char];
      if (next == null) return false;
      current = next;
    }
    return current.isEndOfWord;
  }

  /// Removes a term in O(K) time. Returns true if removed, false if not found.
  bool remove(String term) {
    final normalized = _normalize(term);
    if (normalized.isEmpty) return false;

    bool didRemove = false;
    bool removeHelper(TrieNode<T> current, int depth) {
      if (depth == normalized.length) {
        if (!current.isEndOfWord) return false;
        current.isEndOfWord = false;
        current.fullTerm = null;
        current.payload = null;
        _size--;
        didRemove = true;
        return current.children.isEmpty;
      }

      final char = normalized[depth];
      final child = current.children[char];
      if (child == null) return false;

      final shouldDeleteChild = removeHelper(child, depth + 1);
      if (shouldDeleteChild) {
        current.children.remove(char);
        return !current.isEndOfWord && current.children.isEmpty;
      }

      return false;
    }

    removeHelper(_root, 0);
    return didRemove;
  }

  /// Clears the Trie.
  void clear() {
    _root.children.clear();
    _size = 0;
  }

  static String _normalize(String input) {
    return input.toLowerCase().trim();
  }
}
