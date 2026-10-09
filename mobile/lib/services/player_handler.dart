import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../logic/audio_queue_handler.dart';
import '../logic/smart_shuffle_controller.dart';
import '../logic/next_track_strategy.dart';
import '../models/song.dart';
import 'settings_manager.dart';
import '../domain/models/app_error.dart';
import '../domain/models/lyrics_state.dart';
import '../logic/lyrics/indic_romanizer.dart';
import 'error_handler.dart';
import 'api_client.dart';
import 'history_manager.dart';
import 'equalizer_service.dart';
import 'youtube_client.dart';
import 'radio_engine.dart';
import 'favorites_manager.dart';
import 'playlist_manager.dart';
import 'app_logger.dart';

PaatuAudioHandler? _audioHandlerInstance;

/// Safe accessor for the global [PaatuAudioHandler].
/// Throws typed [AppError] if accessed before initialization is complete.
PaatuAudioHandler get audioHandler {
  final handler = _audioHandlerInstance;
  if (handler == null) {
    throw AppError.internal(
      'Audio handler accessed before initialization was complete.',
      code: 'AUDIO_HANDLER_NOT_INITIALIZED',
    );
  }
  return handler;
}

set audioHandler(PaatuAudioHandler handler) => _audioHandlerInstance = handler;

bool get isAudioHandlerInitialized => _audioHandlerInstance != null;

/// App-lifetime audio background service handler coordinating playback,
/// queue mutations, notification actions, and lock screen media session.
class PaatuAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  late final AudioQueueHandler _queueHandler;
  late final SmartShuffleController _smartShuffleController;

  // Reactive State Notifiers for UI binding
  final ValueNotifier<String?> currentLyricsNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<LyricsState> lyricsStateNotifier = ValueNotifier<LyricsState>(const LyricsState.idle());
  final ValueNotifier<LyricsLanguage> lyricsLanguageNotifier = ValueNotifier<LyricsLanguage>(
    SettingsManager.lyricsPreferredLanguage == 'english' ? LyricsLanguage.english : LyricsLanguage.defaultLang,
  );
  final ValueNotifier<DualLyrics?> dualLyricsNotifier = ValueNotifier<DualLyrics?>(null);
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
  StreamSubscription? _playbackEventSub;
  StreamSubscription? _throttledPositionSub;
  VoidCallback? _favListener;
  VoidCallback? _smartShuffleListener;
  Stream<Duration>? _throttledPositionStream;

  // Cached favorite state to eliminate per-event lookups
  bool _cachedIsFav = false;
  String? _cachedFavSongId;

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

  static final MediaControl _favoriteControlFilled = MediaControl.custom(
    androidIcon: 'drawable/ic_heart_filled',
    label: 'Liked',
    name: 'toggle_favorite',
  );

  static final MediaControl _favoriteControlOutlined = MediaControl.custom(
    androidIcon: 'drawable/ic_heart_outline',
    label: 'Like',
    name: 'toggle_favorite',
  );

  static final List<MediaControl> _controlsPlayingFav = [
    MediaControl.skipToPrevious,
    MediaControl.pause,
    MediaControl.skipToNext,
    _favoriteControlFilled,
  ];

  static final List<MediaControl> _controlsPlayingUnfav = [
    MediaControl.skipToPrevious,
    MediaControl.pause,
    MediaControl.skipToNext,
    _favoriteControlOutlined,
  ];

  static final List<MediaControl> _controlsPausedFav = [
    MediaControl.skipToPrevious,
    MediaControl.play,
    MediaControl.skipToNext,
    _favoriteControlFilled,
  ];

  static final List<MediaControl> _controlsPausedUnfav = [
    MediaControl.skipToPrevious,
    MediaControl.play,
    MediaControl.skipToNext,
    _favoriteControlOutlined,
  ];

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
    _smartShuffleListener = () {
      isSmartShuffleNotifier.value = _smartShuffleController.isSmartActive;
    };
    _smartShuffleController.modeNotifier.addListener(_smartShuffleListener!);

    // Listen to favorite additions/removals to dynamically update notification heart action
    _favListener = () {
      _updateCachedFav();
      _broadcastState();
    };
    FavoritesManager.favoritesNotifier.addListener(_favListener!);

    // Connect 5-band equalizer directly to native audio session ID
    EqualizerService.bindToPlayerSession(_player.androidAudioSessionIdStream);

    _initAudioSession();
    _initStreams();
  }

  void _updateCachedFav() {
    final active = currentSong;
    if (active != null) {
      _cachedIsFav = FavoritesManager.isFavorite(active.id);
      _cachedFavSongId = active.id;
    } else {
      _cachedIsFav = false;
      _cachedFavSongId = null;
    }
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // Handle onAudioBecomingNoisy (e.g. Bluetooth headphones disconnected / unplugged)
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        AppLogger.log('PlayerHandler', 'Audio becoming noisy (headset/BT unplugged) -> auto-pausing');
        pause();
      });
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioSession setup');
    }
  }

  void _handleIdleRelease() {
    AppLogger.log('PlayerHandler', 'Downgrading foreground service notification after 5-minute timeout');
    _isForegroundDowngraded = true;
    _broadcastState(downgradeNotification: true);
  }

  void _onActiveTrackChanged(Song song) {
    AppLogger.log('PlayerHandler', 'Active track changed: "${song.title}" (${song.artist}) [id=${song.id}]');
    // Synchronously update system notification metadata
    mediaItem.add(song.toMediaItem());

    // Update cached favorite status once for new song
    _cachedFavSongId = song.id;
    _cachedIsFav = FavoritesManager.isFavorite(song.id);

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

  /// Sets user-selected lyrics language (Default vs English)
  void setLyricsLanguage(LyricsLanguage lang) {
    lyricsLanguageNotifier.value = lang;
    SettingsManager.setLyricsPreferredLanguage(lang == LyricsLanguage.english ? 'english' : 'default');
    final dual = dualLyricsNotifier.value;
    if (dual != null) {
      final selected = dual.getLyricsForLanguage(lang);
      currentLyricsNotifier.value = selected;
      lyricsStateNotifier.value = LyricsState.loaded(selected, dualLyrics: dual);
    }
  }

  /// Sets custom lyrics directly (from search candidate or paste dialog)
  void setCustomLyrics(String rawLyrics) {
    final dual = _buildDualLyrics(rawLyrics);
    dualLyricsNotifier.value = dual;
    final selected = dual.getLyricsForLanguage(lyricsLanguageNotifier.value);
    currentLyricsNotifier.value = selected;
    lyricsStateNotifier.value = LyricsState.loaded(selected, dualLyrics: dual);
  }

  DualLyrics _buildDualLyrics(String rawLyrics) {
    final isSynced = ApiClient.isSyncedLrc(rawLyrics);
    final script = IndicRomanizer.detectScript(rawLyrics);
    if (IndicRomanizer.hasIndicScript(rawLyrics)) {
      final romanized = IndicRomanizer.romanizeLyrics(rawLyrics);
      return DualLyrics(
        defaultLyrics: rawLyrics,
        englishLyrics: romanized,
        detectedScript: script,
        isSynced: isSynced,
      );
    } else {
      return DualLyrics(
        defaultLyrics: rawLyrics,
        englishLyrics: rawLyrics,
        detectedScript: 'latin',
        isSynced: isSynced,
      );
    }
  }

  /// Reloads lyrics for current or target song with multi-state resolution
  Future<void> reloadLyrics({Song? targetSong}) async {
    final song = targetSong ?? currentSong;
    if (song == null) {
      lyricsStateNotifier.value = const LyricsState.idle();
      currentLyricsNotifier.value = null;
      dualLyricsNotifier.value = null;
      return;
    }

    if (song.lyrics != null && song.lyrics!.isNotEmpty) {
      final dual = _buildDualLyrics(song.lyrics!);
      dualLyricsNotifier.value = dual;
      final selected = dual.getLyricsForLanguage(lyricsLanguageNotifier.value);
      currentLyricsNotifier.value = selected;
      lyricsStateNotifier.value = LyricsState.loaded(selected, dualLyrics: dual);
      return;
    }

    lyricsStateNotifier.value = const LyricsState.loading();
    try {
      final lyrics = await ApiClient.fetchLyrics(song);
      if (currentSong?.id != song.id) return;
      if (lyrics != null && lyrics.trim().isNotEmpty) {
        final dual = _buildDualLyrics(lyrics);
        dualLyricsNotifier.value = dual;
        final selected = dual.getLyricsForLanguage(lyricsLanguageNotifier.value);
        currentLyricsNotifier.value = selected;
        lyricsStateNotifier.value = LyricsState.loaded(selected, dualLyrics: dual);
      } else {
        currentLyricsNotifier.value = null;
        dualLyricsNotifier.value = null;
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
    if (activeSong != null && activeSong.id != _cachedFavSongId) {
      _cachedFavSongId = activeSong.id;
      _cachedIsFav = FavoritesManager.isFavorite(activeSong.id);
    }

    final controls = playing
        ? (_cachedIsFav ? _controlsPlayingFav : _controlsPlayingUnfav)
        : (_cachedIsFav ? _controlsPausedFav : _controlsPausedUnfav);

    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
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
      _updateCachedFav();
      _broadcastState();
    }
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    AppLogger.log('PlayerHandler', 'Custom action received: $name');
    if (name == 'toggle_favorite') {
      final song = currentSong;
      if (song != null) {
        await FavoritesManager.toggleFavorite(song);
        AppLogger.log('PlayerHandler', 'Toggled favorite for: "${song.title}" -> ${FavoritesManager.isFavorite(song.id)}');
        _updateCachedFav();
        _broadcastState();
      }
      return null;
    }
    if (name == 'dispose') {
      await disposeAudioHandler();
      return true;
    }
    return super.customAction(name, extras);
  }

  void _initStreams() {
    _playbackEventSub = _player.playbackEventStream.listen(
      (event) => _broadcastState(),
      onError: (Object e, StackTrace stack) {
        AppLogger.recordError(e, stack, context: 'AudioPlayer.playbackEventStream');
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
    _throttledPositionSub = throttledPositionStream.listen((pos) {
      if (!_hasRecordedListen && pos.inSeconds >= 15 && currentSong != null) {
        _hasRecordedListen = true;
      }
    });
  }

  /// Disposes background audio stream listeners and cleans up subscriptions.
  /// Note: PaatuAudioHandler is an app-lifetime singleton.
  Future<void> disposeAudioHandler() async {
    _becomingNoisySub?.cancel();
    _becomingNoisySub = null;
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _playbackEventSub?.cancel();
    _playbackEventSub = null;
    _throttledPositionSub?.cancel();
    _throttledPositionSub = null;
    if (_favListener != null) {
      FavoritesManager.favoritesNotifier.removeListener(_favListener!);
      _favListener = null;
    }
    if (_smartShuffleListener != null) {
      _smartShuffleController.modeNotifier.removeListener(_smartShuffleListener!);
      _smartShuffleListener = null;
    }
    _smartShuffleController.dispose();
    _queueHandler.dispose();
  }

  /// Master playback volume set by user (0.0 to 1.0)
  double get userVolume => _queueHandler.userVolume;

  /// Sets master playback volume and applies song normalization
  Future<void> setUserVolume(double volume) => _queueHandler.setUserVolume(volume);

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

  void addAllToQueue(List<Song> songs) {
    _queueHandler.addAllToQueue(songs);
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

  void clearUserQueue() {
    _queueHandler.clearUserQueue();
  }

  // ================= Smart Shuffle & Recommendations ================= //

  void toggleSmartShuffle() {
    _smartShuffleController.cycleMode();
  }

  Future<int> addRadioMix({int count = 10}) async {
    final current = currentSong;
    if (current == null) return 0;
    final beforeCount = _queueHandler.queue.length;
    try {
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      final tracks = await strategy.getUpcomingTracks(
        seedSong: current,
        queue: _queueHandler.queue,
        history: HistoryManager.getHistory(),
        count: count,
      );
      if (tracks.isNotEmpty) {
        await _queueHandler.addAutoSuggestions(tracks);
      }
    } catch (e) {
      debugPrint('[PlayerHandler] addRadioMix error: $e');
    }
    return _queueHandler.queue.length - beforeCount;
  }

  /// Handles continuous endless playback when reaching the end of the queue
  Future<void> handleAutoplayQueueEnd(Song current) async {
    try {
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      final tracks = await strategy.getUpcomingTracks(
        seedSong: current,
        queue: _queueHandler.queue,
        history: HistoryManager.getHistory(),
        count: 6,
      );
      if (tracks.isNotEmpty) {
        await _queueHandler.addAutoSuggestions(tracks);
        if (_queueHandler.hasNext) {
          await _queueHandler.skipToNext();
          return;
        }
      }
    } catch (e) {
      debugPrint('[PlayerHandler] handleAutoplayQueueEnd error: $e');
    }
    _queueHandler.startIdleTimer();
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
