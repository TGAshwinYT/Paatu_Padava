import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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
import '../services/smart_cache_service.dart';
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

  // 4. Actually Played in Session (BloomeeTunes model)
  final List<TrackEntity> _actuallyPlayedInSession = [];

  // Anti-double-skip lock and advancement mutex
  String? _lastCompletedTrackId;
  bool _isAdvancing = false;
  bool _isTransitioning = false;
  DateTime _lastTransitionTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Active track state
  TrackEntity? _currentTrack;
  bool _currentTrackIsFromUserQueue = false;
  int _playlistBaseIndex = 0;
  int _loadRequestId = 0;
  bool _isPreparing = false;
  bool get isPreparing => _isPreparing;
  int _activeLoadToken = 0;
  Timer? _preloadDebounceTimer;

  void _schedulePreload() {
    _preloadDebounceTimer?.cancel();
    _preloadDebounceTimer = Timer(const Duration(seconds: 2), () {
      if (!_isDisposed && player.playing && !_isPreparing) {
        preloadUpcomingTracks();
      }
    });
  }

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
  bool _hasDownscaledCurrentTrack = false;
  Timer? _bufferStallTimer;
  bool _isRecovering = false;
  bool _isLookaheadTriggered = false;
  bool _wasStalledByNetwork = false;
  Duration _networkStallOffset = Duration.zero;
  int _consecutivePlaybackErrors = 0;
  static const int _maxConsecutivePlaybackErrors = 3;
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
  List<TrackEntity> get playedTracks => List.unmodifiable(_actuallyPlayedInSession);
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
      if (index == null || _isDisposed || _isTransitioning) return;
      if (index > 0) {
        String? playingId;
        if (index < _playlistSource.length) {
          final playingTag = _playlistSource.sequence[index].tag;
          playingId = (playingTag is MediaItem)
              ? playingTag.id
              : (playingTag is Song ? playingTag.id : null);
        }
        // Advance only if playing source differs from currently playing track
        if (playingId != null) {
          if (playingId != _currentTrack?.id) {
            _advanceToNextTrackFromPlayerStream(playingId);
          }
        } else {
          _advanceToNextTrackFromPlayerStream();
        }
      }
    });

    _positionSub = player.positionStream.listen((pos) {
      if (pos > Duration.zero && player.playing) {
        _lastCompletedTrackId = null;
      }

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
          await handlePlaybackError(e, st, context: 'playbackEventStream');
        },
      );
    } catch (_) {}

    _playerStateSub = player.playerStateStream.listen((state) {
      onPlayStateChanged?.call(state.playing);

      if (state.playing) {
        _consecutivePlaybackErrors = 0;
        _hasRetriedCurrentTrack = false;
        cancelIdleTimer();
      } else {
        startIdleTimer();
      }

      if (state.playing && state.processingState == ProcessingState.buffering) {
        _startBufferStallWatchdog();
      } else {
        _cancelBufferStallWatchdog();
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
        if (_isAdvancing || _isTransitioning || (_currentTrack != null && _lastCompletedTrackId == _currentTrack!.id)) {
          AppLogger.log('AudioQueueHandler', 'ProcessingState.completed ignored: already advancing/transitioning or track ${_currentTrack?.id} already completed');
          return;
        }
        _lastCompletedTrackId = _currentTrack?.id;
        _isAdvancing = true;

        if (_currentTrack != null) {
          if (!_actuallyPlayedInSession.any((t) => t.id == _currentTrack!.id)) {
            _actuallyPlayedInSession.add(_currentTrack!);
          }
        }

        final current = currentSong;
        if (current != null) {
          QueueCooldownManager.recordPlayed(current);
          final dur = player.duration ?? const Duration(seconds: 180);
          if (isAudioHandlerInitialized) {
            audioHandler.smartShuffleController.recordPlaybackFeedback(
              current,
              listenedSeconds: dur.inSeconds,
              totalSeconds: dur.inSeconds,
            );
          }
        }

        // LoopMode.one: Replay current track in place without advancing either queue
        if (_effectiveLoopMode == LoopMode.one) {
          if (_currentTrack != null) {
            _isAdvancing = false;
            player.seek(Duration.zero);
            player.play();
            return;
          }
        }

        if (hasNext) {
          skipToNext(isUserInitiated: false);
        } else if (_effectiveLoopMode == LoopMode.all && _contextQueue.isNotEmpty) {
          handleRepeatAllLoop();
        } else if (SettingsManager.isAutoplayEnabled && current != null && isAudioHandlerInitialized) {
          _isAdvancing = false;
          audioHandler.handleAutoplayQueueEnd(current);
        } else {
          _isAdvancing = false;
          startIdleTimer();
        }
      }
    });
  }

  /// Monitors active playback for prolonged buffer stalls (>3.5s) on weak networks.
  /// If the current track is on a high bitrate (e.g. 320kbps or 160kbps), dynamically
  /// downscales to the next available bitrate (e.g. 160kbps or 96kbps) in-place at the exact
  /// current playback position. This eliminates prolonged buffering without interrupting audio.
  void _startBufferStallWatchdog() {
    _bufferStallTimer?.cancel();
    if (_hasDownscaledCurrentTrack || _isDisposed || _isAdvancing || _isRecovering) return;

    _bufferStallTimer = Timer(const Duration(milliseconds: 3500), () async {
      if (_isDisposed || _isAdvancing || _isRecovering) return;
      final current = currentSong;
      if (current == null || !player.playing || player.processingState != ProcessingState.buffering) return;

      // Local offline downloads never buffer on network
      if (DownloadManager.isDownloaded(current.id)) return;

      final currentUrl = current.streamUrl;
      if (currentUrl == null || currentUrl.isEmpty) return;

      final fallbackUrl = SaavnBitrateHelper.getNextFallbackUrl(currentUrl);
      if (fallbackUrl != null && fallbackUrl != currentUrl && !_isDisposed) {
        _hasDownscaledCurrentTrack = true;
        final currentPos = player.position;
        AppLogger.log(
          'AudioQueueHandler',
          'Buffer stall dynamic rescue: stream stalled >3.5s for "${current.title}". Downscaling to $fallbackUrl at ${currentPos.inSeconds}s to eliminate buffering.',
        );
        current.streamUrl = fallbackUrl;
        _updateTrackStreamUrl(current.id, fallbackUrl);

        final downscaledSource = await _buildAudioSource(current, allowNetworkResolve: false);
        if (downscaledSource != null && !_isDisposed) {
          try {
            _playlistSource = ConcatenatingAudioSource(
              children: [downscaledSource],
              useLazyPreparation: true,
            );
            await player.setAudioSource(_playlistSource, initialPosition: currentPos);
            await _ensureAudioSessionActive();
            await player.play();
            final targetNorm = getEffectiveVolumeForSong(current);
            await player.setVolume(targetNorm);
            _startVolumeWatchdog(current);
            preloadUpcomingTracks();
            AppLogger.log('AudioQueueHandler', 'Buffer stall dynamic rescue succeeded for "${current.title}"');
          } catch (e) {
            AppLogger.log('AudioQueueHandler', 'Buffer stall dynamic rescue notice: $e');
          }
        }
      }
    });
  }

  void _cancelBufferStallWatchdog() {
    _bufferStallTimer?.cancel();
    _bufferStallTimer = null;
  }

  /// Captures the underlying ExoPlayer error status (HTTP 403, 416, SSL, Cleartext)
  /// settling which cause is real even when just_audio masks it as PlatformException(0, Source error).
  static Future<String> diagnosePlaybackError(Song song, dynamic error, StackTrace? stack) async {
    final errStr = error.toString();
    final detailsStr = (error is PlatformException) ? (error.details?.toString() ?? '') : '';
    final combined = '$errStr $detailsStr ${stack?.toString() ?? ''}'.toLowerCase();

    // 1. Direct regex inspection of error & details
    if (combined.contains('403') || combined.contains('response code: 403')) {
      return 'ExoPlayer HTTP 403 Forbidden: Google CDN or host rejected the stream token/headers.';
    }
    if (combined.contains('416') || combined.contains('response code: 416')) {
      return 'ExoPlayer HTTP 416 Range Not Satisfiable: conflicting byte range requested (e.g. manual &range= query parameter conflict).';
    }
    if (combined.contains('cleartext') || combined.contains('cleartextnotpermitted')) {
      return 'ExoPlayer CleartextNotPermittedException: Insecure HTTP cleartext blocked by Android Network Security Config.';
    }
    if (combined.contains('ssl') || combined.contains('handshake') || combined.contains('certpath')) {
      return 'ExoPlayer SSLHandshakeException: TLS/SSL certificate or handshake negotiation failed.';
    }

    // 2. If masked as PlatformException(0, Source error), probe the actual URL with its headers
    final url = song.streamUrl;
    if (url != null && url.startsWith('http')) {
      try {
        final uri = Uri.parse(url);
        final host = uri.host.toLowerCase();
        final isGoogleVideo = host.contains('googlevideo.com');
        final probeHeaders = <String, String>{
          if (isGoogleVideo) 'User-Agent': YouTubeClient.vrUserAgent,
          'Range': 'bytes=0-1024',
          'Accept': '*/*',
        };

        final response = await http.get(uri, headers: probeHeaders).timeout(const Duration(seconds: 3));
        if (response.statusCode == 403) {
          return 'ExoPlayer HTTP 403 Forbidden: Google CDN rejected request (confirmed via live probe on $host).';
        } else if (response.statusCode == 416) {
          return 'ExoPlayer HTTP 416 Range Not Satisfiable: Byte range invalid (confirmed via live probe on $host).';
        } else if (response.statusCode >= 400) {
          return 'ExoPlayer HTTP ${response.statusCode}: Stream server returned error status on $host.';
        } else {
          return 'ExoPlayer probe returned HTTP ${response.statusCode} OK on $host (underlying issue is player decoding/codec or buffer stall, not HTTP rejection).';
        }
      } on SocketException catch (se) {
        return 'ExoPlayer SocketException: Failed to reach stream host: ${se.message}';
      } on HandshakeException catch (he) {
        return 'ExoPlayer SSLHandshakeException: TLS/SSL handshake failed on stream host: ${he.message}';
      } catch (probeErr) {
        final pStr = probeErr.toString().toLowerCase();
        if (pStr.contains('cleartext')) {
          return 'ExoPlayer CleartextNotPermittedException: Non-HTTPS traffic blocked by Android.';
        }
        return 'PlatformException(0, Source error) [Probe failed: $probeErr]';
      }
    }

    return (error is PlatformException)
        ? 'PlatformException(${error.code}, ${error.message}, details: ${error.details})'
        : errStr;
  }

  /// Centralized playback error recovery & diagnostic logger (Bloomee model).
  /// Single entry point for all playback errors (both setAudioSource failures and playbackEventStream runtime errors).
  /// Captures underlying ExoPlayer HTTP status (403, 416, SSL, Cleartext) and attempts Saavn fallback recovery ONCE.
  Future<void> handlePlaybackError(dynamic error, StackTrace? stackTrace, {required String context}) async {
    final current = currentSong;
    if (current == null || _isDisposed) return;

    if (_isRecovering) {
      AppLogger.log('AudioQueueHandler', '[$context] Recovery already in progress for "${current.title}", ignoring duplicate error');
      return;
    }

    // 1. Ignore abort / connection aborted errors (superseded by newer load or seek)
    final errorStr = error.toString().toLowerCase();
    final isAbort = errorStr.contains('abort') ||
        (error is PlatformException &&
            (error.code.toLowerCase() == 'abort' ||
                (error.message != null && error.message!.toLowerCase().contains('abort'))));
    if (isAbort) {
      AppLogger.log('AudioQueueHandler', '[$context] Ignoring aborted load (superseded by newer load): $error');
      return;
    }

    // 2. Attribute errors by playlist slot index:
    // If the error carries {index: 1} or non-playing index, drop the failing preloaded source ONLY.
    // Never blame, reload, or disrupt the healthy playing track!
    int? errorIndex;
    if (error is PlatformException && error.details is Map) {
      final idx = (error.details as Map)['index'];
      if (idx is int) {
        errorIndex = idx;
      }
    }
    if (errorIndex == null) {
      final match = RegExp(r'\{index:\s*(\d+)\}').firstMatch(error.toString());
      if (match != null) {
        errorIndex = int.tryParse(match.group(1)!);
      }
    }

    int? getSafeCurrentIndex() {
      try {
        return player.currentIndex;
      } catch (_) {
        return null;
      }
    }

    final currentPlayingIndex = getSafeCurrentIndex() ?? 0;
    if (errorIndex != null && errorIndex != currentPlayingIndex) {
      AppLogger.log(
        'AudioQueueHandler',
        '[$context] Playback error on non-playing preloaded slot $errorIndex (active playing index is $currentPlayingIndex). Dropping preloaded source without disrupting active playback.',
      );
      if (errorIndex < _playlistSource.length) {
        try {
          await _playlistSource.removeAt(errorIndex);
        } catch (e) {
          AppLogger.log('AudioQueueHandler', 'Safe catch removing preloaded error source: $e');
        }
      }
      final next = nextTrack;
      if (next != null) {
        streamResolver.invalidate(next.id);
        _updateTrackStreamUrl(next.id, '');
      }
      return;
    }

    final token = _sessionToken;
    _isRecovering = true;

    try {
      // 1. Capture and log the real underlying error
      final diagnostic = await diagnosePlaybackError(current, error, stackTrace);
      if (token != _sessionToken || _isDisposed) {
        AppLogger.log('AudioQueueHandler', '[$context] Stale error: session token changed during diagnosis, aborting recovery');
        return;
      }
      AppLogger.log('ExoPlayerDiagnostic', '[$context] Real Error for "${current.title}" (${current.id}) [${current.source}]: $diagnostic');

      final failingUrl = current.streamUrl;
      final isSaavnCdn = current.source == 'saavn' ||
          current.source == 'jiosaavn' ||
          (failingUrl != null && failingUrl.contains('saavncdn.com'));

      // Invalidate stream cache so stale/expired/403 URL is never reused
      streamResolver.invalidate(current.id);
      current.streamUrl = null;

      // 2. Retry handling with Bitrate Fallback + Cross-Provider Fallback
      if (!_hasRetriedCurrentTrack && !_isDisposed && token == _sessionToken) {
        _hasRetriedCurrentTrack = true;

        // STEP 2A: If a Saavn stream failed (e.g. 320kbps 404/403 on CDN), try Bitrate Fallback (160kbps, then 96kbps)
        if (isSaavnCdn && failingUrl != null) {
          final fallbackUrl = SaavnBitrateHelper.getNextFallbackUrl(failingUrl);
          if (fallbackUrl != null && !_isDisposed && token == _sessionToken) {
            AppLogger.log('AudioQueueHandler', 'Saavn bitrate fallback for "${current.title}": switching to lower bitrate $fallbackUrl');
            current.streamUrl = fallbackUrl;
            _updateTrackStreamUrl(current.id, fallbackUrl, source: 'saavn');
            final fallbackSource = await _buildAudioSource(current, allowNetworkResolve: false);
            if (token != _sessionToken || _isDisposed) return;
            if (fallbackSource != null) {
              try {
                _playlistSource = ConcatenatingAudioSource(
                  children: [fallbackSource],
                  useLazyPreparation: true,
                );
                await player.setAudioSource(_playlistSource);
                if (token != _sessionToken || _isDisposed) return;
                await _ensureAudioSessionActive();
                if (token != _sessionToken || _isDisposed) return;
                await player.play();
                if (token != _sessionToken || _isDisposed) return;
                final targetNorm = getEffectiveVolumeForSong(current);
                await player.setVolume(targetNorm);
                _startVolumeWatchdog(current);
                _consecutivePlaybackErrors = 0;
                preloadUpcomingTracks();
                AppLogger.log('AudioQueueHandler', 'Saavn bitrate fallback successful: "${current.title}" playing at reduced bitrate');
                return;
              } catch (bitrateErr, bitrateStack) {
                final bDiag = await diagnosePlaybackError(current, bitrateErr, bitrateStack);
                AppLogger.log('ExoPlayerDiagnostic', 'Saavn bitrate fallback failed for "${current.title}": $bDiag');
              }
            }
          }
        }

        if (token != _sessionToken || _isDisposed) return;

        // STEP 2B: Cross-source resolution fallback
        AppLogger.log('AudioQueueHandler', 'Single-pass fallback: resolving fallback stream for "${current.title}"');
        final freshUrl = await streamResolver.resolve(
          current,
          forceSaavnFallback: !isSaavnCdn,
        );
        if (token != _sessionToken || _isDisposed) return;
        if (freshUrl != null && freshUrl.isNotEmpty) {
          final resolvedSource = freshUrl.contains('saavncdn.com') ? 'saavn' : 'youtube';
          current.streamUrl = freshUrl;
          current.source = resolvedSource;
          _updateTrackStreamUrl(current.id, freshUrl, source: resolvedSource);

          final freshSource = await _buildAudioSource(current, allowNetworkResolve: false);
          if (token != _sessionToken || _isDisposed) return;
          if (freshSource != null) {
            try {
              _playlistSource = ConcatenatingAudioSource(
                children: [freshSource],
                useLazyPreparation: true,
              );
              await player.setAudioSource(_playlistSource);
              if (token != _sessionToken || _isDisposed) return;
              await _ensureAudioSessionActive();
              if (token != _sessionToken || _isDisposed) return;
              await player.play();
              if (token != _sessionToken || _isDisposed) return;
              final targetNorm = getEffectiveVolumeForSong(current);
              await player.setVolume(targetNorm);
              _startVolumeWatchdog(current);
              _consecutivePlaybackErrors = 0;
              preloadUpcomingTracks();
              AppLogger.log('AudioQueueHandler', 'Fallback recovery successful: "${current.title}" now playing via $resolvedSource');
              return;
            } catch (recoveryErr, recoveryStack) {
              final recDiag = await diagnosePlaybackError(current, recoveryErr, recoveryStack);
              AppLogger.log('ExoPlayerDiagnostic', 'Fallback play failed for "${current.title}": $recDiag');
            }
          }
        }
      }

      if (token != _sessionToken || _isDisposed) {
        AppLogger.log('AudioQueueHandler', '[$context] Stale error: user transitioned or token expired, bypassing circuit breaker increment');
        return;
      }

      // 3. If fallback failed or track was already retried once:
      _consecutivePlaybackErrors++;
      if (_consecutivePlaybackErrors >= _maxConsecutivePlaybackErrors) {
        AppLogger.log('AudioQueueHandler', 'Circuit breaker tripped: $_consecutivePlaybackErrors consecutive playback failures. Halting auto-skip storm.');
        _consecutivePlaybackErrors = 0;
        await player.stop();
        final haltErr = AppError(
          category: AppErrorCategory.unknown,
          userMessage: 'Playback paused after multiple track errors. Please check your connection or choose another song.',
          errorCode: 'ERR_PLAYBACK_LOOP_HALTED',
          actionLabel: 'Dismiss',
          actionType: AppActionType.none,
        );
        errorNotifier.value = haltErr;
        onError?.call(haltErr);
        if (isAudioHandlerInitialized) {
          audioHandler.playbackErrorNotifier.value = haltErr;
        }
        return;
      }

      if (!ConnectivityService.currentIsOnline && _currentTrack != null && !DownloadManager.isDownloaded(_currentTrack!.id)) {
        _wasStalledByNetwork = true;
        if (player.position > Duration.zero) {
          _networkStallOffset = player.position;
        }
        AppLogger.log('AudioQueueHandler', 'Network offline during playback error. Cached stall offset ${_networkStallOffset.inSeconds}s for automatic zero-touch recovery.');
      }

      final appErr = ErrorHandler.resolve(error, stackTrace: stackTrace, context: 'Playback error on ${current.title}');
      errorNotifier.value = appErr;
      onError?.call(appErr);
      if (isAudioHandlerInitialized) {
        audioHandler.playbackErrorNotifier.value = appErr;
      }

      if (hasNext && !_isDisposed && token == _sessionToken) {
        AppLogger.log('AudioQueueHandler', 'Advancing to next track after failure on "${current.title}"');
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!_isDisposed && queue.isNotEmpty && _sessionToken == token) skipToNext(isUserInitiated: false);
        });
      }
    } finally {
      _isRecovering = false;
    }
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
            _playlistSource = ConcatenatingAudioSource(
              children: [freshSource],
              useLazyPreparation: true,
            );
            await player.setAudioSource(_playlistSource, initialPosition: resumeOffset);
            await _ensureAudioSessionActive();
            await player.play();
            final targetNorm = getEffectiveVolumeForSong(current);
            await player.setVolume(targetNorm);
            _startVolumeWatchdog(current);
            preloadUpcomingTracks();
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
    final safeInitialIndex = (initialIndex >= 0 && initialIndex < entities.length) ? initialIndex : 0;
    final orderedTracks = [
      ...entities.sublist(safeInitialIndex),
      ...entities.sublist(0, safeInitialIndex),
    ];
    final targetTrack = orderedTracks.first;

    if (_isLoading && _currentTrack?.id == targetTrack.id) {
      AppLogger.log('AudioQueueHandler', 'loadQueue: duplicate call for "${targetTrack.title}" ignored (already loading)');
      return;
    }

    cancelIdleTimer();
    final token = ++_sessionToken;
    _activeLoadSessionToken = token;
    _isLoading = true;

    try {
      AppLogger.log('AudioQueueHandler', 'loadQueue: ${orderedTracks.length} tracks (rotated from initialIndex=$initialIndex), autoPlay=$autoPlay');

      try {
        await player.stop();
      } catch (_) {}

      if (token != _sessionToken) return;

      // Initialize two-tier decoupled queues
      _contextQueue.clear();
      _contextQueue.addAll(orderedTracks);
      _contextShuffleIndices.clear();
      _isShuffleEnabled = false;

      if (!preserveUserQueue) {
        _userQueue.clear();
      }
      _playbackHistory.clear();
      _actuallyPlayedInSession.clear();
      _lastCompletedTrackId = null;
      _isAdvancing = false;
      _hasRetriedCurrentTrack = false;

      _contextIndex = 0;
      _currentTrack = orderedTracks[0];
      _currentTrackIsFromUserQueue = false;

      NextTrackStrategyFactory.resetSession(initialAnchor: _currentTrack?.toSong());

      _syncState();

      final activeSong = _currentTrack!.toSong();
      onSongChanged?.call(activeSong);

      final currentRequestId = ++_loadRequestId;
      // JIT resolve stream URL for active song
      if (activeSong.streamUrl == null || activeSong.streamUrl!.isEmpty || streamResolver.isExpired(activeSong.id)) {
        final resolvedUrl = await _resolveStreamUrl(activeSong);
        if (currentRequestId != _loadRequestId || token != _sessionToken) return;
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
          if (isAudioHandlerInitialized && !hasNext) {
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
        _consecutivePlaybackErrors++;
        if (_consecutivePlaybackErrors >= _maxConsecutivePlaybackErrors) {
          _consecutivePlaybackErrors = 0;
          await player.stop();
          final err = AppError(
            category: AppErrorCategory.songUnavailable,
            userMessage: 'Playback paused after multiple tracks failed to load.',
            actionLabel: 'Dismiss',
            actionType: AppActionType.none,
            errorCode: 'ERR_PLAYBACK_LOOP_HALTED',
          );
          errorNotifier.value = err;
          onError?.call(err);
          if (isAudioHandlerInitialized) {
            audioHandler.playbackErrorNotifier.value = err;
          }
          return;
        }
        if (autoPlay && hasNext) {
          await skipToNext(isUserInitiated: false);
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
        _hasDownscaledCurrentTrack = false;
        _cancelBufferStallWatchdog();
        onQueueProgress?.call(currentIndex, queue.length);
        _schedulePreload();
      } catch (e, stack) {
        AppLogger.recordError(e, stack, context: 'AudioQueueHandler.loadQueue setAudioSource');
        await handlePlaybackError(e, stack, context: 'loadQueue');
      }
    } finally {
      _isPreparing = false;
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
  Future<void> skipToNext({bool isUserInitiated = true}) async {
    if (_isTransitioning) {
      AppLogger.log('AudioQueueHandler', 'skipToNext ignored: transition currently in progress');
      return;
    }
    _isTransitioning = true;
    _lastTransitionTime = DateTime.now();

    try {
      if (isUserInitiated) {
        _lastCompletedTrackId = null;
      }

      if (_currentTrack != null && isUserInitiated) {
        final listenedSec = player.position.inSeconds;
        NextTrackStrategyFactory.recordSkip(_currentTrack!.toSong(), listenedSeconds: listenedSec);
      }

      if (_effectiveLoopMode == LoopMode.one) {
        if (_currentTrack != null) {
          _isAdvancing = false;
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
          if (!_actuallyPlayedInSession.any((t) => t.id == _currentTrack!.id)) {
            _actuallyPlayedInSession.add(_currentTrack!);
          }
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
          if (!_actuallyPlayedInSession.any((t) => t.id == _currentTrack!.id)) {
            _actuallyPlayedInSession.add(_currentTrack!);
          }
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

      _isAdvancing = false;

      // 5. Autoplay replenishment ONLY when at EOF (_contextIndex + 1 >= _contextQueue.length)
      if (SettingsManager.isAutoplayEnabled && _currentTrack != null && isAudioHandlerInitialized) {
        await audioHandler.handleAutoplayQueueEnd(_currentTrack!.toSong());
      }
    } finally {
      _isTransitioning = false;
    }
  }

  /// Skip to previous track in playback history or context sequence
  Future<void> skipToPrevious() async {
    if (player.position.inSeconds > 4) {
      await player.seek(Duration.zero);
      return;
    }

    if (_isTransitioning) {
      AppLogger.log('AudioQueueHandler', 'skipToPrevious ignored: transition currently in progress');
      return;
    }
    _isTransitioning = true;
    _lastTransitionTime = DateTime.now();

    try {
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
    } finally {
      _isTransitioning = false;
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
      if (_currentTrack != null) {
        _playbackHistory.add(_currentTrack!);
        if (!_actuallyPlayedInSession.any((t) => t.id == _currentTrack!.id)) {
          _actuallyPlayedInSession.add(_currentTrack!);
        }
      }
      _contextIndex = ctxIdx;
      _currentTrack = contextSeq[ctxIdx];
      _currentTrackIsFromUserQueue = false;
      await _playTrackEntity(contextSeq[ctxIdx]);
    }
  }

  /// Jumps directly to any track in Up Next, Next in Queue, or Played history in-place
  /// without re-adding or duplicating songs in the context queue.
  Future<void> skipToQueueItem(
    TrackEntity targetTrack, {
    bool fromUserQueue = false,
    bool fromPlayedHistory = false,
  }) async {
    _lastCompletedTrackId = null;
    _isAdvancing = false;
    AppLogger.log('AudioQueueHandler', 'skipToQueueItem: "${targetTrack.title}" (fromUserQueue=$fromUserQueue, fromPlayedHistory=$fromPlayedHistory)');

    if (_currentTrack != null) {
      if (!_actuallyPlayedInSession.any((t) => t.id == _currentTrack!.id)) {
        _actuallyPlayedInSession.add(_currentTrack!);
      }
      _playbackHistory.add(_currentTrack!);
    }

    if (fromUserQueue) {
      final userIdx = _userQueue.indexWhere((t) => t.id == targetTrack.id);
      if (userIdx != -1) {
        for (int i = 0; i < userIdx; i++) {
          final passed = _userQueue.removeAt(0);
          _playbackHistory.add(passed);
          if (!_actuallyPlayedInSession.any((t) => t.id == passed.id)) {
            _actuallyPlayedInSession.add(passed);
          }
        }
        final target = _userQueue.removeAt(0);
        _currentTrack = target;
        _currentTrackIsFromUserQueue = true;
        await _playTrackEntity(target);
        return;
      }
    }

    if (fromPlayedHistory) {
      final ctxIdx = _isShuffleEnabled
          ? _contextShuffleIndices.indexWhere((i) => _contextQueue[i].id == targetTrack.id)
          : _contextQueue.indexWhere((t) => t.id == targetTrack.id);

      if (ctxIdx != -1) {
        _contextIndex = ctxIdx;
        _currentTrack = _isShuffleEnabled
            ? _contextQueue[_contextShuffleIndices[ctxIdx]]
            : _contextQueue[ctxIdx];
        _currentTrackIsFromUserQueue = false;
        await _playTrackEntity(_currentTrack!);
      } else {
        _currentTrack = targetTrack;
        _currentTrackIsFromUserQueue = false;
        await _playTrackEntity(targetTrack);
      }
      return;
    }

    // Tapped in upNextTracks (_contextQueue)
    final targetIndex = _isShuffleEnabled
        ? _contextShuffleIndices.indexWhere((i) => _contextQueue[i].id == targetTrack.id)
        : _contextQueue.indexWhere((t) => t.id == targetTrack.id);

    if (targetIndex != -1) {
      _contextIndex = targetIndex;
      _currentTrack = _isShuffleEnabled
          ? _contextQueue[_contextShuffleIndices[_contextIndex]]
          : _contextQueue[_contextIndex];
      _currentTrackIsFromUserQueue = false;
      await _playTrackEntity(_currentTrack!);
      return;
    }

    final userIdx = _userQueue.indexWhere((t) => t.id == targetTrack.id);
    if (userIdx != -1) {
      for (int i = 0; i < userIdx; i++) {
        _userQueue.removeAt(0);
      }
      final target = _userQueue.removeAt(0);
      _currentTrack = target;
      _currentTrackIsFromUserQueue = true;
      await _playTrackEntity(target);
      return;
    }

    _currentTrack = targetTrack;
    _currentTrackIsFromUserQueue = false;
    await _playTrackEntity(targetTrack);
  }

  /// Handles gapless advance when just_audio ConcatenatingAudioSource fires index 1
  void _advanceToNextTrackFromPlayerStream([String? expectedId]) {
    if (_isTransitioning || _isDisposed) return;
    if (expectedId != null && _currentTrack?.id == expectedId) return;
    _isTransitioning = true;
    _lastTransitionTime = DateTime.now();

    try {
      _lastCompletedTrackId = _currentTrack?.id;

      if (_currentTrack != null && _currentTrackIsFromUserQueue && _userQueue.isNotEmpty && _userQueue.first.id == _currentTrack!.id) {
        _userQueue.removeAt(0);
      }

    if (_userQueue.isNotEmpty) {
      final next = _userQueue.removeAt(0);
      if (_currentTrack != null) {
        _playbackHistory.add(_currentTrack!);
        if (!_actuallyPlayedInSession.any((t) => t.id == _currentTrack!.id)) {
          _actuallyPlayedInSession.add(_currentTrack!);
        }
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
          if (!_actuallyPlayedInSession.any((t) => t.id == _currentTrack!.id)) {
            _actuallyPlayedInSession.add(_currentTrack!);
          }
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
      if (crossfadeSec > 0) {
        final fadeInMs = (crossfadeSec * 600).clamp(250, 2000);
        _fadeVolumeTo(targetNorm, durationMs: fadeInMs);
      } else {
        try {
          player.setVolume(targetNorm);
        } catch (_) {}
      }
      _startVolumeWatchdog(song);
      preloadUpcomingTracks();
    }
  } finally {
    _isTransitioning = false;
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
    final currentRequestId = ++_loadRequestId;
    final activeToken = ++_activeLoadToken;
    _isPreparing = true;

    try {
      final song = entity.toSong();

      // Ensure stream URL is resolved (JIT)
      if (song.streamUrl == null || song.streamUrl!.isEmpty || streamResolver.isExpired(song.id)) {
        final url = await _resolveStreamUrl(song);
        if (currentRequestId != _loadRequestId || token != _sessionToken || activeToken != _activeLoadToken) return;
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
      if (token != _sessionToken || activeToken != _activeLoadToken) return;

      if (activeSrc == null) {
        _consecutivePlaybackErrors++;
        AppLogger.log('AudioQueueHandler', 'Failed to build audio source for "${song.title}". (Consecutive failures: $_consecutivePlaybackErrors)');
        if (_consecutivePlaybackErrors >= _maxConsecutivePlaybackErrors) {
          _consecutivePlaybackErrors = 0;
          await player.stop();
          final err = AppError(
            category: AppErrorCategory.songUnavailable,
            userMessage: 'Playback paused after multiple tracks failed to load.',
            actionLabel: 'Dismiss',
            actionType: AppActionType.none,
            errorCode: 'ERR_PLAYBACK_LOOP_HALTED',
          );
          errorNotifier.value = err;
          onError?.call(err);
          if (isAudioHandlerInitialized) {
            audioHandler.playbackErrorNotifier.value = err;
          }
          return;
        }
        if (hasNext && !_isDisposed) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!_isDisposed && queue.isNotEmpty && _sessionToken == token) {
              skipToNext(isUserInitiated: false);
            }
          });
        }
        return;
      }

      final sources = <AudioSource>[activeSrc];

      // Build immediate next track source if available
      final next = nextTrack;
      if (next != null) {
        final nextSong = next.toSong();
        final nextSrc = await _buildAudioSource(nextSong, allowNetworkResolve: true);
        if (nextSrc != null && token == _sessionToken && activeToken == _activeLoadToken) {
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
        _isAdvancing = false;
        if (token != _sessionToken || activeToken != _activeLoadToken) return;
        await _ensureAudioSessionActive();
        await player.play();
        _consecutivePlaybackErrors = 0; // Playback began successfully
        _hasRetriedCurrentTrack = false;
        _hasDownscaledCurrentTrack = false;
        _cancelBufferStallWatchdog();
        if (crossfadeSec > 0) {
          _fadeVolumeTo(targetNorm, durationMs: (crossfadeSec * 600).clamp(250, 2000));
        } else {
          await player.setVolume(targetNorm);
        }
        _startVolumeWatchdog(song);
        _schedulePreload();
        onQueueProgress?.call(currentIndex, queue.length);
      } catch (e, stack) {
        AppLogger.recordError(e, stack, context: 'AudioQueueHandler._playTrackEntity');
        debugPrint('[AudioQueueHandler] Play track error: $e');
        _consecutivePlaybackErrors++;
        if (_consecutivePlaybackErrors >= _maxConsecutivePlaybackErrors) {
          _consecutivePlaybackErrors = 0;
          await player.stop();
          final err = ErrorHandler.resolve(e, stackTrace: stack, context: 'AudioQueueHandler._playTrackEntity');
          errorNotifier.value = err;
          onError?.call(err);
          if (isAudioHandlerInitialized) {
            audioHandler.playbackErrorNotifier.value = err;
          }
          return;
        }
        if (hasNext && !_isDisposed) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!_isDisposed && queue.isNotEmpty && _sessionToken == token) {
              skipToNext(isUserInitiated: false);
            }
          });
        }
      }
    } finally {
      _isAdvancing = false;
      if (activeToken == _activeLoadToken) {
        _isPreparing = false;
      }
    }
  }

  // ================= Preloading & Sliding Window ================= //

  Future<void> preloadUpcomingTracks([int? fromIndex]) async {
    int? getSafeCurrentIndex() {
      try {
        return player.currentIndex;
      } catch (_) {
        return null;
      }
    }

    final next = nextTrack;
    if (next == null || _isDisposed) {
      final currentPlayingIdx = getSafeCurrentIndex() ?? 0;
      while (_playlistSource.length > currentPlayingIdx + 1) {
        try {
          await _playlistSource.removeAt(_playlistSource.length - 1);
        } catch (_) {
          break;
        }
      }
      return;
    }
    final token = _sessionToken;

    AppLogger.log('AudioQueueHandler', 'Preloading upcoming track: "${next.title}" [id=${next.id}]');

    final wasMissingOrExpired = next.streamUrl == null || next.streamUrl!.isEmpty || streamResolver.isExpired(next.id);
    if (wasMissingOrExpired) {
      final url = await _resolveStreamUrl(next.toSong());
      if (token != _sessionToken || _isDisposed) return;
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

    // 1. Trim played sources prior to currently playing index so window is always [playing, next]
    final currentPlaying = getSafeCurrentIndex() ?? 0;
    if (currentPlaying > 0 && _playlistSource.length > 1) {
      try {
        for (int i = 0; i < currentPlaying; i++) {
          if (_playlistSource.length > 1) {
            await _playlistSource.removeAt(0);
          }
        }
      } catch (e) {
        AppLogger.log('AudioQueueHandler', 'Safe catch during trimming played sources: $e');
      }
    }

    if (token != _sessionToken || _isDisposed) return;

    // 2. Target slot is always the slot strictly after the active playing one
    final activePlayingIndex = getSafeCurrentIndex() ?? 0;
    final targetPlayerIndex = activePlayingIndex + 1;
    _playlistBaseIndex = currentIndex;

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

    // Trim any trailing sources beyond the 2-track window [playing, next]
    while (_playlistSource.length > targetPlayerIndex + 1) {
      try {
        await _playlistSource.removeAt(_playlistSource.length - 1);
      } catch (_) {
        break;
      }
    }

    // Pre-resolve the 2nd upcoming track silently in background so sub-second playback is sustained
    final upcomingList = <TrackEntity>[];
    if (_userQueue.isNotEmpty) {
      upcomingList.addAll(_userQueue);
    }
    upcomingList.addAll(remainingContextTracks);

    if (upcomingList.length > 1) {
      final secondUpcoming = upcomingList[1];
      final needsResolve = secondUpcoming.streamUrl == null ||
          secondUpcoming.streamUrl!.isEmpty ||
          streamResolver.isExpired(secondUpcoming.id);
      if (needsResolve) {
        unawaited(() async {
          try {
            final url2 = await _resolveStreamUrl(secondUpcoming.toSong());
            if (url2 != null && url2.isNotEmpty && token == _sessionToken) {
              _updateTrackStreamUrl(secondUpcoming.id, url2);
              AppLogger.log('AudioQueueHandler', 'Pre-resolved 2nd upcoming track: "${secondUpcoming.title}" [id=${secondUpcoming.id}]');
            }
          } catch (_) {}
        }());
      }
    }

    // Trigger Smart Predictive Offline Caching for upcoming tracks in background
    SmartCacheService.instance.onQueueUpdated(currentSong, queue);
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

  void _updateTrackStreamUrl(String trackId, String url, {String? source}) {
    if (_currentTrack?.id == trackId) {
      _currentTrack = _currentTrack!.copyWith(
        streamUrl: url,
        source: source ?? _currentTrack!.source,
      );
    }
    for (int i = 0; i < _userQueue.length; i++) {
      if (_userQueue[i].id == trackId) {
        _userQueue[i] = _userQueue[i].copyWith(
          streamUrl: url,
          source: source ?? _userQueue[i].source,
        );
      }
    }
    for (int i = 0; i < _contextQueue.length; i++) {
      if (_contextQueue[i].id == trackId) {
        _contextQueue[i] = _contextQueue[i].copyWith(
          streamUrl: url,
          source: source ?? _contextQueue[i].source,
        );
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
    if (!SmartCacheService.instance.isDownloading(song.id)) {
      final smartCacheFile = SmartCacheService.instance.getCachedAudioFile(song.id);
      if (smartCacheFile != null && smartCacheFile.existsSync()) {
        return DecryptedStreamAudioSource(smartCacheFile, tag: song.toMediaItem());
      }
    }

    String? streamUrl = song.streamUrl;
    if ((streamUrl == null || streamUrl.isEmpty) && allowNetworkResolve) {
      streamUrl = await _resolveStreamUrl(song);
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      return null;
    }

    if (song.source == 'saavn' || song.source == 'jiosaavn' || streamUrl.contains('jiosaavn') || streamUrl.contains('saavncdn.com')) {
      final q = SettingsManager.effectiveStreamingQuality;
      streamUrl = SaavnBitrateHelper.toBitrate(streamUrl, q);
    }
    final uri = Uri.tryParse(streamUrl);
    final host = uri?.host.toLowerCase() ?? '';
    final isGoogleVideo = host.contains('googlevideo.com');

    // Headers are ONLY for googlevideo.com; Saavn and other hosts get none (headers: null).
    final Map<String, String>? headers;
    if (isGoogleVideo) {
      final isHls = streamUrl.contains('.m3u8') || streamUrl.contains('hls_variant');
      headers = {
        'User-Agent': isHls
            ? 'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)'
            : YouTubeClient.vrUserAgent,
        'Accept': '*/*',
        'Connection': 'keep-alive',
      };
    } else {
      headers = null;
    }
    song.streamUrl = streamUrl;

    try {
      final tempDir = await getTemporaryDirectory();
      final sanitizedId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final cacheFile = File('${tempDir.path}/audio_$sanitizedId.mp4');
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 100000) {
        return DecryptedStreamAudioSource(cacheFile, tag: song.toMediaItem());
      }
      return AudioSource.uri(
        Uri.parse(streamUrl),
        headers: headers,
        tag: song.toMediaItem(),
      );
    } catch (_) {
      return AudioSource.uri(
        Uri.parse(streamUrl),
        headers: headers,
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
    _cancelBufferStallWatchdog();
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
