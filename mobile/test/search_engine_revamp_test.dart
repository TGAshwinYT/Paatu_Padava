import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/queue_cooldown_manager.dart';
import 'package:paatu_padava_mobile/services/artist_sanitizer.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';

Song createTestSong({
  required String id,
  required String title,
  required String artist,
  String album = 'Test Album',
  String coverUrl = 'https://c.saavncdn.com/test.jpg',
  int duration = 210,
  String source = 'saavn',
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    coverUrl: coverUrl,
    duration: duration,
    source: source,
  );
}

void main() {
  group('Cross-Artist Same Song Deduplication & cleanTitleKey', () {
    test('Generates identical cleanTitleKey for same song with different artist or bracketed tags', () {
      final s1 = createTestSong(
        id: '1',
        title: 'Naa Ready (From "Leo")',
        artist: 'Anirudh Ravichander',
        album: 'Leo',
      );
      final s2 = createTestSong(
        id: '2',
        title: 'Naa Ready',
        artist: 'Thalapathy Vijay',
        album: 'Leo',
      );
      final s3 = createTestSong(
        id: '3',
        title: 'Naa Ready - Lyric Video',
        artist: 'Sony Music South',
        album: 'Leo',
      );
      final s4 = createTestSong(
        id: '4',
        title: 'Naa Ready [Leo]',
        artist: 'Anirudh & Vijay',
        album: 'Leo',
      );

      expect(s1.cleanTitleKey, equals('naa ready'));
      expect(s2.cleanTitleKey, equals('naa ready'));
      expect(s3.cleanTitleKey, equals('naa ready'));
      expect(s4.cleanTitleKey, equals('naa ready'));
    });

    test('deduplicateSongs removes duplicates even when artists differ', () {
      final s1 = createTestSong(
        id: 'saavn_1',
        title: 'Hukum - Thalaivar Alappara (From "Jailer")',
        artist: 'Anirudh Ravichander',
        album: 'Jailer',
        coverUrl: 'https://c.saavncdn.com/jailer.jpg',
        duration: 215,
        source: 'saavn',
      );
      final s2 = createTestSong(
        id: 'yt_1',
        title: 'Hukum - Thalaivar Alappara | Rajinikanth | Anirudh Ravichander',
        artist: 'Sun TV',
        album: 'Jailer',
        coverUrl: 'https://i.ytimg.com/vi/123/hqdefault.jpg',
        duration: 215,
        source: 'youtube',
      );

      final deduped = SongRepository.deduplicateSongs([s1, s2]);
      expect(deduped.length, equals(1));
      expect(deduped.first.id, equals('saavn_1'));
    });

    test('canonicalSongKey prevents different movies songs with generic titles from collapsing', () {
      final themeLeo = createTestSong(
        id: '1',
        title: 'Theme Song',
        artist: 'Anirudh',
        album: 'Leo',
        duration: 120,
      );
      final themeJailer = createTestSong(
        id: '2',
        title: 'Theme Song',
        artist: 'Anirudh',
        album: 'Jailer',
        duration: 180,
      );

      expect(themeLeo.canonicalSongKey, isNot(equals(themeJailer.canonicalSongKey)));
    });
  });

  group('Rolling 75-Song Cooldown Buffer (QueueCooldownManager)', () {
    setUp(() {
      QueueCooldownManager.clear();
    });

    test('Maintains up to 75 songs in cooldown and evicts oldest when capacity is exceeded', () {
      expect(QueueCooldownManager.activeCooldownCount, equals(0));

      final songs = List.generate(
        80,
        (i) => createTestSong(
          id: 'song_$i',
          title: 'Unique Track Title $i',
          artist: 'Artist $i',
        ),
      );

      // Add first 75 songs
      for (var i = 0; i < 75; i++) {
        QueueCooldownManager.recordPlayed(songs[i]);
      }

      expect(QueueCooldownManager.activeCooldownCount, equals(75));
      expect(QueueCooldownManager.isCoolingDown(songs[0]), isTrue);
      expect(QueueCooldownManager.isCoolingDown(songs[74]), isTrue);

      // Add 76th song (should evict song 0)
      QueueCooldownManager.recordPlayed(songs[75]);
      expect(QueueCooldownManager.activeCooldownCount, equals(75));
      expect(QueueCooldownManager.isCoolingDown(songs[0]), isFalse);
      expect(QueueCooldownManager.isCoolingDown(songs[75]), isTrue);

      // Add 77th song (should evict song 1)
      QueueCooldownManager.recordPlayed(songs[76]);
      expect(QueueCooldownManager.isCoolingDown(songs[1]), isFalse);
      expect(QueueCooldownManager.isCoolingDown(songs[76]), isTrue);
    });

    test('isCoolingDown recognizes same song even with different artist tag', () {
      final playedTrack = createTestSong(
        id: 'played_1',
        title: 'Chaleya (From "Jawan")',
        artist: 'Arijit Singh',
      );
      QueueCooldownManager.recordPlayed(playedTrack);

      final candidateTrack = createTestSong(
        id: 'candidate_1',
        title: 'Chaleya',
        artist: 'Anirudh Ravichander & Shilpa Rao',
      );

      expect(QueueCooldownManager.isCoolingDown(candidateTrack), isTrue);
    });

    test('clear() resets all cooldown history', () {
      final s = createTestSong(id: '1', title: 'Test', artist: 'Artist');
      QueueCooldownManager.recordPlayed(s);
      expect(QueueCooldownManager.isCoolingDown(s), isTrue);

      QueueCooldownManager.clear();
      expect(QueueCooldownManager.activeCooldownCount, equals(0));
      expect(QueueCooldownManager.isCoolingDown(s), isFalse);
    });
  });

  group('Single-Song Album Filtering (SearchService.filterGenuineAlbums)', () {
    test('Excludes single-song albums and items with "single" in title', () {
      final rawAlbums = [
        {
          'id': 'alb_1',
          'title': 'Leo (Original Motion Picture Soundtrack)',
          'song_count': '7',
          'year': '2023',
        },
        {
          'id': 'alb_2',
          'title': 'Bloody Sweet (From "Leo") - Single',
          'song_count': '1',
          'year': '2023',
        },
        {
          'id': 'alb_3',
          'title': 'Badass Single',
          'song_count': '2',
          'year': '2023',
        },
        {
          'id': 'alb_4',
          'title': 'Jailer',
          'song_count': '8',
          'year': '2023',
        },
      ];

      final filtered = SearchService.filterGenuineAlbums(rawAlbums);
      expect(filtered.length, equals(2));
      expect(filtered[0]['id'], equals('alb_1'));
      expect(filtered[0]['type'], equals('Album'));
      expect(filtered[1]['id'], equals('alb_4'));
      expect(filtered[1]['type'], equals('Album'));
    });
  });

  group('Artist Sanitizer (ArtistSanitizer)', () {
    test('Rejects record labels, VEVO channels, and media houses', () {
      expect(ArtistSanitizer.isGenuineArtist('Sony Music South'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('T-Series Tamil'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('Saregama Tamil'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('Think Music India'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('Aditya Music'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('Lahari Music'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('Zee Music South'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('AnirudhVEVO'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('Anirudh - Topic'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('Sony Music India'), isFalse);
    });

    test('Rejects non-musician actors', () {
      expect(ArtistSanitizer.isGenuineArtist('Rajinikanth'), isFalse);
      expect(ArtistSanitizer.isGenuineArtist('Thalapathy Vijay'), isFalse);
    });

    test('Approves genuine musicians and singers', () {
      expect(ArtistSanitizer.isGenuineArtist('Anirudh Ravichander'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('A.R. Rahman'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Yuvan Shankar Raja'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Sid Sriram'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Shreya Ghoshal'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Ilaiyaraaja'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('S. P. Balasubrahmanyam'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Harris Jayaraj'), isTrue);
    });

    test('extractArtistFromVideo extracts genuine musician from YouTube video title', () {
      final parsed1 = ArtistSanitizer.extractArtistFromVideo(
        'Naa Ready - Lyric Video | Leo | Thalapathy Vijay | Anirudh Ravichander',
        'Sony Music South',
      );
      expect(parsed1, equals('Anirudh Ravichander'));

      final parsed2 = ArtistSanitizer.extractArtistFromVideo(
        'Hukum - Thalaivar Alappara | Jailer | Rajinikanth | Anirudh Ravichander',
        'Sun TV',
      );
      expect(parsed2, equals('Anirudh Ravichander'));
    });
  });

  group('Album Cover Integrity (SongRepository.ensureDistinctCovers)', () {
    test('Preserves authentic album art and never replaces covers of songs from same album', () {
      const leoCover = 'https://c.saavncdn.com/leo_soundtrack_500x500.jpg';
      final songs = [
        createTestSong(id: '1', title: 'Bloody Sweet', artist: 'Anirudh', album: 'Leo', coverUrl: leoCover),
        createTestSong(id: '2', title: 'Naa Ready', artist: 'Anirudh & Vijay', album: 'Leo', coverUrl: leoCover),
        createTestSong(id: '3', title: 'Badass', artist: 'Anirudh', album: 'Leo', coverUrl: leoCover),
        createTestSong(id: '4', title: 'Ordinary Person', artist: 'Anirudh', album: 'Leo', coverUrl: leoCover),
      ];

      final distinct = SongRepository.ensureDistinctCovers(songs);
      expect(distinct.length, equals(4));
      for (final s in distinct) {
        expect(s.coverUrl, equals(leoCover));
      }
    });

    test('Upgrades insecure HTTP cover URLs to HTTPS', () {
      final songs = [
        createTestSong(id: '1', title: 'Song 1', artist: 'Artist', coverUrl: 'http://c.saavncdn.com/test.jpg'),
      ];

      final distinct = SongRepository.ensureDistinctCovers(songs);
      expect(distinct.first.coverUrl, startsWith('https://'));
    });
  });

  group('Phonetic Query Expansion (SearchService.expandPhoneticQuery)', () {
    test('Expands common South Indian phonetic spellings and Tanglish phrases', () {
      expect(SearchService.expandPhoneticQuery('aniruth'), equals('anirudh'));
      expect(SearchService.expandPhoneticQuery('ar rehman'), equals('ar rahman'));
      expect(SearchService.expandPhoneticQuery('vathi coming'), equals('Vaathi Coming'));
      expect(SearchService.expandPhoneticQuery('rowdy bby'), equals('Rowdy Baby'));
      expect(SearchService.expandPhoneticQuery('arabik kuthu'), equals('Arabic Kuthu'));
      expect(SearchService.expandPhoneticQuery('pudhumazha'), equals('Puthu Mazha'));
    });
  });

  group('Search Cache LRU In-Memory Store (SearchCache)', () {
    setUp(() {
      SearchCache.clear();
    });

    test('Caches and retrieves unified search results instantly', () {
      final testResult = SearchResults(
        topResult: {'title': 'Anirudh Ravichander', 'type': 'Artist'},
        songs: [createTestSong(id: '1', title: 'Hukum', artist: 'Anirudh')],
      );

      expect(SearchCache.get('anirudh_tamil'), isNull);
      SearchCache.put('anirudh_tamil', testResult);

      final cached = SearchCache.get('anirudh_tamil');
      expect(cached, isNotNull);
      expect(cached!.songs.first.title, equals('Hukum'));
    });

    test('Evicts oldest entries when capacity exceeds maxEntries (60)', () {
      for (var i = 0; i < 65; i++) {
        SearchCache.put(
          'query_$i',
          SearchResults(
            songs: [createTestSong(id: '$i', title: 'Title $i', artist: 'Artist')],
          ),
        );
      }

      // First 5 should have been evicted
      expect(SearchCache.get('query_0'), isNull);
      expect(SearchCache.get('query_4'), isNull);
      // Items 5-64 should be present
      expect(SearchCache.get('query_5'), isNotNull);
      expect(SearchCache.get('query_64'), isNotNull);
    });
  });
}
