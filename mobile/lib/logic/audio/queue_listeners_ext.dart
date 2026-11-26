part of '../audio_queue_handler.dart';

extension QueueListenersExt on AudioQueueHandler {
  void _initStreamListenersImpl() {
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

        if (!_hasEnforcedInitialVolume) {
          _hasEnforcedInitialVolume = true;
          final targetNorm = getEffectiveVolumeForSong(currentSong);
          try {
            player.setVolume(targetNorm);
          } catch (e) {
            AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
          }
        }
      }

      if (SettingsManager.crossfadeSeconds > 0) {
        _handleCrossfade(pos);
      }

      final dur = player.duration;
      if (dur != null && dur.inSeconds > 15) {
        final progressRatio = pos.inMilliseconds / dur.inMilliseconds;
        final remainingSec = dur.inSeconds - pos.inSeconds;

        if (!_hasTriggered25PctRecs && (progressRatio >= 0.25 || remainingSec <= 15)) {
          _hasTriggered25PctRecs = true;
          AppLogger.log('AudioQueueHandler', '25% milestone reached: Candidate generation check (upcoming count: $upcomingCount).');

          final remainingUpcoming = upcomingCount;
          if (remainingUpcoming <= 2 &&
              SettingsManager.isAutoplayEnabled &&
              !SleepTimerService.instance.isActive &&
              isAudioHandlerInitialized) {
            final active = currentSong;
            if (active != null) {
              final seed = _lastCompletedSeedSong ?? active;
              AppLogger.log('AudioQueueHandler', 'Triggered recommendation pre-fetch for seed "${seed.title}"');
              audioHandler.prefetchNextRecommendations(seed);
            }
          }
        }

        if (!_hasTriggered70PctPrecache && (progressRatio >= 0.70 || remainingSec <= 15)) {
          _hasTriggered70PctPrecache = true;
          AppLogger.log('AudioQueueHandler', '70% milestone: JIT stream pre-cache for index + 1.');
          if (hasNext) {
            preloadUpcomingTracks();
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
    } catch (e) {
      AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
    }

    _playerStateSub = player.playerStateStream.listen((state) {
      onPlayStateChanged?.call(state.playing);

      if (state.playing) {
        _consecutivePlaybackErrors = 0;
        _hasRetriedCurrentTrack = false;
        cancelIdleTimer();

        if (state.processingState == ProcessingState.ready) {
          final targetNorm = getEffectiveVolumeForSong(currentSong);
          try {
            player.setVolume(targetNorm);
          } catch (e) {
            AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
          }
        }
      } else if (state.processingState != ProcessingState.loading &&
          state.processingState != ProcessingState.buffering &&
          !_isPreparing &&
          !_isAdvancing &&
          !_isLoading) {
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
          _lastCompletedSeedSong = _currentTrack!.toSong();
          if (!_actuallyPlayedInSession.any((t) => t.id == _currentTrack!.id)) {
            _actuallyPlayedInSession.add(_currentTrack!);
          }
        }

        final current = currentSong;
        if (current != null) {
          final dur = player.duration ?? const Duration(seconds: 180);
          if (isAudioHandlerInitialized) {
            audioHandler.smartShuffleController.recordPlaybackFeedback(
              current,
              listenedSeconds: dur.inSeconds,
              totalSeconds: dur.inSeconds,
            );
          }
        }

        if (_effectiveLoopMode == LoopMode.one) {
          if (_currentTrack != null) {
            _isAdvancing = false;
            _crossfadeEngine.reset();
            _hasEnforcedInitialVolume = false;
            _lastCompletedTrackId = null;
            final targetVol = getEffectiveVolumeForSong(_currentTrack!.toSong());
            unawaited(() async {
              await player.setVolume(targetVol);
              await player.seek(Duration.zero);
              player.play().catchError((e, st) => AppLogger.recordError(e, st, context: 'loop one replay'));
            }());
            return;
          }
        }

        if (SleepTimerService.instance.stopAtEndOfTrack) {
          _isAdvancing = false;
          SleepTimerService.instance.triggerSleepNow();
          return;
        }

        if (PartySyncCoordinator.isJoiner) {
          _isAdvancing = false;
          AppLogger.log('AudioQueueHandler', 'Joiner reached track end - holding for host transition barrier');
          player.pause();
          return;
        }

        if (hasNext) {
          skipToNext(isUserInitiated: false);
        } else if (SleepTimerService.instance.stopAtEndOfQueue) {
          _isAdvancing = false;
          SleepTimerService.instance.triggerSleepNow();
          startIdleTimer();
        } else if (_effectiveLoopMode == LoopMode.all && _contextQueue.isNotEmpty) {
          handleRepeatAllLoop();
        } else if (SettingsManager.isAutoplayEnabled &&
            !SleepTimerService.instance.isActive &&
            current != null &&
            isAudioHandlerInitialized) {
          _isAdvancing = false;
          audioHandler.handleAutoplayQueueEnd(_lastCompletedSeedSong ?? current).whenComplete(() => _isAdvancing = false);
        } else {
          _isAdvancing = false;
          startIdleTimer();
        }
      }
    });
  }
}
