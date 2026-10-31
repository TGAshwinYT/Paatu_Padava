import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/domain/models/clustered_track_result.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';

void main() {
  group('SearchService Clustering & Smart Crown Tests', () {
    test('clusterAndClassifySongs groups alternate versions under the official studio track', () {
      final officialSong = Song(
        id: 'saavn_1',
        title: 'Arabic Kuthu',
        artist: 'Anirudh Ravichander, Jonita Gandhi',
        album: 'Beast',
        duration: 280,
        source: 'saavn',
        coverUrl: 'https://example.com/art.jpg',
      );

      final lofiVersion = Song(
        id: 'yt_lofi_1',
        title: 'Arabic Kuthu - Slowed + Reverb (Lofi Chill)',
        artist: 'Anirudh Ravichander',
        album: 'Fan Beats',
        duration: 260,
        source: 'youtube',
        coverUrl: 'https://example.com/lofi.jpg',
      );

      final mashupVersion = Song(
        id: 'yt_mashup_1',
        title: 'Arabic Kuthu x Hukum Epic Mashup',
        artist: 'Anirudh Ravichander',
        album: 'DJ Mix',
        duration: 240,
        source: 'youtube',
        coverUrl: 'https://example.com/mashup.jpg',
      );

      final movieReviewJunk = Song(
        id: 'yt_junk_1',
        title: 'Beast Movie Public Review | Thalapathy Vijay',
        artist: 'Cinema Review Channel',
        album: 'Reviews',
        duration: 340,
        source: 'youtube',
        coverUrl: 'https://example.com/junk.jpg',
      );

      final results = SearchService.clusterAndClassifySongs(
        [movieReviewJunk, lofiVersion, officialSong, mashupVersion],
        query: 'Arabic Kuthu',
      );

      // Junk must be dropped immediately
      expect(results.any((c) => c.primaryTrack.id == 'yt_junk_1'), isFalse);

      // Must cluster into a single consolidated node
      expect(results.length, equals(1));
      final cluster = results.first;

      // Primary track must be the official studio track
      expect(cluster.primaryTrack.id, equals('saavn_1'));
      expect(cluster.category, equals(ContentClassification.officialTrack));

      // Alternate versions must include the fan mixes
      expect(cluster.alternateVersions.length, equals(2));
      expect(cluster.alternateVersions.any((s) => s.id == 'yt_lofi_1'), isTrue);
      expect(cluster.alternateVersions.any((s) => s.id == 'yt_mashup_1'), isTrue);
    });

    test('evaluateTopResult enforces confidence >= 0.85 threshold', () {
      final highConfidenceCluster = ClusteredTrackResult(
        primaryTrack: Song(
          id: 's1',
          title: 'Arabic Kuthu',
          artist: 'Anirudh Ravichander',
          coverUrl: '',
        ),
        category: ContentClassification.officialTrack,
        confidenceScore: 0.92,
      );

      final lowConfidenceCluster = ClusteredTrackResult(
        primaryTrack: Song(
          id: 's2',
          title: 'Unrelated Melody',
          artist: 'Different Artist',
          coverUrl: '',
        ),
        category: ContentClassification.officialTrack,
        confidenceScore: 0.65,
      );

      // High confidence passes
      final top1 = SearchService.evaluateTopResult(
        [highConfidenceCluster],
        query: 'Arabic Kuthu',
      );
      expect(top1, isNotNull);
      expect(top1!.primaryTrack.id, equals('s1'));

      // Low confidence is rejected to avoid showing misleading hero cards
      final top2 = SearchService.evaluateTopResult(
        [lowConfidenceCluster],
        query: 'Arabic Kuthu',
      );
      expect(top2, isNull);
    });

    test('Race condition generation IDs increment deterministically', () {
      final id1 = SearchService.nextGenerationId();
      final id2 = SearchService.nextGenerationId();
      expect(id2, equals(id1 + 1));
      expect(SearchService.currentGenerationId, equals(id2));
    });

    test('parseAlbumSummaries and parsePlaylistSummaries deduplicate and assign correct CollectionType', () {
      final rawAlbums = [
        {'id': 'a1', 'title': 'Leo', 'artist': 'Anirudh', 'image': 'https://a1.jpg', 'song_count': 7},
        {'id': 'a2', 'title': 'Leo', 'artist': 'Anirudh', 'image': 'https://a2.jpg', 'song_count': 7},
        {'id': 'a3', 'title': 'Master', 'artist': 'Anirudh', 'image': 'https://a3.jpg', 'song_count': 8},
      ];

      final albums = SearchService.parseAlbumSummaries(rawAlbums);
      expect(albums.length, equals(2)); // 'Leo' deduplicated
      expect(albums.first.type, equals(CollectionType.album));
      expect(albums.first.title, equals('Leo'));
      expect(albums.first.trackCount, equals(7));

      final rawPlaylists = [
        {'id': 'p1', 'title': 'Tamil Romance 2024', 'subtitle': 'Curated', 'image': 'https://p1.jpg'},
      ];

      final playlists = SearchService.parsePlaylistSummaries(rawPlaylists);
      expect(playlists.length, equals(1));
      expect(playlists.first.type, equals(CollectionType.playlist));
    });
  });
}
