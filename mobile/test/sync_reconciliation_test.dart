import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/playlist_manager.dart';
import 'package:paatu_padava_mobile/services/sync_manager.dart';

void main() {
  group('TrackEntity & Sanitation Tests', () {
    test('deduplicationKey normalizes title and artist across casing and whitespace', () {
      final entity1 = TrackEntity(
        id: '1',
        title: '  Vennilave Vennilave  ',
        artist: 'Hariharan, Sadhana Sargam',
        coverUrl: 'https://example.com/cover1.jpg',
        source: 'saavn',
      );

      final entity2 = TrackEntity(
        id: '2',
        title: 'vennilave vennilave',
        artist: '  HARIHARAN, SADHANA SARGAM  ',
        coverUrl: 'https://example.com/cover2.jpg',
        source: 'youtube',
      );

      expect(entity1.deduplicationKey, equals(entity2.deduplicationKey));
      expect(entity1.deduplicationKey, equals('vennilave vennilave_hariharan, sadhana sargam'));
    });

    test('deduplicationKey distinguishes different tracks', () {
      final entity1 = TrackEntity(
        id: '1',
        title: 'Kandukondain Kandukondain',
        artist: 'A.R. Rahman',
        coverUrl: 'https://example.com/cover1.jpg',
        source: 'saavn',
      );

      final entity2 = TrackEntity(
        id: '2',
        title: 'Enna Solla Pogirai',
        artist: 'A.R. Rahman',
        coverUrl: 'https://example.com/cover2.jpg',
        source: 'saavn',
      );

      expect(entity1.deduplicationKey, isNot(equals(entity2.deduplicationKey)));
    });

    test('sanitize unescapes HTML entities properly', () {
      expect(
        TrackEntity.sanitize('Rock &amp; Roll &#039;N&#039; &quot;Tamil&quot;'),
        equals('Rock & Roll \'N\' "Tamil"'),
      );
    });

    test('sanitize returns fallback for null or empty string', () {
      expect(TrackEntity.sanitize(null, fallback: 'Fallback Title'), equals('Fallback Title'));
      expect(TrackEntity.sanitize('   ', fallback: 'Fallback Title'), equals('Fallback Title'));
    });
  });

  group('Sync Reconciliation & UserPlaylist Serialization', () {
    test('UserPlaylist serialization round-trip maintains integrity', () {
      final song = Song(
        id: 's_001',
        title: 'Aalaporan Thamizhan',
        artist: 'A.R. Rahman, Kailash Kher',
        album: 'Mersal',
        duration: 348,
        coverUrl: 'https://example.com/mersal.jpg',
        streamUrl: 'https://example.com/stream.mp4',
        source: 'saavn',
      );

      final playlist = UserPlaylist(
        id: 'pl_001',
        title: 'AR Rahman Hits',
        createdAt: 1700000000000,
        tracks: [song],
      );

      final map = playlist.toMap();
      expect(map['id'], equals('pl_001'));
      expect(map['title'], equals('AR Rahman Hits'));
      expect((map['tracks'] as List).length, equals(1));

      final restored = UserPlaylist.fromMap(map);
      expect(restored.id, equals(playlist.id));
      expect(restored.title, equals(playlist.title));
      expect(restored.createdAt, equals(playlist.createdAt));
      expect(restored.tracks.length, equals(1));
      expect(restored.tracks.first.id, equals('s_001'));
      expect(restored.coverUrl, equals('https://example.com/mersal.jpg'));
    });

    test('SyncStatusNotifier correctly updates and exposes states', () {
      SyncManager.syncStatusNotifier.value = SyncStatus.idle;
      expect(SyncManager.status, equals(SyncStatus.idle));

      SyncManager.syncStatusNotifier.value = SyncStatus.syncing;
      expect(SyncManager.status, equals(SyncStatus.syncing));

      SyncManager.syncStatusNotifier.value = SyncStatus.synced;
      expect(SyncManager.status, equals(SyncStatus.synced));

      SyncManager.syncStatusNotifier.value = SyncStatus.offline;
      expect(SyncManager.status, equals(SyncStatus.offline));

      SyncManager.syncStatusNotifier.value = SyncStatus.error;
      expect(SyncManager.status, equals(SyncStatus.error));
    });
  });
}
