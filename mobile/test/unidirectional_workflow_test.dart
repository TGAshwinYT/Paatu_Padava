import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/logic/stream_resolver.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/queue_cooldown_manager.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';

class MockAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController = StreamController<int?>.broadcast();
  final StreamController<PlayerState> _playerStateController = StreamController<PlayerState>.broadcast();
  final StreamController<SequenceState?> _sequenceStateController = StreamController<SequenceState?>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();

  double _volume = 1.0;
  bool _playing = false;
  Duration _position = Duration.zero;
  final Duration _duration = const Duration(minutes: 4); // 240 seconds
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

  @override
  Future<void> dispose() async {
    await _currentIndexController.close();
    await _playerStateController.close();
    await _sequenceStateController.close();
    await _positionController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('unidirectional_workflow_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(FavoritesManager.boxName);
    await Hive.openBox(HistoryManager.boxName);
    await Hive.openBox(HistoryManager.pendingBoxName);
    QueueCooldownManager.clear();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    QueueCooldownManager.clear();
  });

  group('Layer 1: Decoupled UI & Repository Abstraction', () {
    test('SearchService.resolveDirectUrlOrEntity handles non-URL text returning null cleanly', () async {
      final result = await SearchService.resolveDirectUrlOrEntity('plain text search query');
      expect(result, isNull);
    });

    test('SongRepository normalizes titles and deduplicates lists cleanly', () {
      final s1 = Song(id: '1', title: 'Hukum (From "Jailer")', artist: 'Anirudh', coverUrl: '');
      final s2 = Song(id: '2', title: 'Hukum [Official Video]', artist: 'Anirudh', coverUrl: '');
      final deduped = SongRepository.deduplicateSongs([s1, s2]);
      expect(deduped.length, equals(1));
    });
  });

  group('Layer 3: Just-In-Time Stream Resolution & Fallbacks', () {
    test('StreamResolver verifies audio match with duration tolerance', () {
      final target = Song(id: 't1', title: 'Arabic Kuthu', artist: 'Anirudh', duration: 280, coverUrl: '');
      final candGood = Song(id: 'c1', title: 'Arabic Kuthu (From Beast)', artist: 'Anirudh Ravichander', duration: 278, coverUrl: '');
      final candLong = Song(id: 'c2', title: 'Arabic Kuthu Non Stop Jukebox', artist: 'Anirudh', duration: 1800, coverUrl: '');

      expect(StreamResolver.verifyMatch(candGood, target), isTrue);
      expect(StreamResolver.verifyMatch(candLong, target), isFalse);
    });
  });

  group('Layer 4: Telemetry & Feedback Loop at 50% Playback Milestone', () {
    test('50% playback progress milestone triggers HistoryManager and QueueCooldownManager', () async {
      final player = MockAudioPlayer();
      final handler = AudioQueueHandler(player: player);

      final track = Song(
        id: 'track_50',
        title: 'Telemetry Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        duration: 240, // 4 minutes
        coverUrl: '',
      );

      await handler.loadQueue([track], autoPlay: false);

      // Play at 25% (60s out of 240s) -> should NOT trigger history yet
      player.simulatePosition(const Duration(seconds: 60));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(QueueCooldownManager.isCoolingDown(track), isFalse);

      // Play past 50% (125s out of 240s) -> triggers Milestone 2: Telemetry
      player.simulatePosition(const Duration(seconds: 125));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(QueueCooldownManager.isCoolingDown(track), isTrue,
          reason: '50% playback milestone must record played track to QueueCooldownManager');

      handler.dispose();
      await player.dispose();
    });
  });
}
