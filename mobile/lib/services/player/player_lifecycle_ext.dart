part of '../player_handler.dart';

extension PlayerLifecycleExt on PaatuAudioHandler {
  void _syncWidgetStateImpl({Song? song, bool? isPlaying}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final active = song ?? currentSong;
        final playing = isPlaying ?? _player.playing;
        PaatuAudioHandler._widgetChannel.invokeMethod('updateWidget', {
          'title': active?.title ?? 'Paatu Padava',
          'artist': active?.artist ?? 'Tap to play',
          'isPlaying': playing,
        }).catchError((_) {});
      } catch (e) {
        AppLogger.debug('PlayerHandler', 'Handled exception: $e');
      }
    }
  }

  void _didChangeAppLifecycleStateImpl(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppTaskRemoved = false;
    }
    final inBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
    if (_isAppInBackground != inBackground) {
      _isAppInBackground = inBackground;
      AppLogger.log(
        'PaatuAudioHandler',
        'Lifecycle state: $state. Background position stream throttling active: $inBackground',
      );
    }
  }

  /// Single centralized position dispatcher fanning out to metrics and stream listeners
  void _onPositionTickImpl(Duration pos) {
    // 1. Telemetry / Scrobble milestone (15s minimum listen, threshold reached)
    final posSec = pos.inSeconds;
    if (!_hasRecordedListen && posSec >= 15 && currentSong != null) {
      _hasRecordedListen = true;
    }

    if (!_hasRecordedHistory && currentSong != null) {
      final song = currentSong!;
      final totalSec = _player.duration?.inSeconds ?? song.duration;
      final thresholdSec = (totalSec > 0 && totalSec < 60) ? (totalSec * 0.5) : 30.0;
      if (posSec >= thresholdSec) {
        _hasRecordedHistory = true;
        final track = TrackEntity.fromSong(song);
        HistoryManager.addToHistory(track);
        QueueCooldownManager.recordPlayed(song);
        AppLogger.log('PlayerHandler', 'Scrobble milestone reached: Recorded play to HistoryManager and QueueCooldownManager for "${song.title}".');
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final isPlaying = _player.playing;

    // 2. High-precision lyrics fan-out (~50ms interval / 20 Hz)
    if (_lyricsPositionController != null && _lyricsPositionController!.hasListener) {
      if (now - _lastLyricsEmitMs >= 50 || !isPlaying) {
        _lastLyricsEmitMs = now;
        _lyricsPositionController!.add(pos);
      }
    }

    // 3. Throttled UI position fan-out (100ms foreground / 1500ms background)
    if (_throttledPositionController != null && _throttledPositionController!.hasListener) {
      final intervalMs = _isAppInBackground ? 1500 : 100;
      if (now - _lastThrottledEmitMs >= intervalMs || !isPlaying) {
        _lastThrottledEmitMs = now;
        _throttledPositionController!.add(pos);
      }
    }
  }

  Future<void> _initAudioSessionImpl() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetoothA2dp |
              AVAudioSessionCategoryOptions.allowAirPlay,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) async {
        AppLogger.log('PlayerHandler', 'ACTION_AUDIO_BECOMING_NOISY (headset/BT unplugged) -> auto-pausing immediately');
        await pause();
      });

      _interruptionSub = session.interruptionEventStream.listen((event) async {
        AppLogger.log('PlayerHandler', 'Audio interruption event: begin=${event.begin}, type=${event.type}');
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              await _player.setVolume((userVolume * 0.2).clamp(0.0, 1.0));
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              _resumeOnInterruptionEnd = _player.playing;
              await pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              await applyVolumeNormalization();
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_resumeOnInterruptionEnd) {
                _resumeOnInterruptionEnd = false;
                try {
                  final activeSession = await AudioSession.instance;
                  await activeSession.setActive(true);
                } catch (e) {
                  AppLogger.debug('PaatuAudioHandler', 'Could not reactivate AudioSession after interruption: $e');
                }
                await play();
              }
              break;
          }
        }
      });
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioSession setup');
    }
  }

  void _updateCachedFavImpl() {
    final active = currentSong;
    if (active != null) {
      _cachedIsFav = FavoritesManager.isFavorite(active.id);
      _cachedFavSongId = active.id;
    } else {
      _cachedIsFav = false;
      _cachedFavSongId = null;
    }
  }

  Future<void> _disposeImpl() async {
    _lyricsDebounceTimer?.cancel();
    _becomingNoisySub?.cancel();
    _interruptionSub?.cancel();
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    _durationSub?.cancel();
    _positionHubSub?.cancel();
    _throttledPositionController?.close();
    _lyricsPositionController?.close();
    _smartShuffleController.dispose();
    _queueHandler.dispose();
  }
}
