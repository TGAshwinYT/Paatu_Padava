import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/user_preference_matrix.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';

void main() {
  test('Movie Soundtrack Tracks rank at top ahead of foreign title matches', () {
    final intent = SearchService.understandQuery('mersal');

    final arabicSong = Song(
      id: 'arabic_1',
      title: 'Mersal',
      artist: 'Alaa Abdel Khalek',
      album: 'Tayyara Waraq',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'saavn',
      language: 'arabic',
    );

    final aalaporaan = Song(
      id: 'aalaporaan_1',
      title: 'Aalaporaan Thamizhan',
      artist: 'A.R. Rahman, Kailash Kher',
      album: 'Mersal',
      coverUrl: 'https://c.saavncdn.com/492/Mersal-Tamil-2017-500x500.jpg',
      source: 'saavn',
      language: 'tamil',
    );

    final neethanae = Song(
      id: 'neethanae_1',
      title: 'Neethanae',
      artist: 'A.R. Rahman, Shreya Ghoshal',
      album: 'Mersal',
      coverUrl: 'https://c.saavncdn.com/492/Mersal-Tamil-2017-500x500.jpg',
      source: 'saavn',
      language: 'tamil',
    );

    final mersalArasan = Song(
      id: 'mersal_arasan_1',
      title: 'Mersal Arasan',
      artist: 'A.R. Rahman, G.V. Prakash',
      album: 'Mersal',
      coverUrl: 'https://c.saavncdn.com/492/Mersal-Tamil-2017-500x500.jpg',
      source: 'saavn',
      language: 'tamil',
    );

    final maacho = Song(
      id: 'maacho_1',
      title: 'Maacho',
      artist: 'A.R. Rahman, Sid Sriram',
      album: 'Mersal',
      coverUrl: 'https://c.saavncdn.com/492/Mersal-Tamil-2017-500x500.jpg',
      source: 'saavn',
      language: 'tamil',
    );

    // 1. Verify foreign language purge: Arabic song gets score 0.0
    final arabicScore = SearchService.calculateCompositeRelevance(arabicSong, intent);
    expect(arabicScore, 0.0, reason: 'Non-regional language song must be purged to 0.0');

    // 2. Movie soundtrack songs must get 1.0
    final aalaScore = SearchService.calculateCompositeRelevance(aalaporaan, intent);
    expect(aalaScore, 1.0, reason: 'Movie soundtrack track must score 1.0');

    // 3. Re-ranking: movie soundtrack songs must be at top positions
    final pool = [arabicSong, aalaporaan, neethanae, mersalArasan, maacho];
    final reranked = UserPreferenceMatrix.reRankWithPreferences(pool, 'mersal');

    expect(reranked.take(4).map((s) => s.album).toSet(), {'Mersal'});
    expect(reranked.any((s) => s.album == 'Mersal'), isTrue);
  });
}
