import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import '../logic/audio_queue_handler.dart';
import '../logic/stream_resolver.dart';
import '../logic/smart_shuffle_controller.dart';
import '../logic/queue/queue_tuner_controller.dart';
import '../logic/queue/queue_tuner_mode.dart';
import '../logic/next_track_strategy.dart';
import '../models/song.dart';
import 'settings_manager.dart';
import '../domain/models/app_error.dart';
import '../domain/models/lyrics_state.dart';
import '../domain/models/track_entity.dart';
import '../logic/lyrics/indic_romanizer.dart';
import 'error_handler.dart';
import 'api_client.dart';
import 'history_manager.dart';
import 'queue_cooldown_manager.dart';
import 'equalizer_service.dart';
import 'radio_engine.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';
import 'favorites_manager.dart';
import 'download_manager.dart';
import 'playlist_manager.dart';
import 'app_logger.dart';
import 'party_sync_coordinator.dart';
import 'sleep_timer_service.dart';
import 'blacklist_manager.dart';
import 'lyrics_client.dart';
import 'smart_cache_service.dart';
import 'search_service.dart';
import 'recent_containers_manager.dart';
import '../data/repositories/song_repository.dart';

part 'player/player_lyrics_ext.dart';
part 'player/player_recommendations_ext.dart';
part 'player/player_lifecycle_ext.dart';
part 'player/player_streams_ext.dart';
part 'player/player_playback_ext.dart';
part 'player/player_controls_ext.dart';
part 'player/player_media_browser_ext.dart';
part 'player/player_party_ext.dart';

/// Context describing where audio playback originated from (e.g. Playlist, Album, Mix, Liked Songs).
class PlaybackContext {
  final String id;
  final String title;
  final String type; // 'playlist', 'album', 'mix', 'liked', 'downloads'
  final String? coverUrl;
  final String? subtitle;

  const PlaybackContext({
    required this.id,
    required this.title,
    required this.type,
    this.coverUrl,
    this.subtitle,
  });
}

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

final ValueNotifier<Song?> _fallbackNullSongNotifier = ValueNotifier<Song?>(null);

/// Safe, null-resilient notifier for the currently active [Song].
/// Returns a static null notifier if the audio pipeline has not initialized yet (e.g. in tests or early startup).
ValueNotifier<Song?> get activeSongNotifier =>
    _audioHandlerInstance?.currentSongNotifier ?? _fallbackNullSongNotifier;

// ignore: experimental_member_use
class YouTubeByteStreamSource extends StreamAudioSource {
  final String videoId;

  YouTubeByteStreamSource(this.videoId, {super.tag});

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final streamInfo = await YouTubeClient.getBestAudioStreamInfo(videoId);
    if (streamInfo == null) {
      throw Exception('Failed to get audio stream info for $videoId');
    }

    final totalBytes = streamInfo.size.totalBytes;
    final effectiveStart = start ?? 0;
    final effectiveEnd = (end != null && end < totalBytes) ? end : totalBytes;

    final stream = YouTubeClient.getAudioByteStream(videoId, start: effectiveStart, end: effectiveEnd);

    // ignore: experimental_member_use
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: totalBytes,
      contentLength: effectiveEnd - effectiveStart,
      offset: effectiveStart,
      stream: stream,
      contentType: streamInfo.codec.mimeType,
    );
  }
}

/// App-lifetime audio background service handler coordinating playback,
/// queue mutations, notification actions, and lock screen media session.
class PaatuAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler, WidgetsBindingObserver {
  final AudioPlayer _player;

  late final AudioQueueHandler _queueHandler;
  late final SmartShuffleController _smartShuffleController;
  late final QueueTunerController _queueTunerController;

  // Reactive State Notifiers for UI binding
  final ValueNotifier<String?> currentLyricsNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<LyricsState> lyricsStateNotifier = ValueNotifier<LyricsState>(const LyricsState.idle());
  final ValueNotifier<LyricsLanguage> lyricsLanguageNotifier = ValueNotifier<LyricsLanguage>(
    SettingsManager.lyricsPreferredLanguage == 'english' ? LyricsLanguage.english : LyricsLanguage.defaultLang,
  );
  final ValueNotifier<DualLyrics?> dualLyricsNotifier = ValueNotifier<DualLyrics?>(null);
  final ValueNotifier<int> lyricsOffsetMsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isKaraokeModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> vocalAttenuationNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<Duration?> sleepTimerRemainingNotifier = ValueNotifier<Duration?>(null);
  final ValueNotifier<bool> isSmartShuffleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<AppError?> playbackErrorNotifier = ValueNotifier<AppError?>(null);

  static const MethodChannel _widgetChannel = MethodChannel('com.tamilgaming.paatupadava/widget');

  void _syncWidgetState({Song? song, bool? isPlaying}) =>
      _syncWidgetStateImpl(song: song, isPlaying: isPlaying);

  bool _hasRecordedListen = false;
  bool _hasRecordedHistory = false;
  bool _isForegroundDowngraded = false;
  bool _isAppInBackground = false;
  bool _isAppTaskRemoved = false;
  bool _resumeOnInterruptionEnd = false;
  StreamSubscription? _becomingNoisySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription? _playbackEventSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionHubSub;
  int _playSongRequestId = 0;
  StreamController<Duration>? _throttledPositionController;
  StreamController<Duration>? _lyricsPositionController;
  int _lastThrottledEmitMs = 0;
  int _lastLyricsEmitMs = 0;
  VoidCallback? _favListener;
  VoidCallback? _smartShuffleListener;
  Timer? _lyricsDebounceTimer;

  // Cached favorite state to eliminate per-event lookups
  bool _cachedIsFav = false;
  String? _cachedFavSongId;

  AudioPlayer get player => _player;
  AudioQueueHandler get queueHandler => _queueHandler;
  SmartShuffleController get smartShuffleController => _smartShuffleController;
  QueueTunerController get queueTunerController => _queueTunerController;
  ValueNotifier<QueueTunerMode> get queueTunerModeNotifier => _queueTunerController.modeNotifier;

  ValueNotifier<Song?> get currentSongNotifier => _queueHandler.currentSongNotifier;
  ValueNotifier<List<Song>> get playlistNotifier => _queueHandler.queueNotifier;
  ValueNotifier<int> get currentIndexNotifier => _queueHandler.currentIndexNotifier;
  ValueNotifier<SmartShuffleMode> get shuffleModeNotifier => _smartShuffleController.modeNotifier;
  final ValueNotifier<PlaybackContext?> currentContextNotifier = ValueNotifier<PlaybackContext?>(null);
  PlaybackContext? get currentContext => currentContextNotifier.value;

  bool get hasRecordedHistory => _hasRecordedHistory;
  List<Song> get playlist => _queueHandler.queue;
  int get currentIndex => _queueHandler.currentIndex;
  Song? get currentSong => _queueHandler.currentSong;
  bool get isAppTaskRemoved => _isAppTaskRemoved;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _didChangeAppLifecycleStateImpl(state);
  }

  /// Centralized position hub: updates every 500ms when in foreground,
  /// or every 1.5 seconds when app is in background / screen off to allow CPU deep sleep (Doze mode).
  Stream<Duration> get throttledPositionStream {
    _throttledPositionController ??= StreamController<Duration>.broadcast(
      onListen: () {
        if (_player.position > Duration.zero) {
          _throttledPositionController?.add(_player.position);
        }
      },
    );
    return _throttledPositionController!.stream;
  }

  /// High-precision position stream for real-time synchronized karaoke lyrics.
  /// Emits updates every ~50ms during active playback to eliminate sync lag and jitter.
  Stream<Duration> get lyricsPositionStream {
    _lyricsPositionController ??= StreamController<Duration>.broadcast(
      onListen: () {
        if (_player.position > Duration.zero) {
          _lyricsPositionController?.add(_player.position);
        }
      },
    );
    return _lyricsPositionController!.stream;
  }

  /// Single centralized position dispatcher fanning out to metrics and stream listeners
  void _onPositionTick(Duration pos) => _onPositionTickImpl(pos);

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

  PaatuAudioHandler({AudioPlayer? player})
      : _player = player ??
            AudioPlayer(
              audioLoadConfiguration: const AudioLoadConfiguration(
                androidLoadControl: AndroidLoadControl(
                  minBufferDuration: Duration(seconds: 20),
                  maxBufferDuration: Duration(seconds: 50),
                  bufferForPlaybackDuration: Duration(milliseconds: 1000),
                  bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
                  backBufferDuration: Duration(seconds: 10),
                ),
              ),
              androidApplyAudioAttributes: true,
            ) {
    _queueHandler = AudioQueueHandler(
      player: _player,
      onSongChanged: (song) => _onActiveTrackChanged(song),
      onPlayStateChanged: (_) => _broadcastState(),
      onQueueProgress: (idx, total) => _broadcastState(),
      onIdleRelease: () => _handleIdleRelease(),
    );

    _smartShuffleController = SmartShuffleController(queueHandler: _queueHandler);
    _queueTunerController = QueueTunerController(queueHandler: _queueHandler);

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

    // Synchronize host queue mutations to all connected party speakers
    _queueHandler.queueNotifier.addListener(() {
      if (PartySyncCoordinator.isHost) {
        PartySyncCoordinator.notifyHostQueueUpdated(
          _queueHandler.queue,
          _queueHandler.currentIndex,
        );
      }
    });

    // Auto-skip if current song or artist is blacklisted by user
    void checkBlacklistOnActive() {
      final cur = currentSong;
      if (cur != null && BlacklistManager.isBlacklisted(cur)) {
        skipToNext();
      }
    }
    BlacklistManager.blacklistedSongsNotifier.addListener(checkBlacklistOnActive);
    BlacklistManager.blacklistedArtistsNotifier.addListener(checkBlacklistOnActive);

    // Connect 5-band equalizer directly to native audio session ID
    int? initialSessionId;
    try {
      initialSessionId = _player.androidAudioSessionId;
    } catch (e) {
      AppLogger.debug('PaatuAudioHandler', 'Android audio session ID not available: $e');
    }
    EqualizerService.bindToPlayerSession(
      _player.androidAudioSessionIdStream,
      initialSessionId: initialSessionId,
    );

    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (e) {
      AppLogger.debug('PaatuAudioHandler', 'Could not register WidgetsBinding observer: $e');
    }

    // Initialize Predictive Smart Cache for queue and radio streams
    SmartCacheService.instance.init();

    _audioSessionInitFuture = _initAudioSession();
    _initStreams();
  }

  Future<void>? _audioSessionInitFuture;

  Future<void> ensureAudioSessionConfigured() =>
      _audioSessionInitFuture ??= _initAudioSession();

  void _updateCachedFav() => _updateCachedFavImpl();

  Future<void> _initAudioSession() => _initAudioSessionImpl();

  void _handleIdleRelease() {
    AppLogger.log('PaatuAudioHandler', 'Idle timeout reached: maintaining paused state');
    // Do not downgrade foreground so notification remains interactive
    _broadcastState();
  }

  void _onActiveTrackChanged(Song song) => _onActiveTrackChangedImpl(song);

  int? _lastReselectedDurationSec;

  void _broadcastState({bool downgradeNotification = false}) =>
      _broadcastStateImpl(downgradeNotification: downgradeNotification);

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

  void _initStreams() => _initStreamsImpl();

  /// Disposes background audio stream listeners and cleans up subscriptions.
  /// Note: PaatuAudioHandler is an app-lifetime singleton.
  Future<void> disposeAudioHandler() => _disposeAudioHandlerImpl();

  /// Master playback volume set by user (0.0 to 1.0)
  double get userVolume => _queueHandler.userVolume;

  /// Sets master playback volume and applies song normalization
  Future<void> setUserVolume(double volume) => _queueHandler.setUserVolume(volume);

  /// Applies ReplayGain / Loudness Normalization: computes track gain and adjusts
  /// _player.setVolume() to balance loudness between YouTube (-14 LUFS) and JioSaavn tracks.
  Future<void> applyVolumeNormalization([Song? targetSong]) async {
    final song = targetSong ?? currentSong;
    final effectiveVolume = _queueHandler.getEffectiveVolumeForSong(song);
    try {
      await _player.setVolume(effectiveVolume);
      AppLogger.log(
        'PlayerHandler',
        'ReplayGain volume normalization applied: ${effectiveVolume.toStringAsFixed(2)} for "${song?.title}" [${song?.source}]',
      );
    } catch (e) {
      debugPrint('[PlayerHandler] applyVolumeNormalization error: $e');
    }
  }

  int _loadRequestId = 0;
  int _activeLoadToken = 0;
  bool _isPreparing = false;
  bool get isPreparing => _isPreparing;
  final StreamResolver _streamResolver = DefaultStreamResolver();



  /// Loads and resolves a track with async request-ID race condition protection
  Future<void> loadTrack(TrackEntity track, {bool autoPlay = true}) =>
      _loadTrackImpl(track, autoPlay: autoPlay);

  /// Launch a standalone track without any surrounding context queue.
  /// Used by History and Search to ensure historical or unplayed tracks never leak into the queue.
  Future<void> playTrack(TrackEntity track) => _playTrackImpl(track);

  /// Load and play a song with gapless ConcatenatingAudioSource preloading
  Future<void> playSong(
    Song song, {
    List<Song>? queue,
    bool preserveUserQueue = false,
    PlaybackContext? context,
    bool isPartySyncInternal = false,
    bool autoPlay = true,
  }) =>
      _playSongImpl(
        song,
        queue: queue,
        preserveUserQueue: preserveUserQueue,
        context: context,
        isPartySyncInternal: isPartySyncInternal,
        autoPlay: autoPlay,
      );

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

  bool get isShuffleEnabled => _queueHandler.isShuffleEnabled;

  Future<void> setShuffleModeEnabled(bool enabled) async {
    await _queueHandler.setShuffleEnabled(enabled);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await _queueHandler.setShuffleEnabled(enabled);
  }

  void toggleSmartShuffle() {
    _smartShuffleController.cycleMode();
  }

  bool _isPrefetchingRecommendations = false;
  Future<void>? _inFlightPrefetchFuture;

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  // ================= Sleep Timer ================= //

  void setSleepTimer(Duration duration, {bool stopAtEnd = false}) {
    SleepTimerService.instance.setTimer(duration, stopAtEnd: stopAtEnd);
  }

  void cancelSleepTimer() {
    SleepTimerService.instance.cancel();
  }

  // ================= Standard Controls ================= //

  @override
  Future<void> play() => _playImpl();

  @override
  Future<void> pause({bool isPartyDriven = false}) => _pauseImpl(isPartyDriven: isPartyDriven);

  @override
  Future<void> onTaskRemoved() => _onTaskRemovedImpl();

  @override
  Future<void> onNotificationDeleted() async {
    AppLogger.log('PaatuAudioHandler', 'Media notification dismissed by user -> stopping service');
    await stop();
  }

  @override
  Future<void> seek(Duration position, {bool isPartyDriven = false}) =>
      _seekImpl(position, isPartyDriven: isPartyDriven);

  @override
  Future<void> stop() async {
    await _stopImpl();
    await super.stop();
  }

  Future<void> dispose() => _disposeImpl();

  Future<void> toggleLoopMode() => _toggleLoopModeImpl();

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) => _setRepeatModeImpl(repeatMode);

  int _lastSkipTimeMs = 0;
  static const int _skipDebounceMs = 300;

  @override
  Future<void> skipToNext() => _skipToNextImpl();

  @override
  Future<void> skipToQueueItem(int index) => _skipToQueueItemImpl(index);

  Future<void> skipToQueueTrack(
    TrackEntity targetTrack, {
    bool fromUserQueue = false,
    bool fromPlayedHistory = false,
  }) =>
      _skipToQueueTrackImpl(
        targetTrack,
        fromUserQueue: fromUserQueue,
        fromPlayedHistory: fromPlayedHistory,
      );

  @override
  Future<void> skipToPrevious() => _skipToPreviousImpl();

  // ================= Android Auto & MediaBrowserService Hierarchy ================= //

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) =>
      _getChildrenImpl(parentMediaId, options);

  @override
  Future<MediaItem?> getMediaItem(String mediaId) => _getMediaItemImpl(mediaId);

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) =>
      _playFromMediaIdImpl(mediaId, extras);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    AppLogger.log('PlayerHandler', 'Android Auto voice search: "$clean"');
    try {
      final results = await SearchService.searchSongsTab(clean, limit: 10);
      if (results.isNotEmpty) {
        await playSong(results.first, queue: results);
      }
    } catch (e) {
      AppLogger.log('PlayerHandler', 'Android Auto playFromSearch error: $e');
    }
  }

  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]) async {
    final isGoogleVideo = uri.host.toLowerCase().contains('googlevideo.com');
    final Map<String, String>? headers = isGoogleVideo
        ? YouTubeClient.headersForUrl(uri.toString())
        : null;
    try {
      final source = AudioSource.uri(uri, headers: headers);
      await _player.setAudioSource(source);
      if (_player.duration != null && _player.duration!.inMilliseconds > 0) {
        if (mediaItem.value != null) {
          mediaItem.add(mediaItem.value!.copyWith(duration: _player.duration));
        }
        _broadcastState();
      }
      await play();
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'PlayerHandler.playFromUri');
      await _queueHandler.handlePlaybackError(e, stack, context: 'PlayerHandler.playFromUri');
    }
  }
}
