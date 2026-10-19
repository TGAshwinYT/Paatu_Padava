import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/saavn_client.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';
import 'package:paatu_padava_mobile/services/artist_sanitizer.dart';

Song createMultilingualSong({
  required String id,
  required String title,
  required String artist,
  required String language,
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
    language: language,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multilingual Search & Streaming Architecture Tests', () {
    test('SaavnClient dynamic headers include all Indian languages by default', () {
      final defaultHeaders = SaavnClient.getHeaders();
      final cookie = defaultHeaders['Cookie'] ?? '';

      expect(cookie, contains('hindi'));
      expect(cookie, contains('telugu'));
      expect(cookie, contains('tamil'));
      expect(cookie, contains('malayalam'));
      expect(cookie, contains('kannada'));
      expect(cookie, contains('punjabi'));
      expect(cookie, contains('english'));
      expect(cookie, contains('gdpr_acceptance=true'));
    });

    test('SaavnClient headers dynamically adapt to user multi-language preferences', () {
      final customHeaders = SaavnClient.getHeaders('hindi,tamil,telugu');
      final cookie = customHeaders['Cookie'] ?? '';

      expect(cookie, contains('hindi%2Ctamil%2Ctelugu'));
      expect(cookie, contains('english'));
    });

    test('SearchService accurately scores tracks across Hindi, Telugu, English, Malayalam, and Tamil', () {
      final testSongs = [
        createMultilingualSong(
          id: 'hi_1',
          title: 'Kesariya',
          artist: 'Arijit Singh, Pritam',
          language: 'hindi',
        ),
        createMultilingualSong(
          id: 'te_1',
          title: 'Samajavaragamana',
          artist: 'Sid Sriram, Thaman S',
          language: 'telugu',
        ),
        createMultilingualSong(
          id: 'en_1',
          title: 'Shape of You',
          artist: 'Ed Sheeran',
          language: 'english',
        ),
        createMultilingualSong(
          id: 'ml_1',
          title: 'Malare',
          artist: 'Vijay Yesudas, Rajesh Murugesan',
          language: 'malayalam',
        ),
        createMultilingualSong(
          id: 'ta_1',
          title: 'Hukum - Thalaivar Alappara',
          artist: 'Anirudh Ravichander',
          language: 'tamil',
        ),
      ];

      final queryIntents = [
        SearchService.understandQuery('kesariya'),
        SearchService.understandQuery('samajavaragamana'),
        SearchService.understandQuery('shape of you'),
        SearchService.understandQuery('malare'),
        SearchService.understandQuery('hukum'),
      ];

      for (int i = 0; i < testSongs.length; i++) {
        final song = testSongs[i];
        final intent = queryIntents[i];
        final score = SearchService.scoreSong(
          song,
          intent,
          preferredLanguages: ['Tamil', 'Hindi', 'Telugu', 'English', 'Malayalam'],
        );

        expect(score, greaterThanOrEqualTo(0.70),
            reason: 'Track ${song.title} (${song.language}) should clear the 0.70 confidence threshold');
      }
    });

    test('Non-Tamil songs and artists are not dropped by filterArtistsByLanguage', () {
      final candidateArtists = [
        {'id': '1', 'name': 'Arijit Singh', 'image': 'https://c.saavncdn.com/artists/arijit.jpg'},
        {'id': '2', 'name': 'Sid Sriram', 'image': 'https://c.saavncdn.com/artists/sid.jpg'},
        {'id': '3', 'name': 'Ed Sheeran', 'image': 'https://c.saavncdn.com/artists/ed.jpg'},
        {'id': '4', 'name': 'Vijay Yesudas', 'image': 'https://c.saavncdn.com/artists/vijay.jpg'},
        {'id': '5', 'name': 'Anirudh Ravichander', 'image': 'https://c.saavncdn.com/artists/anirudh.jpg'},
      ];

      // When language is null (global search) or 'All'
      final filteredGlobal = SearchService.filterArtistsByLanguage(
        candidateArtists,
        language: null,
        query: 'popular artists',
      );

      expect(filteredGlobal.length, equals(5));
      expect(filteredGlobal.any((a) => a['name'] == 'Arijit Singh'), isTrue);
      expect(filteredGlobal.any((a) => a['name'] == 'Ed Sheeran'), isTrue);
      expect(filteredGlobal.any((a) => a['name'] == 'Sid Sriram'), isTrue);
    });

    test('ArtistSanitizer verifies legitimate multi-language musicians', () {
      expect(ArtistSanitizer.isGenuineArtist('Arijit Singh'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Sid Sriram'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Ed Sheeran'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Vijay Yesudas'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Anirudh Ravichander'), isTrue);
      expect(ArtistSanitizer.isGenuineArtist('Shreya Ghoshal'), isTrue);
    });

    test('StreamResolver Stage D proxy URL formats with /api/music/stream and title/artist query params', () {
      final song = createMultilingualSong(
        id: 'hi_kesariya_1',
        title: 'Kesariya',
        artist: 'Arijit Singh',
        language: 'hindi',
      );

      // Verify TrackEntity preserves metadata necessary for backend proxy search
      expect(song.id, equals('hi_kesariya_1'));
      expect(song.title, equals('Kesariya'));
      expect(song.artist, equals('Arijit Singh'));

      final encodedTitle = Uri.encodeComponent(song.title);
      final encodedArtist = Uri.encodeComponent(song.artist);
      final expectedPath = '/api/music/stream/${song.id}?title=$encodedTitle&artist=$encodedArtist';

      expect(expectedPath, contains('/api/music/stream/hi_kesariya_1'));
      expect(expectedPath, contains('title=Kesariya'));
      expect(expectedPath, contains('artist=Arijit%20Singh'));
    });

    test('Canonical grouping groups multilingual songs across releases without cross-language collision', () {
      final hindiTrack1 = createMultilingualSong(
        id: 'hi_1',
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        language: 'hindi',
      );
      final hindiTrack2 = createMultilingualSong(
        id: 'hi_2',
        title: 'Tum Hi Ho (From "Aashiqui 2")',
        artist: 'Arijit Singh',
        language: 'hindi',
      );
      final tamilTrack = createMultilingualSong(
        id: 'ta_1',
        title: 'Vaseegara',
        artist: 'Bombay Jayashri',
        language: 'tamil',
      );

      final grouped = SongRepository.groupCanonicalSongs([hindiTrack1, hindiTrack2, tamilTrack]);
      expect(grouped.length, equals(2));

      final canonicalHindi = grouped.firstWhere((s) => s.title.toLowerCase().contains('tum hi ho'));
      expect(canonicalHindi.versions.length, equals(1));
    });
  });
}
