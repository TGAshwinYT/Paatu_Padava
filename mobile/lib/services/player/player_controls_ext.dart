part of '../player_handler.dart';

extension PlayerControlsExt on PaatuAudioHandler {
  Future<void> _playImpl() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      AppLogger.debug('PaatuAudioHandler', 'AudioSession setActive(true) error on playSong: $e');
    }
    _isForegroundDowngraded = false;
    _queueHandler.cancelIdleTimer();
    _player.play().catchError((e) {
      AppLogger.debug('PaatuAudioHandler', 'Player play error: $e');
    });
    await applyVolumeNormalization();
    _broadcastState();
    if (PartySyncCoordinator.isHost && !_queueHandler.isPartyDrivenLoad) {
      PartySyncCoordinator.notifyHostResume();
    }
  }

  Future<void> _pauseImpl({bool isPartyDriven = false}) async {
    await _player.pause();
    _queueHandler.startIdleTimer();
    _broadcastState();
    if (PartySyncCoordinator.isHost && !isPartyDriven) {
      PartySyncCoordinator.notifyHostPause();
    }
    if (_isAppTaskRemoved && SettingsManager.isPersistentBackgroundPlaybackEnabled) {
      AppLogger.log('PaatuAudioHandler', 'User paused playback after app task was closed -> stopping service completely');
      await stop();
    }
  }

  Future<void> _onTaskRemovedImpl() async {
    _isAppTaskRemoved = true;
    AppLogger.log(
      'PaatuAudioHandler',
      'onTaskRemoved invoked from Android OS. persistentPlayback=${SettingsManager.isPersistentBackgroundPlaybackEnabled}, isPlaying=${_player.playing}',
    );

    if (!SettingsManager.isPersistentBackgroundPlaybackEnabled) {
      await stop();
    } else {
      if (_player.playing) {
        _isForegroundDowngraded = false;
        _broadcastState();
      } else {
        await stop();
      }
    }
  }

  Future<void> _seekImpl(Duration position, {bool isPartyDriven = false}) async {
    await _player.seek(position);
    _broadcastState();
    if (PartySyncCoordinator.isHost && !isPartyDriven) {
      PartySyncCoordinator.notifyHostSeek(position);
    }
  }

  Future<void> _stopImpl() async {
    _queueHandler.cancelIdleTimer();
    YouTubeClient.closeIdleClient();
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      AppLogger.debug('PaatuAudioHandler', 'AudioSession setActive(false) notice on stop: $e');
    }
    await _player.stop();
    _broadcastState();
  }

  Future<void> _toggleLoopModeImpl() async {
    final current = _player.loopMode;
    if (current == LoopMode.off) {
      await _player.setLoopMode(LoopMode.all);
    } else if (current == LoopMode.all) {
      await _player.setLoopMode(LoopMode.one);
    } else {
      await _player.setLoopMode(LoopMode.off);
    }
  }

  Future<void> _setRepeatModeImpl(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        await _player.setLoopMode(LoopMode.all);
        break;
    }
    _broadcastState();
  }

  Future<void> _skipToNextImpl() async {
    if (PartySyncCoordinator.role == PartyRole.joiner) {
      AppLogger.log('PlayerHandler', 'skipToNext ignored on joiner device in party mode');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSkipTimeMs < PaatuAudioHandler._skipDebounceMs) {
      AppLogger.log('PlayerHandler', 'skipToNext ignored due to 300ms debounce lock');
      return;
    }
    _lastSkipTimeMs = now;

    final current = currentSong;
    if (current != null) {
      final pos = _player.position;
      final dur = _player.duration ?? const Duration(seconds: 180);
      _smartShuffleController.recordPlaybackFeedback(
        current,
        listenedSeconds: pos.inSeconds,
        totalSeconds: dur.inSeconds,
      );
    }
    await _queueHandler.skipToNext();
  }

  Future<void> _skipToQueueItemImpl(int index) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSkipTimeMs < PaatuAudioHandler._skipDebounceMs) {
      AppLogger.log('PlayerHandler', 'skipToQueueItem ignored due to 300ms debounce lock');
      return;
    }
    _lastSkipTimeMs = now;

    final current = currentSong;
    if (current != null) {
      final pos = _player.position;
      final dur = _player.duration ?? const Duration(seconds: 180);
      _smartShuffleController.recordPlaybackFeedback(
        current,
        listenedSeconds: pos.inSeconds,
        totalSeconds: dur.inSeconds,
      );
      NextTrackStrategyFactory.recordSkip(current, listenedSeconds: pos.inSeconds);
    }
    await _queueHandler.jumpToIndex(index);
  }

  Future<void> _skipToQueueTrackImpl(
    TrackEntity targetTrack, {
    bool fromUserQueue = false,
    bool fromPlayedHistory = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSkipTimeMs < PaatuAudioHandler._skipDebounceMs) {
      AppLogger.log('PlayerHandler', 'skipToQueueTrack ignored due to 300ms debounce lock');
      return;
    }
    _lastSkipTimeMs = now;

    final current = currentSong;
    if (current != null) {
      final pos = _player.position;
      final dur = _player.duration ?? const Duration(seconds: 180);
      _smartShuffleController.recordPlaybackFeedback(
        current,
        listenedSeconds: pos.inSeconds,
        totalSeconds: dur.inSeconds,
      );
      NextTrackStrategyFactory.recordSkip(current, listenedSeconds: pos.inSeconds);
    }
    await _queueHandler.skipToQueueItem(
      targetTrack,
      fromUserQueue: fromUserQueue,
      fromPlayedHistory: fromPlayedHistory,
    );
  }

  Future<void> _skipToPreviousImpl() async {
    if (PartySyncCoordinator.role == PartyRole.joiner) {
      AppLogger.log('PlayerHandler', 'skipToPrevious ignored on joiner device in party mode');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSkipTimeMs < PaatuAudioHandler._skipDebounceMs) {
      AppLogger.log('PlayerHandler', 'skipToPrevious ignored due to 300ms debounce lock');
      return;
    }
    _lastSkipTimeMs = now;

    await _queueHandler.skipToPrevious();
  }
}
