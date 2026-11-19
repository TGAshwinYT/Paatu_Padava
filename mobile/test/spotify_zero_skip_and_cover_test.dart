import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/spotify_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Spotify Zero-Skip & Label Recognition Tests', () {
    test('Official label channel on YouTube receives full credit and is not disqualified', () {
      const target = SpotifyTrackItem(
        title: 'Naa Ready',
        artist: 'Anirudh Ravichander, Thalapathy Vijay',
        album: 'Leo',
        durationSeconds: 195, // 3m 15s
      );

      // YouTube official video uploaded by Sony Music South, 4m 10s (250s, +55s intro/outro)
      final candidate = Song(
        id: 'dQw4w9WgXcQ',
        title: 'Naa Ready - Official Video | Leo | Thalapathy Vijay | Anirudh Ravichander',
        artist: 'Sony Music South',
        album: 'Leo',
        coverUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: 250,
        source: 'youtube',
      );

      final score = SpotifyImportService.scoreCandidate(
        target: target,
        candidate: candidate,
      );

      // Must NOT be disqualified (-100); score should be >= 60
      expect(score, greaterThanOrEqualTo(60),
          reason: 'Official label channel (Sony Music South) with video intro should match');
    });

    test('Zero-Skip engine imports 100% of tracks without any skips', () async {
      final mockMeta = SpotifyPlaylistMetadata(
        title: 'Test Zero Skip Playlist',
        totalTracks: 3,
        tracks: [
          const SpotifyTrackItem(
            title: 'Track One',
            artist: 'Artist One',
            durationSeconds: 200,
          ),
          const SpotifyTrackItem(
            title: 'Track Two',
            artist: 'Artist Two',
            durationSeconds: 180,
          ),
          const SpotifyTrackItem(
            title: 'Obscure Unknown Track',
            artist: 'Obscure Indie Artist',
            durationSeconds: 210,
          ),
        ],
      );

      int progressEmits = 0;
      final result = await SpotifyImportService.importPlaylistWithProgress(
        metadata: mockMeta,
        onProgress: (current, total, progress, status, matched) {
          progressEmits++;
        },
      );

      expect(result.totalTracks, equals(3));
      expect(result.importedSongs.length, equals(3));
      expect(result.skippedTracks.isEmpty, isTrue, reason: 'Zero tracks should be skipped');
      expect(progressEmits, greaterThan(0));
    });
  });

  group('Offline Cover Art Preservation Tests', () {
    test('TrackEntity.toMediaItem stores remote coverUrl in extras and fromMediaItem preserves it', () {
      final song = Song(
        id: 'song_123',
        title: 'Innum Konjam Neram',
        artist: 'A.R. Rahman, Vijay Prakash, Shweta Mohan',
        album: 'Maryan',
        coverUrl: 'https://c.saavncdn.com/123/Maryan-500x500.jpg',
        localCoverPath: '/data/user/0/com.paatupaadava.music/app_flutter/offline_covers/song_123.jpg',
        isDownloaded: true,
        source: 'offline',
      );

      final mediaItem = song.toMediaItem();
      expect(mediaItem.extras?['coverUrl'], equals('https://c.saavncdn.com/123/Maryan-500x500.jpg'));

      // Converting back to TrackEntity must preserve the remote coverUrl!
      final restored = Song.fromMediaItem(mediaItem);
      expect(restored.coverUrl, equals('https://c.saavncdn.com/123/Maryan-500x500.jpg'),
          reason: 'Remote coverUrl must be preserved even when localCoverPath is set');
      expect(restored.localCoverPath, equals('/data/user/0/com.paatupaadava.music/app_flutter/offline_covers/song_123.jpg'));
    });
  });
}
