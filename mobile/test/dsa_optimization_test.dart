import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/core/dsa/lru_cache.dart';
import 'package:paatu_padava_mobile/core/dsa/prefix_trie.dart';
import 'package:paatu_padava_mobile/core/dsa/circular_buffer.dart';

void main() {
  group('LruCache O(1) Performance & Eviction Tests', () {
    test('LruCache basic put, get, and hit/miss tracking', () {
      final cache = LruCache<String, int>(capacity: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      expect(cache.length, 3);
      expect(cache.get('a'), 1);
      expect(cache.get('b'), 2);
      expect(cache.get('d'), null);

      expect(cache.hits, 2);
      expect(cache.misses, 1);
      expect(cache.hitRate, closeTo(2 / 3, 0.01));
    });

    test('LruCache evicts least recently used item when capacity is reached', () {
      final cache = LruCache<String, String>(capacity: 3);

      cache.put('track_1', 'URL_1');
      cache.put('track_2', 'URL_2');
      cache.put('track_3', 'URL_3');

      // Access track_1 to make it Most Recently Used (MRU)
      expect(cache.get('track_1'), 'URL_1');

      // Insert 4th item: should evict track_2 (since track_1 was accessed, track_2 is now LRU)
      cache.put('track_4', 'URL_4');

      expect(cache.length, 3);
      expect(cache.get('track_2'), null); // Evicted!
      expect(cache.get('track_1'), 'URL_1');
      expect(cache.get('track_3'), 'URL_3');
      expect(cache.get('track_4'), 'URL_4');
      expect(cache.evictions, 1);
    });

    test('LruCache respects TTL expiration', () async {
      final cache = LruCache<String, String>(
        capacity: 5,
        defaultTtl: const Duration(milliseconds: 50),
      );

      cache.put('short_lived', 'value');
      expect(cache.get('short_lived'), 'value');

      await Future.delayed(const Duration(milliseconds: 70));

      // Should be expired and return null
      expect(cache.get('short_lived'), null);
      expect(cache.length, 0);
    });

    test('LruCache remove and clear', () {
      final cache = LruCache<String, int>(capacity: 3);
      cache.put('x', 10);
      cache.put('y', 20);

      expect(cache.remove('x'), 10);
      expect(cache.containsKey('x'), false);
      expect(cache.length, 1);

      cache.clear();
      expect(cache.isEmpty, true);
      expect(cache.hits, 0);
      expect(cache.misses, 0);
    });
  });

  group('PrefixTrie O(K) Autocomplete Search Tests', () {
    test('PrefixTrie insert, exact lookup, and contains', () {
      final trie = PrefixTrie<String>();

      trie.insert('Anirudh Ravichander', weight: 100);
      trie.insert('A.R. Rahman', weight: 95);
      trie.insert('Harris Jayaraj', weight: 80);
      trie.insert('Hiphop Tamizha', weight: 75);

      expect(trie.contains('anirudh ravichander'), true);
      expect(trie.contains('A.R. Rahman'), true);
      expect(trie.contains('Unknown Artist'), false);
    });

    test('PrefixTrie findByPrefix returns top-weighted matches in O(K) time', () {
      final trie = PrefixTrie<String>();

      trie.insert('Hukum', weight: 100);
      trie.insert('Hunter Vantaar', weight: 90);
      trie.insert('Halamithi Habibo', weight: 85);
      trie.insert('Hayyoda', weight: 70);
      trie.insert('Naa Ready', weight: 95);

      // Search prefix "h"
      final matchesH = trie.findByPrefix('h', limit: 3);
      expect(matchesH.length, 3);
      expect(matchesH[0].term, 'Hukum');
      expect(matchesH[1].term, 'Hunter Vantaar');
      expect(matchesH[2].term, 'Halamithi Habibo');

      // Search prefix "naa"
      final matchesNaa = trie.findByPrefix('naa');
      expect(matchesNaa.length, 1);
      expect(matchesNaa.first.term, 'Naa Ready');

      // Search prefix with no matches
      final emptyMatches = trie.findByPrefix('xyz');
      expect(emptyMatches.isEmpty, true);
    });

    test('PrefixTrie remove term', () {
      final trie = PrefixTrie<void>();
      trie.insert('Arabic Kuthu');
      trie.insert('Aalaporaan Thamizhan');

      expect(trie.contains('Arabic Kuthu'), true);
      expect(trie.remove('Arabic Kuthu'), true);
      expect(trie.contains('Arabic Kuthu'), false);
      expect(trie.contains('Aalaporaan Thamizhan'), true);
    });
  });

  group('CircularBuffer O(1) Fixed-Capacity Ring Tests', () {
    test('CircularBuffer appends up to capacity', () {
      final buffer = CircularBuffer<int>(3);
      expect(buffer.isEmpty, true);

      buffer.add(10);
      buffer.add(20);
      expect(buffer.length, 2);
      expect(buffer[0], 10);
      expect(buffer[1], 20);
      expect(buffer.first, 10);
      expect(buffer.last, 20);
    });

    test('CircularBuffer overwrites oldest elements when full', () {
      final buffer = CircularBuffer<String>(3);

      buffer.add('first');
      buffer.add('second');
      buffer.add('third');
      expect(buffer.isFull, true);

      // Adding 4th element overwrites 'first'
      buffer.add('fourth');
      expect(buffer.length, 3);
      expect(buffer[0], 'second');
      expect(buffer[1], 'third');
      expect(buffer[2], 'fourth');
      expect(buffer.first, 'second');
      expect(buffer.last, 'fourth');

      // Adding 5th element overwrites 'second'
      buffer.add('fifth');
      expect(buffer.toList(), ['third', 'fourth', 'fifth']);
    });

    test('CircularBuffer iterator iterates in chronological order', () {
      final buffer = CircularBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4); // Overwrote 1

      final elements = <int>[];
      for (final item in buffer) {
        elements.add(item);
      }
      expect(elements, [2, 3, 4]);
    });
  });
}
