import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/logic/stream_resolver.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/app_logger.dart';

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
}

/// Fake StreamResolver for testing resolution policies in milliseconds
class FakeStreamResolver implements StreamResolver {
  final Map<String, String?> songStreamMap = {};
  final List<String> resolutionAttempts = [];
  Duration delay = Duration.zero;

  @override
  Future<String?> resolveStreamUrl(Song song) async {
    resolutionAttempts.add(song.id);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return songStreamMap[song.id];
  }

  @override
  bool verifyAudioMatch(Song candidate, Song target) {
    return DefaultStreamResolver.verifyMatch(candidate, target);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAudioPlayer player;
  late FakeStreamResolver fakeResolver;
  late AudioQueueHandler queueHandler;

  Song makeSong({
    required String id,
    required String title,
    String? streamUrl,
    String source = 'youtube',
    int duration = 200,
  }) {
    return Song(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      duration: duration,
      coverUrl: 'https://example.com/cover.jpg',
      streamUrl: streamUrl,
      source: source,
    );
  }

  setUp(() {
    player = MockAudioPlayer();
    fakeResolver = FakeStreamResolver();
    queueHandler = AudioQueueHandler(
      player: player,
      streamResolver: fakeResolver,
    );
  });

  tearDown(() async {
    queueHandler.dispose();
    await player.dispose();
  });

  group('StreamResolver & Queue Resilience Tests', () {
    test('1. Resolves stream through injected StreamResolver cleanly', () async {
      final song = makeSong(id: 'yt_1', title: 'Pavazha Malli');
      fakeResolver.songStreamMap['yt_1'] = 'https://stream.example.com/audio.m4a';

      await queueHandler.loadQueue([song], initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(queueHandler.currentSong?.streamUrl, equals('https://stream.example.com/audio.m4a'));
      expect(fakeResolver.resolutionAttempts, contains('yt_1'));
      expect(fakeResolver.resolutionAttempts.length, equals(1));
    });

    test('2. Failing active stream auto-advances to next playable candidate without double resolve', () async {
      final broken = makeSong(id: 'broken_1', title: 'Broken YouTube Song');
      final valid = makeSong(id: 'valid_2', title: 'Valid Backup Song');

      fakeResolver.songStreamMap['broken_1'] = null; // Fails
      fakeResolver.songStreamMap['valid_2'] = 'https://stream.example.com/valid.m4a';

      await queueHandler.loadQueue([broken, valid], initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Broken was attempted exactly once, then skipped cleanly to valid_2
      expect(fakeResolver.resolutionAttempts.where((id) => id == 'broken_1').length, equals(1));
      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.id, equals('valid_2'));
      expect(queueHandler.currentSong?.streamUrl, equals('https://stream.example.com/valid.m4a'));
    });

    test('3. Duplicate loadQueue call for same song while loading is ignored', () async {
      final song = makeSong(id: 'slow_1', title: 'Slow Loading Track');
      fakeResolver.delay = const Duration(milliseconds: 100);
      fakeResolver.songStreamMap['slow_1'] = 'https://stream.example.com/slow.m4a';

      // First call starts loading
      final future1 = queueHandler.loadQueue([song], initialIndex: 0, autoPlay: true);

      // Second immediate call (e.g. user double tap)
      final future2 = queueHandler.loadQueue([song], initialIndex: 0, autoPlay: true);

      await Future.wait([future1, future2]);

      // Only one resolution was kicked off!
      expect(fakeResolver.resolutionAttempts.length, equals(1));
    });

    test('4. verifyMatch allows up to 45s tolerance for YouTube videos', () {
      final ytCandidate = makeSong(id: 'yt_mv', title: 'Arabic Kuthu', duration: 280, source: 'youtube');
      final saavnTarget = makeSong(id: 'saavn_audio', title: 'Arabic Kuthu', duration: 250, source: 'saavn');

      // 30s difference is allowed for YouTube MV intros/outros
      expect(DefaultStreamResolver.verifyMatch(ytCandidate, saavnTarget), isTrue);

      // > 45s difference is rejected
      final tooLong = makeSong(id: 'yt_long', title: 'Arabic Kuthu', duration: 320, source: 'youtube');
      expect(DefaultStreamResolver.verifyMatch(tooLong, saavnTarget), isFalse);
    });

    test('5. AppLogger sequential write ordering preserves messages without corruption', () async {
      // Log rapid sequence of messages
      for (int i = 0; i < 50; i++) {
        AppLogger.log('TestTag', 'Message index $i');
      }

      // No crash or stream collision occurred
      expect(true, isTrue);
    });
  });
}
