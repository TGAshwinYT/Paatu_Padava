import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/catalog_database.dart';
import 'package:paatu_padava_mobile/services/user_preference_matrix.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/artist_sanitizer.dart';

void main() {
  setUp(() async {
    await CatalogDatabase.init();
  });

  group('Curated Movie & Songs Master Catalog (Database) Tests', () {
    test('1. Database initializes with verified pre-seeded catalog', () {
      expect(CatalogDatabase.isInitialized, isTrue);
    });

    test('2. 0ms instant catalog search finds "Hukum" with clean metadata', () async {
      final songs = await CatalogDatabase.searchCatalog('Hukum');
      expect(songs, isNotEmpty);
      final hukum = songs.first;
      expect(hukum.title, contains('Hukum'));
      expect(hukum.album, equals('Jailer'));
      expect(hukum.artist, contains('Anirudh Ravichander'));
      expect(hukum.artist, contains('Super Subu'));
    });

    test('3. Role Isolation: Cast members (Rajinikanth, Vijay) are separated from Singers', () async {
      final songs = await CatalogDatabase.searchCatalog('Naa Ready');
      expect(songs, isNotEmpty);
      final song = songs.first;
      // In Naa Ready, Vijay actually sang the song, so he is included as singer
      expect(song.artist, contains('Vijay'));
      expect(song.artist, contains('Anirudh'));

      // In Hukum, Rajinikanth is Cast, not Singer
      final hukumSongs = await CatalogDatabase.searchCatalog('Hukum');
      final hukum = hukumSongs.first;
      expect(hukum.artist, isNot(contains('Rajinikanth')));
      expect(hukum.artist, contains('Anirudh Ravichander'));
    });

    test('4. Inverted Entity Graph: Searching "Hukum" returns real Artists (Anirudh, Super Subu)', () async {
      final artists = await CatalogDatabase.searchArtists('Hukum');
      expect(artists, isNotEmpty);
      final names = artists.map((a) => a['name'].toString().toLowerCase()).toList();
      expect(names.any((n) => n.contains('anirudh')), isTrue);
      expect(names.any((n) => n.contains('subu')), isTrue);
    });

    test('5. Inverted Entity Graph: Searching "Jailer" returns Movie, Composer and Singers', () async {
      final movies = await CatalogDatabase.searchMovies('Jailer');
      expect(movies, isNotEmpty);
      expect(movies.first['title'], equals('Jailer'));
      expect(movies.first['composer'], equals('Anirudh Ravichander'));
      expect(movies.first['starring'], contains('Rajinikanth'));

      final artists = await CatalogDatabase.searchArtists('Jailer');
      expect(artists, isNotEmpty);
      expect(artists.any((a) => a['name'].toString().toLowerCase().contains('anirudh')), isTrue);
    });

    test('6. Artist discography lookup returns all verified tracks for that musician', () async {
      final anirudhSongs = await CatalogDatabase.getSongsByArtist('Anirudh Ravichander');
      expect(anirudhSongs.length, greaterThanOrEqualTo(5));
      final titles = anirudhSongs.map((s) => s.title.toLowerCase()).toList();
      expect(titles.any((t) => t.contains('hukum')), isTrue);
      expect(titles.any((t) => t.contains('naa ready') || t.contains('badass')), isTrue);
      expect(titles.any((t) => t.contains('vaathi coming')), isTrue);
    });

    test('7. Write-Through Ingestion: New song released today is cached dynamically', () async {
      final newSongToday = Song(
        id: 'new_release_2026_single_001',
        title: 'Thuru Thuru Vizhigal',
        artist: 'Santhosh Narayanan, Pradeep Kumar',
        album: 'Indie New Wave',
        coverUrl: 'https://c.saavncdn.com/new_cover.jpg',
        duration: 215,
        source: 'saavn',
      );

      await CatalogDatabase.insertDynamicSong(
        newSongToday,
        composer: 'Santhosh Narayanan',
        singers: 'Pradeep Kumar',
      );

      final found = await CatalogDatabase.searchCatalog('Thuru Thuru');
      expect(found, isNotEmpty);
      expect(found.first.id, equals('new_release_2026_single_001'));
      expect(found.first.title, equals('Thuru Thuru Vizhigal'));
    });

    test('8. ArtistSanitizer extracts genuine artists and filters non-musicians', () {
      const mixed = 'Rajinikanth, Anirudh Ravichander, Super Subu';
      final genuine = ArtistSanitizer.extractAllGenuineArtists(mixed);
      expect(genuine, contains('Anirudh Ravichander'));
      expect(genuine, contains('Super Subu'));
      expect(genuine, isNot(contains('Rajinikanth')));
    });

    test('9. UserPreferenceMatrix re-ranks candidates prioritizing liked songs & loved artists', () {
      final songA = Song(
        id: 'song_a',
        title: 'Katchi Sera',
        artist: 'Sai Abhyankkar',
        coverUrl: '',
      );
      final songB = Song(
        id: 'song_b',
        title: 'Katchi Paattu',
        artist: 'Unknown Singer',
        coverUrl: '',
      );

      final liked = [songA];
      final ranked = UserPreferenceMatrix.reRankWithPreferences(
        [songB, songA],
        'Katchi',
        likedSongs: liked,
      );

      expect(ranked.first.id, equals('song_a'));
    });
  });
}
