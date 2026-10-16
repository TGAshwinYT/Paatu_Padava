import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/core/dsa/lru_cache.dart';
import 'package:paatu_padava_mobile/core/dsa/prefix_trie.dart';
import 'package:paatu_padava_mobile/core/dsa/circular_buffer.dart';
import 'package:paatu_padava_mobile/core/dsa/bk_tree.dart';
import 'package:paatu_padava_mobile/core/dsa/bloom_filter.dart';
import 'package:paatu_padava_mobile/core/dsa/reversible_shuffle.dart';
import 'package:paatu_padava_mobile/logic/crossfade_engine.dart';
import 'package:paatu_padava_mobile/logic/markov_cosine_radio_strategy.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/fuzzy_search_service.dart';

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

  group('BkTree O(log N) Metric Space Typo-Tolerant Search Tests', () {
    test('Levenshtein distance calculation and early threshold termination', () {
      expect(BkTree.levenshteinDistance('kitten', 'kitten'), 0);
      expect(BkTree.levenshteinDistance('kitten', 'sitting'), 3);
      expect(BkTree.levenshteinDistance('hukum', 'hukm'), 1);
      expect(BkTree.levenshteinDistance('badass', 'badasss'), 1);
      expect(BkTree.levenshteinDistance('vaseegara', 'vasegara'), 1);

      // Early exit beyond maxDistance
      expect(BkTree.levenshteinDistance('anirudh', 'completely_different', maxDistance: 2), 3);
    });

    test('BkTree insertion, contains, and size tracking', () {
      final tree = BkTree<String>();
      expect(tree.isEmpty, true);

      tree.insert('Anirudh');
      tree.insert('A.R. Rahman');
      tree.insert('Harris Jayaraj');
      tree.insert('Yuvan');

      expect(tree.size, 4);
      expect(tree.contains('anirudh'), true);
      expect(tree.contains('A.R. Rahman'), true);
      expect(tree.contains('Unknown Artist'), false);
    });

    test('BkTree search finds nearest matches and prunes irrelevant branches via triangle inequality', () {
      final tree = BkTree<void>();
      final terms = [
        'Hukum',
        'Badass',
        'Vaseegara',
        'Arabic Kuthu',
        'Naa Ready',
        'Kaavaalaa',
        'Leo',
        'Jailer',
        'Vikram',
        'Master',
        'Varisu',
        'Beast',
        'Doctor',
        'Petta',
      ];
      tree.insertAll(terms);
      expect(tree.size, terms.length);

      // Search "Hukm" (1 deletion typo from "Hukum")
      final matchesHukum = tree.search('Hukm', maxDistance: 1);
      expect(matchesHukum.isNotEmpty, true);
      expect(matchesHukum.first.term, 'Hukum');
      expect(matchesHukum.first.distance, 1);
      expect(matchesHukum.first.similarity, closeTo(0.8, 0.05));

      // Verify that triangle inequality actually pruned subtrees
      expect(tree.lastSearchBranchesPruned, greaterThan(0));

      // Search "Vasegara" (1 deletion typo from "Vaseegara")
      final matchesVaseegara = tree.search('Vasegara', maxDistance: 2);
      expect(matchesVaseegara.isNotEmpty, true);
      expect(matchesVaseegara.first.term, 'Vaseegara');
      expect(matchesVaseegara.first.distance, 1);

      // Search with findBestMatch
      final best = tree.findBestMatch('Beest', maxDistance: 1);
      expect(best, isNotNull);
      expect(best!.term, 'Beast');
      expect(best.distance, 1);

      // Unmatched word beyond threshold
      final noMatch = tree.findBestMatch('Xyz12345', maxDistance: 2);
      expect(noMatch, isNull);
    });
  });

  group('FuzzySearchService BK-Tree Typo Correction Tests', () {
    test('findCorrection corrects single and double typo queries', () {
      // "Vasegara" -> "Vaseegara"
      final vasegaraCorrection = FuzzySearchService.findCorrection('Vasegara');
      expect(vasegaraCorrection, isNotNull);
      expect(vasegaraCorrection!.corrected, 'Vaseegara');
      expect(vasegaraCorrection.score, greaterThanOrEqualTo(65));

      // Exact match should return null (no typo correction required)
      final exactHukum = FuzzySearchService.findCorrection('Hukum');
      expect(exactHukum, isNull);

      // Very short queries (< 3 chars) should return null
      expect(FuzzySearchService.findCorrection('hi'), isNull);
    });

    test('registerCandidates dynamically populates the BK-Tree for instant lookup', () {
      FuzzySearchService.registerCandidates(['Thalapathy Kuthu Mix']);

      final correction = FuzzySearchService.findCorrection('Thalapathy Kuthu Mixx');
      expect(correction, isNotNull);
      expect(correction!.corrected, 'Thalapathy Kuthu Mix');
    });
  });

  group('BloomFilter O(1) Probabilistic Set Tests', () {
    test('Zero false negatives: all added items must return true', () {
      final filter = BloomFilter(expectedElements: 50, falsePositiveProbability: 0.01);
      final songIds = List.generate(50, (i) => 'song_track_$i');

      filter.addAll(songIds);

      for (final id in songIds) {
        expect(filter.contains(id), isTrue, reason: 'False negative for $id');
      }
      expect(filter.insertedCount, 50);
    });

    test('Definite absence: items not added return false', () {
      final filter = BloomFilter(expectedElements: 100, falsePositiveProbability: 0.01);
      filter.addAll(['hukum_123', 'badass_456', 'arabic_789']);

      expect(filter.contains('hukum_123'), true);
      expect(filter.contains('unadded_song_999'), false);
      expect(filter.contains('another_missing_track'), false);
    });

    test('Clear resets the bit array', () {
      final filter = BloomFilter(expectedElements: 10);
      filter.add('song_xyz');
      expect(filter.contains('song_xyz'), true);

      filter.clear();
      expect(filter.insertedCount, 0);
      expect(filter.contains('song_xyz'), false);
    });
  });

  group('ReversibleShuffleManager O(N) Fisher-Yates Tests', () {
    test('Knuth Fisher-Yates shuffle preserves anchor at index 0 and contains all items', () {
      final manager = ReversibleShuffleManager<String>();
      final tracks = ['Track A', 'Track B', 'Track C', 'Track D', 'Track E'];

      manager.setSequence(tracks, initialIndex: 2); // 'Track C' active
      expect(manager.currentItem, 'Track C');

      // Enable shuffle: Track C (index 2) must be pinned as anchor at position 0
      manager.setShuffleEnabled(true, activeOriginalIndex: 2);
      expect(manager.isShuffleActive, true);
      expect(manager.currentItem, 'Track C');
      expect(manager.currentShuffledIndex, 0);
      expect(manager.shuffledIndices.first, 2);

      // Shuffled indices must contain all original indices [0..4] without duplicates
      final set = manager.shuffledIndices.toSet();
      expect(set.length, tracks.length);
      expect(set.containsAll([0, 1, 2, 3, 4]), true);
    });

    test('Bidirectional history navigation traverses played sequence correctly', () {
      final manager = ReversibleShuffleManager<String>();
      manager.setSequence(['A', 'B', 'C', 'D'], initialIndex: 0);
      manager.setShuffleEnabled(true, activeOriginalIndex: 0);

      final firstTrack = manager.currentItem;
      final secondTrack = manager.next();
      final thirdTrack = manager.next();

      expect(manager.currentItem, thirdTrack);

      // Rewind backwards
      final rewoundSecond = manager.previous();
      expect(rewoundSecond, secondTrack);

      final rewoundFirst = manager.previous();
      expect(rewoundFirst, firstTrack);
    });

    test('Disabling shuffle restores active track to exact un-shuffled index', () {
      final manager = ReversibleShuffleManager<String>();
      manager.setSequence(['Track 0', 'Track 1', 'Track 2', 'Track 3'], initialIndex: 0);

      manager.setShuffleEnabled(true);
      manager.next(); // Move to next shuffled track
      final activeShuffledTrack = manager.currentItem;

      // Disable shuffle
      manager.setShuffleEnabled(false);
      expect(manager.isShuffleActive, false);
      expect(manager.currentItem, activeShuffledTrack);
    });
  });

  group('EqualPowerCurve & Crossfade Calculations', () {
    test('EqualPowerCurve maintains constant acoustic power V_out^2 + V_in^2 == 1.0', () {
      for (double t = 0.0; t <= 1.0; t += 0.1) {
        final (outVol, inVol) = EqualPowerCurve.calculate(t);
        final acousticPower = (outVol * outVol) + (inVol * inVol);
        expect(acousticPower, closeTo(1.0, 0.001));
      }

      // At start (t = 0.0): out = 1.0, in = 0.0
      final (out0, in0) = EqualPowerCurve.calculate(0.0);
      expect(out0, closeTo(1.0, 0.001));
      expect(in0, closeTo(0.0, 0.001));

      // At midpoint (t = 0.5): out = ~0.7071, in = ~0.7071 (0 dB acoustic drop!)
      final (outMid, inMid) = EqualPowerCurve.calculate(0.5);
      expect(outMid, closeTo(0.7071, 0.01));
      expect(inMid, closeTo(0.7071, 0.01));

      // At end (t = 1.0): out = 0.0, in = 1.0
      final (out1, in1) = EqualPowerCurve.calculate(1.0);
      expect(out1, closeTo(0.0, 0.001));
      expect(in1, closeTo(1.0, 0.001));
    });
  });

  group('Markov-Cosine Radio Vector & Transition Tests', () {
    test('MarkovTransitionMatrix tracks positive and negative transitions', () {
      final matrix = MarkovTransitionMatrix();
      final songA = Song(id: '1', title: 'Hukum', artist: 'Anirudh', album: 'Jailer', coverUrl: 'https://example.com/cover.jpg');
      final songB = Song(id: '2', title: 'Badass', artist: 'Anirudh', album: 'Leo', coverUrl: 'https://example.com/cover.jpg');
      final songC = Song(id: '3', title: 'Vaseegara', artist: 'Harris Jayaraj', album: 'Minnale', coverUrl: 'https://example.com/cover.jpg');

      // Record positive transitions from A -> B
      matrix.recordTransition(songA, songB, isPositive: true);
      matrix.recordTransition(songA, songB, isPositive: true);

      // Transition to C has no recorded history
      final probB = matrix.getProbability(songA, songB);
      final probC = matrix.getProbability(songA, songC);

      expect(probB, greaterThan(probC));
    });

    test('SongFeatureVector cosine similarity scores similar tracks higher', () {
      final seed = Song(
        id: '10',
        title: 'Hukum',
        artist: 'Anirudh Ravichander',
        album: 'Jailer (2023)',
        coverUrl: 'https://example.com/cover.jpg',
        language: 'Tamil',
        duration: 210,
      );

      final similar = Song(
        id: '11',
        title: 'Badass',
        artist: 'Anirudh Ravichander',
        album: 'Leo (2023)',
        coverUrl: 'https://example.com/cover.jpg',
        language: 'Tamil',
        duration: 220,
      );

      final distant = Song(
        id: '12',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        album: 'Divide (2017)',
        coverUrl: 'https://example.com/cover.jpg',
        language: 'English',
        duration: 235,
      );

      final vecSimilar = SongFeatureVector.extractRelative(seed, similar);
      final vecDistant = SongFeatureVector.extractRelative(seed, distant);

      final simScoreSimilar = vecSimilar.cosineSimilarityTo(SongFeatureVector.ideal);
      final simScoreDistant = vecDistant.cosineSimilarityTo(SongFeatureVector.ideal);

      expect(simScoreSimilar, greaterThan(simScoreDistant));
    });
  });
}
