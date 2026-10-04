import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/models/song.dart';

/// Lightweight mock player for queue index alignment tests.
/// Verifies that queue index and player index stay synchronized
/// across loadQueue, jumpToIndex, skipToNext, and skipToPrevious.
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

  Song song(int i) => Song(
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

  const tick = Duration(milliseconds: 50);

  group('Queue Playback Alignment — Middle-of-List Start', () {
    test('Starting from index 7 of 15 songs keeps queue[i].id == currentSong.id at every step', () async {
      final songs = List.generate(15, (i) => song(i));
      await handler.loadQueue(songs, initialIndex: 7, autoPlay: false);
      await Future<void>.delayed(tick);

      // Verify initial alignment
      expect(handler.currentIndex, equals(7));
      expect(handler.currentSong?.id, equals('q_7'));
      expect(handler.currentSongNotifier.value?.id, equals('q_7'));
      expect(handler.queue[handler.currentIndex].id, equals(handler.currentSong?.id),
          reason: 'queue[currentIndex] must match currentSong after loadQueue');

      // Walk forward through every remaining track
      for (int expected = 8; expected < 15; expected++) {
        await handler.skipToNext();
        await Future<void>.delayed(tick);

        expect(handler.currentIndex, equals(expected),
            reason: 'After skip #${expected - 7}, index should be $expected');
        expect(handler.currentSong?.id, equals('q_$expected'));
        expect(handler.queue[handler.currentIndex].id, equals(handler.currentSong?.id),
            reason: 'queue[currentIndex] must match currentSong at index $expected');
      }

      // At end, no more next
      expect(handler.hasNext, isFalse);
    });

    test('jumpToIndex from middle keeps alignment across arbitrary jumps', () async {
      final songs = List.generate(10, (i) => song(i));
      await handler.loadQueue(songs, initialIndex: 5, autoPlay: false);
      await Future<void>.delayed(tick);

      expect(handler.currentIndex, equals(5));
      expect(handler.queue[5].id, equals(handler.currentSong?.id));

      // Jump backward
      await handler.jumpToIndex(2);
      await Future<void>.delayed(tick);
      expect(handler.currentIndex, equals(2));
      expect(handler.currentSong?.id, equals('q_2'));
      expect(handler.queue[handler.currentIndex].id, equals(handler.currentSong?.id));

      // Jump forward past original start
      await handler.jumpToIndex(8);
      await Future<void>.delayed(tick);
      expect(handler.currentIndex, equals(8));
      expect(handler.currentSong?.id, equals('q_8'));
      expect(handler.queue[handler.currentIndex].id, equals(handler.currentSong?.id));

      // Jump to first
      await handler.jumpToIndex(0);
      await Future<void>.delayed(tick);
      expect(handler.currentIndex, equals(0));
      expect(handler.currentSong?.id, equals('q_0'));
      expect(handler.queue[handler.currentIndex].id, equals(handler.currentSong?.id));
    });

    test('Remove + reorder from middle-start preserves correct alignment', () async {
      final songs = List.generate(8, (i) => song(i));
      await handler.loadQueue(songs, initialIndex: 4, autoPlay: false);
      await Future<void>.delayed(tick);

      expect(handler.currentSong?.id, equals('q_4'));

      // Remove track before current (index 1)
      await handler.removeAt(1);
      await Future<void>.delayed(tick);
      // Current should shift down by 1 but same song
      expect(handler.currentSong?.id, equals('q_4'));
      expect(handler.queue[handler.currentIndex].id, equals('q_4'));

      // Remove track after current
      final afterIdx = handler.currentIndex + 1;
      if (afterIdx < handler.queue.length) {
        final removedId = handler.queue[afterIdx].id;
        await handler.removeAt(afterIdx);
        await Future<void>.delayed(tick);
        expect(handler.currentSong?.id, equals('q_4'), reason: 'Current song unchanged after removing a later track');
        expect(handler.queue[handler.currentIndex].id, equals('q_4'));
        // Verify removed track is actually gone
        expect(handler.queue.any((s) => s.id == removedId), isFalse);
      }
    });

    test('Notifiers stay in sync with queue state after every operation', () async {
      final songs = List.generate(6, (i) => song(i));
      await handler.loadQueue(songs, initialIndex: 3, autoPlay: false);
      await Future<void>.delayed(tick);

      // Check all three notifiers agree
      void assertNotifiersInSync(String label) {
        expect(handler.currentIndexNotifier.value, equals(handler.currentIndex),
            reason: '$label: currentIndexNotifier out of sync');
        expect(handler.currentSongNotifier.value?.id, equals(handler.currentSong?.id),
            reason: '$label: currentSongNotifier out of sync');
        expect(handler.queueNotifier.value.length, equals(handler.queue.length),
            reason: '$label: queueNotifier length out of sync');
      }

      assertNotifiersInSync('After loadQueue');

      await handler.skipToNext();
      await Future<void>.delayed(tick);
      assertNotifiersInSync('After skipToNext');

      await handler.jumpToIndex(0);
      await Future<void>.delayed(tick);
      assertNotifiersInSync('After jumpToIndex(0)');

      await handler.removeAt(2);
      await Future<void>.delayed(tick);
      assertNotifiersInSync('After removeAt(2)');

      final newSong = song(99);
      await handler.insertNext(newSong);
      await Future<void>.delayed(tick);
      assertNotifiersInSync('After insertNext');
    });
  });
}
