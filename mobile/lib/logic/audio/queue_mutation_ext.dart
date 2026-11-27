part of '../audio_queue_handler.dart';

extension QueueMutationExt on AudioQueueHandler {
  Future<void> _updateContextQueuePreservingCurrentImpl(
    List<dynamic> tracks, {
    required int currentIndex,
  }) async {
    final entities = tracks.map((t) => AudioQueueHandler._toEntity(t)).toList();
    _contextQueue
      ..clear()
      ..addAll(entities);
    if (_isShuffleEnabled) {
      _contextShuffleIndices
        ..clear()
        ..addAll(List<int>.generate(_contextQueue.length, (i) => i));
    }
    if (_currentTrack != null) {
      final match = _contextQueue.indexWhere((t) => t.id == _currentTrack!.id);
      _contextIndex = match != -1
          ? match
          : (_contextQueue.isEmpty ? 0 : currentIndex.clamp(0, _contextQueue.length - 1));
    } else {
      _contextIndex = _contextQueue.isEmpty ? 0 : currentIndex.clamp(0, _contextQueue.length - 1);
    }
    _syncState();
    onQueueProgress?.call(this.currentIndex, queue.length);
    if (!PartySyncCoordinator.isJoiner) {
      preloadUpcomingTracks();
    }
  }

  Future<void> _playNextImpl(dynamic track) async {
    final entity = AudioQueueHandler._toEntity(track).copyWith(isUserEnqueued: true);
    AppLogger.log('AudioQueueHandler', 'playNext: "${entity.title}" [id=${entity.id}]');

    if (_contextQueue.isEmpty && _userQueue.isEmpty && _currentTrack == null) {
      await loadQueue([entity], initialIndex: 0, autoPlay: true);
      return;
    }

    _userQueue.insert(0, entity);
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  Future<void> _addToQueueImpl(dynamic track) async {
    final entity = AudioQueueHandler._toEntity(track).copyWith(isUserEnqueued: true);
    AppLogger.log('AudioQueueHandler', 'addToQueue: "${entity.title}" [id=${entity.id}]');

    if (_contextQueue.isEmpty && _userQueue.isEmpty && _currentTrack == null) {
      await loadQueue([entity], initialIndex: 0, autoPlay: true);
      return;
    }

    _userQueue.add(entity);
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  Future<void> _addAllToQueueImpl(List<dynamic> tracks) async {
    if (tracks.isEmpty) return;
    if (_contextQueue.isEmpty && _userQueue.isEmpty && _currentTrack == null) {
      await loadQueue(tracks, initialIndex: 0, autoPlay: true);
      return;
    }
    for (final t in tracks) {
      _userQueue.add(AudioQueueHandler._toEntity(t).copyWith(isUserEnqueued: true));
    }
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  Future<void> _insertAtImpl(int index, dynamic track) async {
    final entity = AudioQueueHandler._toEntity(track);
    final curIdx = currentIndex;

    if (entity.isUserEnqueued) {
      final userOffset = (index - (curIdx + 1)).clamp(0, _userQueue.length);
      _userQueue.insert(userOffset, entity);
    } else {
      final safeIdx = index.clamp(0, _contextQueue.length);
      _contextQueue.insert(safeIdx, entity);
      if (_isShuffleEnabled) {
        _contextShuffleIndices.insert(safeIdx.clamp(0, _contextShuffleIndices.length), _contextQueue.length - 1);
      }
      if (safeIdx <= _contextIndex) {
        _contextIndex++;
      }
    }
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  Future<void> _setShuffleEnabledImpl(bool enable) async {
    if (_isShuffleEnabled == enable) return;
    if (_contextQueue.isEmpty) {
      _isShuffleEnabled = enable;
      return;
    }

    if (enable) {
      _isShuffleEnabled = true;
      int activeRawIdx = _contextIndex.clamp(0, math.max(0, _contextQueue.length - 1));
      if (_currentTrack != null && !_currentTrackIsFromUserQueue) {
        final match = _contextQueue.indexWhere((t) => t.id == _currentTrack!.id);
        if (match != -1) activeRawIdx = match;
      }

      _contextShuffleIndices.clear();
      _contextShuffleIndices.addAll(_shufflePermutator.generateShuffleTable(
        totalLength: _contextQueue.length,
        activeRawIndex: activeRawIdx,
      ));
      _contextIndex = 0;
      _playlistBaseIndex = currentIndex;

      _syncState();
      AppLogger.log('AudioQueueHandler', 'Shuffle enabled: ${_currentTrack?.title} pinned to index 0, ${_contextShuffleIndices.length} context items permuted');
      _invalidateUpcomingPlaylistSource();
      preloadUpcomingTracks();
    } else {
      _isShuffleEnabled = false;

      int restoredRawIdx = _contextIndex.clamp(0, math.max(0, _contextQueue.length - 1));
      if (_currentTrack != null && !_currentTrackIsFromUserQueue) {
        final match = _contextQueue.indexWhere((t) => t.id == _currentTrack!.id);
        if (match != -1) {
          restoredRawIdx = match;
        } else {
          restoredRawIdx = _shufflePermutator.restoreRawIndex(
            permutationTable: _contextShuffleIndices,
            currentPermutedIndex: _contextIndex,
          );
        }
      } else {
        restoredRawIdx = _shufflePermutator.restoreRawIndex(
          permutationTable: _contextShuffleIndices,
          currentPermutedIndex: _contextIndex,
        );
      }

      _contextIndex = restoredRawIdx;
      _contextShuffleIndices.clear();
      _playlistBaseIndex = currentIndex;

      _syncState();
      AppLogger.log('AudioQueueHandler', 'Shuffle disabled: anchored to raw index $restoredRawIdx for "${_currentTrack?.title}"');
      _invalidateUpcomingPlaylistSource();
      preloadUpcomingTracks();
    }
  }

  Future<void> _removeAtImpl(int index) async {
    final merged = _buildMergedQueue();
    if (index < 0 || index >= merged.length) return;
    final isRemovingCurrent = index == currentIndex;
    final target = merged[index];

    AppLogger.log('AudioQueueHandler', 'removeAt index $index: "${target.title}" (isCurrent=$isRemovingCurrent)');

    if (target.isUserEnqueued) {
      _userQueue.removeWhere((t) => t.id == target.id);
    } else {
      final ctxIdx = _contextQueue.indexWhere((t) => t.id == target.id);
      if (ctxIdx != -1) {
        _contextQueue.removeAt(ctxIdx);
        if (_isShuffleEnabled) {
          final posInShuffle = _contextShuffleIndices.indexOf(ctxIdx);
          if (posInShuffle != -1) _contextShuffleIndices.removeAt(posInShuffle);
          for (int i = 0; i < _contextShuffleIndices.length; i++) {
            if (_contextShuffleIndices[i] > ctxIdx) {
              _contextShuffleIndices[i]--;
            }
          }
        }
        if (ctxIdx < _contextIndex) {
          _contextIndex--;
        }
      }
    }

    if (isRemovingCurrent) {
      if (_userQueue.isNotEmpty) {
        final next = _userQueue.removeAt(0);
        _currentTrack = next;
        _currentTrackIsFromUserQueue = true;
        await _playTrackEntity(next);
      } else if (_contextQueue.isNotEmpty) {
        if (_contextIndex >= _contextQueue.length) {
          _contextIndex = _contextQueue.length - 1;
        }
        final next = _isShuffleEnabled
            ? _contextQueue[_contextShuffleIndices[_contextIndex]]
            : _contextQueue[_contextIndex];
        _currentTrack = next;
        _currentTrackIsFromUserQueue = false;
        await _playTrackEntity(next);
      } else {
        await clear();
      }
    } else {
      _syncState();
      _invalidateUpcomingPlaylistSource();
      preloadUpcomingTracks();
      onQueueProgress?.call(currentIndex, queue.length);
    }
  }

  Future<void> _reorderImpl(int oldIndex, int newIndex) async {
    try {
      final merged = _buildMergedQueue();
      if (oldIndex < 0 || oldIndex >= merged.length) return;
      if (newIndex < 0 || newIndex > merged.length) return;

      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      if (oldIndex == newIndex) return;

      final movingItem = merged[oldIndex];
      AppLogger.log('AudioQueueHandler', 'reorder: $oldIndex -> $newIndex ("${movingItem.title}")');

      if (movingItem.isUserEnqueued) {
        final curIdx = currentIndex;
        final oldUserIdx = (oldIndex - (curIdx + 1)).clamp(0, _userQueue.length - 1);
        final newUserIdx = (newIndex - (curIdx + 1)).clamp(0, _userQueue.length);
        if (oldUserIdx >= 0 && oldUserIdx < _userQueue.length) {
          final removed = _userQueue.removeAt(oldUserIdx);
          _userQueue.insert(newUserIdx.clamp(0, _userQueue.length), removed);
        }
      } else {
        final curIdx = currentIndex;
        final baseOffset = curIdx + 1 + _userQueue.length;
        if (_isShuffleEnabled && _contextShuffleIndices.isNotEmpty) {
          final oldCtxIdx = _contextQueue.indexWhere((t) => t.id == movingItem.id);
          final oldShufflePos = _contextShuffleIndices.indexOf(oldCtxIdx);
          if (oldShufflePos != -1) {
            final targetShufflePos = (newIndex - _userQueue.length).clamp(0, _contextShuffleIndices.length - 1);
            final removed = _contextShuffleIndices.removeAt(oldShufflePos);
            _contextShuffleIndices.insert(targetShufflePos, removed);
          }
        } else {
          final oldCtxIdx = _contextQueue.indexWhere((t) => t.id == movingItem.id);
          if (oldCtxIdx != -1) {
            final removed = _contextQueue.removeAt(oldCtxIdx);
            final targetCtxOffset = (newIndex >= baseOffset)
                ? (newIndex - _userQueue.length)
                : newIndex;
            final safeNewCtxIdx = targetCtxOffset.clamp(0, _contextQueue.length);
            _contextQueue.insert(safeNewCtxIdx, removed);

            if (oldCtxIdx == _contextIndex) {
              _contextIndex = safeNewCtxIdx;
            } else if (oldCtxIdx < _contextIndex && safeNewCtxIdx >= _contextIndex) {
              _contextIndex--;
            } else if (oldCtxIdx > _contextIndex && safeNewCtxIdx <= _contextIndex) {
              _contextIndex++;
            }
          }
        }
      }

      _syncState();
      _invalidateUpcomingPlaylistSource();
      preloadUpcomingTracks();
      onQueueProgress?.call(currentIndex, queue.length);
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'AudioQueueHandler.reorder');
    }
  }

  Future<void> _replaceUpcomingQueueImpl(List<dynamic> newUpcoming) async {
    _userQueue.clear();
    for (final raw in newUpcoming) {
      _userQueue.add(AudioQueueHandler._toEntity(raw).copyWith(isUserEnqueued: true));
    }
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  Future<void> _clearUserQueueImpl() async {
    AppLogger.log('AudioQueueHandler', 'Clearing user queue');
    _userQueue.clear();
    _syncState();
    _invalidateUpcomingPlaylistSource();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);
  }

  Future<void> _clearImpl() async {
    AppLogger.log('AudioQueueHandler', 'Queue cleared');
    cancelIdleTimer();
    YouTubeClient.closeIdleClient();
    NextTrackStrategyFactory.resetSession();
    _sessionToken++;
    try {
      await player.stop();
    } catch (e) {
      AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
    }

    _contextQueue.clear();
    _contextShuffleIndices.clear();
    _isShuffleEnabled = false;
    _userQueue.clear();
    _playbackHistory.clear();
    _currentTrack = null;
    _currentTrackIsFromUserQueue = false;
    _contextIndex = -1;
    _playlistBaseIndex = 0;

    _syncState();

    try {
      await _playlistSource.clear();
    } catch (e) {
      AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
    }

    currentSongNotifier.value = null;
    onQueueProgress?.call(-1, 0);
  }
}
