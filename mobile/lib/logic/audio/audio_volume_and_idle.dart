part of '../audio_queue_handler.dart';

extension AudioVolumeAndIdleExt on AudioQueueHandler {
  Future<void> _ensureAudioSessionActive() async {
    try {
      if (isAudioHandlerInitialized) {
        await audioHandler.ensureAudioSessionConfigured();
      }
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      AppLogger.log('AudioQueueHandler', 'AudioSession.setActive(true) notice: $e');
    }
  }

  void _startVolumeWatchdog(Song? song) {
    if (song == null || _isDisposed) return;
    _volumeWatchdogTimer?.cancel();
    int ticks = 0;
    _volumeWatchdogTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
      ticks++;
      if (_isDisposed || ticks > 16) {
        timer.cancel();
        return;
      }
      if (player.playing) {
        final targetNorm = getEffectiveVolumeForSong(song);
        bool isReady = false;
        try {
          isReady = player.processingState == ProcessingState.ready;
        } catch (e) {
          AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
        }

        if (isReady) {
          try {
            await player.setVolume(targetNorm);
          } catch (e) {
            AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
          }
          timer.cancel();
        } else {
          double vol = 1.0;
          try {
            vol = player.volume;
          } catch (e) {
            AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
          }
          if (vol < 0.1 && targetNorm >= 0.2) {
            AppLogger.log('AudioQueueHandler', 'Volume watchdog: Restoring stuck volume ($vol -> $targetNorm)');
            try {
              await player.setVolume(targetNorm);
            } catch (e) {
              AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
            }
          }
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
      } catch (e) {
        AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
      }
      return;
    }

    const int steps = 8;
    final stepMs = (durationMs / steps).round();
    for (int i = 1; i <= steps; i++) {
      if (_isDisposed || myToken != _fadeToken) return;
      final v = startVolume + (targetVolume - startVolume) * (i / steps);
      try {
        await player.setVolume(v.clamp(0.0, 1.0));
      } catch (e) {
        AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
      }
      await Future.delayed(Duration(milliseconds: stepMs));
    }
    if (!_isDisposed && myToken == _fadeToken) {
      try {
        await player.setVolume(targetVolume);
      } catch (e) {
        AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
      }
    }
  }

  void _onNormalizationChanged() {
    final target = getEffectiveVolumeForSong(currentSong);
    _fadeVolumeTo(target, durationMs: 250);
  }

  void _handleCrossfade(Duration pos) {
    if (_effectiveLoopMode == LoopMode.one) return;
    final crossfadeSec = SettingsManager.crossfadeSeconds;
    final isBeatMatch = SettingsManager.isBeatMatchEnabled;
    if (crossfadeSec <= 0 && !isBeatMatch) return;
    final duration = player.duration;
    if (duration == null || duration.inSeconds <= (crossfadeSec > 0 ? crossfadeSec * 2 : 6)) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCrossfadeTimeMs < 80) return;
    _lastCrossfadeTimeMs = now;

    final targetNorm = getEffectiveVolumeForSong(currentSong);
    if (currentSong != null) {
      _crossfadeEngine.prepareTransition(outgoing: currentSong!, incoming: nextSong);
    }
    _crossfadeEngine.applyEqualPowerFadeOut(
      position: pos,
      duration: duration,
      baseTargetVolume: targetNorm,
    );
  }

  Timer? get idleTimeoutTimer => _idleTimeoutTimer;
  bool get isIdleTimeoutActive => _idleTimeoutTimer != null && _idleTimeoutTimer!.isActive;

  void startIdleTimer({Duration timeout = const Duration(minutes: 15)}) {
    cancelIdleTimer();
    if (player.playing || _isLoading || _isPreparing || _isAdvancing) return;
    _idleTimeoutTimer = Timer(timeout, () {
      handleIdleRelease();
    });
    AppLogger.log('AudioQueueHandler', 'Started 15-minute idle timeout countdown');
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
    AppLogger.log('AudioQueueHandler', '15-minute idle timeout reached. Releasing idle resources.');
    YouTubeClient.closeIdleClient();

    try {
      final session = await AudioSession.instance;
      if (_currentTrack == null) await session.setActive(false);
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioSession.setActive(false)');
    }

    try {
      if (_currentTrack == null) await BatteryOptimizationService.detachForeground();
    } catch (e) {
      AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
    }

    onIdleRelease?.call();
  }
}
