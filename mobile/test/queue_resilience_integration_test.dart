import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/logic/audio_queue_handler.dart';
import 'package:paatu_padava_mobile/logic/smart_shuffle_controller.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/domain/models/app_error.dart';
import 'package:paatu_padava_mobile/services/radio_engine.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';
import 'package:paatu_padava_mobile/services/api_client.dart';

/// Test mock player that tracks audio source state and allows simulating
/// playback transitions, seeking, and errors.
class _IntegrationMockPlayer extends Fake implements AudioPlayer {
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

  @override
  Future<void> setVolume(double v) async => _volume = v;

  @override
  Future<void> play() async {
    _playing = true;
    _stateCtrl.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _stateCtrl.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _stateCtrl.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource src, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    _audioSource = src;
    _sourceIndex = initialIndex ?? 0;
    _indexCtrl.add(_sourceIndex);
    return _dur;
  }

  @override
  Future<void> seek(Duration? pos, {int? index}) async {
    if (pos != null) {
      _position = pos;
      _posCtrl.add(pos);
    }
    if (index != null) {
      _sourceIndex = index;
      _indexCtrl.add(index);
    }
  }

  void simulateTrackTransition(int nextIndex) {
    _sourceIndex = nextIndex;
    _indexCtrl.add(nextIndex);
  }

  @override
  Future<void> dispose() async {
    await _indexCtrl.close();
    await _stateCtrl.close();
    await _seqCtrl.close();
    await _posCtrl.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _IntegrationMockPlayer player;
  late AudioQueueHandler queueHandler;
  Song? changedSong;
  AppError? reportedError;

  setUp(() {
    player = _IntegrationMockPlayer();
    changedSong = null;
    reportedError = null;

    queueHandler = AudioQueueHandler(
      player: player,
      onSongChanged: (song) {
        changedSong = song;
      },
      onError: (err) {
        reportedError = err;
      },
    );
  });

  tearDown(() async {
    queueHandler.dispose();
    await player.dispose();
  });

  const tick = Duration(milliseconds: 60);

  Song makeSong({
    required String id,
    required String title,
    String? streamUrl,
    String source = 'saavn',
    String artist = 'Test Artist',
    String album = 'Test Album',
    String? language,
    int duration = 200,
  }) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      coverUrl: 'https://cdn.example.com/cover.jpg',
      duration: duration,
      streamUrl: streamUrl,
      source: source,
      language: language,
    );
  }

  group('Queue & Player Integration with Slow & Failing Streams (Item 16)', () {
    test('1. Multi-track queue plays through natural transitions and sequential skips', () async {
      final songs = [
        makeSong(id: 'track_1', title: 'Song One', streamUrl: 'https://stream.example.com/1.mp3'),
        makeSong(id: 'track_2', title: 'Song Two', streamUrl: 'https://stream.example.com/2.mp3'),
        makeSong(id: 'track_3', title: 'Song Three', streamUrl: 'https://stream.example.com/3.mp3'),
      ];

      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('track_1'));
      expect(player.playing, isTrue);

      // Advance through skipToNext
      await queueHandler.skipToNext();
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.id, equals('track_2'));
      expect(changedSong?.id, equals('track_2'));

      // Simulate natural completion transition to track 3
      player.simulateTrackTransition(2);
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(2));
      expect(queueHandler.currentSong?.id, equals('track_3'));
      expect(changedSong?.id, equals('track_3'));
    });

    test('2. Slow unresolved upcoming stream does not block current track playback', () async {
      final songs = [
        makeSong(id: 'fast_1', title: 'Fast Track', streamUrl: 'https://stream.example.com/fast.mp3'),
        // Track 2 has no streamUrl, requires resolution
        makeSong(id: 'slow_2', title: 'Slow Unresolved Track', streamUrl: null),
        makeSong(id: 'fast_3', title: 'Fast Track 3', streamUrl: 'https://stream.example.com/fast3.mp3'),
      ];

      // Load queue - track 1 should start playing immediately without waiting for track 2 resolution
      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('fast_1'));
      expect(player.playing, isTrue);

      // Preload upcoming tracks concurrently
      final preloadFuture = queueHandler.preloadUpcomingTracks(0);

      // Current playback remains active and untouched
      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('fast_1'));

      await preloadFuture;
      await Future<void>.delayed(tick);

      // Ensure queue structure is intact
      expect(queueHandler.queue.length, equals(3));
      expect(queueHandler.queue[1].id, equals('slow_2'));
    });

    test('3. Skipping past an in-flight slow resolution invalidates session token safely', () async {
      final songs = [
        makeSong(id: 'track_A', title: 'Track A', streamUrl: 'https://stream.example.com/a.mp3'),
        makeSong(id: 'track_B', title: 'Track B (Slow)', streamUrl: null),
        makeSong(id: 'track_C', title: 'Track C', streamUrl: 'https://stream.example.com/c.mp3'),
      ];

      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      // Start preloading upcoming track B
      final preload = queueHandler.preloadUpcomingTracks(0);

      // User immediately skips directly to track C before preload completes
      await queueHandler.jumpToIndex(2);
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(2));
      expect(queueHandler.currentSong?.id, equals('track_C'));

      // Wait for background preload to finish
      await preload;
      await Future<void>.delayed(tick);

      // Active song must still be Track C (obsolete resolution did not overwrite current track)
      expect(queueHandler.currentIndex, equals(2));
      expect(queueHandler.currentSong?.id, equals('track_C'));
    });

    test('4. Failing stream resolution triggers safe error handling without crashing pipeline', () async {
      final songs = [
        makeSong(id: 'unplayable_1', title: 'Broken Unresolvable', streamUrl: null, source: 'unknown_source'),
        makeSong(id: 'playable_2', title: 'Playable Backup', streamUrl: 'https://stream.example.com/good.mp3'),
      ];

      // Loading a queue with an initially unresolvable track
      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(tick);

      // Queue initialized safely with fallback
      expect(queueHandler.queue.length, equals(2));
      expect(queueHandler.errorNotifier.value, isNotNull);
      expect(queueHandler.errorNotifier.value?.category, equals(AppErrorCategory.songUnavailable));
      expect(reportedError, isNotNull);
      expect(reportedError?.category, equals(AppErrorCategory.songUnavailable));

      // Player should be able to skip to next playable track cleanly
      await queueHandler.skipToNext();
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.id, equals('playable_2'));
    });

    test('5. Reordering queue while playback is active preserves active song identity', () async {
      final songs = [
        makeSong(id: 'playing_0', title: 'Current Song', streamUrl: 'https://stream.example.com/0.mp3'),
        makeSong(id: 'next_1', title: 'Next Song', streamUrl: 'https://stream.example.com/1.mp3'),
        makeSong(id: 'later_2', title: 'Later Song', streamUrl: 'https://stream.example.com/2.mp3'),
      ];

      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('playing_0'));

      // Move next_1 (index 1) to position after later_2 (index 2 -> ReorderableListView uses drop index 3)
      await queueHandler.reorder(1, 3);
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(0));
      expect(queueHandler.currentSong?.id, equals('playing_0'));
      expect(queueHandler.queue[1].id, equals('later_2'));
      expect(queueHandler.queue[2].id, equals('next_1'));
    });

    test('6. Selecting non-zero index in a playlist plays the exact selected song, not the next song', () async {
      final songs = [
        makeSong(id: 'song_0', title: 'First Song', streamUrl: 'https://stream.example.com/0.mp3'),
        makeSong(id: 'song_1', title: 'Second Song (Clicked)', streamUrl: 'https://stream.example.com/1.mp3'),
        makeSong(id: 'song_2', title: 'Third Song', streamUrl: 'https://stream.example.com/2.mp3'),
        makeSong(id: 'song_3', title: 'Fourth Song', streamUrl: 'https://stream.example.com/3.mp3'),
      ];

      // User selects song 1 from the playlist
      await queueHandler.loadQueue(songs, initialIndex: 1, autoPlay: true);
      await Future<void>.delayed(tick);

      // Must be Song 1 (not Song 2!)
      expect(queueHandler.currentIndex, equals(1));
      expect(queueHandler.currentSong?.id, equals('song_1'));
      expect(changedSong?.id, equals('song_1'));
      expect(player._sourceIndex, equals(0)); // Player window starts at 0 for active song!

      // Now skip to next
      await queueHandler.skipToNext();
      await Future<void>.delayed(tick);
      expect(queueHandler.currentIndex, equals(2));
      expect(queueHandler.currentSong?.id, equals('song_2'));
    });

    test('7. Adding to queue operates as stack (LIFO next priority) tagged as user-enqueued', () async {
      final songs = [
        makeSong(id: 'active_0', title: 'Active Playing', streamUrl: 'https://stream.example.com/0.mp3'),
        makeSong(id: 'playlist_1', title: 'Playlist Song 1', streamUrl: 'https://stream.example.com/1.mp3'),
      ];

      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      expect(queueHandler.currentIndex, equals(0));

      // User queues track A
      final userTrackA = makeSong(id: 'user_A', title: 'User Track A', streamUrl: 'https://stream.example.com/a.mp3');
      await queueHandler.addToQueue(userTrackA);
      await Future<void>.delayed(tick);

      // User queues track B (pushed onto stack ahead of track A)
      final userTrackB = makeSong(id: 'user_B', title: 'User Track B', streamUrl: 'https://stream.example.com/b.mp3');
      await queueHandler.addToQueue(userTrackB);
      await Future<void>.delayed(tick);

      // Queue order must be: [active_0, user_B, user_A, playlist_1]
      expect(queueHandler.queue[0].id, equals('active_0'));
      expect(queueHandler.queue[1].id, equals('user_B'));
      expect(queueHandler.queue[1].isUserEnqueued, isTrue);
      expect(queueHandler.queue[2].id, equals('user_A'));
      expect(queueHandler.queue[2].isUserEnqueued, isTrue);
      expect(queueHandler.queue[3].id, equals('playlist_1'));
      expect(queueHandler.queue[3].isUserEnqueued, isFalse);

      // Skipping next plays user_B
      await queueHandler.skipToNext();
      await Future<void>.delayed(tick);
      expect(queueHandler.currentSong?.id, equals('user_B'));

      // Skipping next plays user_A
      await queueHandler.skipToNext();
      await Future<void>.delayed(tick);
      expect(queueHandler.currentSong?.id, equals('user_A'));
    });

    test('8. Auto-suggestions append to queue end, and clearUserQueue removes stack tracks', () async {
      final songs = [
        makeSong(id: 'active_0', title: 'Active Playing', streamUrl: 'https://stream.example.com/0.mp3'),
      ];

      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      // Push user song to stack
      final userSong = makeSong(id: 'user_1', title: 'User Priority', streamUrl: 'https://stream.example.com/u1.mp3');
      await queueHandler.addToQueue(userSong);
      await Future<void>.delayed(tick);

      // Add auto-suggestions
      final autoSuggestions = [
        makeSong(id: 'auto_1', title: 'Auto Suggestion 1', streamUrl: 'https://stream.example.com/as1.mp3'),
        makeSong(id: 'auto_2', title: 'Auto Suggestion 2', streamUrl: 'https://stream.example.com/as2.mp3'),
      ];
      await queueHandler.addAutoSuggestions(autoSuggestions);
      await Future<void>.delayed(tick);

      // Order should be: active_0, user_1 (user stack), auto_1 (auto), auto_2 (auto)
      expect(queueHandler.queue.length, equals(4));
      expect(queueHandler.queue[1].id, equals('user_1'));
      expect(queueHandler.queue[1].isUserEnqueued, isTrue);
      expect(queueHandler.queue[2].id, equals('auto_1'));
      expect(queueHandler.queue[2].isUserEnqueued, isFalse);
      expect(queueHandler.queue[3].id, equals('auto_2'));
      expect(queueHandler.queue[3].isUserEnqueued, isFalse);

      // Clear user queue removes user_1 while keeping auto suggestions
      await queueHandler.clearUserQueue();
      await Future<void>.delayed(tick);

      expect(queueHandler.queue.length, equals(3));
      expect(queueHandler.queue[0].id, equals('active_0'));
      expect(queueHandler.queue[1].id, equals('auto_1'));
      expect(queueHandler.queue[2].id, equals('auto_2'));
    });

    test('9. isSameSongOrDub detects cross-language dubs and duplicate recordings', () {
      final seedTamil = makeSong(
        id: 'arabic_kuthu_tamil',
        title: 'Arabic Kuthu - Halamithi Habibo',
        artist: 'Anirudh Ravichander',
        album: 'Beast',
        duration: 280,
        language: 'tamil',
      );

      final dubTelugu = makeSong(
        id: 'arabic_kuthu_telugu',
        title: 'Halamithi Habibo (Telugu)',
        artist: 'Anirudh Ravichander',
        album: 'Beast (Telugu)',
        duration: 280,
        language: 'telugu',
      );

      final dubHindi = makeSong(
        id: 'arabic_kuthu_hindi',
        title: 'Halamithi Habibo (Hindi Version)',
        artist: 'Anirudh Ravichander',
        album: 'Raw (Hindi)',
        duration: 281, // within ±4s
        language: 'hindi',
      );

      final differentSong = makeSong(
        id: 'beast_mode',
        title: 'Beast Mode',
        artist: 'Anirudh Ravichander',
        album: 'Beast',
        duration: 220, // Different duration
        language: 'tamil',
      );

      expect(dubTelugu.isSameSongOrDub(seedTamil), isTrue, reason: 'Telugu dub of same song must match');
      expect(dubHindi.isSameSongOrDub(seedTamil), isTrue, reason: 'Hindi dub of same song must match');
      expect(differentSong.isSameSongOrDub(seedTamil), isFalse, reason: 'Different song by same composer must not match');
    });

    test('10. RadioEngine enforces strict target language isolation and anti-dub deduplication', () {
      final seed = makeSong(
        id: 'seed_tamil',
        title: 'Naan Pizhai',
        artist: 'Anirudh Ravichander',
        duration: 245,
        language: 'tamil',
      );

      final candidates = [
        // Cross-language dub: same artist, same duration (±4s)
        makeSong(id: 'dub_telugu', title: 'Naan Pizhai Telugu', artist: 'Anirudh Ravichander', duration: 245, language: 'telugu'),
        // Different language song
        makeSong(id: 'hindi_song', title: 'Kesariya', artist: 'Pritam', duration: 260, language: 'hindi'),
        // Genuine same-language songs
        makeSong(id: 'tamil_hit_1', title: 'Bae', artist: 'Anirudh Ravichander', duration: 230, language: 'tamil'),
        makeSong(id: 'tamil_hit_2', title: 'Megham Karukatha', artist: 'Dhanush', duration: 250, language: 'tamil'),
      ];

      final radioQueue = RadioEngine.shapeRadioQueue(
        seedSong: seed,
        candidatePool: candidates,
        targetLanguage: 'tamil',
        limit: 10,
      );

      final trackIds = radioQueue.map((s) => s.id).toList();
      expect(trackIds, contains('seed_tamil'));
      expect(trackIds, contains('tamil_hit_1'));
      expect(trackIds, contains('tamil_hit_2'));
      expect(trackIds, isNot(contains('dub_telugu')), reason: 'Cross-language dub must be filtered');
      expect(trackIds, isNot(contains('hindi_song')), reason: 'Non-target language track must be filtered');
    });

    test('11. Repeated queue reordering keeps queue in sync without crashing', () async {
      final songs = [
        makeSong(id: 'playing', title: 'Current Track'),
        makeSong(id: 'user_1', title: 'User Track 1'),
        makeSong(id: 'user_2', title: 'User Track 2'),
        makeSong(id: 'sug_1', title: 'Suggested 1'),
      ];

      await queueHandler.loadQueue(songs, initialIndex: 0, autoPlay: true);
      await Future<void>.delayed(tick);

      // Reorder user_1 and user_2
      await queueHandler.reorder(1, 3);
      await Future<void>.delayed(tick);

      expect(queueHandler.queue[1].id, equals('user_2'));
      expect(queueHandler.queue[2].id, equals('user_1'));

      // Reorder again backwards
      await queueHandler.reorder(2, 1);
      await Future<void>.delayed(tick);

      expect(queueHandler.queue[1].id, equals('user_1'));
      expect(queueHandler.queue[2].id, equals('user_2'));
    });

    test('12. SettingsManager autoplay defaults to true and updates synchronously', () {
      expect(SettingsManager.isAutoplayEnabled, isTrue);
      SettingsManager.autoplayNotifier.value = false;
      expect(SettingsManager.isAutoplayEnabled, isFalse);
      SettingsManager.autoplayNotifier.value = true;
      expect(SettingsManager.isAutoplayEnabled, isTrue);
    });

    test('13. fetchSmartShuffle only produces IDs present in the queue when currentSong is not in queue', () async {
      final upcoming = [
        makeSong(id: 'up_1', title: 'Track 1', artist: 'Artist A'),
        makeSong(id: 'up_2', title: 'Track 2', artist: 'Artist A'),
        makeSong(id: 'up_3', title: 'Track 3', artist: 'Artist B'),
      ];
      final currentSong = makeSong(id: 'playing_now', title: 'Current Song', artist: 'Artist A');

      final orderedIds = await ApiClient.fetchSmartShuffle(upcoming, currentSong);
      expect(orderedIds, isNotEmpty);
      expect(orderedIds.contains('playing_now'), isFalse);
      expect(orderedIds.toSet(), equals({'up_1', 'up_2', 'up_3'}));
    });

    test('14. SmartShuffleController cleanly cycles across 3 states: off -> standard -> smart -> off', () {
      final controller = SmartShuffleController(queueHandler: queueHandler);
      expect(controller.mode, equals(SmartShuffleMode.off));
      expect(controller.isStandardActive, isFalse);
      expect(controller.isSmartActive, isFalse);

      controller.cycleMode();
      expect(controller.mode, equals(SmartShuffleMode.standard));
      expect(controller.isStandardActive, isTrue);
      expect(controller.isSmartActive, isFalse);

      controller.cycleMode();
      expect(controller.mode, equals(SmartShuffleMode.smart));
      expect(controller.isStandardActive, isFalse);
      expect(controller.isSmartActive, isTrue);

      controller.cycleMode();
      expect(controller.mode, equals(SmartShuffleMode.off));
      expect(controller.isStandardActive, isFalse);
      expect(controller.isSmartActive, isFalse);
    });
  });
}
