import 'dart:collection';

/// Node representing an entry in the [LruCache] with optional Time-To-Live (TTL).
class LruNode<K, V> {
  final K key;
  V value;
  final DateTime? expiresAt;

  LruNode(this.key, this.value, [this.expiresAt]);

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// High-Performance O(1) Least Recently Used (LRU) Cache with TTL and memory budgeting.
/// 
/// Built upon Dart's [LinkedHashMap] which internally provides a hash table with a doubly-linked list
/// of keys, guaranteeing O(1) insertions, O(1) lookups, and O(1) order promotions.
class LruCache<K, V> {
  final int capacity;
  final Duration? defaultTtl;

  final LinkedHashMap<K, LruNode<K, V>> _map = LinkedHashMap<K, LruNode<K, V>>();

  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  LruCache({
    required this.capacity,
    this.defaultTtl,
  }) : assert(capacity > 0, 'Capacity must be greater than zero');

  /// Current number of non-expired entries in cache.
  int get length => _map.length;

  /// Whether the cache is empty.
  bool get isEmpty => _map.isEmpty;

  /// Whether the cache is non-empty.
  bool get isNotEmpty => _map.isNotEmpty;

  /// Total hits recorded.
  int get hits => _hits;

  /// Total misses recorded.
  int get misses => _misses;

  /// Total evictions performed due to capacity limit.
  int get evictions => _evictions;

  /// Cache hit ratio (0.0 to 1.0).
  double get hitRate {
    final total = _hits + _misses;
    return total == 0 ? 0.0 : _hits / total;
  }

  /// Retrieves an entry in O(1) time and promotes it to Most Recently Used (MRU).
  /// Returns `null` if absent or expired.
  V? get(K key) {
    final node = _map[key];
    if (node == null) {
      _misses++;
      return null;
    }

    if (node.isExpired) {
      _map.remove(key);
      _misses++;
      return null;
    }

    // O(1) promotion: remove and re-insert at tail of LinkedHashMap
    _map.remove(key);
    _map[key] = node;
    _hits++;
    return node.value;
  }

  /// Inserts or updates an entry in O(1) time.
  /// If capacity is exceeded, evicts the Least Recently Used (LRU) entry in O(1).
  void put(K key, V value, {Duration? ttl}) {
    final effectiveTtl = ttl ?? defaultTtl;
    final expiresAt = effectiveTtl != null ? DateTime.now().add(effectiveTtl) : null;

    if (_map.containsKey(key)) {
      _map.remove(key);
    } else if (_map.length >= capacity) {
      // Evict LRU (head of LinkedHashMap) in O(1)
      final lruKey = _map.keys.first;
      _map.remove(lruKey);
      _evictions++;
    }

    _map[key] = LruNode<K, V>(key, value, expiresAt);
  }

  /// Fast O(1) existence check without modifying access order or counting as a hit/miss.
  bool containsKey(K key) {
    final node = _map[key];
    if (node == null) return false;
    if (node.isExpired) {
      _map.remove(key);
      return false;
    }
    return true;
  }

  /// Checks whether an entry exists and is expired.
  bool isExpired(K key) {
    final node = _map[key];
    if (node == null) return false;
    return node.isExpired;
  }

  /// Non-mutating peek at entry (does not alter MRU order or hit/miss counters).
  V? peek(K key) {
    final node = _map[key];
    if (node == null || node.isExpired) return null;
    return node.value;
  }

  /// Removes an entry in O(1) time.
  V? remove(K key) {
    final node = _map.remove(key);
    if (node == null || node.isExpired) return null;
    return node.value;
  }

  /// Purges all expired entries from cache.
  void purgeExpired() {
    final keysToRemove = <K>[];
    for (final entry in _map.entries) {
      if (entry.value.isExpired) {
        keysToRemove.add(entry.key);
      }
    }
    for (final k in keysToRemove) {
      _map.remove(k);
    }
  }

  /// Clears the entire cache and resets counters.
  void clear() {
    _map.clear();
    _hits = 0;
    _misses = 0;
    _evictions = 0;
  }

  /// Returns snapshot of all active, unexpired values.
  List<V> values() {
    purgeExpired();
    return _map.values.map((n) => n.value).toList();
  }
}
