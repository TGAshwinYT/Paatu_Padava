import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/logic/smart_shuffle_controller.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';

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
  group('Search Pipeline - Query Understanding & Script Detection', () {
    test('Detects native Tamil script correctly', () {
      final parsed = SearchService.understandQuery('மீசைய முறுக்கு');
      expect(parsed.detectedLanguage, equals('tamil'));
      expect(parsed.cleanQuery, equals('மீசைய முறுக்கு'));
    });

    test('Detects native Telugu, Malayalam, Kannada, Devanagari scripts', () {
      expect(SearchService.understandQuery('రాములో రాములా').detectedLanguage, equals('telugu'));
      expect(SearchService.understandQuery('പുതുമഴ').detectedLanguage, equals('malayalam'));
      expect(SearchService.understandQuery('ಬಾ ಬೆಳಕೆ').detectedLanguage, equals('kannada'));
      expect(SearchService.understandQuery('केसरिया तेरा').detectedLanguage, equals('hindi'));
    });

    test('Extracts explicit language in query as override and strips language word', () {
      final parsed = SearchService.understandQuery('Meesaya Murukku Tamil');
      expect(parsed.explicitLanguageOverride, equals('tamil'));
      expect(parsed.cleanQuery, equals('Meesaya Murukku'));
    });

    test('Transliterates real-world queries with typos: "Meesaya Murukku"', () {
      final typo1 = SearchService.understandQuery('mesaya muruku');
      expect(typo1.transliteratedQuery.toLowerCase(), equals('meesaya murukku'));
      expect(typo1.didYouMeanSuggestion?.toLowerCase(), equals('meesaya murukku'));

      final typo2 = SearchService.understandQuery('mesaya murukku');
      expect(typo2.transliteratedQuery.toLowerCase(), equals('meesaya murukku'));
    });

    test('Transliterates real-world queries: "Oorum Blood" and "Puthu Mazha"', () {
      final oorum = SearchService.understandQuery('oorum blood');
      expect(oorum.transliteratedQuery.toLowerCase(), equals('oorum blood'));

      final puthu = SearchService.understandQuery('puthu mazha');
      expect(puthu.transliteratedQuery.toLowerCase(), equals('puthu mazha'));
    });
  });

  group('Canonical Song Grouping & Version Tagging', () {
    test('Groups alternate versions and duplicate releases into one canonical song', () {
      final song1 = createTestSong(
        id: 's1',
        title: 'Meesaya Murukku (From "Meesaya Murukku")',
        artist: 'Hiphop Tamizha',
        album: 'Meesaya Murukku',
        duration: 210,
        coverUrl: 'https://c.saavncdn.com/official_album_500x500.jpg',
        source: 'saavn',
      );

      final song2 = createTestSong(
        id: 's2',
        title: 'Meesaya Murukku - Remix',
        artist: 'Hiphop Tamizha',
        album: 'Remix Hits',
        duration: 212, // within 3-second band
        coverUrl: 'https://i.ytimg.com/vi/thumb.jpg',
        source: 'youtube',
      );

      final song3 = createTestSong(
        id: 's3',
        title: 'Meesaya Murukku (Lofi Flip)',
        artist: 'Hiphop Tamizha',
        album: 'Lofi Vibes',
        duration: 211, // within 3-second band
        coverUrl: 'https://i.ytimg.com/vi/thumb2.jpg',
        source: 'youtube',
      );

      expect(song1.canonicalBaseKey, equals(song2.canonicalBaseKey));
      expect(song1.canonicalBaseKey, equals(song3.canonicalBaseKey));

      expect(song1.versionTag, equals('From film'));
      expect(song2.versionTag, equals('Remix'));
      expect(song3.versionTag, equals('Lofi'));

      final grouped = SongRepository.groupCanonicalSongs([song1, song2, song3]);
      expect(grouped.length, equals(1));
      final primary = grouped.first;
      expect(primary.id, equals('s1')); // Prefers official JioSaavn 320k album art
      expect(primary.versions.length, equals(2));
      expect(primary.versions.map((v) => v.versionTag), containsAll(['Remix', 'Lofi']));
    });

    test('TrackEntity grouping maintains canonical base key and versions list', () {
      final t1 = TrackEntity(
        id: 't1',
        title: 'Puthu Mazha',
        artist: 'Vijay Yesudas',
        album: 'Film Hits',
        duration: 240,
        streamUrl: 'https://stream1',
        coverUrl: 'https://c.saavncdn.com/art.jpg',
        source: 'saavn',
      );

      final t2 = TrackEntity(
        id: 't2',
        title: 'Puthu Mazha (Live in Concert)',
        artist: 'Vijay Yesudas',
        album: 'Live Concert',
        duration: 242,
        streamUrl: 'https://stream2',
        coverUrl: 'https://ytimg.com/art.jpg',
        source: 'youtube',
      );

      final grouped = TrackEntity.groupTracks([t1, t2]);
      expect(grouped.length, equals(1));
      expect(grouped.first.versions.length, equals(1));
      expect(grouped.first.versions.first.versionTag, equals('Live'));
    });
  });

  group('Audio Match Verification Before Playing', () {
    test('Verifies audio match accepts valid candidate with same title and artist', () {
      final target = createTestSong(
        id: 'yt_123',
        title: 'Meesaya Murukku Official Video',
        artist: 'Hiphop Tamizha',
        album: 'Meesaya Murukku',
        duration: 210,
        source: 'youtube',
      );

      final candidate = createTestSong(
        id: 'saavn_456',
        title: 'Meesaya Murukku (From "Meesaya Murukku")',
        artist: 'Hiphop Tamizha, Kharesma Ravichandran',
        album: 'Meesaya Murukku',
        duration: 212,
        source: 'saavn',
      );

      expect(AudioQueueHandler.verifyAudioMatch(candidate, target), isTrue);
    });

    test('Rejects candidate when duration difference exceeds tolerance (> 12s)', () {
      final target = createTestSong(
        id: 'yt_123',
        title: 'Meesaya Murukku Song',
        artist: 'Hiphop Tamizha',
        album: 'Meesaya Murukku',
        duration: 210,
        source: 'youtube',
      );

      final mismatchedCandidate = createTestSong(
        id: 'saavn_trailer',
        title: 'Meesaya Murukku Teaser',
        artist: 'Hiphop Tamizha',
        album: 'Meesaya Murukku',
        duration: 45, // Teaser duration mismatch
        source: 'saavn',
      );

      expect(AudioQueueHandler.verifyAudioMatch(mismatchedCandidate, target), isFalse);
    });

    test('Rejects candidate when artist and title tokens do not match', () {
      final target = createTestSong(
        id: 'yt_123',
        title: 'Puthu Mazha',
        artist: 'Vijay Yesudas',
        album: 'Film Songs',
        duration: 240,
        source: 'youtube',
      );

      final unrelatedCandidate = createTestSong(
        id: 'saavn_wrong',
        title: 'Mazha Paattu',
        artist: 'Unni Menon',
        album: 'Album 1',
        duration: 240,
        source: 'saavn',
      );

      expect(AudioQueueHandler.verifyAudioMatch(unrelatedCandidate, target), isFalse);
    });
  });

  group('Smart Shuffle Diversity & Feedback Logic', () {
    test('Enforces artist diversity cap of at most 1 song per artist in 5 consecutive tracks', () {
      final controller = SmartShuffleController();
      final songA1 = createTestSong(id: '1', title: 'Vaadi Pulla', artist: 'Hiphop Tamizha', duration: 200);
      final songA2 = createTestSong(id: '2', title: 'Machan Inga', artist: 'Hiphop Tamizha', duration: 210);
      final songB1 = createTestSong(id: '3', title: 'Marana Mass', artist: 'Anirudh Ravichander', duration: 220);
      final songC1 = createTestSong(id: '4', title: 'Rowdy Baby', artist: 'Dhanush', duration: 230);
      final songD1 = createTestSong(id: '5', title: 'Vaseegara', artist: 'Harris Jayaraj', duration: 240);

      final List<Song> window = [songA1, songB1, songC1, songD1];
      // Hiphop Tamizha is already in the last 4 tracks, so another track by Hiphop Tamizha should be blocked
      expect(controller.isArtistAllowed(songA2, window), isFalse);

      // An artist not in the last 4 tracks (or a 5th track after slide) is allowed
      final songE1 = createTestSong(id: '6', title: 'Nenjukkul Peidhidum', artist: 'Hariharan', duration: 250);
      expect(controller.isArtistAllowed(songE1, window), isTrue);
    });

    test('Skips (< 30s) are recorded as negative feedback while listens (> 30s) are positive', () {
      final controller = SmartShuffleController();
      final song = createTestSong(id: 'test_song', title: 'Test Track', artist: 'Test Artist', duration: 180);

      // Record early skip (e.g. 10 seconds into track)
      controller.recordPlaybackFeedback(song, listenedSeconds: 10, totalSeconds: 180);
      expect(controller.getSongAffinityScore(song), lessThan(0.0));

      // Record completed listen on a second track (e.g. 160 seconds)
      final likedSong = createTestSong(id: 'liked_song', title: 'Liked Track', artist: 'Liked Artist', duration: 180);
      controller.recordPlaybackFeedback(likedSong, listenedSeconds: 160, totalSeconds: 180);
      expect(controller.getSongAffinityScore(likedSong), greaterThan(0.0));
    });
  });

  group('Search Confidence Bar for Top Result', () {
    test('Top result is set when confidence bar (score >= 0.70) is satisfied', () {
      final song = createTestSong(
        id: '1',
        title: 'Meesaya Murukku',
        artist: 'Hiphop Tamizha',
        album: 'Meesaya Murukku',
        duration: 210,
        source: 'saavn',
      );
      final intent = SearchService.understandQuery('meesaya murukku');
      final score = SearchService.scoreSong(song, intent, preferredLanguages: ['tamil']);
      expect(score, greaterThanOrEqualTo(0.70));
    });

    test('Weak match score (< 0.70) falls below confidence threshold', () {
      final unrelatedSong = createTestSong(
        id: '2',
        title: 'A Random English Instrumental',
        artist: 'Unknown Artist',
        album: 'Acoustic Sessions',
        duration: 120,
        source: 'youtube',
      );
      final intent = SearchService.understandQuery('meesaya murukku');
      final score = SearchService.scoreSong(unrelatedSong, intent, preferredLanguages: ['tamil']);
      expect(score, lessThan(0.70));
    });
  });
}
