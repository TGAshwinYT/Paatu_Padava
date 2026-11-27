part of '../audio_queue_handler.dart';

extension QueueSuggestionsExt on AudioQueueHandler {
  Future<void> _onConnectivityChangedImpl() async {
    if (_isDisposed) return;
    final isOnline = ConnectivityService.currentIsOnline;
    if (isOnline && _wasStalledByNetwork && _currentTrack != null) {
      AppLogger.log(
        'AudioQueueHandler',
        'Zero-touch network recovery: Connection restored! Re-resolving fresh stream for "${_currentTrack!.title}" at offset ${_networkStallOffset.inSeconds}s',
      );
      _wasStalledByNetwork = false;
      final current = _currentTrack!.toSong();
      final resumeOffset = _networkStallOffset;

      current.streamUrl = null;
      streamResolver.invalidate(current.id);
      DefaultStreamResolver.invalidateStream(current.id);
      YouTubeClient.invalidateStream(current.id);

      final freshUrl = await _resolveStreamUrl(current);
      if (freshUrl != null && freshUrl.isNotEmpty && !_isDisposed) {
        current.streamUrl = freshUrl;
        _updateTrackStreamUrl(current.id, freshUrl);
        final freshSource = await _buildAudioSource(current, allowNetworkResolve: false);
        if (freshSource != null && !_isDisposed) {
          try {
            _playlistSource = ConcatenatingAudioSource(
              children: [freshSource],
              useLazyPreparation: true,
            );
            await player.setAudioSource(_playlistSource, initialPosition: resumeOffset);
            await _ensureAudioSessionActive();
            player.play().catchError((e, st) => AppLogger.recordError(e, st, context: 'stall rescue play'));
            final targetNorm = getEffectiveVolumeForSong(current);
            await player.setVolume(targetNorm);
            _startVolumeWatchdog(current);
            preloadUpcomingTracks();
            AppLogger.log('AudioQueueHandler', 'Zero-touch network recovery succeeded for "${current.title}"');
          } catch (e) {
            AppLogger.log('AudioQueueHandler', 'Zero-touch network recovery resume notice: $e');
          }
        }
      }
    }
  }

  Future<void> _addAutoSuggestionsImpl(List<dynamic> tracks, {bool autoAdvanceIfCompleted = false}) async {
    if (tracks.isEmpty) return;
    final existingTitleKeys = <String>{};
    for (final t in _contextQueue) {
      if (t.cleanTitleKey.isNotEmpty) existingTitleKeys.add(t.cleanTitleKey);
    }
    for (final t in _userQueue) {
      if (t.cleanTitleKey.isNotEmpty) existingTitleKeys.add(t.cleanTitleKey);
    }
    if (_currentTrack != null && _currentTrack!.cleanTitleKey.isNotEmpty) {
      existingTitleKeys.add(_currentTrack!.cleanTitleKey);
    }

    final deduplicated = <TrackEntity>[];
    for (final raw in tracks) {
      var t = AudioQueueHandler._toEntity(raw).copyWith(isSmartRecommended: true, isUserEnqueued: false);
      if (t.coverUrl.isEmpty || t.coverUrl.contains('default.jpg')) {
        final catalogArt = CatalogDatabase.getSongCoverArt(t.title, artist: t.artist, album: t.album) ??
            CatalogDatabase.getMoviePoster(t.album);
        if (catalogArt != null && catalogArt.isNotEmpty) {
          t = t.copyWith(coverUrl: catalogArt);
        }
      }
      final key = t.cleanTitleKey;
      if (key.isNotEmpty && existingTitleKeys.contains(key)) continue;
      if (QueueCooldownManager.isCoolingDown(t.toSong())) continue;
      if (key.isNotEmpty) existingTitleKeys.add(key);
      deduplicated.add(t);
    }

    if (deduplicated.isEmpty) return;
    AppLogger.log('AudioQueueHandler', 'addAutoSuggestions: appending ${deduplicated.length} fresh tracks');
    for (final t in deduplicated) {
      _contextQueue.add(t);
      if (_isShuffleEnabled) {
        _contextShuffleIndices.add(_contextQueue.length - 1);
      }
    }
    QueueCooldownManager.recordSuggested(deduplicated.map((e) => e.toSong()));
    _syncState();
    preloadUpcomingTracks();
    onQueueProgress?.call(currentIndex, queue.length);

    if (autoAdvanceIfCompleted &&
        !_isHandlingCompleted &&
        player.processingState == ProcessingState.completed &&
        !player.playing &&
        !PartySyncCoordinator.isJoiner &&
        SettingsManager.isAutoplayEnabled &&
        hasNext) {
      await preloadUpcomingTracks(currentIndex);
      await skipToNext(isUserInitiated: false, bypassTransitionLock: true);
    }
  }

  Future<void> _replaceAutoSuggestionsImpl(List<dynamic> newSuggestions) async {
    if (_contextIndex >= 0 && _contextIndex < _contextQueue.length) {
      final playedContext = _contextQueue.sublist(0, _contextIndex + 1);
      final originalUpcoming = _contextQueue
          .sublist(_contextIndex + 1)
          .where((t) => !t.isSmartRecommended)
          .toList();
      _contextQueue.clear();
      _contextQueue.addAll(playedContext);
      _contextQueue.addAll(originalUpcoming);

      if (_isShuffleEnabled) {
        _contextShuffleIndices.clear();
        for (int i = 0; i < _contextQueue.length; i++) {
          _contextShuffleIndices.add(i);
        }
      }
    } else if (_contextIndex == -1 && _contextQueue.isNotEmpty) {
      final originalNonRec = _contextQueue.where((t) => !t.isSmartRecommended).toList();
      _contextQueue.clear();
      _contextQueue.addAll(originalNonRec);
      if (_isShuffleEnabled) {
        _contextShuffleIndices.clear();
        for (int i = 0; i < _contextQueue.length; i++) {
          _contextShuffleIndices.add(i);
        }
      }
    }
    await addAutoSuggestions(newSuggestions);
  }
}
