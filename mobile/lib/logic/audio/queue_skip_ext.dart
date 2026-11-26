part of '../audio_queue_handler.dart';

extension QueueSkipExt on AudioQueueHandler {
  Future<void> _skipToNextImpl({bool isUserInitiated = true}) async {
    if (!isUserInitiated && SleepTimerService.instance.stopAtEndOfTrack) {
      _isTransitioning = false;
      SleepTimerService.instance.triggerSleepNow();
      return;
    }
    if (_isTransitioning) {
      AppLogger.log('AudioQueueHandler', 'skipToNext ignored: transition currently in progress');
      return;
    }
    _isTransitioning = true;

    try {
      if (isUserInitiated) {
        _lastCompletedTrackId = null;
      }

      if (_currentTrack != null) {
        final listenedSec = player.position.inSeconds;
        if (isUserInitiated) {
          NextTrackStrategyFactory.recordSkip(_currentTrack!.toSong(), listenedSeconds: listenedSec);
          if (listenedSec >= 30) {
            _lastCompletedSeedSong = _currentTrack!.toSong();
          }
        } else {
          _lastCompletedSeedSong = _currentTrack!.toSong();
        }
      }

      if (_effectiveLoopMode == LoopMode.one) {
        if (_currentTrack != null) {
          _isAdvancing = false;
          _crossfadeEngine.reset();
          _hasEnforcedInitialVolume = false;
          _lastCompletedTrackId = null;
          final targetVol = getEffectiveVolumeForSong(_currentTrack!.toSong());
          await player.setVolume(targetVol);
          await player.seek(Duration.zero);
          player.play().catchError((e, st) => AppLogger.recordError(e, st, context: 'loop one play'));
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
          final previous = _currentTrack!;
          final listenedSec = player.position.inSeconds;
          NextTrackStrategyFactory.recordTransition(
            previous.toSong(),
            next.toSong(),
            isPositive: !isUserInitiated || listenedSec >= 30,
          );
          _playbackHistory.add(previous);
          if (!_actuallyPlayedInSession.any((t) => t.id == previous.id)) {
            _actuallyPlayedInSession.add(previous);
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
          final previous = _currentTrack!;
          final listenedSec = player.position.inSeconds;
          NextTrackStrategyFactory.recordTransition(
            previous.toSong(),
            next.toSong(),
            isPositive: !isUserInitiated || listenedSec >= 30,
          );
          _playbackHistory.add(previous);
          if (!_actuallyPlayedInSession.any((t) => t.id == previous.id)) {
            _actuallyPlayedInSession.add(previous);
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
      if (SettingsManager.isAutoplayEnabled &&
          !SleepTimerService.instance.isActive &&
          _currentTrack != null &&
          isAudioHandlerInitialized) {
        await audioHandler.handleAutoplayQueueEnd(_lastCompletedSeedSong ?? _currentTrack!.toSong());
      }
    } finally {
      _isTransitioning = false;
    }
  }
}
