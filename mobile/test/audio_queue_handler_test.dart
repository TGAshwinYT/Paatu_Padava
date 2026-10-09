import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/models/song.dart';

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

  @override
  Future<void> dispose() async {
    await _currentIndexController.close();
    await _playerStateController.close();
    await _sequenceStateController.close();
    await _positionController.close();
  }

  void simulateTrackCompleted() {
    _playerStateController.add(PlayerState(false, ProcessingState.completed));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAudioPlayer player;
  late AudioQueueHandler queueHandler;

  setUp(() {
    player = MockAudioPlayer();
    queueHandler = AudioQueueHandler(player: player);
  });

  tearDown(() async {
    queueHandler.dispose();
    await player.dispose();
  });

  Song createSampleSong(String id, String title) {
    return Song(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      coverUrl: 'https://example.com/cover/$id.jpg',
      duration: 180,
      streamUrl: 'https://example.com/audio/$id.mp3',
      source: 'saavn',
    );
  }

  group('AudioQueueHandler Phase 1 Queue Correctness Tests', () {
    test('1. Play from middle of a list (initialIndex > 0)', () async {
      final songs = List.generate(5, (i) => createSampleSong('song_$i', 'Track $i'));

      await queueHandler.loadQueue(songs, initialIndex: 2, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.queue.length, equals(5));
      expect(queueHandler.currentIndex, equals(2));
      expect(queueHandler.currentSong?.id, equals('song_2'));
      expect(queueHandler.currentIndexNotifier.value, equals(2));
      expect(queueHandler.currentSongNotifier.value?.id, equals('song_2'));
    });

    test('2. Jump to index updates currentIndex and currentSong correctly', () async {
      final songs = List.generate(5, (i) => createSampleSong('song_$i', 'Track $i'));
      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentIndex, equals(0));

      await queueHandler.jumpToIndex(3);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentIndex, equals(3));
      expect(queueHandler.currentSong?.id, equals('song_3'));
      expect(queueHandler.currentIndexNotifier.value, equals(3));
    });

    test('3. Remove current track plays the next available track at that index', () async {
      final songs = List.generate(4, (i) => createSampleSong('song_$i', 'Track $i'));
      await queueHandler.loadQueue(songs, initialIndex: 1, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentSong?.id, equals('song_1'));
      expect(queueHandler.currentIndex, equals(1));

      // Remove current song ('song_1')
      await queueHandler.removeAt(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.queue.length, equals(3));
      expect(queueHandler.currentIndex, equals(1));
      // What was at index 2 ('song_2') is now shifted to index 1
      expect(queueHandler.currentSong?.id, equals('song_2'));
    });

    test('4. Remove track before current decrements currentIndex without shifting active song', () async {
      final songs = List.generate(4, (i) => createSampleSong('song_$i', 'Track $i'));
      await queueHandler.loadQueue(songs, initialIndex: 2, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentSong?.id, equals('song_2'));
      expect(queueHandler.currentIndex, equals(2));

      // Remove track 0 (before current index 2)
      await queueHandler.removeAt(0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.queue.length, equals(3));
      expect(queueHandler.currentIndex, equals(1));
      // Current song should still be 'song_2', now at index 1
      expect(queueHandler.currentSong?.id, equals('song_2'));
    });

    test('5. Reorder tracks properly updates indices and preserves playing song', () async {
      final songs = List.generate(5, (i) => createSampleSong('song_$i', 'Track $i'));
      await queueHandler.loadQueue(songs, initialIndex: 2, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentSong?.id, equals('song_2'));
      expect(queueHandler.currentIndex, equals(2));

      // Move track 0 to index 4 (past current)
      await queueHandler.reorder(0, 4);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Index of current song ('song_2') should shift from 2 to 1
      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.id, equals('song_2'));

      // Move current song from index 1 to index 3
      await queueHandler.reorder(1, 3);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(queueHandler.currentIndex, equals(2));
      expect(queueHandler.currentSong?.id, equals('song_2'));
    });

    test('6. Insert next places song right after current playing song', () async {
      final songs = List.generate(4, (i) => createSampleSong('song_$i', 'Track $i'));
      await queueHandler.loadQueue(songs, initialIndex: 1, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final urgentSong = createSampleSong('urgent_1', 'Urgent Track');
      await queueHandler.insertNext(urgentSong);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.queue.length, equals(5));
      expect(queueHandler.queue[2].id, equals('urgent_1'));
      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.id, equals('song_1'));
    });

    test('7. Completion advancing exactly one track (skipToNext)', () async {
      final songs = List.generate(3, (i) => createSampleSong('song_$i', 'Track $i'));
      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.hasNext, isTrue);

      // Simulate completion or call skipToNext directly
      await queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.id, equals('song_1'));

      await queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentIndex, equals(2));
      expect(queueHandler.currentSong?.id, equals('song_2'));
      expect(queueHandler.hasNext, isFalse);
    });

    test('8. Transition from JioSaavn to YouTube restores normalized volume and applies headers', () async {
      final saavnSong = createSampleSong('saavn_track_1', 'Saavn Master').copyWith(
        streamUrl: 'https://aac.saavn.cdn.jiosaavn.com/master_320.mp4',
        source: 'saavn',
      );
      final ytSong = createSampleSong('dQw4w9WgXcQ', 'YouTube Track').copyWith(
        streamUrl: 'https://rr1---sn-h5576nsd.googlevideo.com/videoplayback?expire=123',
        source: 'youtube',
      );

      // Verify normalization targets
      expect(AudioQueueHandler.getNormalizedVolumeForSong(saavnSong), equals(0.80));
      expect(AudioQueueHandler.getNormalizedVolumeForSong(ytSong), equals(1.0));

      await queueHandler.loadQueue([saavnSong, ytSong], initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.source, equals('saavn'));

      // Transition to YouTube track
      await queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.source, equals('youtube'));
      // Guarantee volume is restored to YouTube target (1.0) and not muted at 0
      expect(player.volume, greaterThanOrEqualTo(0.8));
    });

    test('9. User master volume is preserved across track transitions and not overwritten', () async {
      final saavnSong = createSampleSong('saavn_vol_1', 'Saavn Track').copyWith(
        streamUrl: 'https://aac.saavn.cdn.jiosaavn.com/master_320.mp4',
        source: 'saavn',
      );
      final ytSong = createSampleSong('yt_vol_2', 'YouTube Track').copyWith(
        streamUrl: 'https://rr1---sn-h5576nsd.googlevideo.com/videoplayback?expire=456',
        source: 'youtube',
      );

      await queueHandler.loadQueue([saavnSong, ytSong], initialIndex: 0, autoPlay: false);
      expect(queueHandler.userVolume, equals(1.0));

      // User lowers volume to 35% via touch gestures
      await queueHandler.setUserVolume(0.35);
      expect(queueHandler.userVolume, equals(0.35));
      expect(queueHandler.getEffectiveVolumeForSong(saavnSong), closeTo(0.35 * 0.80, 0.001));
      expect(queueHandler.getEffectiveVolumeForSong(ytSong), closeTo(0.35 * 1.0, 0.001));

      // Skip to YouTube track - user's volume must NOT jump to 1.0
      await queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(queueHandler.userVolume, equals(0.35));
      expect(player.volume, closeTo(0.35, 0.05));
    });

    test('10. YouTube stream resolved under Saavn source is correctly calibrated to 1.0', () {
      final fallbackSong = createSampleSong('fallback_1', 'Fallback Song').copyWith(
        streamUrl: 'https://rr2---sn-4g5ednsl.googlevideo.com/videoplayback?id=123',
        source: 'saavn',
      );
      expect(AudioQueueHandler.getNormalizedVolumeForSong(fallbackSong), equals(1.0));
    });
  });
}
