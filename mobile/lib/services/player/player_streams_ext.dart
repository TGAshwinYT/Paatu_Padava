part of '../player_handler.dart';

extension PlayerStreamsExt on PaatuAudioHandler {
  void _broadcastStateImpl({bool downgradeNotification = false}) {
    final playing = _player.playing;
    final AudioProcessingState processingState;
    if (downgradeNotification || _isForegroundDowngraded) {
      processingState = (currentSong != null) ? AudioProcessingState.ready : AudioProcessingState.idle;
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
        ? (_cachedIsFav ? PaatuAudioHandler._controlsPlayingFav : PaatuAudioHandler._controlsPlayingUnfav)
        : (_cachedIsFav ? PaatuAudioHandler._controlsPausedFav : PaatuAudioHandler._controlsPausedUnfav);

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
    _syncWidgetState(isPlaying: playing);
  }

  void _initStreamsImpl() {
    _playbackEventSub = _player.playbackEventStream.listen(
      (event) {
        if (_player.duration != null && _player.duration!.inMilliseconds > 0) {
          if (currentSong != null && currentSong!.duration == 0) {
            currentSong!.duration = _player.duration!.inSeconds;
          }
          if (mediaItem.value != null && mediaItem.value?.duration != _player.duration) {
            mediaItem.add(mediaItem.value!.copyWith(duration: _player.duration));
          }
        }
        _broadcastState();
      },
      onError: (Object e, StackTrace stack) {
        AppLogger.recordError(e, stack, context: 'AudioPlayer.playbackEventStream');
        final err = ErrorHandler.resolve(e, stackTrace: stack, context: 'AudioPlayer.playbackEventStream');
        playbackErrorNotifier.value = err;
        debugPrint('[PlayerHandler] Playback error: ${err.userMessage}');
      },
    );

    try {
      _durationSub = _player.durationStream.listen((dur) {
        if (dur != null && dur.inMilliseconds > 0) {
          if (currentSong != null && currentSong!.duration == 0) {
            currentSong!.duration = dur.inSeconds;
          }
          if (mediaItem.value != null && mediaItem.value?.duration != dur) {
            mediaItem.add(mediaItem.value!.copyWith(duration: dur));
          }
          _broadcastState();
          if (currentSong != null) {
            _checkLyricsDurationReselection(currentSong!, dur.inSeconds);
          }
        }
      });
    } catch (e, st) {
      AppLogger.recordError(e, st, context: 'PaatuAudioHandler duration stream subscription');
    }

    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.playing) {
        _isForegroundDowngraded = false;
        if (SleepTimerService.instance.hasExpired) {
          SleepTimerService.instance.triggerSleepNow();
          return;
        }
      }
      if (state.processingState == ProcessingState.ready) {
        EqualizerService.refreshDspStatus();
      }
      _broadcastState();
    });

    // Unified Position Hub: single subscription to player.positionStream fanning out to metrics & UI controllers
    _positionHubSub = _player.positionStream.listen(
      _onPositionTick,
      onError: (e, st) {
        AppLogger.recordError(e, st, context: 'Position hub stream error');
        _throttledPositionController?.addError(e, st);
        _lyricsPositionController?.addError(e, st);
      },
    );
  }

  Future<void> _disposeAudioHandlerImpl() async {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      AppLogger.debug('PaatuAudioHandler', 'Could not remove WidgetsBinding observer: $e');
    }
    _becomingNoisySub?.cancel();
    _becomingNoisySub = null;
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _playbackEventSub?.cancel();
    _playbackEventSub = null;
    _durationSub?.cancel();
    _durationSub = null;
    _positionHubSub?.cancel();
    _positionHubSub = null;
    _throttledPositionController?.close();
    _throttledPositionController = null;
    _lyricsPositionController?.close();
    _lyricsPositionController = null;
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
}
