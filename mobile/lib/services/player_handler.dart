import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../logic/audio_queue_handler.dart';
import '../logic/smart_shuffle_controller.dart';
import '../models/song.dart';
import '../domain/models/app_error.dart';
import '../domain/models/lyrics_state.dart';
import 'error_handler.dart';
import 'api_client.dart';
import 'history_manager.dart';
import 'equalizer_service.dart';
import 'youtube_client.dart';
import 'radio_engine.dart';
import 'favorites_manager.dart';
import 'playlist_manager.dart';

late PaatuAudioHandler audioHandler;

class PaatuAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  late final AudioQueueHandler _queueHandler;
  late final SmartShuffleController _smartShuffleController;

  // Reactive State Notifiers for UI binding
  final ValueNotifier<String?> currentLyricsNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<LyricsState> lyricsStateNotifier = ValueNotifier<LyricsState>(const LyricsState.idle());
  final ValueNotifier<int> lyricsOffsetMsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<Duration?> sleepTimerRemainingNotifier = ValueNotifier<Duration?>(null);
  final ValueNotifier<bool> isSmartShuffleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<AppError?> playbackErrorNotifier = ValueNotifier<AppError?>(null);

  Timer? _sleepTimer;
  Timer? _countdownTicker;
  bool _hasRecordedListen = false;
  bool _isForegroundDowngraded = false;
  StreamSubscription? _becomingNoisySub;
  StreamSubscription<PlayerState>? _playerStateSub;
  Stream<Duration>? _throttledPositionStream;

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

  /// Throttled position stream that updates no faster than once every 500ms
  /// Eliminates rapid continuous wakeups to preserve Android Doze mode and battery.
  Stream<Duration> get throttledPositionStream {
    _throttledPositionStream ??= Stream<Duration>.multi((controller) {
      int lastEmitMs = 0;
      final sub = _player.positionStream.listen(
        (pos) {
          final now = DateTime.now().millisecondsSinceEpoch;
          // Emit at most once per 500ms during active playback, or immediately on seek / pause
          if (now - lastEmitMs >= 500 || !_player.playing) {
            lastEmitMs = now;
            controller.add(pos);
          }
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () => sub.cancel();
    }).asBroadcastStream();
    return _throttledPositionStream!;
  }

  static const MediaControl _favoriteControlFilled = MediaControl(
    androidIcon: 'drawable/ic_heart_filled',
    label: 'Liked',
    action: MediaAction.setRating,
  );

  static const MediaControl _favoriteControlOutlined = MediaControl(
    androidIcon: 'drawable/ic_heart_outline',
    label: 'Like',
    action: MediaAction.setRating,
  );

  PaatuAudioHandler() {
    _queueHandler = AudioQueueHandler(
      player: _player,
      onSongChanged: (song) => _onActiveTrackChanged(song),
      onPlayStateChanged: (_) => _broadcastState(),
      onQueueProgress: (idx, total) => _broadcastState(),
      onIdleRelease: () => _handleIdleRelease(),
    );

    _smartShuffleController = SmartShuffleController(queueHandler: _queueHandler);

    // Keep legacy boolean notifier in sync with Smart mode
    _smartShuffleController.modeNotifier.addListener(() {
      isSmartShuffleNotifier.value = _smartShuffleController.isSmartActive;
    });

    // Listen to favorite additions/removals to dynamically update notification heart action
    FavoritesManager.favoritesNotifier.addListener(_broadcastState);

    // Connect 5-band equalizer directly to native audio session ID
    EqualizerService.bindToPlayerSession(_player.androidAudioSessionIdStream);

    _initAudioSession();
    _initStreams();
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // Handle onAudioBecomingNoisy (e.g. Bluetooth headphones disconnected / unplugged)
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        debugPrint('[PaatuAudioHandler] Audio becoming noisy (headset/BT unplugged) -> auto-pausing & starting idle countdown');
        pause();
      });
    } catch (e) {
      debugPrint('[PaatuAudioHandler] AudioSession setup error: $e');
    }
  }

  void _handleIdleRelease() {
    debugPrint('[PaatuAudioHandler] Downgrading foreground service notification after 5-minute timeout');
    _isForegroundDowngraded = true;
    _broadcastState(downgradeNotification: true);
  }

  void _onActiveTrackChanged(Song song) {
    // Synchronously update system notification metadata
    mediaItem.add(song.toMediaItem());

    // Coordinated play recording: atomic local Hive + cloud Supabase with retry
    HistoryManager.recordPlay(song);
    _smartShuffleController.recordRecentlyPlayed(song);

    // Reset listen history & lyrics offset
    _hasRecordedListen = false;
    lyricsOffsetMsNotifier.value = 0;

    // Load lyrics with distinct state tracking
    reloadLyrics(targetSong: song);

    _broadcastState();
  }

  /// Reloads lyrics for current or target song with multi-state resolution
  Future<void> reloadLyrics({Song? targetSong}) async {
    final song = targetSong ?? currentSong;
    if (song == null) {
      lyricsStateNotifier.value = const LyricsState.idle();
      currentLyricsNotifier.value = null;
      return;
    }

    if (song.lyrics != null && song.lyrics!.isNotEmpty) {
      currentLyricsNotifier.value = song.lyrics;
      lyricsStateNotifier.value = LyricsState.loaded(song.lyrics!);
      return;
    }

    lyricsStateNotifier.value = const LyricsState.loading();
    try {
      final lyrics = await ApiClient.fetchLyrics(song);
      if (currentSong?.id != song.id) return;
      if (lyrics != null && lyrics.trim().isNotEmpty) {
        currentLyricsNotifier.value = lyrics;
        lyricsStateNotifier.value = LyricsState.loaded(lyrics);
      } else {
        currentLyricsNotifier.value = null;
        lyricsStateNotifier.value = const LyricsState.notFound();
      }
    } catch (e, stack) {
      if (currentSong?.id != song.id) return;
      final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'PaatuAudioHandler.reloadLyrics');
      lyricsStateNotifier.value = LyricsState.error(appErr);
    }
  }

  void _broadcastState({bool downgradeNotification = false}) {
    final playing = _player.playing;
    final AudioProcessingState processingState;
    if (downgradeNotification || _isForegroundDowngraded) {
      processingState = AudioProcessingState.idle;
    } else {
      processingState = const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState] ?? AudioProcessingState.idle;
    }

    final activeSong = currentSong;
    final isFav = activeSong != null && FavoritesManager.isFavorite(activeSong.id);
    final favControl = isFav ? _favoriteControlFilled : _favoriteControlOutlined;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        favControl,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setRating,
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

  @override
  Future<void> setRating(Rating rating, [Map<String, dynamic>? extras]) async {
    final song = currentSong;
    if (song != null) {
      await FavoritesManager.toggleFavorite(song);
      _broadcastState();
    }
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'toggle_favorite') {
      final song = currentSong;
      if (song != null) {
        await FavoritesManager.toggleFavorite(song);
        _broadcastState();
      }
      return null;
    }
    return super.customAction(name, extras);
  }

  void _initStreams() {
    _player.playbackEventStream.listen(
      (event) => _broadcastState(),
      onError: (Object e, StackTrace stack) {
        final err = ErrorHandler.resolve(e, stackTrace: stack, context: 'AudioPlayer.playbackEventStream');
        playbackErrorNotifier.value = err;
        debugPrint('[PlayerHandler] Playback error: ${err.userMessage}');
        if (_queueHandler.hasNext) {
          Future.delayed(const Duration(seconds: 2), () {
            _queueHandler.skipToNext();
          });
        }
      },
    );

    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.playing) {
        _isForegroundDowngraded = false;
      }
      _broadcastState();
    });

    // 15-second listen tracker
    throttledPositionStream.listen((pos) {
      if (!_hasRecordedListen && pos.inSeconds >= 15 && currentSong != null) {
        _hasRecordedListen = true;
      }
    });
  }

  /// Load and play a song with gapless ConcatenatingAudioSource preloading
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
    _isForegroundDowngraded = false;
    _queueHandler.cancelIdleTimer();

    final isNewSingleQueue = queue == null || (queue.length == 1 && queue.first.id == song.id);
    final initialIndex = queue != null ? queue.indexWhere((s) => s.id == song.id) : 0;
    final targetIndex = initialIndex != -1 ? initialIndex : 0;

    await _queueHandler.loadQueue(
      queue ?? [song],
      initialIndex: targetIndex,
      autoPlay: true,
    );

    // If starting a fresh queue containing only this song, auto-fill Up Next using the recommendation algorithm
    if (isNewSingleQueue) {
      _smartShuffleController.populateUpNextForNewQueue(song);
    }
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

  Future<int> startSongRadio(Song seedSong) async {
    final radioQueue = await RadioEngine.buildSongRadio(seedSong);
    if (radioQueue.isNotEmpty) {
      await playSong(seedSong, queue: radioQueue);
      return radioQueue.length;
    }
    return 0;
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
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
    _isForegroundDowngraded = false;
    _queueHandler.cancelIdleTimer();
    await _player.play();
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    YouTubeClient.closeIdleClient();
    _queueHandler.startIdleTimer();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    _becomingNoisySub?.cancel();
    _playerStateSub?.cancel();
    _queueHandler.cancelIdleTimer();
    YouTubeClient.closeIdleClient();
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    await _player.stop();
    _isForegroundDowngraded = true;
    _broadcastState(downgradeNotification: true);
    await super.stop();
  }

  Future<void> dispose() async {
    _becomingNoisySub?.cancel();
    _playerStateSub?.cancel();
    _queueHandler.dispose();
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
    final current = currentSong;
    if (current != null) {
      final pos = _player.position;
      final dur = _player.duration ?? const Duration(seconds: 180);
      _smartShuffleController.recordPlaybackFeedback(
        current,
        listenedSeconds: pos.inSeconds,
        totalSeconds: dur.inSeconds,
      );
    }
    await _queueHandler.skipToNext();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final current = currentSong;
    if (current != null) {
      final pos = _player.position;
      final dur = _player.duration ?? const Duration(seconds: 180);
      _smartShuffleController.recordPlaybackFeedback(
        current,
        listenedSeconds: pos.inSeconds,
        totalSeconds: dur.inSeconds,
      );
    }
    await _queueHandler.jumpToIndex(index);
  }

  @override
  Future<void> skipToPrevious() async {
    await _queueHandler.skipToPrevious();
  }

  // ================= Android Auto & MediaBrowserService Hierarchy ================= //

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    // 1. Root Level
    if (parentMediaId == AudioService.MEDIA_ROOT_ID) {
      return [
        const MediaItem(
          id: 'root_liked',
          title: 'Liked Songs',
          playable: false,
        ),
        const MediaItem(
          id: 'root_history',
          title: 'Recently Played',
          playable: false,
        ),
        const MediaItem(
          id: 'root_playlists',
          title: 'Playlists',
          playable: false,
        ),
      ];
    }

    // 2. Liked Songs
    if (parentMediaId == 'root_liked') {
      final songs = FavoritesManager.getFavorites();
      return songs.map((s) => s.toMediaItem().copyWith(playable: true)).toList();
    }

    // 3. Recently Played
    if (parentMediaId == 'root_history') {
      final songs = HistoryManager.getHistory();
      return songs.take(30).map((s) => s.toMediaItem().copyWith(playable: true)).toList();
    }

    // 4. Playlists list
    if (parentMediaId == 'root_playlists') {
      final playlists = PlaylistManager.getPlaylists();
      return playlists.map<MediaItem>((pl) => MediaItem(
        id: 'pl_${pl.id}',
        title: pl.title,
        playable: false,
        artUri: pl.coverUrl.isNotEmpty ? Uri.tryParse(pl.coverUrl) : null,
      )).toList();
    }

    // 5. Specific Playlist songs
    if (parentMediaId.startsWith('pl_')) {
      final plId = parentMediaId.substring(3);
      final playlist = PlaylistManager.getPlaylist(plId);
      if (playlist != null) {
        return playlist.tracks.map((s) => s.toMediaItem().copyWith(playable: true)).toList();
      }
    }

    return [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    for (final song in playlist) {
      if (song.id == mediaId) return song.toMediaItem();
    }
    final liked = FavoritesManager.getFavorites();
    for (final song in liked) {
      if (song.id == mediaId) return song.toMediaItem();
    }
    final history = HistoryManager.getHistory();
    for (final song in history) {
      if (song.id == mediaId) return song.toMediaItem();
    }
    return null;
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    // 1. Current Queue
    for (int i = 0; i < playlist.length; i++) {
      if (playlist[i].id == mediaId) {
        await skipToQueueItem(i);
        return;
      }
    }

    // 2. Favorites
    final liked = FavoritesManager.getFavorites();
    final likedIdx = liked.indexWhere((s) => s.id == mediaId);
    if (likedIdx != -1) {
      await playSong(liked[likedIdx], queue: liked);
      return;
    }

    // 3. History
    final history = HistoryManager.getHistory();
    final histIdx = history.indexWhere((s) => s.id == mediaId);
    if (histIdx != -1) {
      await playSong(history[histIdx], queue: history);
      return;
    }

    // 4. Playlists
    final playlists = PlaylistManager.getPlaylists();
    for (final pl in playlists) {
      final idx = pl.tracks.indexWhere((s) => s.id == mediaId);
      if (idx != -1) {
        await playSong(pl.tracks[idx], queue: pl.tracks);
        return;
      }
    }
  }
}
