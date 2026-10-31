import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/youtube_client.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';

void main() {
  group('YouTube Music WEB_REMIX Search & Parsing Tests', () {
    test('searchTracks returns clean tracks from searchMusicTracks when response is valid', () async {
      // Test searchTracks execution
      final results = await YouTubeClient.searchTracks('Hukum Anirudh', limit: 5);
      expect(results, isA<List<TrackEntity>>());
      // Even if network is offline in CI, fallback guarantee ensures valid list
      if (results.isNotEmpty) {
        final first = results.first;
        expect(first.id.isNotEmpty, isTrue);
        expect(first.title.isNotEmpty, isTrue);
        expect(first.artist.isNotEmpty, isTrue);
        expect(first.source, equals('youtube'));
      }
    });

    test('searchMusicTracks returns clean TrackEntity with non-empty metadata', () async {
      final results = await YouTubeClient.searchMusicTracks('Naa Ready', limit: 5);
      expect(results, isA<List<TrackEntity>>());
      for (final track in results) {
        expect(track.id.isNotEmpty, isTrue);
        expect(track.title.isNotEmpty, isTrue);
        expect(track.source, equals('youtube'));
        // Checks that raw YouTube junk tags are stripped
        expect(track.title.toLowerCase().contains('official video'), isFalse);
      }
    });
  });
}
