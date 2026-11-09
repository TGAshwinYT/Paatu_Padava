import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/spotify_import_service.dart';

void main() {
  group('Spotify Importer Hybrid Matcher Tests', () {
    test('cleanTrackTitle sanitizes parentheticals and tags cleanly', () {
      expect(
        SpotifyImportService.cleanTrackTitle('Minnalvala (From "Narivetta")'),
        equals('Minnalvala'),
      );
      expect(
        SpotifyImportService.cleanTrackTitle('Melliname (From "Shajahaan")'),
        equals('Melliname'),
      );
      expect(
        SpotifyImportService.cleanTrackTitle('Puthu Mazha (Original Motion Picture Soundtrack)'),
        equals('Puthu Mazha'),
      );
    });

    test('extractMovieFromTitle extracts film name from title tags', () {
      expect(
        SpotifyImportService.extractMovieFromTitle('Minnalvala (From "Narivetta")'),
        equals('Narivetta'),
      );
      expect(
        SpotifyImportService.extractMovieFromTitle('Melliname (From "Shajahaan")'),
        equals('Shajahaan'),
      );
      expect(
        SpotifyImportService.extractMovieFromTitle('Stand Alone Song'),
        isNull,
      );
    });

    test('normalizeTanglish normalizes transliteration variants', () {
      expect(
        SpotifyImportService.normalizeTanglish('Mellinamae'),
        equals('melliname'),
      );
      expect(
        SpotifyImportService.normalizeTanglish('Mellinamey'),
        equals('melliname'),
      );
      expect(
        SpotifyImportService.normalizeTanglish('Pudhu'),
        equals('puthu'),
      );
    });

    test('computeTitleSimilarity handles Tanglish transliterations with 100% score', () {
      final sim = SpotifyImportService.computeTitleSimilarity('Melliname', 'Mellinamae');
      expect(sim, equals(100));
    });

    test('extractAllArtists parses multiple playback singers and composers', () {
      final artists = SpotifyImportService.extractAllArtists('Justin Prabhakaran, Shakthisree Gopalan & Manu Manjith');
      expect(artists, contains('justin prabhakaran'));
      expect(artists, contains('shakthisree gopalan'));
      expect(artists, contains('manu manjith'));
    });

    test('computeArtistSimilarity awards higher score to female/featured artist inclusion', () {
      const target = 'Justin Prabhakaran, Shakthisree Gopalan';
      const candidateFull = 'Justin Prabhakaran, Shakthisree Gopalan, Manu Manjith';
      const candidateSolo = 'Justin Prabhakaran';

      final fullScore = SpotifyImportService.computeArtistSimilarity(target, candidateFull);
      final soloScore = SpotifyImportService.computeArtistSimilarity(target, candidateSolo);

      expect(fullScore, greaterThan(soloScore));
      expect(fullScore, equals(100));
    });

    test('computeDurationScore penalizes covers/extended cuts (> 20s difference) heavily', () {
      // 327s (original Shajahaan) vs 327s
      expect(SpotifyImportService.computeDurationScore(327, 327), equals(20));

      // 327s vs 324s (standard slight difference across platforms)
      expect(SpotifyImportService.computeDurationScore(327, 324), equals(20));

      // 327s vs 280s (47s difference: indie cover)
      expect(SpotifyImportService.computeDurationScore(327, 280), equals(-60));
    });

    test('scoreCandidate ranks authentic movie soundtrack above indie covers and wrong languages', () {
      const targetMelliname = SpotifyTrackItem(
        title: 'Melliname',
        artist: 'Harish Raghavendra, Mani Sharma',
        album: 'Shajahaan',
        durationSeconds: 327,
      );

      final originalCandidate = Song(
        id: 'orig_1',
        title: 'Mellinamae',
        artist: 'Mani Sharma',
        album: 'Shajahaan',
        coverUrl: '',
        streamUrl: 'https://aac.saavncdn.com/test_320.mp4',
        duration: 327,
        source: 'saavn',
        language: 'tamil',
      );

      final coverCandidate = Song(
        id: 'cover_1',
        title: 'Melliname',
        artist: 'Tajmeel Sherif, Mani Sharma',
        album: 'Melliname Melliname',
        coverUrl: '',
        streamUrl: 'https://aac.saavncdn.com/cover_320.mp4',
        duration: 280,
        source: 'saavn',
        language: 'tamil',
      );

      final origScore = SpotifyImportService.scoreCandidate(
        target: targetMelliname,
        candidate: originalCandidate,
      );

      final coverScore = SpotifyImportService.scoreCandidate(
        target: targetMelliname,
        candidate: coverCandidate,
      );

      expect(origScore, greaterThan(coverScore));
      expect(origScore, greaterThanOrEqualTo(85));
      expect(coverScore, lessThan(60)); // Rejected
    });

    test('scoreCandidate preserves Malayalam original for Puthu Mazha', () {
      const targetPuthuMazha = SpotifyTrackItem(
        title: 'Puthu Mazha',
        artist: 'Justin Prabhakaran, Shakthisree Gopalan, Manu Manjith',
        album: 'Sarvam Maya',
        durationSeconds: 262,
      );

      final malayalamFemaleOrig = Song(
        id: 'mal_orig',
        title: 'Puthu Mazha',
        artist: 'Justin Prabhakaran, Shakthisree Gopalan, Manu Manjith',
        album: 'Sarvam Maya (Original Motion Picture Soundtrack)',
        coverUrl: '',
        streamUrl: 'https://aac.saavncdn.com/mal_320.mp4',
        duration: 262,
        source: 'saavn',
        language: 'malayalam',
      );

      final tamilMusicOrigins = Song(
        id: 'tam_orig',
        title: 'Puthu Mazha',
        artist: 'Justin Prabhakaran',
        album: 'Sarvam Maya-Music Origins (Original Motion Picture Soundtrack)',
        coverUrl: '',
        streamUrl: 'https://aac.saavncdn.com/tam_320.mp4',
        duration: 256,
        source: 'saavn',
        language: 'tamil',
      );

      final malScore = SpotifyImportService.scoreCandidate(
        target: targetPuthuMazha,
        candidate: malayalamFemaleOrig,
      );

      final tamScore = SpotifyImportService.scoreCandidate(
        target: targetPuthuMazha,
        candidate: tamilMusicOrigins,
      );

      expect(malScore, greaterThan(tamScore));
      expect(malayalamFemaleOrig.language, equals('malayalam'));
    });
  });
}

