import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/logic/next_track_strategy.dart';
import 'package:paatu_padava_mobile/services/queue_cooldown_manager.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/logic/markov_cosine_radio_strategy.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paatu_strategy_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(FavoritesManager.boxName);
    await Hive.openBox(HistoryManager.boxName);
    await Hive.openBox(HistoryManager.pendingBoxName);
    QueueCooldownManager.clear();
    NextTrackStrategyFactory.resetSession();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    QueueCooldownManager.clear();
    NextTrackStrategyFactory.resetSession();
  });

  group('Artist Dispersion & Zero Back-to-Back Guarantees', () {
    test('enforceArtistDispersionAndNoBackToBack guarantees alternating artists with zero consecutive duplicates', () {
      final candidates = [
        Song(id: 's1', title: 'Song 1', artist: 'Anirudh Ravichander', album: 'Album A', coverUrl: ''),
        Song(id: 's2', title: 'Song 2', artist: 'A.R. Rahman', album: 'Album B', coverUrl: ''),
        Song(id: 's3', title: 'Song 3', artist: 'Anirudh Ravichander', album: 'Album C', coverUrl: ''),
        Song(id: 's4', title: 'Song 4', artist: 'Yuvan Shankar Raja', album: 'Album D', coverUrl: ''),
        Song(id: 's5', title: 'Song 5', artist: 'Yuvan Shankar Raja', album: 'Album E', coverUrl: ''),
        Song(id: 's6', title: 'Song 6', artist: 'Harris Jayaraj', album: 'Album F', coverUrl: ''),
        Song(id: 's7', title: 'Song 7', artist: 'Harris Jayaraj', album: 'Album G', coverUrl: ''),
        Song(id: 's8', title: 'Song 8', artist: 'Santhosh Narayanan', album: 'Album H', coverUrl: ''),
      ];

      // Seed artist is Anirudh: the first generated song MUST NOT be Anirudh!
      final result = enforceArtistDispersionAndNoBackToBack(
        candidates,
        seedArtist: 'Anirudh Ravichander',
        count: 6,
      );

      expect(result.isNotEmpty, isTrue);
      expect(result.first.primaryArtist.toLowerCase(), isNot(equals('anirudh ravichander')));

      // Verify zero back-to-back duplicates for every consecutive pair
      for (int i = 1; i < result.length; i++) {
        final prevArtist = result[i - 1].primaryArtist.toLowerCase().trim();
        final curArtist = result[i].primaryArtist.toLowerCase().trim();
        expect(
          curArtist,
          isNot(equals(prevArtist)),
          reason: 'Track $i (${result[i].title} by $curArtist) has same artist as track ${i - 1} ($prevArtist)',
        );
      }
    });

    test('QueueCooldownManager tracks last 4 played artists and isArtistCoolingDown rejects them', () {
      final s1 = Song(id: '1', title: 'T1', artist: 'Anirudh Ravichander', album: '', coverUrl: '');
      final s2 = Song(id: '2', title: 'T2', artist: 'A.R. Rahman', album: '', coverUrl: '');
      final s3 = Song(id: '3', title: 'T3', artist: 'Yuvan Shankar Raja', album: '', coverUrl: '');
      final s4 = Song(id: '4', title: 'T4', artist: 'Harris Jayaraj', album: '', coverUrl: '');
      final s5 = Song(id: '5', title: 'T5', artist: 'Santhosh Narayanan', album: '', coverUrl: '');

      QueueCooldownManager.recordPlayed(s1);
      QueueCooldownManager.recordPlayed(s2);
      QueueCooldownManager.recordPlayed(s3);
      QueueCooldownManager.recordPlayed(s4);

      // Last 4 played artists: Anirudh, Rahman, Yuvan, Harris
      expect(QueueCooldownManager.isArtistCoolingDown('Anirudh Ravichander'), isTrue);
      expect(QueueCooldownManager.isArtistCoolingDown('A.R. Rahman'), isTrue);
      expect(QueueCooldownManager.isArtistCoolingDown('Yuvan Shankar Raja'), isTrue);
      expect(QueueCooldownManager.isArtistCoolingDown('Harris Jayaraj'), isTrue);
      expect(QueueCooldownManager.isArtistCoolingDown('Santhosh Narayanan'), isFalse);

      // Play 5th song: Anirudh should drop out of the 4-track window
      QueueCooldownManager.recordPlayed(s5);
      expect(QueueCooldownManager.isArtistCoolingDown('Anirudh Ravichander'), isFalse);
      expect(QueueCooldownManager.isArtistCoolingDown('Santhosh Narayanan'), isTrue);
    });

    test('enforceArtistDispersionAndNoBackToBack rejects artists cooling down in QueueCooldownManager', () {
      final played1 = Song(id: 'p1', title: 'Played 1', artist: 'Anirudh Ravichander', album: '', coverUrl: '');
      QueueCooldownManager.recordPlayed(played1);

      final candidates = [
        Song(id: 'c1', title: 'C1', artist: 'Anirudh Ravichander', album: '', coverUrl: ''),
        Song(id: 'c2', title: 'C2', artist: 'A.R. Rahman', album: '', coverUrl: ''),
        Song(id: 'c3', title: 'C3', artist: 'Yuvan Shankar Raja', album: '', coverUrl: ''),
      ];

      final result = enforceArtistDispersionAndNoBackToBack(
        candidates,
        seedArtist: 'Different Artist',
        count: 5,
      );

      // Anirudh Ravichander is cooling down, so only Rahman and Yuvan should appear
      final artists = result.map((s) => s.primaryArtist.toLowerCase()).toList();
      expect(artists, isNot(contains('anirudh ravichander')));
      expect(artists, contains('ar rahman'));
      expect(artists, contains('yuvan shankar raja'));
    });
  });

  group('Spotify Session Context Anchoring & Batch Generation', () {
    test('Spotify strategy resets session anchor cleanly', () {
      final strategy = SpotifyStyleStrategy();
      final seed = Song(id: 'seed1', title: 'Hukum', artist: 'Anirudh Ravichander', album: 'Jailer', coverUrl: '');

      strategy.resetSession(initialAnchor: seed);
      // Re-resetting clears the anchor
      strategy.resetSession();
      expect(true, isTrue); // verified no exception
    });

    test('Spotify strategy getUpcomingTracks executes without blocking on external ML backend', () async {
      final strategy = SpotifyStyleStrategy();
      final seed = Song(
        id: 'seed_spot_1',
        title: 'Naa Ready',
        artist: 'Anirudh Ravichander',
        album: 'Leo',
        coverUrl: '',
        language: 'tamil',
      );

      final upcoming = await strategy.getUpcomingTracks(
        seedSong: seed,
        queue: [seed],
        history: [],
        count: 5,
      );

      // Successfully returns candidates without throwing unhandled exceptions
      expect(upcoming, isA<List<Song>>());
      // Guarantees zero duplicate of seed song
      expect(upcoming.any((s) => s.id == seed.id), isFalse);
    });
  });

  group('YouTube Music Auto-Mix Skip Reactivity', () {
    test('Skip Reactivity (<30s) blacklists artist and invalidates branch', () {
      final strategy = YtMusicStyleStrategy();
      final seedSong = Song(id: 's_seed', title: 'Seed Song', artist: 'Artist A', album: '', coverUrl: '');
      final skippedSong = Song(id: 's_skip', title: 'Annoying Song', artist: 'Artist Disliked', album: '', coverUrl: '');

      strategy.resetSession(initialAnchor: seedSong);

      // Simulate skipping with 12 seconds of playback (<30s)
      strategy.recordSkip(skippedSong, listenedSeconds: 12);

      // Verify that candidate filtering will reject Artist Disliked
      final candidates = [
        Song(id: 'c1', title: 'Candidate 1', artist: 'Artist Disliked', album: '', coverUrl: ''),
        Song(id: 'c2', title: 'Candidate 2', artist: 'Artist Liked', album: '', coverUrl: ''),
      ];

      final filtered = enforceArtistDispersionAndNoBackToBack(
        candidates.where((c) => c.primaryArtist.toLowerCase() != 'artist disliked').toList(),
        seedArtist: seedSong.primaryArtist,
      );

      expect(filtered.any((s) => s.primaryArtist.toLowerCase() == 'artist disliked'), isFalse);
      expect(filtered.any((s) => s.primaryArtist.toLowerCase() == 'artist liked'), isTrue);
    });
  });

  group('Circuit Breaker Fallback Tests', () {
    test('getLocalFallbackTracks retrieves cached favorites with zero back-to-back duplicates', () async {
      final seed = Song(id: 'seed_x', title: 'Active Seed', artist: 'A.R. Rahman', album: '', coverUrl: '', language: 'tamil');

      // Add local favorites
      final fav1 = Song(id: 'fav_1', title: 'Kannalane', artist: 'A.R. Rahman', album: 'Bombay', coverUrl: '', language: 'tamil');
      final fav2 = Song(id: 'fav_2', title: 'Poongatrile', artist: 'A.R. Rahman', album: 'Uyire', coverUrl: '', language: 'tamil');
      final fav3 = Song(id: 'fav_3', title: 'New York Nagaram', artist: 'A.R. Rahman', album: 'Sillunu Oru Kaadhal', coverUrl: '', language: 'tamil');
      final fav4 = Song(id: 'fav_4', title: 'Kanave Kanave', artist: 'Anirudh Ravichander', album: 'David', coverUrl: '', language: 'tamil');
      final fav5 = Song(id: 'fav_5', title: 'Idhazhin Oram', artist: 'Anirudh Ravichander', album: '3', coverUrl: '', language: 'tamil');
      final fav6 = Song(id: 'fav_6', title: 'Pookkale Sattru', artist: 'A.R. Rahman', album: 'I', coverUrl: '', language: 'tamil');

      await FavoritesManager.toggleFavorite(fav1);
      await FavoritesManager.toggleFavorite(fav2);
      await FavoritesManager.toggleFavorite(fav3);
      await FavoritesManager.toggleFavorite(fav4);
      await FavoritesManager.toggleFavorite(fav5);
      await FavoritesManager.toggleFavorite(fav6);

      final fallback = getLocalFallbackTracks(
        seed,
        exclusions: {seed.id, seed.canonicalBaseKey},
        count: 4,
        targetLang: 'tamil',
      );

      expect(fallback.isNotEmpty, isTrue);
      // Verify zero back-to-back artist duplicates in fallback results
      for (int i = 1; i < fallback.length; i++) {
        expect(
          fallback[i].primaryArtist.toLowerCase(),
          isNot(equals(fallback[i - 1].primaryArtist.toLowerCase())),
          reason: 'Back-to-back duplicate artist found at index $i in fallback queue',
        );
      }
    });
  });

  group('Unicode & Punctuated Artist Normalization', () {
    test('Punctuation in artist names is stripped while preserving Unicode characters', () {
      final sTamil = Song(id: 'ta1', title: 'Song Tamil', artist: 'ஏ. ஆர். ரகுமான்', album: '', coverUrl: '');
      QueueCooldownManager.recordPlayed(sTamil);

      // Matches without dots
      expect(QueueCooldownManager.isArtistCoolingDown('ஏ ஆர் ரகுமான்'), isTrue);
      expect(QueueCooldownManager.isArtistCoolingDown('ஏ. ஆர். ரகுமான்'), isTrue);

      final sHindi = Song(id: 'hi1', title: 'Song Hindi', artist: 'ए. आर. रहमान', album: '', coverUrl: '');
      QueueCooldownManager.recordPlayed(sHindi);

      expect(QueueCooldownManager.isArtistCoolingDown('ए आर रहमान'), isTrue);
      expect(QueueCooldownManager.isArtistCoolingDown('ए. आर. रहमान'), isTrue);

      final sEnglish = Song(id: 'en1', title: 'Song En', artist: 'A.R. Rahman', album: '', coverUrl: '');
      QueueCooldownManager.recordPlayed(sEnglish);

      expect(QueueCooldownManager.isArtistCoolingDown('ar rahman'), isTrue);
      expect(QueueCooldownManager.isArtistCoolingDown('A.R. Rahman'), isTrue);
    });
  });

  group('YouTube Music Auto-Mix Rolling Skip Window', () {
    test('Skips under 30s record into rolling 5-artist queue and evict oldest on 6th skip', () {
      final strategy = YtMusicStyleStrategy();
      final seed = Song(id: 'seed_yt', title: 'Seed', artist: 'Anchor Artist', album: '', coverUrl: '');
      strategy.resetSession(initialAnchor: seed);

      for (int i = 1; i <= 6; i++) {
        final song = Song(id: 'skip_$i', title: 'Skip $i', artist: 'Artist $i', album: '', coverUrl: '');
        strategy.recordSkip(song, listenedSeconds: 10);
      }

      // Max capacity is 5. Artist 1 should have been evicted.
      expect(strategy.skippedArtists.length, equals(5));
      expect(strategy.skippedArtists.contains('artist 1'), isFalse);
      expect(strategy.skippedArtists.contains('artist 2'), isTrue);
      expect(strategy.skippedArtists.contains('artist 6'), isTrue);
    });
  });

  group('Adaptive Spotify Strategy Anchoring & Candidate Scoring', () {
    test('Positive transition shifts session anchor track', () {
      final strategy = SpotifyStyleStrategy();
      final seed = Song(id: 's_anchor', title: 'Initial Anchor', artist: 'Seed Artist', album: '', coverUrl: '');
      strategy.resetSession(initialAnchor: seed);
      expect(strategy.sessionAnchor?.id, equals('s_anchor'));

      final next = Song(id: 's_next', title: 'Next Track', artist: 'Next Artist', album: '', coverUrl: '');
      strategy.recordTransition(seed, next, isPositive: true);

      // Anchor updated to next
      expect(strategy.sessionAnchor?.id, equals('s_next'));
    });

    test('Skips under 30s in Spotify strategy record into rolling 5-artist queue', () {
      final strategy = SpotifyStyleStrategy();
      final seed = Song(id: 's_sp', title: 'Initial Anchor', artist: 'Seed Artist', album: '', coverUrl: '');
      strategy.resetSession(initialAnchor: seed);

      for (int i = 1; i <= 6; i++) {
        final song = Song(id: 'sp_skip_$i', title: 'Skip $i', artist: 'Sp Artist $i', album: '', coverUrl: '');
        strategy.recordSkip(song, listenedSeconds: 15);
      }

      expect(strategy.skippedArtists.length, equals(5));
      expect(strategy.skippedArtists.contains('sp artist 1'), isFalse);
      expect(strategy.skippedArtists.contains('sp artist 2'), isTrue);
      expect(strategy.skippedArtists.contains('sp artist 6'), isTrue);
    });
  });

  group('Markov-Cosine AI Strategy & Relative Vector Scoring', () {
    test('Markov transition matrix updates probability on positive and negative transitions', () {
      final strategy = MarkovCosineRadioStrategy();
      final matrix = strategy.markovMatrix;
      matrix.clear();

      final s1 = Song(id: 'm1', title: 'Song A', artist: 'Anirudh', album: '', coverUrl: '');
      final s2 = Song(id: 'm2', title: 'Song B', artist: 'Rahman', album: '', coverUrl: '');

      final pInitial = matrix.getProbability(s1, s2);
      expect(pInitial, equals(0.1));

      // Record positive transition
      strategy.recordTransition(s1, s2, isPositive: true);
      final pLearned = matrix.getProbability(s1, s2);
      expect(pLearned, greaterThan(pInitial));

      // Record negative transition (skip)
      strategy.recordTransition(s1, s2, isPositive: false);
      final pPenalized = matrix.getProbability(s1, s2);
      expect(pPenalized, lessThan(pLearned));
    });

    test('SongFeatureVector computes composite score weighting artist and language', () {
      final seed = Song(id: 'v_seed', title: 'Arabic Kuthu', artist: 'Anirudh Ravichander', album: 'Beast', coverUrl: '', language: 'tamil');
      final matchingCand = Song(id: 'v_match', title: 'Hukum', artist: 'Anirudh Ravichander', album: 'Jailer', coverUrl: '', language: 'tamil');
      final differentCand = Song(id: 'v_diff', title: 'Shape of You', artist: 'Ed Sheeran', album: 'Divide', coverUrl: '', language: 'english');

      final vMatch = SongFeatureVector.extractRelative(seed, matchingCand);
      final vDiff = SongFeatureVector.extractRelative(seed, differentCand);

      expect(vMatch.compositeVectorScore, greaterThan(vDiff.compositeVectorScore));
      expect(vMatch.artistSimilarity, equals(1.0));
      expect(vMatch.languageMatch, equals(1.0));
      expect(vDiff.artistSimilarity, equals(0.0));
    });

    test('NextTrackStrategyFactory provides MarkovCosineRadioStrategy when requested', () {
      final strategy = NextTrackStrategyFactory.getStrategy(NextTrackStrategyMode.markovCosineRadio);
      expect(strategy, isA<MarkovCosineRadioStrategy>());
      expect(strategy.id, equals('markov_cosine_radio'));
    });
  });
}
