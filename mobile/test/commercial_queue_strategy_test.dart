import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/models/song.dart';

class _MockPlayer extends Fake implements AudioPlayer {
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

  @override Stream<int?> get currentIndexStream => _currentIndexController.stream;
  @override Stream<PlayerState> get playerStateStream => _playerStateController.stream;
  @override Stream<SequenceState?> get sequenceStateStream => _sequenceStateController.stream;
  @override Stream<Duration> get positionStream => _positionController.stream;
  @override double get volume => _volume;
  @override bool get playing => _playing;
  @override Duration get position => _position;
  @override Duration? get duration => _duration;
  @override AudioSource? get audioSource => _audioSource;
  @override LoopMode get loopMode => _loopMode;

  @override
  Future<void> setVolume(double value) async {
    _volume = value;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
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
  Future<void> seek(Duration? pos, {int? index}) async {
    if (pos != null) {
      _position = pos;
      _positionController.add(pos);
    }
    if (index != null) {
      _sourceIndex = index;
      _currentIndexController.add(index);
    }
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

  late _MockPlayer player;
  late AudioQueueHandler queueHandler;

  setUp(() {
    player = _MockPlayer();
    queueHandler = AudioQueueHandler(player: player);
  });

  tearDown(() async {
    queueHandler.dispose();
    await player.dispose();
  });

  Song createSampleSong(String id, String title, {bool isUserEnqueued = false}) {
    return Song(
      id: id,
      title: title,
      artist: 'Artist',
      album: 'Album',
      coverUrl: 'https://example.com/cover/$id.jpg',
      duration: 180,
      streamUrl: 'https://example.com/audio/$id.mp3',
      source: 'saavn',
      isUserEnqueued: isUserEnqueued,
    );
  }

  group('Commercial Streaming Queue Architecture Tests (Spotify & YouTube Music)', () {
    test('1. "Add to Queue" Dual-Queue Priority: appends to user queue block before context queue', () async {
      // 20-track album
      final albumTracks = List.generate(20, (i) => createSampleSong('album_$i', 'Album Track ${i + 1}'));
      await queueHandler.loadQueue(albumTracks, initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('album_0'));
      expect(queueHandler.getPendingUserQueueCount(), equals(0));
      expect(queueHandler.userQueueEndIndex, equals(1));

      // 1. User selects "Add to Queue" on User Song 1
      final userSong1 = createSampleSong('user_1', 'User Song 1');
      await queueHandler.addToQueue(userSong1);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // In Spotify / YT Music, User Song 1 is at index 1 (right after now playing),
      // NOT sent to index 21 at the end of the 20-track album!
      expect(queueHandler.queue.length, equals(21));
      expect(queueHandler.queue[1].id, equals('user_1'));
      expect(queueHandler.queue[1].isUserEnqueued, isTrue);
      expect(queueHandler.queue[2].id, equals('album_1')); // Next album track pushed to index 2
      expect(queueHandler.getPendingUserQueueCount(), equals(1));
      expect(queueHandler.userQueueEndIndex, equals(2));

      // 2. User selects "Add to Queue" on User Song 2
      final userSong2 = createSampleSong('user_2', 'User Song 2');
      await queueHandler.addToQueue(userSong2);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Appends right after User Song 1 (at index 2), before album track 1 (now index 3)
      expect(queueHandler.queue.length, equals(22));
      expect(queueHandler.queue[1].id, equals('user_1'));
      expect(queueHandler.queue[2].id, equals('user_2'));
      expect(queueHandler.queue[2].isUserEnqueued, isTrue);
      expect(queueHandler.queue[3].id, equals('album_1'));
      expect(queueHandler.getPendingUserQueueCount(), equals(2));
      expect(queueHandler.userQueueEndIndex, equals(3));

      // 3. User selects "Play Next" on Urgent Song
      // Play Next has O(1) immediate priority: inserts at currentIndex + 1 (index 1)
      final urgentSong = createSampleSong('urgent_1', 'Urgent Track');
      await queueHandler.insertNext(urgentSong);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.queue.length, equals(23));
      expect(queueHandler.queue[1].id, equals('urgent_1'));
      expect(queueHandler.queue[2].id, equals('user_1'));
      expect(queueHandler.queue[3].id, equals('user_2'));
      expect(queueHandler.queue[4].id, equals('album_1'));
      expect(queueHandler.getPendingUserQueueCount(), equals(3));
      expect(queueHandler.userQueueEndIndex, equals(4));

      // 4. User selects "Add to Queue" on User Song 3
      final userSong3 = createSampleSong('user_3', 'User Song 3');
      await queueHandler.addToQueue(userSong3);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.queue[1].id, equals('urgent_1'));
      expect(queueHandler.queue[2].id, equals('user_1'));
      expect(queueHandler.queue[3].id, equals('user_2'));
      expect(queueHandler.queue[4].id, equals('user_3'));
      expect(queueHandler.queue[5].id, equals('album_1'));
    });

    test('2. "Play Next" Under Shuffle: inserts at currentShuffleIndex + 1 and plays immediately next', () async {
      final songs = List.generate(10, (i) => createSampleSong('song_$i', 'Track $i'));
      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Enable shuffle mode
      await queueHandler.setShuffleEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.isShuffleEnabled, isTrue);
      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('song_0'));

      // User selects "Play Next" on New Shuffled Next Track
      final playNextSong = createSampleSong('play_next_1', 'Play Next Track');
      await queueHandler.insertNext(playNextSong);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Must be inserted at currentShuffleIndex + 1 (index 1) in active queue
      expect(queueHandler.queue[1].id, equals('play_next_1'));
      expect(queueHandler.queue[1].isUserEnqueued, isTrue);

      // Verify track was added to the decoupled userQueue with FIFO priority, not corrupting contextQueue
      expect(queueHandler.userQueue.isNotEmpty, isTrue);
      expect(queueHandler.userQueue.first.id, equals('play_next_1'));
      expect(queueHandler.contextQueue.any((s) => s.id == 'play_next_1'), isFalse);

      // Skip to next track: player MUST play the newly selected track immediately!
      await queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.id, equals('play_next_1'));
    });

    test('3. RepeatMode.all Looping: transient user-enqueued tracks are discarded upon loop', () async {
      // 3-track album: [album_0, album_1, album_2]
      final albumTracks = List.generate(3, (i) => createSampleSong('album_$i', 'Album $i'));
      await queueHandler.loadQueue(albumTracks, initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Set repeat mode to all
      await player.setLoopMode(LoopMode.all);

      // User queues a transient song
      final userSong = createSampleSong('user_transient', 'Transient Song');
      await queueHandler.addToQueue(userSong);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Queue is: [album_0, user_transient, album_1, album_2]
      expect(queueHandler.queue.length, equals(4));
      expect(queueHandler.queue[1].id, equals('user_transient'));

      // Play through album_0 -> user_transient -> album_1 -> album_2
      await queueHandler.jumpToIndex(3); // Now playing album_2 (last track)
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(queueHandler.currentSong?.id, equals('album_2'));
      expect(queueHandler.hasNext, isFalse);

      // Advance at EOF under RepeatMode.all
      await queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Looped back to start: transient user-enqueued song MUST BE DISCARDED!
      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('album_0'));
      expect(queueHandler.queue.length, equals(3));
      expect(queueHandler.queue.any((s) => s.id == 'user_transient'), isFalse);
      expect(queueHandler.queue.map((s) => s.id).toList(), equals(['album_0', 'album_1', 'album_2']));
    });

    test('4. Dual-queue user block preserved when toggling shuffle OFF', () async {
      final albumTracks = List.generate(5, (i) => createSampleSong('album_$i', 'Album $i'));
      await queueHandler.loadQueue(albumTracks, initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Enable shuffle
      await queueHandler.setShuffleEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // User adds a song to queue while in shuffle mode
      final userSong = createSampleSong('user_shuffle', 'User Shuffle Song');
      await queueHandler.addToQueue(userSong);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.queue[1].id, equals('user_shuffle'));

      // Toggle shuffle OFF:
      await queueHandler.setShuffleEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // User song MUST still be placed immediately following the active track
      expect(queueHandler.isShuffleEnabled, isFalse);
      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('album_0'));
      expect(queueHandler.queue[1].id, equals('user_shuffle'));
      expect(queueHandler.queue[1].isUserEnqueued, isTrue);
      expect(queueHandler.queue[2].id, equals('album_1'));
    });

    test('5. addAllToQueue inserts multiple tracks sequentially into the user queue block', () async {
      final albumTracks = List.generate(10, (i) => createSampleSong('album_$i', 'Album $i'));
      await queueHandler.loadQueue(albumTracks, initialIndex: 2, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // User is on Album Track 2 (index 2). Adds 3 tracks via addAllToQueue
      final batch = [
        createSampleSong('batch_1', 'Batch 1'),
        createSampleSong('batch_2', 'Batch 2'),
        createSampleSong('batch_3', 'Batch 3'),
      ];
      await queueHandler.addAllToQueue(batch);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.queue.length, equals(13));
      expect(queueHandler.queue[3].id, equals('batch_1'));
      expect(queueHandler.queue[4].id, equals('batch_2'));
      expect(queueHandler.queue[5].id, equals('batch_3'));
      expect(queueHandler.queue[6].id, equals('album_3')); // Next album track shifted to 6
    });

    test('6. "Play Next" completion cleanly resumes album context sequence at contextIndex + 1 without jumping to Auto-Suggestion', () async {
      // 5-track album: [album_0, album_1, album_2, album_3, album_4]
      final albumTracks = List.generate(5, (i) => createSampleSong('album_$i', 'Album $i'));
      await queueHandler.loadQueue(albumTracks, initialIndex: 1, autoPlay: false); // Playing album_1
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.currentSong?.id, equals('album_1'));
      expect(queueHandler.contextIndex, equals(1));

      // User selects "Play Next" for user_next
      final playNextSong = createSampleSong('user_next', 'User Next Song');
      await queueHandler.insertNext(playNextSong);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Play Next is immediately next in queue
      expect(queueHandler.queue[2].id, equals('user_next'));
      expect(queueHandler.userQueue.length, equals(1));

      // 1. Advance to user_next
      await queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(queueHandler.currentSong?.id, equals('user_next'));
      expect(queueHandler.currentTrackIsFromUserQueue, isTrue);
      // contextIndex remains anchored to 1
      expect(queueHandler.contextIndex, equals(1));

      // 2. Finished playing user_next -> Skip or complete track
      await queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // MUST resume album sequence at album_2 (contextIndex 2), NOT trigger auto-suggestion!
      expect(queueHandler.currentSong?.id, equals('album_2'));
      expect(queueHandler.currentTrackIsFromUserQueue, isFalse);
      expect(queueHandler.contextIndex, equals(2));
      expect(queueHandler.hasNext, isTrue);
    });
  });
}
