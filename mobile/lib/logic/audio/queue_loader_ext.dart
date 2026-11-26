part of '../audio_queue_handler.dart';

extension QueueLoaderExt on AudioQueueHandler {
  Future<void> _loadQueueImpl(
    List<dynamic> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
    bool isPartyDriven = false,
    bool preserveUserQueue = false,
  }) async {
    if (isPartyDriven) {
      isPartyDrivenLoad = true;
    }
    if (tracks.isEmpty) {
      _isLoading = false;
      return;
    }

    final entities = tracks.map((t) => AudioQueueHandler._toEntity(t)).toList();
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
      } catch (e) {
        AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
      }

      if (token != _sessionToken) return;

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
      _hasEnforcedInitialVolume = false;
      _resetTrackMilestones();

      _contextIndex = 0;
      _currentTrack = orderedTracks[0];
      _lastCompletedSeedSong = _currentTrack?.toSong();
      _currentTrackIsFromUserQueue = false;

      NextTrackStrategyFactory.resetSession(initialAnchor: _currentTrack?.toSong());

      _syncState();

      final activeSong = _currentTrack!.toSong();
      if (!isPartyDrivenLoad) {
        onSongChanged?.call(activeSong);
      }

      final currentRequestId = ++_loadRequestId;
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

      final List<AudioSource> sources = [];
      final activeSrc = (activeSong.streamUrl != null && activeSong.streamUrl!.isNotEmpty)
          ? await _buildAudioSource(activeSong, allowNetworkResolve: true)
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
      try {
        await player.setVolume(targetNorm);
      } catch (e) {
        AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
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
          player.play().catchError((e, st) {
            AppLogger.recordError(e, st, context: 'player.play in loadQueue');
          });
          try {
            await player.setVolume(targetNorm);
          } catch (e) {
            AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
          }
          _startVolumeWatchdog(activeSong);
        } else {
          try {
            if (player.processingState != ProcessingState.ready) {
              await player.processingStateStream
                  .firstWhere((state) => state == ProcessingState.ready || state == ProcessingState.idle)
                  .timeout(const Duration(seconds: 8));
            }
          } catch (e) {
            AppLogger.log('AudioQueueHandler', 'autoPlay=false wait for ready timed out or noticed: $e');
          }
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
}
