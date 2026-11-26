part of '../audio_queue_handler.dart';

extension QueuePlaybackExt on AudioQueueHandler {
  void _advanceToNextTrackFromPlayerStreamImpl([String? expectedId]) {
    if (SleepTimerService.instance.stopAtEndOfTrack) {
      _isTransitioning = false;
      SleepTimerService.instance.triggerSleepNow();
      return;
    }
    if (_isTransitioning || _isDisposed) return;
    if (expectedId != null && _currentTrack?.id == expectedId) return;
    _isTransitioning = true;

    try {
      _lastCompletedTrackId = _currentTrack?.id;

      if (_currentTrack != null && _currentTrackIsFromUserQueue && _userQueue.isNotEmpty && _userQueue.first.id == _currentTrack!.id) {
        _userQueue.removeAt(0);
      }

      if (_userQueue.isNotEmpty) {
        final next = _userQueue.removeAt(0);
        if (_currentTrack != null) {
          final previous = _currentTrack!;
          NextTrackStrategyFactory.recordTransition(
            previous.toSong(),
            next.toSong(),
            isPositive: true,
          );
          _playbackHistory.add(previous);
          if (!_actuallyPlayedInSession.any((t) => t.id == previous.id)) {
            _actuallyPlayedInSession.add(previous);
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
            final previous = _currentTrack!;
            NextTrackStrategyFactory.recordTransition(
              previous.toSong(),
              next.toSong(),
              isPositive: true,
            );
            _playbackHistory.add(previous);
            if (!_actuallyPlayedInSession.any((t) => t.id == previous.id)) {
              _actuallyPlayedInSession.add(previous);
            }
          }
          _currentTrack = next;
          _currentTrackIsFromUserQueue = false;
        }
      }

      _sessionToken++;
      _playlistBaseIndex = currentIndex;
      _hasRetriedCurrentTrack = false;
      _hasEnforcedInitialVolume = false;
      _resetTrackMilestones();
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
          } catch (e) {
            AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
          }
        }
        _startVolumeWatchdog(song);
        preloadUpcomingTracks();
      }
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _handleRepeatAllLoopImpl() async {
    AppLogger.log('AudioQueueHandler', 'RepeatMode.all: Looping context queue.');
    _userQueue.clear();

    if (_contextQueue.isEmpty) {
      startIdleTimer();
      return;
    }

    if (_isShuffleEnabled) {
      _contextShuffleIndices.clear();
      final indices = List<int>.generate(_contextQueue.length, (i) => i);
      final rng = Random();
      for (int i = indices.length - 1; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final temp = indices[i];
        indices[i] = indices[j];
        indices[j] = temp;
      }
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

  Future<void> _playTrackEntityImpl(TrackEntity entity) async {
    final token = ++_sessionToken;
    final currentRequestId = ++_loadRequestId;
    final activeToken = ++_activeLoadToken;
    _isPreparing = true;

    try {
      var song = entity.toSong();

      final verifiedLocalPath = (song.localFilePath != null && File(song.localFilePath!).existsSync())
          ? song.localFilePath
          : (DownloadManager.getLocalFilePath(song.id) ??
              DownloadManager.findDownloadedMatch(song)?.localFilePath);
      if (verifiedLocalPath != null && File(verifiedLocalPath).existsSync()) {
        song = song.copyWith(
          localFilePath: verifiedLocalPath,
          localCoverPath: DownloadManager.getLocalCoverPath(song.id) ??
              DownloadManager.findDownloadedMatch(song)?.localCoverPath ??
              song.localCoverPath,
          isDownloaded: true,
          source: 'offline',
        );
      } else if (song.streamUrl == null || song.streamUrl!.isEmpty || streamResolver.isExpired(song.id)) {
        final url = await _resolveStreamUrl(song);
        if (currentRequestId != _loadRequestId || token != _sessionToken || activeToken != _activeLoadToken) return;
        if (url != null && url.isNotEmpty) {
          song.streamUrl = url;
          _updateTrackStreamUrl(song.id, url);
        }
      }

      _playlistBaseIndex = currentIndex;
      _hasRetriedCurrentTrack = false;
      _resetTrackMilestones();
      _syncState();
      onSongChanged?.call(song);

      final activeSrc = await _buildAudioSource(song, allowNetworkResolve: true);
      if (token != _sessionToken || activeToken != _activeLoadToken) return;

      if (activeSrc == null) {
        _consecutivePlaybackErrors++;
        AppLogger.log('AudioQueueHandler', 'Failed to build audio source for "${song.title}". (Consecutive failures: $_consecutivePlaybackErrors)');
        if (_consecutivePlaybackErrors >= AudioQueueHandler._maxConsecutivePlaybackErrors) {
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
        } else {
          final err = streamResolver.lastResolutionError ?? AppError.songUnavailable(song.title);
          errorNotifier.value = err;
          onError?.call(err);
          if (isAudioHandlerInitialized) {
            audioHandler.playbackErrorNotifier.value = err;
          }
        }
        return;
      }

      final sources = <AudioSource>[activeSrc];

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
        player.play().catchError((e, st) => AppLogger.recordError(e, st, context: 'track advance play'));
        _crossfadeEngine.onIncomingTrackStarted(player);
        _consecutivePlaybackErrors = 0;
        _hasRetriedCurrentTrack = false;
        _hasDownscaledCurrentTrack = false;
        _hasEnforcedInitialVolume = false;
        _crossfadeEngine.reset();
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
        await handlePlaybackError(e, stack, context: '_playTrackEntity');
      }
    } finally {
      _isAdvancing = false;
      if (activeToken == _activeLoadToken) {
        _isPreparing = false;
      }
    }
  }
}
