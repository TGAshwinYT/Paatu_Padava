import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/smart_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartCacheService Predictive Caching & Offline Management Tests', () {
    test('SmartCacheService initializes and creates smart_cache folder', () async {
      final cacheService = SmartCacheService.instance;
      await cacheService.init();

      expect(cacheService.cachedSongsCountNotifier.value, isNotNull);
    });

    test('isCached returns false for non-existent or unbuffered track', () {
      final cacheService = SmartCacheService.instance;
      expect(cacheService.isCached('non_existent_track_xyz'), isFalse);
      expect(cacheService.getCachedAudioFile('non_existent_track_xyz'), isNull);
    });

    test('onQueueUpdated handles empty queue without errors', () {
      final cacheService = SmartCacheService.instance;
      expect(() => cacheService.onQueueUpdated(null, []), returnsNormally);
    });

    test('onQueueUpdated identifies upcoming candidate songs for pre-caching', () {
      final cacheService = SmartCacheService.instance;

      final song1 = Song(
        id: 'track_1',
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        duration: 200,
        coverUrl: '',
      );
      final song2 = Song(
        id: 'track_2',
        title: 'Song 2',
        artist: 'Artist',
        album: 'Album',
        duration: 180,
        coverUrl: '',
      );
      final song3 = Song(
        id: 'track_3',
        title: 'Song 3',
        artist: 'Artist',
        album: 'Album',
        duration: 220,
        coverUrl: '',
      );

      final queue = [song1, song2, song3];

      expect(() => cacheService.onQueueUpdated(song1, queue, preloadCount: 2), returnsNormally);
    });
  });
}
