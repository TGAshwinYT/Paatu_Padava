import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../domain/models/track_entity.dart';
import '../domain/models/app_error.dart';
import '../services/download_manager.dart';
import '../services/settings_manager.dart';
import '../services/youtube_client.dart';
import '../services/error_handler.dart';
import '../services/player_handler.dart';
import '../services/app_logger.dart';
import '../services/battery_optimization_service.dart';
import '../services/queue_cooldown_manager.dart';
import '../services/des_decrypt.dart';
import '../services/connectivity_service.dart';
import 'stream_resolver.dart';
import 'next_track_strategy.dart';

/// AudioQueueHandler: Two-Tier Decoupled Queue Engine matching Spotify and YouTube Music.
/// 
/// Decouples manual user additions from the album/playlist context queue:
/// 1. `_contextQueue` (List<TrackEntity>): Immutable/persistent album or playlist context.
/// 2. `_userQueue` (List<TrackEntity>): High-priority manual user queue ("Play Next" & "Add to Queue").
/// 3. `_contextShuffleIndices` (List<int>): Non-destructive index permutation table applied ONLY to `_contextQueue`.
/// 4. `_playbackHistory` (List<TrackEntity>): Previous track stack for backward navigation.
///
/// Priority Order: [Current Track] -> [_userQueue] -> [Remaining _contextQueue]
class AudioQueueHandler {
  final AudioPlayer player;
  final StreamResolver streamResolver;

  // Persistent ConcatenatingAudioSource for Spotify-grade gapless playback
  ConcatenatingAudioSource _playlistSource = ConcatenatingAudioSource(
    children: [],
    useLazyPreparation: true,
  );

  // ================= Two-Tier Architecture State ================= //

  // 1. Context Queue: persistent album / playlist context
  final List<TrackEntity> _contextQueue = [];
  final List<int> _contextShuffleIndices = [];
  int _contextIndex = -1;
  bool _isShuffleEnabled = false;

  // 2. User Queue: high-priority explicit user queue (never shuffled, FIFO priority)
  final List<TrackEntity> _userQueue = [];

  // 3. Playback History: tracks played prior to current track
  final List<TrackEntity> _playbackHistory = [];

  // Active track state
  TrackEntity? _currentTrack;
  bool _currentTrackIsFromUserQueue = false;
  int _playlistBaseIndex = 0;

  // Streams for two-tier architecture
  final StreamController<TrackEntity?> _currentTrackController = StreamController<TrackEntity?>.broadcast();
  final StreamController<TrackEntity?> _nextTrackController = StreamController<TrackEntity?>.broadcast();
  final StreamController<List<TrackEntity>> _queueStreamController = StreamController<List<TrackEntity>>.broadcast();

  Stream<TrackEntity?> get currentTrackStream => _currentTrackController.stream;
  Stream<TrackEntity?> get nextTrackStream => _nextTrackController.stream;
  Stream<List<TrackEntity>> get queueStream => _queueStreamController.stream;

  // Atomic state notifiers for UI and notification sync
  final ValueNotifier<List<Song>> queueNotifier = ValueNotifier<List<Song>>([]);
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier<Song?>(null);
  final ValueNotifier<AppError?> errorNotifier = ValueNotifier<AppError?>(null);

  // Callbacks
  final void Function(Song song)? onSongChanged;
  final void Function(int currentIndex, int totalQueue)? onQueueProgress;
  final void Function(bool isPlaying)? onPlayStateChanged;
  final VoidCallback? onIdleRelease;
  final void Function(AppError error)? onError;

  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<SequenceState?>? _sequenceStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  Timer? _idleTimeoutTimer;

  int _sessionToken = 0;
  int _activeLoadSessionToken = 0;
  bool _isLoading = false;
  bool _isDisposed = false;
  int _fadeToken = 0;
  int _lastCrossfadeTimeMs = 0;
  bool _hasRetriedCurrentTrack = false;
  bool _isLookaheadTriggered = false;
  bool _wasStalledByNetwork = false;
  Duration _networkStallOffset = Duration.zero;
  VoidCallback? _connectivityListener;

  AudioQueueHandler({
    required this.player,
    StreamResolver? streamResolver,
    this.onSongChanged,
    this.onQueueProgress,
    this.onPlayStateChanged,
    this.onIdleRelease,
    this.onError,
  }) : streamResolver = streamResolver ?? DefaultStreamResolver() {
    _initStreamListeners();
    SettingsManager.volumeNormalizationNotifier.addListener(_onNormalizationChanged);
    _connectivityListener = () => _onConnectivityChanged();
    ConnectivityService.isOnlineNotifier.addListener(_connectivityListener!);
  }

  // ================= Public Queue Getters ================= //

  LoopMode get _effectiveLoopMode {
    try {
      return player.loopMode;
    } catch (_) {
      return LoopMode.off;
    }
  }

  TrackEntity? get currentTrack => _currentTrack;

  TrackEntity? get nextTrack {
    // 1. User queue has absolute immediate priority
    if (_userQueue.isNotEmpty) {
      return _userQueue.first;
    }
    // 2. Remaining context tracks
    final remaining = remainingContextTracks;
    if (remaining.isNotEmpty) {
      return remaining.first;
    }
    // 3. RepeatMode.all: loop context queue only
    if (_effectiveLoopMode == LoopMode.all && _contextQueue.isNotEmpty) {
      if (_isShuffleEnabled && _contextShuffleIndices.isNotEmpty) {
        return _contextQueue[_contextShuffleIndices[0]];
      }
      return _contextQueue[0];
    }
    return null;
  }

  List<TrackEntity> get contextQueue => List.unmodifiable(_contextQueue);
  List<TrackEntity> get userQueue => List.unmodifiable(_userQueue);
  List<TrackEntity> get playbackHistory => List.unmodifiable(_playbackHistory);
  List<int> get contextShuffleIndices => List.unmodifiable(_contextShuffleIndices);
  List<int> get shuffleIndices => _isShuffleEnabled ? contextShuffleIndices : List.generate(_contextQueue.length, (i) => i);
  bool get isShuffleEnabled => _isShuffleEnabled;
  int get contextIndex => _contextIndex;
  bool get currentTrackIsFromUserQueue => _currentTrackIsFromUserQueue;

  /// Remaining context tracks following current position in context sequence
  List<TrackEntity> get remainingContextTracks {
    if (_contextQueue.isEmpty) return const [];
    if (_isShuffleEnabled) {
      if (_contextIndex + 1 < _contextShuffleIndices.length) {
        return _contextShuffleIndices
            .sublist(_contextIndex + 1)
            .map((i) => _contextQueue[i])
            .toList();
      }
      return const [];
    } else {
      if (_contextIndex + 1 < _contextQueue.length) {
        return _contextQueue.sublist(_contextIndex + 1);
      }
      return const [];
    }
  }

  /// Merged effective queue: [Played Context] + [Current Track] + [_userQueue] + [Remaining _contextQueue]
  List<Song> get queue => _buildMergedQueue().map((t) => t.toSong()).toList();
  List<Song> get rawQueue => _contextQueue.map((t) => t.toSong()).toList();
  List<Song> get originalQueue => _contextQueue.map((t) => t.toSong()).toList();

  int get currentIndex {
    final merged = _buildMergedQueue();
    if (_currentTrack == null || merged.isEmpty) return -1;
    final idx = merged.indexWhere((t) => t.id == _currentTrack!.id);
    return idx != -1 ? idx : 0;
  }

  int get playlistBaseIndex => _playlistBaseIndex;
  Song? get currentSong => _currentTrack?.toSong();
  Song? get nextSong => nextTrack?.toSong();
  bool get hasNext => _userQueue.isNotEmpty || remainingContextTracks.isNotEmpty;
  bool get hasPrevious => _playbackHistory.isNotEmpty || _contextIndex > 0;
  int get upcomingCount => _userQueue.length + remainingContextTracks.length;
  bool get isLoading => _isLoading;

  int getPendingUserQueueCount() => _userQueue.length;
  int get userQueueEndIndex => currentIndex + 1 + _userQueue.length;

  // ================= Master Volume & Normalization ================= //

  double _userVolume = 1.0;
  double get userVolume => _userVolume;

  /// Sets master playback volume (0.0 to 1.0) and applies song normalization
  Future<void> setUserVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    final effective = getEffectiveVolumeForSong(currentSong);
    try {
      await player.setVolume(effective);
    } catch (_) {}
  }

  /// Calculates target normalized volume (0.0 to 1.0)
  static double getNormalizedVolumeForSong(Song? song) {
    if (!SettingsManager.isVolumeNormalizationEnabled) {
      return 1.0;
    }
    if (song == null) return 1.0;

    if (song.source == 'youtube' ||
        (song.streamUrl != null &&
            (song.streamUrl!.contains('googlevideo.com') ||
                song.streamUrl!.contains('webm') ||
                song.streamUrl!.contains('youtube')))) {
      return 1.0;
    }

    final isHotStudioMaster = song.source == 'saavn' ||
        song.source == 'jiosaavn' ||
        (song.streamUrl != null &&
            (song.streamUrl!.contains('jiosaavn') || song.streamUrl!.contains('.mp4')));

    if (isHotStudioMaster) {
      return 0.80; // ~ -2.0 dB calibration to match YouTube -14 LUFS reference
    }
    return 1.0;
  }

  /// Calculates effective volume taking both master volume and song calibration into account
  double getEffectiveVolumeForSong(Song? song) {
    return (_userVolume * getNormalizedVolumeForSong(song)).clamp(0.0, 1.0);
  }

  Future<void> _ensureAudioSessionActive() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      AppLogger.log('AudioQueueHandler', 'AudioSession.setActive(true) notice: $e');
    }
  }

  void _startVolumeWatchdog(Song? song) {
    if (song == null) return;
    Future.delayed(const Duration(milliseconds: 380), () {
      if (!_isDisposed && player.playing) {
        final targetNorm = getEffectiveVolumeForSong(song);
        if (player.volume < 0.1 && targetNorm >= 0.2) {
          AppLogger.log('AudioQueueHandler', 'Volume watchdog: Restoring stuck volume (${player.volume} -> $targetNorm)');
          try {
            player.setVolume(targetNorm);
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _fadeVolumeTo(double targetVolume, {int durationMs = 250}) async {
    if (_isDisposed) return;
    final myToken = ++_fadeToken;
    final startVolume = player.volume;
    if ((startVolume - targetVolume).abs() < 0.02) {
      try {
        await player.setVolume(targetVolume);
      } catch (_) {}
      return;
    }

    const int steps = 8;
    final stepMs = (durationMs / steps).round();
    for (int i = 1; i <= steps; i++) {
      if (_isDisposed || myToken != _fadeToken) return;
      final v = startVolume + (targetVolume - startVolume) * (i / steps);
      try {
        await player.setVolume(v.clamp(0.0, 1.0));
      } catch (_) {}
      await Future.delayed(Duration(milliseconds: stepMs));
    }
    if (!_isDisposed && myToken == _fadeToken) {
      try {
        await player.setVolume(targetVolume);
      } catch (_) {}
    }
  }

  void _onNormalizationChanged() {
    final target = getEffectiveVolumeForSong(currentSong);
    _fadeVolumeTo(target, durationMs: 250);
  }

  void _handleCrossfade(Duration pos) {
    final crossfadeSec = SettingsManager.crossfadeSeconds;
    if (crossfadeSec <= 0) return;
    final duration = player.duration;
    if (duration == null || duration.inSeconds <= crossfadeSec * 2) return;

    final remaining = duration - pos;
    if (remaining.inSeconds <= crossfadeSec && remaining.inMilliseconds > 250) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCrossfadeTimeMs < 100) return;
      _lastCrossfadeTimeMs = now;

      final targetNorm = getEffectiveVolumeForSong(currentSong);
      final ratio = (remaining.inMilliseconds / (crossfadeSec * 1000)).clamp(0.0, 1.0);
      final fadedVolume = targetNorm * ratio;
      try {
        player.setVolume(fadedVolume.clamp(0.0, 1.0));
      } catch (_) {}
    }
  }

  // ================= Idle Timeout & Battery Management ================= //

  Timer? get idleTimeoutTimer => _idleTimeoutTimer;
  bool get isIdleTimeoutActive => _idleTimeoutTimer != null && _idleTimeoutTimer!.isActive;

  void startIdleTimer({Duration timeout = const Duration(seconds: 45)}) {
    cancelIdleTimer();
    if (player.playing || _isLoading) return;
    _idleTimeoutTimer = Timer(timeout, () {
      handleIdleRelease();
    });
    AppLogger.log('AudioQueueHandler', 'Started 45-second idle timeout countdown');
  }

  void cancelIdleTimer() {
    if (_idleTimeoutTimer != null) {
      _idleTimeoutTimer?.cancel();
      _idleTimeoutTimer = null;
      AppLogger.log('AudioQueueHandler', 'Cancelled idle timeout countdown');
    }
  }

  Future<void> handleIdleRelease() async {
    if (player.playing || _isLoading) {
      AppLogger.log('AudioQueueHandler', 'handleIdleRelease aborted: player is still active or loading');
      cancelIdleTimer();
      return;
    }
    AppLogger.log('AudioQueueHandler', '45-second idle timeout reached. Downgrading notification & releasing WakeLocks.');
    YouTubeClient.closeIdleClient();

    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioSession.setActive(false)');
    }

    try {
      await BatteryOptimizationService.detachForeground();
    } catch (_) {}

    onIdleRelease?.call();
  }

  // ================= Stream Listeners ================= //

  void _initStreamListeners() {
    // Sequence state listener: updates current song tag metadata without modifying index
    _sequenceStateSub = player.sequenceStateStream.listen((sequenceState) {
      if (sequenceState == null) return;
      final currentSource = sequenceState.currentSource;
      if (currentSource != null && currentSource.tag != null) {
        final tag = currentSource.tag;
        Song? activeSong;
        if (tag is Song) {
          activeSong = tag;
        } else if (tag is MediaItem) {
          activeSong = Song.fromMediaItem(tag);
        }
        if (activeSong != null && activeSong.id != currentSongNotifier.value?.id) {
          currentSongNotifier.value = activeSong;
          onSongChanged?.call(activeSong);
          onQueueProgress?.call(currentIndex, queue.length);
        }
      }
    });

    // Gapless track advance in ConcatenatingAudioSource sliding window
    _currentIndexSub = player.currentIndexStream.listen((index) {
      if (index != null && index > 0) {
        // Player advanced naturally to the upcoming primed track
        _advanceToNextTrackFromPlayerStream();
      }
    });

    _positionSub = player.positionStream.listen((pos) {
      if (SettingsManager.crossfadeSeconds > 0) {
        _handleCrossfade(pos);
      }

      // Lookahead Pre-Resolution & Recommendation Pre-fetch (80% progress or <= 15s remaining)
      final dur = player.duration;
      if (dur != null && dur.inSeconds > 15 && !_isLookaheadTriggered) {
        final remainingSec = dur.inSeconds - pos.inSeconds;
        final progressRatio = pos.inMilliseconds / dur.inMilliseconds;
        if (progressRatio >= 0.80 || remainingSec <= 15) {
          _isLookaheadTriggered = true;
          AppLogger.log('AudioQueueHandler', 'Lookahead threshold reached (${(progressRatio * 100).toInt()}% / ${remainingSec}s remaining).');

          if (hasNext) {
            preloadUpcomingTracks();
          }

          final remainingUpcoming = upcomingCount;
          if (remainingUpcoming <= 1 && SettingsManager.isAutoplayEnabled && isAudioHandlerInitialized) {
            final active = currentSong;
            if (active != null) {
              AppLogger.log('AudioQueueHandler', 'Lookahead triggered recommendation pre-fetch for "${active.title}" (upcoming count: $remainingUpcoming)');
              audioHandler.prefetchNextRecommendations(active);
            }
          }
        }
      }
    });

    try {
      _playbackEventSub = player.playbackEventStream.listen(
        (_) {},
        onError: (Object e, StackTrace st) async {
          AppLogger.recordError(e, st, context: 'AudioQueueHandler.playbackEventStream');
          final current = currentSong;
          if (current != null) {
            AppLogger.log('AudioQueueHandler', 'Playback error on active track "${current.title}" (${current.id})');
            current.streamUrl = null;
            streamResolver.invalidate(current.id);
            DefaultStreamResolver.invalidateStream(current.id);
            YouTubeClient.invalidateStream(current.id);

            if (!_hasRetriedCurrentTrack && !_isDisposed) {
              _hasRetriedCurrentTrack = true;
              AppLogger.log('AudioQueueHandler', 'Auto-recovery: re-resolving fresh stream for "${current.title}"');
              final freshUrl = await _resolveStreamUrl(current);
              if (freshUrl != null && freshUrl.isNotEmpty && !_isDisposed) {
                current.streamUrl = freshUrl;
                _updateTrackStreamUrl(current.id, freshUrl);
                final freshSource = await _buildAudioSource(current, allowNetworkResolve: false);
                if (freshSource != null && !_isDisposed) {
                  try {
                    await player.setAudioSource(freshSource);
                    await _ensureAudioSessionActive();
                    await player.play();
                    final targetNorm = getEffectiveVolumeForSong(current);
                    await player.setVolume(targetNorm);
                    _startVolumeWatchdog(current);
                    AppLogger.log('AudioQueueHandler', 'Auto-recovery successful for "${current.title}"');
                    return;
                  } catch (recoveryErr) {
                    AppLogger.log('AudioQueueHandler', 'Auto-recovery play failed: $recoveryErr');
                  }
                }
              }
            }

            if (!ConnectivityService.currentIsOnline && _currentTrack != null && !DownloadManager.isDownloaded(_currentTrack!.id)) {
              _wasStalledByNetwork = true;
              if (player.position > Duration.zero) {
                _networkStallOffset = player.position;
              }
              AppLogger.log('AudioQueueHandler', 'Network offline during playback error. Cached stall offset ${_networkStallOffset.inSeconds}s for automatic zero-touch recovery.');
            }

            final appErr = ErrorHandler.resolve(e, stackTrace: st, context: 'Playback event on ${current.title}');
            errorNotifier.value = appErr;
            onError?.call(appErr);
            if (isAudioHandlerInitialized) {
              audioHandler.playbackErrorNotifier.value = appErr;
            }
          }
        },
      );
    } catch (_) {}

    _playerStateSub = player.playerStateStream.listen((state) {
      onPlayStateChanged?.call(state.playing);

      if (state.playing) {
        cancelIdleTimer();
      } else {
        startIdleTimer();
      }

      if (!ConnectivityService.currentIsOnline && _currentTrack != null && !DownloadManager.isDownloaded(_currentTrack!.id)) {
        if (state.processingState == ProcessingState.buffering || state.processingState == ProcessingState.idle || !state.playing) {
          _wasStalledByNetwork = true;
          if (player.position > Duration.zero) {
            _networkStallOffset = player.position;
          }
        }
      }

      if (state.processingState == ProcessingState.completed) {
        final current = currentSong;
        if (current != null) {
          QueueCooldownManager.recordPlayed(current);
          final dur = player.duration ?? const Duration(seconds: 180);
          audioHandler.smartShuffleController.recordPlaybackFeedback(
            current,
            listenedSeconds: dur.inSeconds,
            totalSeconds: dur.inSeconds,
          );
        }

        // LoopMode.one: Replay current track in place without advancing either queue
        if (_effectiveLoopMode == LoopMode.one) {
          if (_currentTrack != null) {
            player.seek(Duration.zero);
            player.play();
            return;
          }
        }

        if (hasNext) {
          skipToNext();
        } else if (_effectiveLoopMode == LoopMode.all && _contextQueue.isNotEmpty) {
          handleRepeatAllLoop();
        } else if (SettingsManager.isAutoplayEnabled && current != null && isAudioHandlerInitialized) {
          audioHandler.handleAutoplayQueueEnd(current);
        } else {
          startIdleTimer();
        }
      }
    });
  }

  /// Automatic stream re-attachment engine:
  /// When network reconnects after an outage, automatically invalidates expired/broken stream URLs,
  /// obtains a fresh stream URL, seeks to the cached playback offset, and resumes without user intervention.
  Future<void> _onConnectivityChanged() async {
    if (_isDisposed) return;
    final isOnline = ConnectivityService.currentIsOnline;
    if (isOnline && _wasStalledByNetwork && _currentTrack != null) {
      AppLogger.log(
        'AudioQueueHandler',
        'Zero-touch network recovery: Connection restored! Re-resolving fresh stream for "${_currentTrack!.title}" at offset ${_networkStallOffset.inSeconds}s',
      );
      _wasStalledByNetwork = false;
      final current = _currentTrack!.toSong();
      final resumeOffset = _networkStallOffset;

      // Invalidate expired/broken stream URL
      current.streamUrl = null;
      streamResolver.invalidate(current.id);
      DefaultStreamResolver.invalidateStream(current.id);
      YouTubeClient.invalidateStream(current.id);

      final freshUrl = await _resolveStreamUrl(current);
      if (freshUrl != null && freshUrl.isNotEmpty && !_isDisposed) {
        current.streamUrl = freshUrl;
        _updateTrackStreamUrl(current.id, freshUrl);
        final freshSource = await _buildAudioSource(current, allowNetworkResolve: false);
        if (freshSource != null && !_isDisposed) {
          try {
            await player.setAudioSource(freshSource, initialPosition: resumeOffset);
            await _ensureAudioSessionActive();
            await player.play();
            final targetNorm = getEffectiveVolumeForSong(current);
            await player.setVolume(targetNorm);
            _startVolumeWatchdog(current);
            AppLogger.log('AudioQueueHandler', 'Zero-touch network recovery succeeded for "${current.title}"');
          } catch (e) {
            AppLogger.log('AudioQueueHandler', 'Zero-touch network recovery resume notice: $e');
          }
        }
      }
    }
  }

  void _syncState() {
    final merged = _buildMergedQueue();
    final curSong = _currentTrack?.toSong();
    final curIdx = currentIndex;

    currentIndexNotifier.value = curIdx;
    queueNotifier.value = merged.map((t) => t.toSong()).toList();
    currentSongNotifier.value = curSong;

    _currentTrackController.add(_currentTrack);
    _nextTrackController.add(nextTrack);
    _queueStreamController.add(merged);
  }

  // ================= Load Queue & Initial Setup ================= //

  /// Plays a standalone track (e.g. from History or Search), clearing context queue
  /// and resetting session playback history while preserving any manual user queue.
  Future<void> playTrack(TrackEntity track, {bool preserveUserQueue = true}) async {
    await loadQueue(
      [track],
      initialIndex: 0,
      autoPlay: true,
      preserveUserQueue: preserveUserQueue,
    );
  }

  Future<void> loadQueue(
    List<dynamic> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
    bool preserveUserQueue = false,
  }) async {
    if (tracks.isEmpty) {
      _isLoading = false;
      return;
    }

    final entities = tracks.map((t) => _toEntity(t)).toList();
    final targetTrack = (initialIndex >= 0 && initialIndex < entities.length)
        ? entities[initialIndex]
        : entities.first;

    if (_isLoading && _currentTrack?.id == targetTrack.id) {
      AppLogger.log('AudioQueueHandler', 'loadQueue: duplicate call for "${targetTrack.title}" ignored (already loading)');
      return;
    }

    cancelIdleTimer();
    final token = ++_sessionToken;
    _activeLoadSessionToken = token;
    _isLoading = true;

    try {
      AppLogger.log('AudioQueueHandler', 'loadQueue: ${entities.length} tracks, initialIndex=$initialIndex, autoPlay=$autoPlay');

      try {
        await player.stop();
      } catch (_) {}

      if (token != _sessionToken) return;

      // Initialize two-tier decoupled queues
      _contextQueue.clear();
      _contextQueue.addAll(entities);
      _contextShuffleIndices.clear();
      _isShuffleEnabled = false;

      if (!preserveUserQueue) {
        _userQueue.clear();
      }
      _playbackHistory.clear();

      _contextIndex = (initialIndex >= 0 && initialIndex < entities.length) ? initialIndex : 0;
      _currentTrack = entities[_contextIndex];
      _currentTrackIsFromUserQueue = false;

      NextTrackStrategyFactory.resetSession(initialAnchor: _currentTrack?.toSong());

      _syncState();

      final activeSong = _currentTrack!.toSong();
      onSongChanged?.call(activeSong);

      // JIT resolve stream URL for active song
      if (activeSong.streamUrl == null || activeSong.streamUrl!.isEmpty || streamResolver.isExpired(activeSong.id)) {
        final resolvedUrl = await _resolveStreamUrl(activeSong);
        if (token != _sessionToken) return;
        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          activeSong.streamUrl = resolvedUrl;
          _updateTrackStreamUrl(activeSong.id, resolvedUrl);
        } else {
          AppLogger.log('AudioQueueHandler', 'Failed to resolve active song: "${activeSong.title}".');
          final appErr = AppError.songUnavailable(
            activeSong.title,
            debugDetails: 'Active song stream resolution returned null in loadQueue',
          );
          errorNotifier.value = appErr;
          onError?.call(appErr);
          if (isAudioHandlerInitialized) {
            audioHandler.playbackErrorNotifier.value = appErr;
          }
        }
      }

      // Build initial sliding window: [activeTrack, nextTrack]
      final List<AudioSource> sources = [];
      final activeSrc = (activeSong.streamUrl != null && activeSong.streamUrl!.isNotEmpty)
          ? await _buildAudioSource(activeSong, allowNetworkResolve: false)
          : null;

      if (activeSrc != null) {
        sources.add(activeSrc);
        final next = nextTrack;
        if (next != null) {
          final nextSrc = await _buildAudioSource(next.toSong(), allowNetworkResolve: true);
          if (nextSrc != null && token == _sessionToken) {
            sources.add(nextSrc);
          }
        }
      } else {
        AppLogger.log('AudioQueueHandler', 'Active song "${activeSong.title}" could not be resolved.');
        if (autoPlay && hasNext) {
          await skipToNext();
          return;
        }
      }

      if (sources.isEmpty) {
        AppLogger.log('AudioQueueHandler', 'No playable tracks found in audio source window.');
        return;
      }

      _playlistBaseIndex = currentIndex;
      _playlistSource = ConcatenatingAudioSource(
        children: sources,
        useLazyPreparation: true,
      );

      final targetNorm = getEffectiveVolumeForSong(activeSong);
      final crossfadeSec = SettingsManager.crossfadeSeconds;
      if (crossfadeSec > 0) {
        try {
          await player.setVolume(0.0);
        } catch (_) {}
      } else {
        try {
          await player.setVolume(targetNorm);
        } catch (_) {}
      }

      try {
        await player.setAudioSource(
          _playlistSource,
          initialIndex: 0,
          initialPosition: Duration.zero,
        );

        if (token != _sessionToken) return;

        if (autoPlay) {
          await _ensureAudioSessionActive();
          await player.play();
          if (crossfadeSec > 0) {
            _fadeVolumeTo(targetNorm, durationMs: (crossfadeSec * 600).clamp(250, 2000));
          } else {
            await player.setVolume(targetNorm);
          }
          _startVolumeWatchdog(activeSong);
        }

        _hasRetriedCurrentTrack = false;
        onQueueProgress?.call(currentIndex, queue.length);
        preloadUpcomingTracks();
      } catch (e, stack) {
        AppLogger.recordError(e, stack, context: 'AudioQueueHandler.loadQueue setAudioSource');
        final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'AudioQueueHandler.loadQueue');
        audioHandler.playbackErrorNotifier.value = appErr;
        if (hasNext) {
          Future.delayed(const Duration(seconds: 2), () {
            if (!_isDisposed && queue.isNotEmpty) skipToNext();
          });
        }
      }
    } finally {
      if (_activeLoadSessionToken == token) {
        _isLoading = false;
      }
    }
  }

  // ================= Deterministic "Play Next" and "Add to Queue" ================= //

  /// Insert track at index 0 of the user queue.
  /// MUST play immediately after the current song, regardless of shuffle state.
  Future<void> playNext(dynamic track) async {
    final entity = _toEntity(track).copyWith(isUserEnqueued: true);
    AppLogger.log('AudioQueueHandler', 'playNext: "${entity.title}" [id=${entity.id}]');

    if (_contextQueue.isEmpty && _userQueue.isEmpty && _currentTrack == null) {
      await loadQueue([entity], initialIndex: 0, autoPlay: true);
      return;
    }

    _userQueue.insert(0, entity);
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  /// Backward-compatible alias for playNext
  Future<void> insertNext(dynamic track) => playNext(track);

  /// Append track to the end of the user queue.
  /// Plays after all existing user-queued tracks, before returning to the context queue.
  Future<void> addToQueue(dynamic track) async {
    final entity = _toEntity(track).copyWith(isUserEnqueued: true);
    AppLogger.log('AudioQueueHandler', 'addToQueue: "${entity.title}" [id=${entity.id}]');

    if (_contextQueue.isEmpty && _userQueue.isEmpty && _currentTrack == null) {
      await loadQueue([entity], initialIndex: 0, autoPlay: true);
      return;
    }

    _userQueue.add(entity);
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  /// Append multiple tracks sequentially to the user queue
  Future<void> addAllToQueue(List<dynamic> tracks) async {
    if (tracks.isEmpty) return;
    if (_contextQueue.isEmpty && _userQueue.isEmpty && _currentTrack == null) {
      await loadQueue(tracks, initialIndex: 0, autoPlay: true);
      return;
    }
    for (final t in tracks) {
      _userQueue.add(_toEntity(t).copyWith(isUserEnqueued: true));
    }
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  /// Insert track at specific index in merged queue maintaining two-tier separation
  Future<void> insertAt(int index, dynamic track) async {
    final entity = _toEntity(track);
    final curIdx = currentIndex;

    if (entity.isUserEnqueued) {
      final userOffset = (index - (curIdx + 1)).clamp(0, _userQueue.length);
      _userQueue.insert(userOffset, entity);
    } else {
      final safeIdx = index.clamp(0, _contextQueue.length);
      _contextQueue.insert(safeIdx, entity);
      if (_isShuffleEnabled) {
        _contextShuffleIndices.insert(safeIdx.clamp(0, _contextShuffleIndices.length), _contextQueue.length - 1);
      }
      if (safeIdx <= _contextIndex) {
        _contextIndex++;
      }
    }
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  // ================= Non-Destructive Shuffle Permutation ================= //

  /// Apply shuffle ONLY to _contextQueue using an index permutation list.
  /// Never shuffles _userQueue (user queue retains strict FIFO priority).
  /// - When enabled: keeps active track at index 0 of _contextShuffleIndices and randomizes remainder.
  /// - When disabled: anchors active track back to its exact index in _contextQueue.
  Future<void> setShuffleEnabled(bool enable) async {
    if (_isShuffleEnabled == enable) return;
    if (_contextQueue.isEmpty) {
      _isShuffleEnabled = enable;
      return;
    }

    if (enable) {
      _isShuffleEnabled = true;
      int activeRawIdx = 0;
      if (_currentTrack != null) {
        final match = _contextQueue.indexWhere((t) => t.id == _currentTrack!.id);
        if (match != -1) activeRawIdx = match;
      } else if (_contextIndex >= 0 && _contextIndex < _contextQueue.length) {
        activeRawIdx = _contextIndex;
      }

      final List<int> remainder = [];
      for (int i = 0; i < _contextQueue.length; i++) {
        if (i != activeRawIdx) remainder.add(i);
      }
      remainder.shuffle();

      _contextShuffleIndices.clear();
      _contextShuffleIndices.add(activeRawIdx);
      _contextShuffleIndices.addAll(remainder);
      _contextIndex = 0;
      _playlistBaseIndex = currentIndex;

      _syncState();
      AppLogger.log('AudioQueueHandler', 'Shuffle enabled: ${_currentTrack?.title} pinned to index 0, ${_contextShuffleIndices.length} context items permuted');
      _invalidateUpcomingPlaylistSource();
      preloadUpcomingTracks();
    } else {
      _isShuffleEnabled = false;

      int restoredRawIdx = 0;
      if (_currentTrack != null) {
        final match = _contextQueue.indexWhere((t) => t.id == _currentTrack!.id);
        if (match != -1) restoredRawIdx = match;
      } else if (_contextIndex >= 0 && _contextIndex < _contextShuffleIndices.length) {
        restoredRawIdx = _contextShuffleIndices[_contextIndex];
      }

      _contextIndex = restoredRawIdx;
      _contextShuffleIndices.clear();
      _playlistBaseIndex = currentIndex;

      _syncState();
      AppLogger.log('AudioQueueHandler', 'Shuffle disabled: anchored to raw index $restoredRawIdx for "${_currentTrack?.title}"');
      _invalidateUpcomingPlaylistSource();
      preloadUpcomingTracks();
    }
  }

  Future<void> toggleShuffle() async {
    await setShuffleEnabled(!_isShuffleEnabled);
  }

  // ================= Track Navigation & Consumption ================= //

  /// Skip to next track: consumes _userQueue first, then advances _contextQueue
  Future<void> skipToNext() async {
    if (_currentTrack != null) {
      final listenedSec = player.position.inSeconds;
      NextTrackStrategyFactory.recordSkip(_currentTrack!.toSong(), listenedSeconds: listenedSec);
    }

    if (_effectiveLoopMode == LoopMode.one) {
      if (_currentTrack != null) {
        await player.seek(Duration.zero);
        await player.play();
        return;
      }
    }

    // 1. If currently playing track was from user queue and is still at index 0, pop it
    if (_currentTrack != null && _currentTrackIsFromUserQueue && _userQueue.isNotEmpty && _userQueue.first.id == _currentTrack!.id) {
      _userQueue.removeAt(0);
    }

    // 2. If _userQueue still has items, play _userQueue.first (popping it)
    if (_userQueue.isNotEmpty) {
      final next = _userQueue.removeAt(0);
      if (_currentTrack != null) {
        _playbackHistory.add(_currentTrack!);
      }
      _currentTrack = next;
      _currentTrackIsFromUserQueue = true;
      await _playTrackEntity(next);
      return;
    }

    // 3. _userQueue is empty:
    // When transitioning from a user-queued track, user tracks do NOT exist in _contextQueue.
    // Do NOT call _contextQueue.indexOf(currentTrack).
    // Instead, cleanly RESUME _contextQueue at _contextIndex + 1.
    // DO NOT call next_track_strategy unless _contextIndex + 1 >= _contextQueue.length.
    final hasNextContext = _isShuffleEnabled
        ? (_contextIndex + 1 < _contextShuffleIndices.length)
        : (_contextIndex + 1 < _contextQueue.length);

    if (hasNextContext) {
      _contextIndex++;
      final next = _isShuffleEnabled
          ? _contextQueue[_contextShuffleIndices[_contextIndex]]
          : _contextQueue[_contextIndex];
      if (_currentTrack != null) {
        _playbackHistory.add(_currentTrack!);
      }
      _currentTrack = next;
      _currentTrackIsFromUserQueue = false;
      await _playTrackEntity(next);
      return;
    }

    // 4. End of context queue reached (_contextIndex + 1 >= _contextQueue.length): Check LoopMode.all
    if (_effectiveLoopMode == LoopMode.all && _contextQueue.isNotEmpty) {
      await handleRepeatAllLoop();
      return;
    }

    // 5. Autoplay replenishment ONLY when at EOF (_contextIndex + 1 >= _contextQueue.length)
    if (SettingsManager.isAutoplayEnabled && _currentTrack != null && isAudioHandlerInitialized) {
      await audioHandler.handleAutoplayQueueEnd(_currentTrack!.toSong());
    }
  }

  /// Skip to previous track in playback history or context sequence
  Future<void> skipToPrevious() async {
    if (player.position.inSeconds > 4) {
      await player.seek(Duration.zero);
      return;
    }

    if (_playbackHistory.isNotEmpty) {
      final prev = _playbackHistory.removeLast();
      _currentTrack = prev;
      _currentTrackIsFromUserQueue = prev.isUserEnqueued;
      if (!prev.isUserEnqueued) {
        final matchIdx = _isShuffleEnabled
            ? _contextShuffleIndices.indexWhere((i) => _contextQueue[i].id == prev.id)
            : _contextQueue.indexWhere((t) => t.id == prev.id);
        if (matchIdx != -1) _contextIndex = matchIdx;
      }
      await _playTrackEntity(prev);
      return;
    }

    if (_contextIndex > 0) {
      _contextIndex--;
      final prev = _isShuffleEnabled
          ? _contextQueue[_contextShuffleIndices[_contextIndex]]
          : _contextQueue[_contextIndex];
      _currentTrack = prev;
      _currentTrackIsFromUserQueue = false;
      await _playTrackEntity(prev);
      return;
    }

    if (_effectiveLoopMode == LoopMode.all && _contextQueue.isNotEmpty) {
      _contextIndex = _isShuffleEnabled ? _contextShuffleIndices.length - 1 : _contextQueue.length - 1;
      final prev = _isShuffleEnabled
          ? _contextQueue[_contextShuffleIndices[_contextIndex]]
          : _contextQueue[_contextIndex];
      _currentTrack = prev;
      _currentTrackIsFromUserQueue = false;
      await _playTrackEntity(prev);
    }
  }

  /// Jump directly to any index in the merged queue with guaranteed index alignment
  Future<void> jumpToIndex(int targetIndex) async {
    final merged = _buildMergedQueue();
    if (targetIndex < 0 || targetIndex >= merged.length) return;
    final targetEntity = merged[targetIndex];

    AppLogger.log('AudioQueueHandler', 'jumpToIndex: targetIndex=$targetIndex ("${targetEntity.title}")');

    // Any items before targetIndex in merged sequence that were in _userQueue are consumed into _playbackHistory
    final passedItems = merged.sublist(0, targetIndex);
    for (final passed in passedItems) {
      if (_userQueue.remove(passed)) {
        _playbackHistory.add(passed);
      }
    }

    // Check if target is inside _userQueue
    final userIdx = _userQueue.indexWhere((t) => t.id == targetEntity.id);
    if (userIdx != -1) {
      for (int i = 0; i < userIdx; i++) {
        _playbackHistory.add(_userQueue.removeAt(0));
      }
      final target = _userQueue.removeAt(0);
      if (_currentTrack != null) _playbackHistory.add(_currentTrack!);
      _currentTrack = target;
      _currentTrackIsFromUserQueue = true;
      await _playTrackEntity(target);
      return;
    }

    // Target is in context sequence
    final contextSeq = _isShuffleEnabled
        ? _contextShuffleIndices.map((i) => _contextQueue[i]).toList()
        : _contextQueue;
    final ctxIdx = contextSeq.indexWhere((t) => t.id == targetEntity.id);
    if (ctxIdx != -1) {
      if (_currentTrack != null) _playbackHistory.add(_currentTrack!);
      _contextIndex = ctxIdx;
      _currentTrack = contextSeq[ctxIdx];
      _currentTrackIsFromUserQueue = false;
      await _playTrackEntity(contextSeq[ctxIdx]);
    }
  }

  /// Handles gapless advance when just_audio ConcatenatingAudioSource fires index 1
  void _advanceToNextTrackFromPlayerStream() {
    if (_currentTrack != null && _currentTrackIsFromUserQueue && _userQueue.isNotEmpty && _userQueue.first.id == _currentTrack!.id) {
      _userQueue.removeAt(0);
    }

    if (_userQueue.isNotEmpty) {
      final next = _userQueue.removeAt(0);
      if (_currentTrack != null) {
        _playbackHistory.add(_currentTrack!);
      }
      _currentTrack = next;
      _currentTrackIsFromUserQueue = true;
    } else {
      final hasNextContext = _isShuffleEnabled
          ? (_contextIndex + 1 < _contextShuffleIndices.length)
          : (_contextIndex + 1 < _contextQueue.length);

      if (hasNextContext) {
        _contextIndex++;
        final next = _isShuffleEnabled
            ? _contextQueue[_contextShuffleIndices[_contextIndex]]
            : _contextQueue[_contextIndex];
        if (_currentTrack != null) {
          _playbackHistory.add(_currentTrack!);
        }
        _currentTrack = next;
        _currentTrackIsFromUserQueue = false;
      }
    }

    _sessionToken++;
    _playlistBaseIndex = currentIndex;
    _hasRetriedCurrentTrack = false;
    _isLookaheadTriggered = false;
    _syncState();

    final song = currentSong;
    if (song != null) {
      AppLogger.log('AudioQueueHandler', 'Track transition: "${song.title}" [id=${song.id}]');
      _ensureAudioSessionActive();
      onSongChanged?.call(song);
      onQueueProgress?.call(currentIndex, queue.length);

      final targetNorm = getEffectiveVolumeForSong(song);
      final crossfadeSec = SettingsManager.crossfadeSeconds;
      final fadeInMs = crossfadeSec > 0 ? (crossfadeSec * 600).clamp(250, 2000) : 150;
      _fadeVolumeTo(targetNorm, durationMs: fadeInMs);
      _startVolumeWatchdog(song);
      preloadUpcomingTracks();
    }
  }

  /// Handles seamless looping when RepeatMode.all / LoopMode.all reaches EOF.
  /// Loops ONLY _contextQueue; user-enqueued tracks are transient and never repeat.
  Future<void> handleRepeatAllLoop() async {
    AppLogger.log('AudioQueueHandler', 'RepeatMode.all: Looping context queue.');
    _userQueue.clear();

    if (_contextQueue.isEmpty) {
      startIdleTimer();
      return;
    }

    if (_isShuffleEnabled) {
      _contextShuffleIndices.clear();
      final indices = List<int>.generate(_contextQueue.length, (i) => i)..shuffle();
      _contextShuffleIndices.addAll(indices);
      _contextIndex = 0;
      final next = _contextQueue[_contextShuffleIndices[0]];
      if (_currentTrack != null) _playbackHistory.add(_currentTrack!);
      _currentTrack = next;
      _currentTrackIsFromUserQueue = false;
      await _playTrackEntity(next);
    } else {
      _contextIndex = 0;
      final next = _contextQueue[0];
      if (_currentTrack != null) _playbackHistory.add(_currentTrack!);
      _currentTrack = next;
      _currentTrackIsFromUserQueue = false;
      await _playTrackEntity(next);
    }
  }

  Future<void> _playTrackEntity(TrackEntity entity) async {
    final token = ++_sessionToken;
    final song = entity.toSong();

    // Ensure stream URL is resolved (JIT)
    if (song.streamUrl == null || song.streamUrl!.isEmpty || streamResolver.isExpired(song.id)) {
      final url = await _resolveStreamUrl(song);
      if (token != _sessionToken) return;
      if (url != null && url.isNotEmpty) {
        song.streamUrl = url;
        _updateTrackStreamUrl(song.id, url);
      }
    }

    _playlistBaseIndex = currentIndex;
    _hasRetriedCurrentTrack = false;
    _isLookaheadTriggered = false;
    _syncState();
    onSongChanged?.call(song);

    // Build audio source
    final activeSrc = await _buildAudioSource(song, allowNetworkResolve: false);
    if (activeSrc == null || token != _sessionToken) return;

    final sources = <AudioSource>[activeSrc];

    // Build immediate next track source if available
    final next = nextTrack;
    if (next != null) {
      final nextSong = next.toSong();
      final nextSrc = await _buildAudioSource(nextSong, allowNetworkResolve: true);
      if (nextSrc != null && token == _sessionToken) {
        sources.add(nextSrc);
      }
    }

    _playlistSource = ConcatenatingAudioSource(
      children: sources,
      useLazyPreparation: true,
    );

    final targetNorm = getEffectiveVolumeForSong(song);
    final crossfadeSec = SettingsManager.crossfadeSeconds;

    try {
      await player.setAudioSource(
        _playlistSource,
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
      if (token != _sessionToken) return;
      await _ensureAudioSessionActive();
      await player.play();
      if (crossfadeSec > 0) {
        _fadeVolumeTo(targetNorm, durationMs: (crossfadeSec * 600).clamp(250, 2000));
      } else {
        await player.setVolume(targetNorm);
      }
      _startVolumeWatchdog(song);
      preloadUpcomingTracks();
      onQueueProgress?.call(currentIndex, queue.length);
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioQueueHandler._playTrackEntity');
      debugPrint('[AudioQueueHandler] Play track error: $e');
    }
  }

  // ================= Preloading & Sliding Window ================= //

  Future<void> preloadUpcomingTracks([int? fromIndex]) async {
    final next = nextTrack;
    if (next == null || _isDisposed) return;
    final token = _sessionToken;

    AppLogger.log('AudioQueueHandler', 'Preloading upcoming track: "${next.title}" [id=${next.id}]');

    final wasMissingOrExpired = next.streamUrl == null || next.streamUrl!.isEmpty || streamResolver.isExpired(next.id);
    if (wasMissingOrExpired) {
      final url = await _resolveStreamUrl(next.toSong());
      if (token != _sessionToken) return;
      if (url != null && url.isNotEmpty) {
        _updateTrackStreamUrl(next.id, url);
      } else {
        AppLogger.log('AudioQueueHandler', 'Preload stream resolution failed for "${next.title}".');
        return;
      }
    }

    if (token != _sessionToken || _isDisposed) return;

    final song = next.toSong();
    final source = await _buildAudioSource(song, allowNetworkResolve: false);
    if (source == null || token != _sessionToken || _isDisposed) return;

    _playlistBaseIndex = currentIndex;
    const targetPlayerIndex = 1;

    if (targetPlayerIndex < _playlistSource.length) {
      try {
        final existingTag = _playlistSource.sequence[targetPlayerIndex].tag;
        final existingId = (existingTag is MediaItem) ? existingTag.id : (existingTag is Song ? existingTag.id : null);
        if (existingId != next.id) {
          await _playlistSource.removeAt(targetPlayerIndex);
          await _playlistSource.insert(targetPlayerIndex, source);
        }
      } catch (e) {
        AppLogger.log('AudioQueueHandler', 'Safe catch during playlist source update: $e');
      }
    } else if (targetPlayerIndex == _playlistSource.length) {
      try {
        await _playlistSource.add(source);
      } catch (e) {
        AppLogger.log('AudioQueueHandler', 'Safe catch during playlist source add: $e');
      }
    }
  }

  Future<void> _invalidateUpcomingPlaylistSource() async {
    _playlistBaseIndex = currentIndex;
    while (_playlistSource.length > 1) {
      try {
        await _playlistSource.removeAt(_playlistSource.length - 1);
      } catch (_) {
        break;
      }
    }
  }

  void _updateTrackStreamUrl(String trackId, String url) {
    if (_currentTrack?.id == trackId) {
      _currentTrack = _currentTrack!.copyWith(streamUrl: url);
    }
    for (int i = 0; i < _userQueue.length; i++) {
      if (_userQueue[i].id == trackId) {
        _userQueue[i] = _userQueue[i].copyWith(streamUrl: url);
      }
    }
    for (int i = 0; i < _contextQueue.length; i++) {
      if (_contextQueue[i].id == trackId) {
        _contextQueue[i] = _contextQueue[i].copyWith(streamUrl: url);
      }
    }
  }

  // ================= Auto-Suggestions & Recommendations ================= //

  Future<void> addAutoSuggestions(List<dynamic> tracks) async {
    if (tracks.isEmpty) return;
    final existingTitleKeys = <String>{};
    for (final t in _contextQueue) {
      if (t.cleanTitleKey.isNotEmpty) existingTitleKeys.add(t.cleanTitleKey);
    }
    for (final t in _userQueue) {
      if (t.cleanTitleKey.isNotEmpty) existingTitleKeys.add(t.cleanTitleKey);
    }
    if (_currentTrack != null && _currentTrack!.cleanTitleKey.isNotEmpty) {
      existingTitleKeys.add(_currentTrack!.cleanTitleKey);
    }

    final deduplicated = <TrackEntity>[];
    for (final raw in tracks) {
      final t = _toEntity(raw).copyWith(isSmartRecommended: true, isUserEnqueued: false);
      final key = t.cleanTitleKey;
      if (key.isNotEmpty && existingTitleKeys.contains(key)) continue;
      if (QueueCooldownManager.isCoolingDown(t.toSong())) continue;
      if (key.isNotEmpty) existingTitleKeys.add(key);
      deduplicated.add(t);
    }

    if (deduplicated.isEmpty) return;
    AppLogger.log('AudioQueueHandler', 'addAutoSuggestions: appending ${deduplicated.length} fresh tracks');
    for (final t in deduplicated) {
      _contextQueue.add(t);
      if (_isShuffleEnabled) {
        _contextShuffleIndices.add(_contextQueue.length - 1);
      }
    }
    _syncState();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  // ================= Queue Mutation (Remove, Reorder, Clear) ================= //

  Future<void> removeAt(int index) async {
    final merged = _buildMergedQueue();
    if (index < 0 || index >= merged.length) return;
    final isRemovingCurrent = index == currentIndex;
    final target = merged[index];

    AppLogger.log('AudioQueueHandler', 'removeAt index $index: "${target.title}" (isCurrent=$isRemovingCurrent)');

    if (target.isUserEnqueued) {
      _userQueue.removeWhere((t) => t.id == target.id);
    } else {
      final ctxIdx = _contextQueue.indexWhere((t) => t.id == target.id);
      if (ctxIdx != -1) {
        _contextQueue.removeAt(ctxIdx);
        if (_isShuffleEnabled) {
          final posInShuffle = _contextShuffleIndices.indexOf(ctxIdx);
          if (posInShuffle != -1) _contextShuffleIndices.removeAt(posInShuffle);
          for (int i = 0; i < _contextShuffleIndices.length; i++) {
            if (_contextShuffleIndices[i] > ctxIdx) {
              _contextShuffleIndices[i]--;
            }
          }
        }
        if (ctxIdx < _contextIndex) {
          _contextIndex--;
        }
      }
    }

    if (isRemovingCurrent) {
      if (_userQueue.isNotEmpty) {
        final next = _userQueue.removeAt(0);
        _currentTrack = next;
        _currentTrackIsFromUserQueue = true;
        await _playTrackEntity(next);
      } else if (_contextQueue.isNotEmpty) {
        if (_contextIndex >= _contextQueue.length) {
          _contextIndex = _contextQueue.length - 1;
        }
        final next = _isShuffleEnabled
            ? _contextQueue[_contextShuffleIndices[_contextIndex]]
            : _contextQueue[_contextIndex];
        _currentTrack = next;
        _currentTrackIsFromUserQueue = false;
        await _playTrackEntity(next);
      } else {
        await clear();
      }
    } else {
      _syncState();
      _invalidateUpcomingPlaylistSource();
      preloadUpcomingTracks();
      onQueueProgress?.call(currentIndex, queue.length);
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    try {
      final merged = _buildMergedQueue();
      if (oldIndex < 0 || oldIndex >= merged.length) return;
      if (newIndex < 0 || newIndex > merged.length) return;

      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      if (oldIndex == newIndex) return;

      final movingItem = merged[oldIndex];
      AppLogger.log('AudioQueueHandler', 'reorder: $oldIndex -> $newIndex ("${movingItem.title}")');

      if (movingItem.isUserEnqueued) {
        final curIdx = currentIndex;
        final oldUserIdx = (oldIndex - (curIdx + 1)).clamp(0, _userQueue.length - 1);
        final newUserIdx = (newIndex - (curIdx + 1)).clamp(0, _userQueue.length);
        if (oldUserIdx >= 0 && oldUserIdx < _userQueue.length) {
          final removed = _userQueue.removeAt(oldUserIdx);
          _userQueue.insert(newUserIdx.clamp(0, _userQueue.length), removed);
        }
      } else {
        final curIdx = currentIndex;
        final baseOffset = curIdx + 1 + _userQueue.length;
        if (_isShuffleEnabled && _contextShuffleIndices.isNotEmpty) {
          final oldCtxIdx = _contextQueue.indexWhere((t) => t.id == movingItem.id);
          final oldShufflePos = _contextShuffleIndices.indexOf(oldCtxIdx);
          if (oldShufflePos != -1) {
            final targetShufflePos = (newIndex - _userQueue.length).clamp(0, _contextShuffleIndices.length - 1);
            final removed = _contextShuffleIndices.removeAt(oldShufflePos);
            _contextShuffleIndices.insert(targetShufflePos, removed);
          }
        } else {
          final oldCtxIdx = _contextQueue.indexWhere((t) => t.id == movingItem.id);
          if (oldCtxIdx != -1) {
            final removed = _contextQueue.removeAt(oldCtxIdx);
            final targetCtxOffset = (newIndex >= baseOffset)
                ? (newIndex - _userQueue.length)
                : newIndex;
            final safeNewCtxIdx = targetCtxOffset.clamp(0, _contextQueue.length);
            _contextQueue.insert(safeNewCtxIdx, removed);

            if (oldCtxIdx == _contextIndex) {
              _contextIndex = safeNewCtxIdx;
            } else if (oldCtxIdx < _contextIndex && safeNewCtxIdx >= _contextIndex) {
              _contextIndex--;
            } else if (oldCtxIdx > _contextIndex && safeNewCtxIdx <= _contextIndex) {
              _contextIndex++;
            }
          }
        }
      }

      _syncState();
      _invalidateUpcomingPlaylistSource();
      preloadUpcomingTracks();
      onQueueProgress?.call(currentIndex, queue.length);
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioQueueHandler.reorder');
    }
  }

  Future<void> replaceUpcomingQueue(List<dynamic> newUpcoming) async {
    _userQueue.clear();
    for (final raw in newUpcoming) {
      _userQueue.add(_toEntity(raw).copyWith(isUserEnqueued: true));
    }
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  Future<void> clearUserQueue() async {
    AppLogger.log('AudioQueueHandler', 'Clearing user queue');
    _userQueue.clear();
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  Future<void> clear() async {
    AppLogger.log('AudioQueueHandler', 'Queue cleared');
    cancelIdleTimer();
    YouTubeClient.closeIdleClient();
    NextTrackStrategyFactory.resetSession();
    _sessionToken++;
    try {
      await player.stop();
    } catch (_) {}

    _contextQueue.clear();
    _contextShuffleIndices.clear();
    _isShuffleEnabled = false;
    _userQueue.clear();
    _playbackHistory.clear();
    _currentTrack = null;
    _currentTrackIsFromUserQueue = false;
    _contextIndex = -1;
    _playlistBaseIndex = 0;

    _syncState();

    try {
      await _playlistSource.clear();
    } catch (_) {}

    currentSongNotifier.value = null;
    onQueueProgress?.call(-1, 0);
  }

  // ================= Private AudioSource Builders & Helpers ================= //

  static TrackEntity _toEntity(dynamic track) {
    if (track is TrackEntity) return track;
    if (track is Song) return TrackEntity.fromSong(track);
    if (track is MediaItem) return TrackEntity.fromMediaItem(track);
    throw ArgumentError('Track must be TrackEntity, Song, or MediaItem: $track');
  }

  List<TrackEntity> _buildMergedQueue() {
    final result = <TrackEntity>[];
    if (_contextQueue.isEmpty && _userQueue.isEmpty && _currentTrack == null) {
      return result;
    }

    final contextSeq = _isShuffleEnabled
        ? _contextShuffleIndices.map((i) => _contextQueue[i]).toList()
        : _contextQueue;

    if (!_currentTrackIsFromUserQueue) {
      if (_contextIndex > 0 && _contextIndex <= contextSeq.length) {
        result.addAll(contextSeq.sublist(0, _contextIndex));
      }
      if (_currentTrack != null) {
        result.add(_currentTrack!);
      }
      result.addAll(_userQueue);
      if (_contextIndex + 1 < contextSeq.length) {
        result.addAll(contextSeq.sublist(_contextIndex + 1));
      }
    } else {
      if (_contextIndex >= 0 && _contextIndex < contextSeq.length) {
        result.addAll(contextSeq.sublist(0, _contextIndex + 1));
      }
      if (_currentTrack != null) {
        result.add(_currentTrack!);
      }
      result.addAll(_userQueue);
      if (_contextIndex + 1 < contextSeq.length) {
        result.addAll(contextSeq.sublist(_contextIndex + 1));
      }
    }

    return result;
  }

  Future<AudioSource?> _buildAudioSource(Song song, {bool allowNetworkResolve = true}) async {
    if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
      return DecryptedStreamAudioSource(File(song.localFilePath!), tag: song.toMediaItem());
    }
    if (DownloadManager.isDownloaded(song.id)) {
      final downloadedSongs = DownloadManager.getDownloadedSongs();
      final match = downloadedSongs.firstWhere((s) => s.id == song.id, orElse: () => song);
      if (match.localFilePath != null && File(match.localFilePath!).existsSync()) {
        return DecryptedStreamAudioSource(File(match.localFilePath!), tag: song.toMediaItem());
      }
    }

    String? streamUrl = song.streamUrl;
    if ((streamUrl == null || streamUrl.isEmpty) && allowNetworkResolve) {
      streamUrl = await _resolveStreamUrl(song);
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      return null;
    }

    if (song.source == 'saavn' || song.source == 'jiosaavn' || streamUrl.contains('jiosaavn')) {
      final q = SettingsManager.streamingQuality;
      if (q == '96kbps') {
        streamUrl = streamUrl.replaceAll('_320.mp4', '_96.mp4').replaceAll('_160.mp4', '_96.mp4');
      } else if (q == '160kbps') {
        streamUrl = streamUrl.replaceAll('_320.mp4', '_160.mp4').replaceAll('_96.mp4', '_160.mp4');
      } else {
        streamUrl = streamUrl.replaceAll('_96.mp4', '_320.mp4').replaceAll('_160.mp4', '_320.mp4');
      }
    }
    song.streamUrl = streamUrl;

    final headers = <String, String>{};
    if (song.source == 'youtube' || streamUrl.contains('googlevideo.com') || song.id.length == 11) {
      headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      headers['Accept'] = '*/*';
      headers['Connection'] = 'keep-alive';
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final sanitizedId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final cacheFile = File('${tempDir.path}/audio_$sanitizedId.mp4');
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 100000) {
        return DecryptedStreamAudioSource(cacheFile, tag: song.toMediaItem());
      }
      return AudioSource.uri(
        Uri.parse(streamUrl),
        headers: headers.isNotEmpty ? headers : null,
        tag: song.toMediaItem(),
      );
    } catch (_) {
      return AudioSource.uri(
        Uri.parse(streamUrl),
        headers: headers.isNotEmpty ? headers : null,
        tag: song.toMediaItem(),
      );
    }
  }

  static bool verifyAudioMatch(Song candidate, Song target) {
    return DefaultStreamResolver.verifyMatch(candidate, target);
  }

  Future<String?> _resolveStreamUrl(Song song) async {
    return streamResolver.resolveStreamUrl(song);
  }

  void dispose() {
    _isDisposed = true;
    _fadeToken++;
    if (_connectivityListener != null) {
      ConnectivityService.isOnlineNotifier.removeListener(_connectivityListener!);
      _connectivityListener = null;
    }
    SettingsManager.volumeNormalizationNotifier.removeListener(_onNormalizationChanged);
    _playbackEventSub?.cancel();
    _positionSub?.cancel();
    cancelIdleTimer();
    _sequenceStateSub?.cancel();
    _currentIndexSub?.cancel();
    _playerStateSub?.cancel();
    _currentTrackController.close();
    _nextTrackController.close();
    _queueStreamController.close();
    queueNotifier.dispose();
    currentIndexNotifier.dispose();
    currentSongNotifier.dispose();
    errorNotifier.dispose();
  }
}
