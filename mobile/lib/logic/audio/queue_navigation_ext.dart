part of '../audio_queue_handler.dart';

extension QueueNavigationExt on AudioQueueHandler {
  Future<void> _skipToPreviousImpl() async {
    if (player.position.inSeconds > 4) {
      await player.seek(Duration.zero);
      return;
    }

    if (_isTransitioning) {
      AppLogger.log('AudioQueueHandler', 'skipToPrevious ignored: transition currently in progress');
      return;
    }
    _isTransitioning = true;

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

  Future<void> _jumpToIndexImpl(int targetIndex) async {
    final merged = _buildMergedQueue();
    if (targetIndex < 0 || targetIndex >= merged.length) return;
    final targetEntity = merged[targetIndex];

    AppLogger.log('AudioQueueHandler', 'jumpToIndex: targetIndex=$targetIndex ("${targetEntity.title}")');

    final passedItems = merged.sublist(0, targetIndex);
    for (final passed in passedItems) {
      if (_userQueue.remove(passed)) {
        _playbackHistory.add(passed);
      }
    }

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

  Future<void> _skipToQueueItemImpl(
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
}
