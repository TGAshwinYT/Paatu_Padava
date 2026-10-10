import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../services/download_manager.dart';
import '../services/settings_manager.dart';
import '../services/youtube_client.dart';
import '../services/error_handler.dart';
import '../services/player_handler.dart';
import '../services/app_logger.dart';
import '../services/queue_cooldown_manager.dart';
import '../domain/models/app_error.dart';
import 'stream_resolver.dart';

class AudioQueueHandler {
  final AudioPlayer player;
  final StreamResolver streamResolver;

  // Persistent ConcatenatingAudioSource for Spotify-grade gapless playback
  ConcatenatingAudioSource _playlistSource = ConcatenatingAudioSource(
    children: [],
    useLazyPreparation: true,
  );

  // Queue state
  final List<Song> _queue = [];
  final List<Song> _originalQueue = [];
  int _currentIndex = -1;
  int _playlistBaseIndex = 0;
  int get playlistBaseIndex => _playlistBaseIndex;

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
  }

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
  /// Balances uncompressed studio masters (JioSaavn) against normalized YouTube Opus audio (-14 LUFS)
  static double getNormalizedVolumeForSong(Song? song) {
    if (!SettingsManager.isVolumeNormalizationEnabled) {
      return 1.0;
    }
    if (song == null) return 1.0;

    // YouTube streams are already loudness-normalized to -14 LUFS
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
      return 0.80; // ~ -2.0 dB calibration to match YouTube's -14 LUFS reference
    }
    return 1.0;
  }

  /// Calculates effective volume taking both user-selected master volume and song calibration into account
  double getEffectiveVolumeForSong(Song? song) {
    return (_userVolume * getNormalizedVolumeForSong(song)).clamp(0.0, 1.0);
  }

  /// Guarantees that the native Android/iOS AudioSession is active and holds audio focus
  Future<void> _ensureAudioSessionActive() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      AppLogger.log('AudioQueueHandler', 'AudioSession.setActive(true) notice: $e');
    }
  }

  /// Watchdog timer to ensure sound output is active and not stuck at 0.0 from race conditions
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

  /// Smoothly ramps player volume to [targetVolume] over [durationMs] with token-guaranteed restoration
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
      if (now - _lastCrossfadeTimeMs < 100) return; // Throttle to max 10Hz
      _lastCrossfadeTimeMs = now;

      final targetNorm = getEffectiveVolumeForSong(currentSong);
      final ratio = (remaining.inMilliseconds / (crossfadeSec * 1000)).clamp(0.0, 1.0);
      final fadedVolume = targetNorm * ratio;
      try {
        player.setVolume(fadedVolume.clamp(0.0, 1.0));
      } catch (_) {}
    }
  }

  Timer? get idleTimeoutTimer => _idleTimeoutTimer;
  bool get isIdleTimeoutActive => _idleTimeoutTimer != null && _idleTimeoutTimer!.isActive;

  /// Starts the 5-minute idle timeout timer when playback is paused, completed, or idle
  void startIdleTimer({Duration timeout = const Duration(minutes: 5)}) {
    cancelIdleTimer();
    if (player.playing || _isLoading) return;
    _idleTimeoutTimer = Timer(timeout, () {
      handleIdleRelease();
    });
    AppLogger.log('AudioQueueHandler', 'Started 5-minute idle timeout countdown');
  }

  /// Cancels any active idle timeout countdown
  void cancelIdleTimer() {
    if (_idleTimeoutTimer != null) {
      _idleTimeoutTimer?.cancel();
      _idleTimeoutTimer = null;
      AppLogger.log('AudioQueueHandler', 'Cancelled idle timeout countdown');
    }
  }

  /// Downgrades foreground service notification and releases native CPU WakeLocks
  Future<void> handleIdleRelease() async {
    if (player.playing || _isLoading) {
      AppLogger.log('AudioQueueHandler', 'handleIdleRelease aborted: player is still active or loading');
      cancelIdleTimer();
      return;
    }
    AppLogger.log('AudioQueueHandler', '5-minute idle timeout reached. Downgrading notification & releasing WakeLocks.');
    // 1. Close idle YouTube client sockets
    YouTubeClient.closeIdleClient();

    // 2. Deactivate AudioSession to release native CPU wake locks & audio focus
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioSession.setActive(false)');
    }

    // 3. Callback to PaatuAudioHandler to downgrade notification (remove ongoing flag)
    onIdleRelease?.call();
  }

  List<Song> get queue => List.unmodifiable(_queue);
  List<Song> get originalQueue => List.unmodifiable(_originalQueue);
  int get currentIndex => _currentIndex;
  Song? get currentSong => (_currentIndex >= 0 && _currentIndex < _queue.length) ? _queue[_currentIndex] : null;
  bool get hasNext => _currentIndex + 1 < _queue.length;
  bool get hasPrevious => _currentIndex > 0;
  int get upcomingCount => _queue.length - (_currentIndex + 1);
  bool get isLoading => _isLoading;

  void _initStreamListeners() {
    // Sequence state listener: updates current song tag metadata without modifying _currentIndex
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
          onQueueProgress?.call(_currentIndex, _queue.length);
        }
      }
    });

    // Sole index writer on track transition: updates UI & notification atomically
    _currentIndexSub = player.currentIndexStream.listen((index) {
      if (index != null && index >= 0) {
        final actualIndex = _playlistBaseIndex + index;
        if (actualIndex >= 0 && actualIndex < _queue.length && actualIndex != _currentIndex) {
          final oldIndex = _currentIndex;
          _currentIndex = actualIndex;
          _hasRetriedCurrentTrack = false;
          _sessionToken++; // Invalidate in-flight preloads from the previous track so they cannot mutate active track
          _syncState();

          final song = _queue[_currentIndex];
          AppLogger.log('AudioQueueHandler', 'Track transition: index $oldIndex -> $actualIndex ("${song.title}" [id=${song.id}])');
          _ensureAudioSessionActive();
          onSongChanged?.call(song);
          onQueueProgress?.call(_currentIndex, _queue.length);

          // Smooth volume normalization and crossfade entry
          final targetNorm = getEffectiveVolumeForSong(song);
          final crossfadeSec = SettingsManager.crossfadeSeconds;
          final fadeInMs = crossfadeSec > 0 ? (crossfadeSec * 600).clamp(250, 2000) : 150;
          _fadeVolumeTo(targetNorm, durationMs: fadeInMs).then((_) {
            if (!_isDisposed && player.volume < 0.1 && targetNorm >= 0.5) {
              try {
                player.setVolume(targetNorm);
              } catch (_) {}
            }
          });
          _startVolumeWatchdog(song);

          // Preload upcoming tracks for instantaneous gapless transition
          preloadUpcomingTracks(_currentIndex);
        }
      }
    });

    _positionSub = player.positionStream.listen((pos) {
      if (SettingsManager.crossfadeSeconds > 0) {
        _handleCrossfade(pos);
      }
    });

    // Underlying playback event listener: catches stream/decoder failure on active track
    try {
      _playbackEventSub = player.playbackEventStream.listen(
        (_) {},
        onError: (Object e, StackTrace st) async {
          AppLogger.recordError(e, st, context: 'AudioQueueHandler.playbackEventStream');
          final current = currentSong;
          if (current != null) {
            AppLogger.log('AudioQueueHandler', 'Playback error on active track "${current.title}" (${current.id})');
            current.streamUrl = null;
            YouTubeClient.invalidateStream(current.id);

            // Transparent auto-recovery: try to re-resolve fresh stream URL once if failed
            if (!_hasRetriedCurrentTrack && !_isDisposed) {
              _hasRetriedCurrentTrack = true;
              AppLogger.log('AudioQueueHandler', 'Auto-recovery: re-resolving fresh stream for "${current.title}"');
              final freshUrl = await _resolveStreamUrl(current);
              if (freshUrl != null && freshUrl.isNotEmpty && !_isDisposed) {
                current.streamUrl = freshUrl;
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

    // Single source of truth for player completion & lifecycle
    _playerStateSub = player.playerStateStream.listen((state) {
      onPlayStateChanged?.call(state.playing);

      if (state.playing) {
        cancelIdleTimer();
      } else {
        // Paused, completed, or idle: begin 5-minute countdown
        startIdleTimer();
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
        if (hasNext) {
          skipToNext();
        } else if (SettingsManager.isAutoplayEnabled && current != null && isAudioHandlerInitialized) {
          audioHandler.handleAutoplayQueueEnd(current);
        } else {
          startIdleTimer();
        }
      }
    });
  }

  void _syncState() {
    currentIndexNotifier.value = _currentIndex;
    queueNotifier.value = List.from(_queue);
    currentSongNotifier.value = currentSong;
  }

  /// Initialize and load a queue with gapless ConcatenatingAudioSource index-aligned to _queue
  Future<void> loadQueue(
    List<Song> songs, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    if (songs.isEmpty) {
      _isLoading = false;
      return;
    }

    final targetSong = (initialIndex >= 0 && initialIndex < songs.length) ? songs[initialIndex] : songs.first;

    // Guard against duplicate loadQueue calls for the same active song while already loading
    if (_isLoading && _queue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length && _queue[_currentIndex].id == targetSong.id) {
      AppLogger.log('AudioQueueHandler', 'loadQueue: duplicate call for "${targetSong.title}" [id=${targetSong.id}] ignored (already loading)');
      return;
    }

    cancelIdleTimer();
    final token = ++_sessionToken;
    _activeLoadSessionToken = token;
    _isLoading = true;

    try {
      AppLogger.log('AudioQueueHandler', 'loadQueue: ${songs.length} songs, initialIndex=$initialIndex, autoPlay=$autoPlay');

      try {
        await player.stop();
      } catch (_) {}

      if (token != _sessionToken) return;

      _queue.clear();
      _originalQueue.clear();
      _queue.addAll(songs);
      _originalQueue.addAll(songs);
      _currentIndex = (initialIndex >= 0 && initialIndex < songs.length) ? initialIndex : 0;

      _syncState();

      final activeSong = _queue[_currentIndex];
      onSongChanged?.call(activeSong);

      // Resolve active song first to guarantee immediate playback
      if (activeSong.streamUrl == null || activeSong.streamUrl!.isEmpty) {
        final resolvedUrl = await _resolveStreamUrl(activeSong);
        if (token != _sessionToken) return;
        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          activeSong.streamUrl = resolvedUrl;
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

      // Build forward sliding window starting at _currentIndex: [ activeSong, nextSong ]
      final List<AudioSource> sources = [];

      final activeSrc = (activeSong.streamUrl != null && activeSong.streamUrl!.isNotEmpty)
          ? await _buildAudioSource(activeSong, allowNetworkResolve: false)
          : null;

      if (activeSrc != null) {
        sources.add(activeSrc);
        // Preload immediate next track if available
        if (_currentIndex + 1 < _queue.length) {
          final nextSong = _queue[_currentIndex + 1];
          final nextSrc = await _buildAudioSource(nextSong, allowNetworkResolve: true);
          if (nextSrc != null && token == _sessionToken) {
            sources.add(nextSrc);
          }
        }
      } else {
        AppLogger.log('AudioQueueHandler', 'Active song "${activeSong.title}" could not be resolved.');
        if (autoPlay && _currentIndex + 1 < _queue.length) {
          AppLogger.log('AudioQueueHandler', 'Auto-advancing to next playable track in queue.');
          await skipToNext();
          return;
        }
      }

      if (sources.isEmpty) {
        AppLogger.log('AudioQueueHandler', 'No playable tracks found in audio source window.');
        return;
      }

      _playlistBaseIndex = _currentIndex;

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

        if (token != _sessionToken) {
          if (crossfadeSec > 0) {
            try {
              await player.setVolume(targetNorm);
            } catch (_) {}
          }
          return;
        }

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
        onQueueProgress?.call(_currentIndex, _queue.length);

        // Asynchronously preload upcoming tracks
        preloadUpcomingTracks(_currentIndex);
      } catch (e, stack) {
        AppLogger.recordError(e, stack, context: 'AudioQueueHandler.loadQueue setAudioSource');
        final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'AudioQueueHandler.loadQueue');
        audioHandler.playbackErrorNotifier.value = appErr;
        if (hasNext) {
          Future.delayed(const Duration(seconds: 2), () {
            if (!_isDisposed && _queue.isNotEmpty) skipToNext();
          });
        }
      }
    } finally {
      if (_activeLoadSessionToken == token) {
        _isLoading = false;
      }
    }
  }

  /// Preloads the immediate upcoming track for battery conservation & gapless transition
  Future<void> preloadUpcomingTracks(int fromIndex) async {
    final token = _sessionToken;
    final targetIndex = fromIndex + 1;
    if (targetIndex >= 0 && targetIndex < _queue.length) {
      final song = _queue[targetIndex];
      AppLogger.log('AudioQueueHandler', 'Preloading upcoming track [$targetIndex]: "${song.title}"');

      // Resolve stream URL if missing
      final wasMissingUrl = song.streamUrl == null || song.streamUrl!.isEmpty;
      if (wasMissingUrl) {
        final url = await _resolveStreamUrl(song);
        if (token != _sessionToken) {
          AppLogger.log('AudioQueueHandler', 'Preload aborted: session changed during resolution for "${song.title}"');
          return;
        }
        if (url != null && url.isNotEmpty) {
          song.streamUrl = url;
        } else {
          AppLogger.log('AudioQueueHandler', 'Preload stream resolution failed for "${song.title}". Will skip gracefully on playback.');
          return; // Do NOT mount an invalid or unresolvable source!
        }
      }

      // Check if targetIndex became the current index while we were resolving:
      if (targetIndex == _currentIndex || token != _sessionToken) {
        AppLogger.log('AudioQueueHandler', 'Preload target [$targetIndex] is now active. Aborting mutation.');
        return;
      }

      final source = await _buildAudioSource(song, allowNetworkResolve: false);
      if (source == null || token != _sessionToken || targetIndex == _currentIndex) return;

      final targetPlayerIndex = targetIndex - _playlistBaseIndex;
      if (targetPlayerIndex < 0) return;

      if (targetPlayerIndex < _playlistSource.length) {
        // ONLY replace if targetPlayerIndex is strictly greater than player's active index AND URL was newly resolved
        final currentPlayerIndex = _currentIndex - _playlistBaseIndex;
        if (targetPlayerIndex > currentPlayerIndex && wasMissingUrl) {
          try {
            await _playlistSource.removeAt(targetPlayerIndex);
            await _playlistSource.insert(targetPlayerIndex, source);
            AppLogger.log('AudioQueueHandler', 'Replaced playlist source at player index $targetPlayerIndex with resolved stream');
          } catch (e) {
            AppLogger.log('AudioQueueHandler', 'Safe catch during playlist source update at $targetPlayerIndex: $e');
          }
        }
      } else if (targetPlayerIndex == _playlistSource.length) {
        try {
          await _playlistSource.add(source);
          AppLogger.log('AudioQueueHandler', 'Appended resolved source at player index $targetPlayerIndex to playlist');
        } catch (e) {
          AppLogger.log('AudioQueueHandler', 'Safe catch during playlist source add at $targetPlayerIndex: $e');
        }
      }
    }
  }

  /// Skip to next track in queue with gapless transition
  Future<void> skipToNext() async {
    if (!hasNext) return;
    await jumpToIndex(_currentIndex + 1);
  }

  /// Skip to previous track in queue
  Future<void> skipToPrevious() async {
    if (player.position.inSeconds > 4) {
      await player.seek(Duration.zero);
      return;
    }
    if (!hasPrevious) return;
    await jumpToIndex(_currentIndex - 1);
  }

  /// Jump directly to any index in the queue with guaranteed 1-to-1 index alignment
  Future<void> jumpToIndex(int targetIndex) async {
    if (targetIndex < 0 || targetIndex >= _queue.length) return;
    final token = ++_sessionToken;

    final targetSong = _queue[targetIndex];
    AppLogger.log('AudioQueueHandler', 'jumpToIndex: targetIndex=$targetIndex ("${targetSong.title}")');
    final targetNorm = getEffectiveVolumeForSong(targetSong);
    final crossfadeSec = SettingsManager.crossfadeSeconds;

    // Smooth micro fade-out before jumping ONLY if crossfade is enabled
    if (player.playing && player.volume > 0.05 && crossfadeSec > 0) {
      await _fadeVolumeTo(0.0, durationMs: 120);
    }

    // Ensure target track is resolved
    if (targetSong.streamUrl == null || targetSong.streamUrl!.isEmpty) {
      final url = await _resolveStreamUrl(targetSong);
      if (token != _sessionToken) return;
      if (url != null && url.isNotEmpty) {
        targetSong.streamUrl = url;
      }
    }

    final targetPlayerIndex = targetIndex - _playlistBaseIndex;

    // If targetIndex is already present within current _playlistSource window, use gapless seek
    if (targetPlayerIndex >= 0 && targetPlayerIndex < _playlistSource.length) {
      try {
        await player.seek(Duration.zero, index: targetPlayerIndex);
        await _ensureAudioSessionActive();
        if (!player.playing) {
          await player.play();
        }
        _currentIndex = targetIndex;
        _hasRetriedCurrentTrack = false;
        _syncState();
        onSongChanged?.call(targetSong);
        if (crossfadeSec > 0) {
          _fadeVolumeTo(targetNorm, durationMs: (crossfadeSec * 600).clamp(250, 2000));
        } else {
          await player.setVolume(targetNorm);
        }
        _startVolumeWatchdog(targetSong);
        preloadUpcomingTracks(targetIndex);
        onQueueProgress?.call(_currentIndex, _queue.length);
        return;
      } catch (e) {
        AppLogger.log('AudioQueueHandler', 'Gapless seek failed at $targetPlayerIndex: $e. Re-centering playlist source.');
      }
    }

    // Re-center _playlistSource window at targetIndex
    final List<AudioSource> sources = [];
    final activeSrc = (targetSong.streamUrl != null && targetSong.streamUrl!.isNotEmpty)
        ? await _buildAudioSource(targetSong, allowNetworkResolve: false)
        : null;
    if (activeSrc != null) {
      sources.add(activeSrc);
    }

    if (targetIndex + 1 < _queue.length) {
      final nextSong = _queue[targetIndex + 1];
      final nextSrc = await _buildAudioSource(nextSong, allowNetworkResolve: true);
      if (nextSrc != null && token == _sessionToken) {
        sources.add(nextSrc);
      }
    }

    _playlistBaseIndex = targetIndex;
    _currentIndex = targetIndex;
    _hasRetriedCurrentTrack = false;
    _syncState();
    onSongChanged?.call(targetSong);

    _playlistSource = ConcatenatingAudioSource(
      children: sources,
      useLazyPreparation: true,
    );

    try {
      await player.setAudioSource(
        _playlistSource,
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
      if (token != _sessionToken) {
        try {
          await player.setVolume(targetNorm);
        } catch (_) {}
        return;
      }
      await _ensureAudioSessionActive();
      await player.play();
      if (crossfadeSec > 0) {
        _fadeVolumeTo(targetNorm, durationMs: (crossfadeSec * 600).clamp(250, 2000));
      } else {
        await player.setVolume(targetNorm);
      }
      _startVolumeWatchdog(targetSong);
      preloadUpcomingTracks(targetIndex);
      onQueueProgress?.call(_currentIndex, _queue.length);
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioQueueHandler.jumpToIndex setAudioSource');
      debugPrint('[AudioQueueHandler] Jump error: $e');
    }
  }

  /// Add track to queue as stack (pushed to play next right after current track)
  Future<void> addToQueue(Song song) async {
    final queued = song.copyWith(isUserEnqueued: true);
    AppLogger.log('AudioQueueHandler', 'addToQueue (stack push): "${queued.title}" [id=${queued.id}]');
    if (_queue.isEmpty || _currentIndex < 0) {
      await loadQueue([queued], initialIndex: 0, autoPlay: true);
      return;
    }
    final insertIdx = (_currentIndex >= 0 && _currentIndex < _queue.length) ? _currentIndex + 1 : _queue.length;
    await insertAt(insertIdx, queued);
  }

  /// Add multiple tracks to queue sequentially maintaining playlist order
  Future<void> addAllToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    if (_queue.isEmpty || _currentIndex < 0) {
      await loadQueue(songs, initialIndex: 0, autoPlay: true);
      return;
    }
    int baseInsertIdx = (_currentIndex >= 0 && _currentIndex < _queue.length) ? _currentIndex + 1 : _queue.length;
    for (int i = 0; i < songs.length; i++) {
      final queued = songs[i].copyWith(isUserEnqueued: true);
      await insertAt(baseInsertIdx + i, queued);
    }
  }

  /// Insert track to play next (pushed onto top of queue stack)
  Future<void> insertNext(Song song) async {
    final queued = song.copyWith(isUserEnqueued: true);
    final insertIdx = (_currentIndex >= 0 && _currentIndex < _queue.length) ? _currentIndex + 1 : _queue.length;
    await insertAt(insertIdx, queued);
  }

  /// Insert track at specific index maintaining playlist source alignment
  Future<void> insertAt(int index, Song song) async {
    final safeIndex = index.clamp(0, _queue.length);
    AppLogger.log('AudioQueueHandler', 'insertAt index $safeIndex: "${song.title}" [id=${song.id}]');
    _queue.insert(safeIndex, song);
    if (!song.isSmartRecommended) {
      _originalQueue.insert(safeIndex.clamp(0, _originalQueue.length), song);
    }
    if (safeIndex <= _currentIndex) {
      _currentIndex++;
      _playlistBaseIndex++;
    }
    _syncState();

    final targetPlayerIndex = safeIndex - _playlistBaseIndex;
    if (targetPlayerIndex >= 0 && targetPlayerIndex <= _playlistSource.length) {
      final source = await _buildAudioSource(song, allowNetworkResolve: false);
      if (source != null) {
        try {
          if (targetPlayerIndex < _playlistSource.length) {
            await _playlistSource.insert(targetPlayerIndex, source);
          } else {
            await _playlistSource.add(source);
          }
        } catch (e) {
          AppLogger.log('AudioQueueHandler', 'PlaylistSource insert error: $e');
        }
      }
    }
    preloadUpcomingTracks(_currentIndex);
    onQueueProgress?.call(_currentIndex, _queue.length);
  }

  /// Appends auto-suggested / recommended tracks to the end of the queue
  /// Enforces cross-artist title deduplication and rolling 75-song cooldown.
  Future<void> addAutoSuggestions(List<Song> songs) async {
    if (songs.isEmpty) return;
    final existingTitleKeys = _queue.map((s) => s.cleanTitleKey).where((k) => k.isNotEmpty).toSet();
    final List<Song> deduplicated = [];

    for (final song in songs) {
      final key = song.cleanTitleKey;
      if (key.isNotEmpty && existingTitleKeys.contains(key)) {
        AppLogger.log('AudioQueueHandler', 'addAutoSuggestions dropped duplicate track: "${song.title}"');
        continue;
      }
      if (QueueCooldownManager.isCoolingDown(song)) {
        AppLogger.log('AudioQueueHandler', 'addAutoSuggestions dropped cooling down track: "${song.title}"');
        continue;
      }
      if (key.isNotEmpty) existingTitleKeys.add(key);
      deduplicated.add(song.copyWith(isSmartRecommended: true, isUserEnqueued: false));
    }

    if (deduplicated.isEmpty) return;
    AppLogger.log('AudioQueueHandler', 'addAutoSuggestions: appending ${deduplicated.length} fresh tracks');
    for (final song in deduplicated) {
      _queue.add(song);
      _originalQueue.add(song);
    }
    _syncState();
    preloadUpcomingTracks(_currentIndex);
    onQueueProgress?.call(_currentIndex, _queue.length);
  }

  /// Remove track at index without disrupting playback or desynchronizing indices
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final isRemovingCurrent = index == _currentIndex;

    final removed = _queue.removeAt(index);
    AppLogger.log('AudioQueueHandler', 'removeAt index $index: "${removed.title}" (isCurrent=$isRemovingCurrent)');
    _originalQueue.removeWhere((s) => s.id == removed.id);

    final targetPlayerIndex = index - _playlistBaseIndex;
    if (targetPlayerIndex >= 0 && targetPlayerIndex < _playlistSource.length) {
      try {
        await _playlistSource.removeAt(targetPlayerIndex);
      } catch (e) {
        AppLogger.log('AudioQueueHandler', 'PlaylistSource removeAt error: $e');
      }
    }

    if (isRemovingCurrent) {
      if (_currentIndex < _queue.length) {
        await jumpToIndex(_currentIndex);
      } else if (_queue.isNotEmpty) {
        await jumpToIndex(_queue.length - 1);
      } else {
        await clear();
      }
    } else {
      if (index < _currentIndex) {
        _currentIndex--;
        _playlistBaseIndex--;
      }
      _syncState();
      onQueueProgress?.call(_currentIndex, _queue.length);
    }
  }

  /// Reorder tracks seamlessly and keep player indices aligned
  Future<void> reorder(int oldIndex, int newIndex) async {
    try {
      if (oldIndex < 0 || oldIndex >= _queue.length) return;
      if (newIndex < 0 || newIndex > _queue.length) return;

      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      if (oldIndex == newIndex) return;

      final song = _queue.removeAt(oldIndex);
      AppLogger.log('AudioQueueHandler', 'reorder: $oldIndex -> $newIndex ("${song.title}")');
      _queue.insert(newIndex, song);

      // Adjust current index tracking
      if (oldIndex == _currentIndex) {
        _currentIndex = newIndex;
      } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
        _playlistBaseIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
        _playlistBaseIndex++;
      }

      _syncState();

      final oldPlayerIdx = oldIndex - _playlistBaseIndex;
      final newPlayerIdx = newIndex - _playlistBaseIndex;
      if (oldPlayerIdx >= 0 && oldPlayerIdx < _playlistSource.length &&
          newPlayerIdx >= 0 && newPlayerIdx < _playlistSource.length) {
        try {
          await _playlistSource.move(oldPlayerIdx, newPlayerIdx);
        } catch (_) {}
      }

      preloadUpcomingTracks(_currentIndex);
      onQueueProgress?.call(_currentIndex, _queue.length);
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioQueueHandler.reorder');
    }
  }

  /// Replace upcoming queue with new list of tracks (used by Smart Shuffle & next-song algorithms)
  Future<void> replaceUpcomingQueue(List<Song> newUpcoming) async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;

    AppLogger.log('AudioQueueHandler', 'replaceUpcomingQueue with ${newUpcoming.length} tracks');
    // Keep history and current playing song intact
    final kept = _queue.sublist(0, _currentIndex + 1);
    _queue.clear();
    _queue.addAll(kept);
    _queue.addAll(newUpcoming);

    final currentPlayerIndex = _currentIndex - _playlistBaseIndex;
    // Remove old upcoming items from _playlistSource
    while (_playlistSource.length > currentPlayerIndex + 1) {
      try {
        await _playlistSource.removeAt(_playlistSource.length - 1);
      } catch (_) {
        break;
      }
    }

    // Add new upcoming items to _playlistSource
    for (final song in newUpcoming) {
      final src = await _buildAudioSource(song, allowNetworkResolve: false);
      if (src != null) {
        try {
          await _playlistSource.add(src);
        } catch (_) {}
      }
    }

    _syncState();
    preloadUpcomingTracks(_currentIndex);
    onQueueProgress?.call(_currentIndex, _queue.length);
  }

  /// Clear queue
  Future<void> clear() async {
    AppLogger.log('AudioQueueHandler', 'Queue cleared');
    cancelIdleTimer();
    YouTubeClient.closeIdleClient();
    _sessionToken++;
    try {
      await player.stop();
    } catch (_) {}

    _queue.clear();
    _originalQueue.clear();
    _currentIndex = -1;
    _playlistBaseIndex = 0;
    _syncState();

    try {
      await _playlistSource.clear();
    } catch (_) {}

    currentSongNotifier.value = null;
    onQueueProgress?.call(-1, 0);
  }

  /// Clear only tracks explicitly added by user to the queue stack
  Future<void> clearUserQueue() async {
    if (_queue.isEmpty || _currentIndex >= _queue.length - 1) return;
    AppLogger.log('AudioQueueHandler', 'Clearing user queue');
    final toRemove = <int>[];
    for (int i = _queue.length - 1; i > _currentIndex; i--) {
      if (_queue[i].isUserEnqueued) {
        toRemove.add(i);
      }
    }
    for (final idx in toRemove) {
      await removeAt(idx);
    }
  }

  // ================= Private AudioSource Builders ================= //

  Future<AudioSource?> _buildAudioSource(Song song, {bool allowNetworkResolve = true}) async {
    // 1. Local downloaded file
    if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
      return AudioSource.file(song.localFilePath!, tag: song.toMediaItem());
    }
    if (DownloadManager.isDownloaded(song.id)) {
      final downloadedSongs = DownloadManager.getDownloadedSongs();
      final match = downloadedSongs.firstWhere((s) => s.id == song.id, orElse: () => song);
      if (match.localFilePath != null && File(match.localFilePath!).existsSync()) {
        return AudioSource.file(match.localFilePath!, tag: song.toMediaItem());
      }
    }

    // 2. Stream URL
    String? streamUrl = song.streamUrl;
    if ((streamUrl == null || streamUrl.isEmpty) && allowNetworkResolve) {
      streamUrl = await _resolveStreamUrl(song);
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      // Do NOT mount fake .invalid URLs that cause ExoPlayer DNS lookup crashes
      return null;
    }

    // Quality bitrate adjustments for JioSaavn
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

    // Headers for streaming reliability (essential for YouTube / googlevideo.com streams)
    final headers = <String, String>{};
    if (song.source == 'youtube' || streamUrl.contains('googlevideo.com') || song.id.length == 11) {
      headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      headers['Accept'] = '*/*';
      headers['Connection'] = 'keep-alive';
    }

    // 3. Cache verification
    try {
      final tempDir = await getTemporaryDirectory();
      final sanitizedId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final cacheFile = File('${tempDir.path}/audio_$sanitizedId.mp4');
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 100000) {
        return AudioSource.file(cacheFile.path, tag: song.toMediaItem());
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

  /// Verifies candidate audio track against target before playing (title, artist, duration)
  static bool verifyAudioMatch(Song candidate, Song target) {
    return DefaultStreamResolver.verifyMatch(candidate, target);
  }

  Future<String?> _resolveStreamUrl(Song song) async {
    return streamResolver.resolveStreamUrl(song);
  }

  void dispose() {
    _isDisposed = true;
    _fadeToken++;
    SettingsManager.volumeNormalizationNotifier.removeListener(_onNormalizationChanged);
    _playbackEventSub?.cancel();
    _positionSub?.cancel();
    cancelIdleTimer();
    _sequenceStateSub?.cancel();
    _currentIndexSub?.cancel();
    _playerStateSub?.cancel();
    queueNotifier.dispose();
    currentIndexNotifier.dispose();
    currentSongNotifier.dispose();
    errorNotifier.dispose();
  }
}
