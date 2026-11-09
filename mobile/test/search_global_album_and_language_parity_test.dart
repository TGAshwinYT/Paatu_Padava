import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';
import 'package:paatu_padava_mobile/services/user_preference_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Global Album & Playlist Extraction (Fix for Missing Albums on "Hi")', () {
    test('extractAlbumsFromSongList extracts clean movie album from single with (From "Movie")', () {
      final pachaPulla = Song(
        id: 's_pacha',
        title: 'Pacha Pulla (From "Hi")',
        artist: 'Jen Martin, Sathyan',
        album: 'Pacha Pulla (From "Hi") - Single',
        coverUrl: 'https://example.com/pacha.jpg',
        duration: 210,
        source: 'saavn',
        language: 'tamil',
      );

      final odiyamma = Song(
        id: 's_odi',
        title: 'Odiyamma',
        artist: 'Dhruv Vikram, Shruti Haasan',
        album: 'Hi Nanna',
        coverUrl: 'https://example.com/odi.jpg',
        duration: 230,
        source: 'saavn',
        language: 'telugu',
      );

      final extracted = SearchService.extractAlbumsFromSongList(
        [pachaPulla, odiyamma],
        query: 'Hi',
        preferredLanguages: ['tamil'],
      );

      expect(extracted.isNotEmpty, isTrue);
      final titles = extracted.map((a) => a['title']).toList();
      expect(titles, contains('Hi'));
      expect(titles, contains('Hi Nanna'));

      // Check album metadata integrity
      final hiAlbum = extracted.firstWhere((a) => a['title'] == 'Hi');
      expect(hiAlbum['type'], equals('Album'));
      expect(hiAlbum['is_movie'], isTrue);
      expect(hiAlbum['artist'], equals('Jen Martin, Sathyan'));
      expect(hiAlbum['image'], equals('https://example.com/pacha.jpg'));
    });

    test('ensurePopulatedPlaylists generates rich playlists from query and albums when provider playlists are empty', () {
      final dummySongs = [
        Song(
          id: 's_pacha',
          title: 'Pacha Pulla',
          artist: 'Jen Martin',
          album: 'Hi',
          coverUrl: 'https://example.com/pacha.jpg',
          duration: 210,
          source: 'saavn',
        ),
      ];

      final dummyAlbums = [
        {
          'id': 'hi_album',
          'title': 'Hi',
          'artist': 'Jen Martin',
          'image': 'https://example.com/pacha.jpg',
          'type': 'Album',
        },
        {
          'id': 'hi_nanna_album',
          'title': 'Hi Nanna',
          'artist': 'Hesham Abdul Wahab',
          'image': 'https://example.com/odi.jpg',
          'type': 'Album',
        },
      ];

      final playlists = SearchService.ensurePopulatedPlaylists(
        [],
        dummySongs,
        dummyAlbums,
        'Hi',
        preferredLanguages: ['tamil'],
      );

      expect(playlists.isNotEmpty, isTrue);
      final titles = playlists.map((p) => p['title']).toList();
      expect(titles, contains('Hi Hits'));
      expect(titles, contains('Hi Soundtracks'));
      expect(titles, contains('Hi Nanna Soundtracks'));
    });
  });

  group('Multi-Language Parity & Language Priority (Fix for "Hi Nanna" Telugu Flood)', () {
    test('Tamil user searching "Hi Nanna" scores Tamil track higher than Telugu track', () {
      final intent = SearchService.understandQuery('hi nanna');

      final tamilTrack = Song(
        id: 's_tamil',
        title: 'Nee Mayavan (From "Hi Nanna")',
        artist: 'Hesham Abdul Wahab',
        album: 'Hi Nanna (Tamil)',
        coverUrl: 'https://example.com/hinanna_ta.jpg',
        duration: 250,
        source: 'saavn',
        language: 'tamil',
      );

      final teluguTrack = Song(
        id: 's_telugu',
        title: 'Gaaju Bomma (From "Hi Nanna")',
        artist: 'Hesham Abdul Wahab',
        album: 'Hi Nanna',
        coverUrl: 'https://example.com/hinanna_te.jpg',
        duration: 250,
        source: 'saavn',
        language: 'telugu',
      );

      final tamilScore = SearchService.calculateCompositeRelevance(
        tamilTrack,
        intent,
        preferredLanguages: ['tamil'],
      );

      final teluguScore = SearchService.calculateCompositeRelevance(
        teluguTrack,
        intent,
        preferredLanguages: ['tamil'],
      );

      // Tamil track must score 1.0; non-preferred Telugu track must score 0.85
      expect(tamilScore, equals(1.0));
      expect(teluguScore, equals(0.85));
      expect(tamilScore > teluguScore, isTrue);
    });

    test('groupCanonicalSongs promotes user preferred language as primary canonical track', () {
      final tamilTrack = Song(
        id: 's_tamil',
        title: 'Gaaju Bomma',
        artist: 'Hesham Abdul Wahab',
        album: 'Hi Nanna',
        coverUrl: 'https://example.com/hinanna_ta.jpg',
        duration: 250,
        source: 'saavn',
        language: 'tamil',
      );

      final teluguTrack = Song(
        id: 's_telugu',
        title: 'Gaaju Bomma',
        artist: 'Hesham Abdul Wahab',
        album: 'Hi Nanna',
        coverUrl: 'https://example.com/hinanna_te.jpg',
        duration: 250,
        source: 'saavn',
        language: 'telugu',
      );

      // Pass preferredLanguages: ['tamil']
      final grouped = SongRepository.groupCanonicalSongs(
        [teluguTrack, tamilTrack],
        preferredLanguages: ['tamil'],
      );

      expect(grouped.length, equals(1));
      // The Tamil track must be the primary canonical entry!
      expect(grouped.first.language, equals('tamil'));
      expect(grouped.first.versions.length, equals(1));
      expect(grouped.first.versions.first.language, equals('telugu'));
    });

    test('filterGenuineAlbums sorts regional preferred language album ahead of other languages', () {
      final rawAlbums = [
        {
          'id': '101',
          'title': 'Hi Nanna - Telugu',
          'song_count': '6',
          'language': 'telugu',
        },
        {
          'id': '102',
          'title': 'Hi Nanna - Tamil',
          'song_count': '1',
          'language': 'tamil',
        },
      ];

      final filtered = SearchService.filterGenuineAlbums(
        rawAlbums,
        query: 'Hi Nanna',
        preferredLanguages: ['tamil'],
      );

      expect(filtered.length, equals(2));
      expect(filtered.first['title'], equals('Hi Nanna - Tamil'));
      expect(filtered.last['title'], equals('Hi Nanna - Telugu'));
    });

    test('UserPreferenceMatrix breaks ties in favor of user preferred language', () {
      final tamilTrack = Song(
        id: 's_tamil_2',
        title: 'Hi Nanna Theme',
        artist: 'Hesham Abdul Wahab',
        album: 'Hi Nanna',
        coverUrl: 'https://example.com/cover.jpg',
        duration: 180,
        source: 'saavn',
        language: 'tamil',
      );

      final teluguTrack = Song(
        id: 's_telugu_2',
        title: 'Hi Nanna Theme',
        artist: 'Hesham Abdul Wahab',
        album: 'Hi Nanna',
        coverUrl: 'https://example.com/cover.jpg',
        duration: 180,
        source: 'saavn',
        language: 'telugu',
      );

      final reRanked = UserPreferenceMatrix.reRankWithPreferences(
        [teluguTrack, tamilTrack],
        'Hi Nanna',
        preferredLanguages: ['tamil'],
      );

      expect(reRanked.first.language, equals('tamil'));
    });
  });

  group('English & Cross-Language Artist Discovery & Soft Language Boosting', () {
    test('filterArtistsByLanguage preserves English artists like Taylor Swift and Ed Sheeran when language is null', () {
      final candidates = [
        {'id': 'art_taylor', 'name': 'Taylor Swift', 'role': 'Artist', 'image': 'https://example.com/taylor.jpg'},
        {'id': 'art_ed', 'name': 'Ed Sheeran', 'role': 'Artist', 'image': 'https://example.com/ed.jpg'},
        {'id': 'art_anirudh', 'name': 'Anirudh Ravichander', 'role': 'Music Director', 'image': 'https://example.com/anirudh.jpg'},
      ];

      final filtered = SearchService.filterArtistsByLanguage(
        candidates,
        language: null,
        query: 'Taylor Swift',
      );

      final names = filtered.map((a) => a['name']).toList();
      expect(names, contains('Taylor Swift'));
      expect(names, contains('Ed Sheeran'));
      expect(names, contains('Anirudh Ravichander'));
    });

    test('calculateCompositeRelevance gives soft boost to preferred language without dropping English songs', () {
      final intent = SearchService.understandQuery('shape of you');
      final edSong = Song(
        id: 's_ed_1',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        album: 'Divide',
        coverUrl: 'https://example.com/divide.jpg',
        duration: 233,
        source: 'saavn',
        language: 'english',
      );

      final scoreWithoutPref = SearchService.calculateCompositeRelevance(
        edSong,
        intent,
        preferredLanguages: [],
      );

      final scoreWithTamilPref = SearchService.calculateCompositeRelevance(
        edSong,
        intent,
        preferredLanguages: ['tamil'],
      );

      // Should have a high score (exact title match >= 0.75) and NOT be zeroed out
      expect(scoreWithoutPref, greaterThanOrEqualTo(0.75));
      expect(scoreWithTamilPref, greaterThanOrEqualTo(0.75));
    });

    test('Artist discography does not scramble or penalize tracks when artist does not sing in user preferred language', () {
      final s1 = Song(id: '1', title: 'Shape of You', artist: 'Ed Sheeran', coverUrl: 'https://example.com/1.jpg', duration: 233, source: 'saavn', language: 'english');
      final s2 = Song(id: '2', title: 'Perfect', artist: 'Ed Sheeran', coverUrl: 'https://example.com/2.jpg', duration: 263, source: 'saavn', language: 'english');
      final s3 = Song(id: '3', title: 'Bad Habits', artist: 'Ed Sheeran', coverUrl: 'https://example.com/3.jpg', duration: 231, source: 'saavn', language: 'english');

      final songs = [s1, s2, s3];
      final effectivePrefLangs = ['tamil'];
      final hasPreferredSongs = effectivePrefLangs.isNotEmpty &&
          songs.any((s) => effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(s, l)));

      expect(hasPreferredSongs, isFalse);
      // Because hasPreferredSongs is false, list remains in original hit order
      if (hasPreferredSongs) {
        songs.sort((a, b) {
          final aIsMismatch = !effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(a, l));
          final bIsMismatch = !effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(b, l));
          if (!aIsMismatch && bIsMismatch) return -1;
          if (aIsMismatch && !bIsMismatch) return 1;
          return 0;
        });
      }
      expect(songs.map((s) => s.title).toList(), equals(['Shape of You', 'Perfect', 'Bad Habits']));
    });
  });
}
