import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/sleep_timer_service.dart';

/// Lightweight mock player for queue alignment and anti-double-skip testing.
class _MockPlayer extends Fake implements AudioPlayer {
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
  LoopMode _loopMode = LoopMode.off;

  @override LoopMode get loopMode => _loopMode;
  @override Future<void> setLoopMode(LoopMode mode) async => _loopMode = mode;
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

  void emitState(PlayerState s) {
    _playing = s.playing;
    _stateCtrl.add(s);
  }

  void emitPosition(Duration p) {
    _position = p;
    _posCtrl.add(p);
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

  late _MockPlayer player;
  late AudioQueueHandler handler;

  Song createTestSong(int i) => Song(
    id: 'q_$i',
    title: 'Queue Track $i',
    artist: 'Artist ${i % 3}',
    album: 'Album',
    coverUrl: 'https://x.com/$i.jpg',
    duration: 200,
    streamUrl: 'https://x.com/$i.mp3',
    source: 'saavn',
  );

  setUp(() {
    player = _MockPlayer();
    handler = AudioQueueHandler(player: player);
  });

  tearDown(() async {
    handler.dispose();
    await player.dispose();
  });

  const tick = Duration(milliseconds: 60);

  group('BloomeeTunes Queue State Machine Alignment & Anti-Double-Skip', () {
    test('Test 1: Firing ProcessingState.completed twice for the same track only advances by 1 song', () async {
      final songs = List.generate(5, (i) => createTestSong(i));
      await handler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      expect(handler.currentSong?.id, equals('q_0'));

      // Simulate ExoPlayer/just_audio firing ProcessingState.completed twice consecutively
      player.emitState(PlayerState(true, ProcessingState.completed));
      player.emitState(PlayerState(true, ProcessingState.completed));
      await Future<void>.delayed(tick);

      // Mutex and _lastCompletedTrackId lock must prevent double-skipping to q_2
      expect(handler.currentSong?.id, equals('q_1'),
          reason: 'Duplicate ProcessingState.completed must only advance queue by exactly 1 track');

      // Now simulate track q_1 actually playing (position > Duration.zero)
      player.emitPosition(const Duration(seconds: 2));
      await Future<void>.delayed(tick);

      // Track q_1 completes naturally
      player.emitState(PlayerState(true, ProcessingState.completed));
      await Future<void>.delayed(tick);

      // Now advances cleanly to q_2
      expect(handler.currentSong?.id, equals('q_2'),
          reason: 'Next track completes naturally after lock reset');
    });

    test('Test 2: loadQueue on 10-song playlist at initialIndex: 4 has playedTracks.isEmpty and in-place skipToQueueItem', () async {
      final songs = List.generate(10, (i) => createTestSong(i));
      await handler.loadQueue(songs, initialIndex: 4, autoPlay: true);
      await Future<void>.delayed(tick);

      // 1. Initial State: Unplayed songs 0..3 are NOT shown as played!
      expect(handler.playedTracks.isEmpty, isTrue,
          reason: 'Unplayed songs 0..3 must NOT show up in playedTracks when starting playlist at index 4');
      expect(handler.currentSong?.id, equals('q_4'),
          reason: 'Target track from initialIndex: 4 is playing');
      expect(handler.currentIndex, equals(0),
          reason: 'Active track is at context index 0 in rotated context queue');
      expect(handler.queue.length, equals(10),
          reason: 'Total queue contains all 10 tracks');

      // Unplayed songs 0..3 are at the tail of Up Next (ordered: 4, 5, 6, 7, 8, 9, 0, 1, 2, 3)
      final queueIds = handler.queue.map((s) => s.id).toList();
      expect(queueIds, equals(['q_4', 'q_5', 'q_6', 'q_7', 'q_8', 'q_9', 'q_0', 'q_1', 'q_2', 'q_3']));

      // 2. Tapping a song in Up Next (e.g. q_7) jumps in-place WITHOUT queue duplication
      final targetTrack = TrackEntity.fromSong(createTestSong(7));
      await handler.skipToQueueItem(targetTrack);
      await Future<void>.delayed(tick);

      expect(handler.currentSong?.id, equals('q_7'),
          reason: 'Current song must jump directly to tapped track');
      expect(handler.queue.length, equals(10),
          reason: 'Tapping a track in Up Next must NOT add or duplicate songs in queue');
      expect(handler.playedTracks.length, equals(1),
          reason: 'Previously active song q_4 is now recorded in playedTracks');
      expect(handler.playedTracks.first.id, equals('q_4'));
    });

    test('skipToQueueItem in userQueue and playedTracks preserves queue size', () async {
      final songs = List.generate(6, (i) => createTestSong(i));
      await handler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      // Add user queued tracks
      final urgentTrack = createTestSong(99);
      await handler.insertNext(urgentTrack);
      await Future<void>.delayed(tick);

      expect(handler.queue.length, equals(7));

      // Tap user queue track
      await handler.skipToQueueItem(TrackEntity.fromSong(urgentTrack), fromUserQueue: true);
      await Future<void>.delayed(tick);

      expect(handler.currentSong?.id, equals('q_99'));
      expect(handler.playedTracks.any((t) => t.id == 'q_0'), isTrue);

      // Tap previously played track (q_0) from history
      await handler.skipToQueueItem(TrackEntity.fromSong(createTestSong(0)), fromPlayedHistory: true);
      await Future<void>.delayed(tick);

      expect(handler.currentSong?.id, equals('q_0'));
      expect(handler.queue.length, equals(6));
    });
  });

  group('SleepTimerService Lifecycle, Countdown & Cancellation', () {
    test('Test 3: SleepTimerService custom duration countdown and cancellation', () async {
      final timer = SleepTimerService.instance;
      timer.cancel(); // Ensure clean initial state

      expect(timer.isActive, isFalse);
      expect(timer.remainingTime, equals(Duration.zero));

      // 1. Set custom timer for 2 seconds
      timer.setTimer(const Duration(seconds: 2));
      expect(timer.isActive, isTrue);
      expect(timer.remainingTime.inSeconds, equals(2));
      expect(timer.formattedRemainingShort, equals('00:02'));

      // Wait 1.1s for tick
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(timer.remainingTime.inSeconds, lessThanOrEqualTo(1));

      // 2. Add 5 minutes extension
      timer.addTime(const Duration(minutes: 5));
      expect(timer.remainingTime.inMinutes, greaterThanOrEqualTo(5));
      expect(timer.isActive, isTrue);

      // 3. Cancel timer
      timer.cancel();
      expect(timer.isActive, isFalse);
      expect(timer.remainingTime, equals(Duration.zero));
    });

    test('SleepTimerService stopAtEndOfTrack mode arms and completes on track finish', () async {
      final timer = SleepTimerService.instance;
      timer.cancel();

      timer.setTimer(Duration.zero, stopAtEnd: true);
      expect(timer.isActive, isTrue);
      expect(timer.stopAtEndOfTrack, isTrue);
      expect(timer.formattedRemaining, equals('End of Track'));
      expect(timer.formattedRemainingShort, equals('End'));

      timer.cancel();
      expect(timer.isActive, isFalse);
      expect(timer.stopAtEndOfTrack, isFalse);
    });
  });
}
