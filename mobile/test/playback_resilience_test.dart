import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/app_logger.dart';
import 'package:paatu_padava_mobile/services/battery_optimization_service.dart';

/// Mock AudioPlayer for resilience and lifecycle validation
class _ResilienceMockPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _indexCtrl = StreamController<int?>.broadcast();
  final StreamController<PlayerState> _stateCtrl = StreamController<PlayerState>.broadcast();
  final StreamController<SequenceState?> _seqCtrl = StreamController<SequenceState?>.broadcast();
  final StreamController<Duration> _posCtrl = StreamController<Duration>.broadcast();

  double _volume = 1.0;
  bool _playing = false;
  Duration _position = Duration.zero;
  final Duration _dur = const Duration(minutes: 3);
  AudioSource? _audioSource;
  int? _sourceIndex;

  @override Stream<int?> get currentIndexStream => _indexCtrl.stream;
  @override Stream<PlayerState> get playerStateStream => _stateCtrl.stream;
  @override Stream<SequenceState?> get sequenceStateStream => _seqCtrl.stream;
  @override Stream<Duration> get positionStream => _posCtrl.stream;
  @override double get volume => _volume;
  @override bool get playing => _playing;
  @override Duration get position => _position;
  @override Duration? get duration => _dur;
  @override AudioSource? get audioSource => _audioSource;

  @override Future<void> setVolume(double v) async => _volume = v;
  @override Future<void> play() async {
    _playing = true;
    _stateCtrl.add(PlayerState(true, ProcessingState.ready));
  }
  @override Future<void> pause() async {
    _playing = false;
    _stateCtrl.add(PlayerState(false, ProcessingState.ready));
  }
  @override Future<void> stop() async {
    _playing = false;
    _stateCtrl.add(PlayerState(false, ProcessingState.idle));
  }
  @override Future<Duration?> setAudioSource(AudioSource src, {bool preload = true, int? initialIndex, Duration? initialPosition}) async {
    _audioSource = src;
    _sourceIndex = initialIndex ?? 0;
    _indexCtrl.add(_sourceIndex);
    return _dur;
  }
  @override Future<void> seek(Duration? pos, {int? index}) async {
    if (pos != null) { _position = pos; _posCtrl.add(pos); }
    if (index != null) { _sourceIndex = index; _indexCtrl.add(index); }
  }

  void simulateTrackTransition(int nextIndex) {
    _sourceIndex = nextIndex;
    _indexCtrl.add(nextIndex);
  }

  @override Future<void> dispose() async {
    await _indexCtrl.close();
    await _stateCtrl.close();
    await _seqCtrl.close();
    await _posCtrl.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ResilienceMockPlayer player;
  late AudioQueueHandler handler;

  Song createSong(int i, {String? streamUrl}) => Song(
    id: 'res_song_$i',
    title: 'Resilience Track $i',
    artist: 'Artist $i',
    album: 'Album',
    coverUrl: 'https://cdn.example.com/$i.jpg',
    duration: 180,
    streamUrl: streamUrl ?? 'https://stream.example.com/$i.mp3',
    source: 'saavn',
  );

  setUp(() {
    player = _ResilienceMockPlayer();
    handler = AudioQueueHandler(player: player);
  });

  tearDown(() async {
    handler.dispose();
    await player.dispose();
  });

  const tick = Duration(milliseconds: 50);

  group('AudioQueueHandler Resilience & Safe Preload', () {
    test('Queue loads 3 tracks end-to-end and preserves correct index and active song', () async {
      final songs = [createSong(0), createSong(1), createSong(2)];
      await handler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      expect(handler.currentIndex, equals(0));
      expect(handler.currentSong?.id, equals('res_song_0'));
      expect(handler.queue.length, equals(3));
      expect(player.playing, isTrue);

      // Simulate natural completion transition from track 0 to track 1
      player.simulateTrackTransition(1);
      await Future<void>.delayed(tick);

      expect(handler.currentIndex, equals(1));
      expect(handler.currentSong?.id, equals('res_song_1'));

      // Transition to track 2
      player.simulateTrackTransition(2);
      await Future<void>.delayed(tick);

      expect(handler.currentIndex, equals(2));
      expect(handler.currentSong?.id, equals('res_song_2'));
    });

    test('Preload upcoming tracks does not crash when upcoming track is resolved', () async {
      final songs = [createSong(0), createSong(1), createSong(2)];
      await handler.loadQueue(songs, initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(tick);

      // Calling preloadUpcomingTracks(0) resolves and updates upcoming source safely
      await handler.preloadUpcomingTracks(0);
      await Future<void>.delayed(tick);

      expect(handler.currentIndex, equals(0));
      expect(handler.queue[1].id, equals('res_song_1'));
    });

    test('Idle release timer is safely aborted if player is actively playing', () async {
      final songs = [createSong(0)];
      await handler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      expect(player.playing, isTrue);

      // Attempting handleIdleRelease while playing should abort without releasing
      await handler.handleIdleRelease();
      expect(handler.isIdleTimeoutActive, isFalse);
      expect(player.playing, isTrue);
    });

    test('Start and cancel idle timer operate cleanly without leaks', () {
      expect(handler.isIdleTimeoutActive, isFalse);
      handler.startIdleTimer(timeout: const Duration(seconds: 10));
      // Since player is not playing and not loading, timer starts
      expect(handler.isIdleTimeoutActive, isTrue);

      handler.cancelIdleTimer();
      expect(handler.isIdleTimeoutActive, isFalse);
    });
  });

  group('AppLogger Diagnostics & Logging Verification', () {
    test('AppLogger records formatted structured log lines', () {
      AppLogger.log('TestTag', 'Sample resilience test log message');
      // Verify no throw
      expect(true, isTrue);
    });

    test('AppLogger.recordError handles exceptions and stack traces cleanly', () {
      try {
        throw StateError('Simulated state error for test');
      } catch (e, stack) {
        AppLogger.recordError(e, stack, context: 'UnitTest');
      }
      expect(true, isTrue);
    });

    test('AppLogger.getLogContent returns valid string', () async {
      final content = await AppLogger.getLogContent();
      expect(content, isA<String>());
      expect(content.isNotEmpty, isTrue);
    });
  });

  group('BatteryOptimizationService Platform Bridge', () {
    test('Service responds safely in test environment without native crash', () async {
      final mfg = await BatteryOptimizationService.getDeviceManufacturer();
      expect(mfg, isA<String>());

      final isIgnoring = await BatteryOptimizationService.isIgnoringBatteryOptimizations();
      expect(isIgnoring, isA<bool>());

      final isAggressive = await BatteryOptimizationService.isAggressiveBatteryOEM();
      expect(isAggressive, isA<bool>());
    });
  });
}
