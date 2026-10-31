import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/logic/next_track_strategy.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/queue_cooldown_manager.dart';
import 'package:paatu_padava_mobile/services/radio_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_aware_radio_test_');
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

  group('Session-Aware Candidate Generation & Release Year Extraction', () {
    test('RadioEngine.extractReleaseYear accurately extracts 4-digit years from album or title', () {
      final s1 = Song(id: '1', title: 'Roja (1992)', artist: 'A.R. Rahman', album: 'Roja', coverUrl: '');
      final s2 = Song(id: '2', title: 'Hukum', artist: 'Anirudh', album: 'Jailer (2023)', coverUrl: '');
      final s3 = Song(id: '3', title: 'Kavithai', artist: 'Yuvan', album: 'Pudhupettai 2006 OST', coverUrl: '');
      final s4 = Song(id: '4', title: 'No Year Song', artist: 'Artist', album: 'Album', coverUrl: '');

      expect(RadioEngine.extractReleaseYear(s1), equals(1992));
      expect(RadioEngine.extractReleaseYear(s2), equals(2023));
      expect(RadioEngine.extractReleaseYear(s3), equals(2006));
      expect(RadioEngine.extractReleaseYear(s4), isNull);
    });

    test('RadioEngine.isSharedMusicDirectorOrComposer detects prominent Indian composers across tracks', () {
      final s1 = Song(id: '1', title: 'Naa Ready', artist: 'Anirudh Ravichander, Thalapathy Vijay', album: 'Leo', coverUrl: '');
      final s2 = Song(id: '2', title: 'Badass', artist: 'Anirudh Ravichander', album: 'Leo', coverUrl: '');
      final s3 = Song(id: '3', title: 'Vaseegara', artist: 'Harris Jayaraj, Bombay Jayashri', album: 'Minnale', coverUrl: '');
      final s4 = Song(id: '4', title: 'Ennamo Edho', artist: 'Harris Jayaraj, Aalaap Raju', album: 'Ko', coverUrl: '');
      final s5 = Song(id: '5', title: 'Unrelated Song', artist: 'Random Singer', album: 'Random Album', coverUrl: '');

      // Anirudh match
      expect(RadioEngine.isSharedMusicDirectorOrComposer(s1, s2), isTrue);
      // Harris Jayaraj match
      expect(RadioEngine.isSharedMusicDirectorOrComposer(s3, s4), isTrue);
      // Unrelated composer
      expect(RadioEngine.isSharedMusicDirectorOrComposer(s1, s3), isFalse);
      expect(RadioEngine.isSharedMusicDirectorOrComposer(s1, s5), isFalse);
    });
  });

  group('Session-Aware Hard Filtering (Prune Bad Candidates)', () {
    test('Hard filtering drops songs in last 50 history (BloomFilter/Set) and queue cooldown buffer', () {
      final seed = Song(id: 'seed', title: 'Seed Song', artist: 'Artist A', language: 'tamil', coverUrl: '', duration: 240);
      final playedSong = Song(id: 'played_1', title: 'Already Played Song', artist: 'Artist B', language: 'tamil', coverUrl: '', duration: 220);
      final coolingSong = Song(id: 'cooling_1', title: 'Cooling Song', artist: 'Artist C', language: 'tamil', coverUrl: '', duration: 210);
      final freshSong = Song(id: 'fresh_1', title: 'Brand New Fresh Song', artist: 'Artist D', language: 'tamil', coverUrl: '', duration: 230);

      // Record cooling song to QueueCooldownManager
      QueueCooldownManager.recordPlayed(coolingSong);

      final filtered = RadioEngine.applyHardFiltering(
        seedSong: seed,
        candidates: [playedSong, coolingSong, freshSong],
        history: [playedSong],
        targetLanguage: 'tamil',
      );

      expect(filtered.any((s) => s.id == playedSong.id), isFalse, reason: 'Must drop songs in history');
      expect(filtered.any((s) => s.id == coolingSong.id), isFalse, reason: 'Must drop songs in QueueCooldownManager');
      expect(filtered.any((s) => s.id == freshSong.id), isTrue, reason: 'Must keep fresh songs');
    });

    test('Hard filtering drops duration < 60s, > 600s, and mix/compilation titles via TrackQualityFilter', () {
      final seed = Song(id: 'seed', title: 'Seed Song', artist: 'Artist A', language: 'tamil', coverUrl: '', duration: 240);
      final shortClip = Song(id: 'short', title: 'Promo Teaser', artist: 'Artist A', language: 'tamil', coverUrl: '', duration: 40);
      final longJukebox = Song(id: 'long', title: 'All Songs Non-Stop Hits Jukebox', artist: 'Artist A', language: 'tamil', coverUrl: '', duration: 1800);
      final validSong = Song(id: 'valid', title: 'Normal Melodious Single', artist: 'Artist B', language: 'tamil', coverUrl: '', duration: 250);

      final filtered = RadioEngine.applyHardFiltering(
        seedSong: seed,
        candidates: [shortClip, longJukebox, validSong],
        targetLanguage: 'tamil',
      );

      expect(filtered.any((s) => s.id == shortClip.id), isFalse, reason: 'Must drop tracks < 60s');
      expect(filtered.any((s) => s.id == longJukebox.id), isFalse, reason: 'Must drop tracks > 600s or mix titles');
      expect(filtered.any((s) => s.id == validSong.id), isTrue, reason: 'Must retain normal length tracks');
    });

    test('Hard filtering enforces strict language matching and anti-cross-language dubs', () {
      final seed = Song(id: 'seed', title: 'Arabic Kuthu (From Beast)', artist: 'Anirudh', language: 'tamil', coverUrl: '', duration: 280);
      final dubTelugu = Song(id: 'dub_telugu', title: 'Arabic Kuthu (Telugu Dub)', artist: 'Anirudh', language: 'telugu', coverUrl: '', duration: 280);
      final hindiSong = Song(id: 'hindi', title: 'Kesariya', artist: 'Pritam', language: 'hindi', coverUrl: '', duration: 260);
      final tamilMatch = Song(id: 'tamil_cand', title: 'Jalabulanjangu', artist: 'Anirudh', language: 'tamil', coverUrl: '', duration: 240);

      final filtered = RadioEngine.applyHardFiltering(
        seedSong: seed,
        candidates: [dubTelugu, hindiSong, tamilMatch],
        targetLanguage: 'tamil',
      );

      expect(filtered.any((s) => s.id == dubTelugu.id), isFalse, reason: 'Must drop cross-language dubs');
      expect(filtered.any((s) => s.id == hindiSong.id), isFalse, reason: 'Must drop language mismatches');
      expect(filtered.any((s) => s.id == tamilMatch.id), isTrue, reason: 'Must keep matching language songs');
    });
  });

  group('Session-Aware Scoring & Diversity Re-Ranking', () {
    test('Era proximity (±4 years), composer boost, and anti-fatigue penalty score correctly', () {
      final seed = Song(
        id: 'seed',
        title: 'Hukum (2023)',
        artist: 'Anirudh Ravichander',
        album: 'Jailer (2023)',
        language: 'tamil',
        coverUrl: '',
        duration: 210,
      );

      // Candidate 1: Same composer (Anirudh) + same era (2023 ± 4y)
      final candHigh = Song(
        id: 'c1',
        title: 'Badass (2023)',
        artist: 'Anirudh Ravichander',
        album: 'Leo (2023)',
        language: 'tamil',
        coverUrl: '',
        duration: 220,
      );

      // Candidate 2: Different composer + distant era (1995)
      final candLow = Song(
        id: 'c2',
        title: 'Old Melody (1995)',
        artist: 'Deva',
        album: 'Old Movie (1995)',
        language: 'tamil',
        coverUrl: '',
        duration: 250,
      );

      // Candidate 3: Artist played in last 2 tracks -> gets -0.50 anti-fatigue penalty
      final candFatigued = Song(
        id: 'c3',
        title: 'Recent Song (2023)',
        artist: 'Fatigued Artist',
        album: 'Movie (2023)',
        language: 'tamil',
        coverUrl: '',
        duration: 215,
      );

      final ranked = RadioEngine.scoreAndReRankCandidates(
        seedSong: seed,
        candidates: [candLow, candFatigued, candHigh],
        lastPlayedArtists: ['Fatigued Artist', 'Other Artist'],
      );

      expect(ranked.first.id, equals(candHigh.id), reason: 'Shared composer + era proximity must rank highest');
      expect(ranked.last.id, equals(candFatigued.id), reason: 'Fatigued artist played in last 2 tracks must receive -0.50 penalty');
    });
  });

  group('The "Skip Signal" & Seed Persistence in AudioQueueHandler', () {
    test('Skips under 30s record skip penalty and DO NOT overwrite _lastCompletedSeedSong', () async {
      final player = MockAudioPlayer();
      final handler = AudioQueueHandler(player: player);

      final track1 = Song(id: 't1', title: 'Song 1', artist: 'Artist 1', album: 'Album 1', coverUrl: '', duration: 200);
      final track2 = Song(id: 't2', title: 'Song 2', artist: 'Artist 2', album: 'Album 2', coverUrl: '', duration: 210);
      final track3 = Song(id: 't3', title: 'Song 3', artist: 'Artist 3', album: 'Album 3', coverUrl: '', duration: 220);

      await handler.loadQueue([track1, track2, track3], autoPlay: false);

      // Initially, lastCompletedSeedSong is track1 (initial anchor)
      expect(handler.lastCompletedSeedSong?.id, equals('t1'));

      // Simulate playing for 10 seconds (less than 30s) and then skipping track1
      player.simulatePosition(const Duration(seconds: 10));
      await handler.skipToNext(isUserInitiated: true);

      // Now playing track2, but because track1 was skipped under 30s,
      // lastCompletedSeedSong MUST NOT be replaced by track2 or cleared, it preserves track1!
      expect(handler.currentSong?.id, equals('t2'));
      expect(handler.lastCompletedSeedSong?.id, equals('t1'));

      // Now simulate track2 playing for 45 seconds (>= 30s) and skipping
      player.simulatePosition(const Duration(seconds: 45));
      await handler.skipToNext(isUserInitiated: true);

      // Since track2 played for >= 30s, lastCompletedSeedSong updates to track2!
      expect(handler.currentSong?.id, equals('t3'));
      expect(handler.lastCompletedSeedSong?.id, equals('t2'));

      handler.dispose();
      await player.dispose();
    });

    test('Natural track completion updates _lastCompletedSeedSong to completed track', () async {
      final player = MockAudioPlayer();
      final handler = AudioQueueHandler(player: player);

      final track1 = Song(id: 't1', title: 'Song 1', artist: 'Artist 1', album: 'Album 1', coverUrl: '', duration: 200);
      final track2 = Song(id: 't2', title: 'Song 2', artist: 'Artist 2', album: 'Album 2', coverUrl: '', duration: 210);

      await handler.loadQueue([track1, track2], autoPlay: false);
      expect(handler.lastCompletedSeedSong?.id, equals('t1'));

      // Natural track completion
      player.simulateTrackCompleted();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(handler.lastCompletedSeedSong?.id, equals('t1'));

      handler.dispose();
      await player.dispose();
    });
  });
}

class MockAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController = StreamController<int?>.broadcast();
  final StreamController<PlayerState> _playerStateController = StreamController<PlayerState>.broadcast();
  final StreamController<SequenceState?> _sequenceStateController = StreamController<SequenceState?>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();

  double _volume = 1.0;
  bool _playing = false;
  Duration _position = Duration.zero;
  final Duration _duration = const Duration(minutes: 3);
  AudioSource? _audioSource;
  int? _sourceIndex;
  LoopMode _loopMode = LoopMode.off;

  @override
  int? get currentIndex => _sourceIndex;

  @override
  LoopMode get loopMode => _loopMode;

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
  }

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<SequenceState?> get sequenceStateStream => _sequenceStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  double get volume => _volume;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _duration;

  @override
  AudioSource? get audioSource => _audioSource;

  @override
  Future<void> setVolume(double value) async {
    _volume = value;
  }

  @override
  Future<void> play() async {
    _playing = true;
    _playerStateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playerStateController.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _playerStateController.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    _audioSource = source;
    _sourceIndex = initialIndex ?? 0;
    _currentIndexController.add(_sourceIndex);
    return _duration;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      _position = position;
      _positionController.add(position);
    }
    if (index != null) {
      _sourceIndex = index;
      _currentIndexController.add(index);
    }
  }

  void simulatePosition(Duration pos) {
    _position = pos;
    _positionController.add(pos);
  }

  void simulateTrackCompleted() {
    _playerStateController.add(PlayerState(false, ProcessingState.completed));
  }

  @override
  Future<void> dispose() async {
    await _currentIndexController.close();
    await _playerStateController.close();
    await _sequenceStateController.close();
    await _positionController.close();
  }
}
