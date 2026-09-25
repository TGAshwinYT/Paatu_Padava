import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../logic/audio_queue_handler.dart';
import '../logic/smart_shuffle_controller.dart';
import '../models/song.dart';
import 'api_client.dart';
import 'history_manager.dart';
import 'equalizer_service.dart';
import 'supabase_service.dart';
import 'auth_manager.dart';

late PaatuAudioHandler audioHandler;

class PaatuAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  late final AudioQueueHandler _queueHandler;
  late final SmartShuffleController _smartShuffleController;

  // Reactive State Notifiers for UI binding
  final ValueNotifier<String?> currentLyricsNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<int> lyricsOffsetMsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<Duration?> sleepTimerRemainingNotifier = ValueNotifier<Duration?>(null);
  final ValueNotifier<bool> isSmartShuffleNotifier = ValueNotifier<bool>(false);

  Timer? _sleepTimer;
  Timer? _countdownTicker;
  bool _hasRecordedListen = false;

  AudioPlayer get player => _player;
  AudioQueueHandler get queueHandler => _queueHandler;
  SmartShuffleController get smartShuffleController => _smartShuffleController;

  ValueNotifier<Song?> get currentSongNotifier => _queueHandler.currentSongNotifier;
  ValueNotifier<List<Song>> get playlistNotifier => _queueHandler.queueNotifier;
  ValueNotifier<int> get currentIndexNotifier => _queueHandler.currentIndexNotifier;
  ValueNotifier<SmartShuffleMode> get shuffleModeNotifier => _smartShuffleController.modeNotifier;

  List<Song> get playlist => _queueHandler.queue;
  int get currentIndex => _queueHandler.currentIndex;
  Song? get currentSong => _queueHandler.currentSong;

  PaatuAudioHandler() {
    _queueHandler = AudioQueueHandler(
      player: _player,
      onSongChanged: (song) => _onActiveTrackChanged(song),
      onPlayStateChanged: (_) => _broadcastState(),
      onQueueProgress: (idx, total) => _broadcastState(),
    );

    _smartShuffleController = SmartShuffleController(queueHandler: _queueHandler);

    // Keep legacy boolean notifier in sync with Smart mode
    _smartShuffleController.modeNotifier.addListener(() {
      isSmartShuffleNotifier.value = _smartShuffleController.isSmartActive;
    });

    // Connect 5-band equalizer directly to native audio session ID
    EqualizerService.bindToPlayerSession(_player.androidAudioSessionIdStream);

    _initStreams();
  }

  void _onActiveTrackChanged(Song song) {
    // Synchronously update system notification metadata
    mediaItem.add(song.toMediaItem());

    // Record to local & Supabase listen history & anti-repetition cache
    HistoryManager.addSong(song);
    SupabaseService.recordUserHistory(AuthManager.currentUser?.id ?? '', song);
    _smartShuffleController.recordRecentlyPlayed(song.id);

    // Reset listen history & lyrics offset
    _hasRecordedListen = false;
    lyricsOffsetMsNotifier.value = 0;

    // Load lyrics
    currentLyricsNotifier.value = (song.lyrics != null && song.lyrics!.isNotEmpty) ? song.lyrics : null;
    ApiClient.fetchLyrics(song).then((lyrics) {
      if (currentSong?.id == song.id && lyrics != null && lyrics.isNotEmpty) {
        currentLyricsNotifier.value = lyrics;
      }
    });

    _broadcastState();
  }

  void _broadcastState() {
    final playing = _player.playing;
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState] ?? AudioProcessingState.idle;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _queueHandler.currentIndex,
    ));
  }

  void _initStreams() {
    _player.playbackEventStream.listen((event) => _broadcastState());

    _player.playerStateStream.listen((state) {
      _broadcastState();
      if (state.processingState == ProcessingState.completed) {
        if (_queueHandler.hasNext) {
          _queueHandler.skipToNext();
        }
      }
    });

    // 15-second listen tracker: trains backend item-item collaborative filtering ML graph
    _player.positionStream.listen((pos) {
      if (!_hasRecordedListen && pos.inSeconds >= 15 && currentSong != null) {
        _hasRecordedListen = true;
        ApiClient.addListenHistory(currentSong!);
      }
    });
  }

  /// Load and play a song with gapless ConcatenatingAudioSource preloading
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    final initialIndex = queue != null ? queue.indexWhere((s) => s.id == song.id) : 0;
    final targetIndex = initialIndex != -1 ? initialIndex : 0;

    await _queueHandler.loadQueue(
      queue ?? [song],
      initialIndex: targetIndex,
      autoPlay: true,
    );
  }

  // ================= Queue Management ================= //

  void insertNext(Song song) {
    _queueHandler.insertNext(song);
  }

  void addToQueue(Song song) {
    _queueHandler.addToQueue(song);
  }

  void removeAt(int index) {
    _queueHandler.removeAt(index);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    _queueHandler.reorder(oldIndex, newIndex);
  }

  Future<void> jumpToIndex(int index) async {
    await _queueHandler.jumpToIndex(index);
  }

  void clearQueue() {
    _queueHandler.clear();
  }

  // ================= Smart Shuffle & Recommendations ================= //

  void toggleSmartShuffle() {
    _smartShuffleController.cycleMode();
  }

  Future<int> addRadioMix() async {
    final beforeCount = _queueHandler.queue.length;
    await _smartShuffleController.ingestSmartRecommendations();
    return _queueHandler.queue.length - beforeCount;
  }

  // ================= Sleep Timer ================= //

  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    DateTime endTime = DateTime.now().add(duration);
    sleepTimerRemainingNotifier.value = duration;

    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = endTime.difference(DateTime.now());
      if (remaining.isNegative) {
        cancelSleepTimer();
        pause();
      } else {
        sleepTimerRemainingNotifier.value = remaining;
      }
    });

    _sleepTimer = Timer(duration, () {
      pause();
      cancelSleepTimer();
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _countdownTicker?.cancel();
    _sleepTimer = null;
    _countdownTicker = null;
    sleepTimerRemainingNotifier.value = null;
  }

  // ================= Standard Controls ================= //

  @override
  Future<void> play() async {
    await _player.play();
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _broadcastState();
    await super.stop();
  }

  Future<void> toggleLoopMode() async {
    final current = _player.loopMode;
    if (current == LoopMode.off) {
      await _player.setLoopMode(LoopMode.all);
    } else if (current == LoopMode.all) {
      await _player.setLoopMode(LoopMode.one);
    } else {
      await _player.setLoopMode(LoopMode.off);
    }
  }

  @override
  Future<void> skipToNext() async {
    await _queueHandler.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _queueHandler.skipToPrevious();
  }
}
