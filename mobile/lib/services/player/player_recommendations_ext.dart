part of '../player_handler.dart';

extension PlayerRecommendationsExt on PaatuAudioHandler {
  Future<int> addRadioMix({int count = 10}) async {
    final current = currentSong;
    if (current == null) return 0;
    final beforeCount = _queueHandler.queue.length;
    try {
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      final tracks = await strategy.getUpcomingTracks(
        seedSong: current,
        queue: _queueHandler.queue,
        history: HistoryManager.getHistory(),
        count: count,
      );
      if (tracks.isNotEmpty) {
        await _queueHandler.addAutoSuggestions(tracks);
      }
    } catch (e) {
      debugPrint('[PlayerHandler] addRadioMix error: $e');
    }
    return _queueHandler.queue.length - beforeCount;
  }

  Future<void> prefetchNextRecommendations(Song seedSong) async {
    if (_isPrefetchingRecommendations) return;
    _isPrefetchingRecommendations = true;
    try {
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      const count = 20;
      AppLogger.log('PlayerHandler', 'Prefetching next recommendations via ${strategy.displayName} for "${seedSong.title}"');
      final tracks = await strategy.getUpcomingTracks(
        seedSong: seedSong,
        queue: _queueHandler.queue,
        history: HistoryManager.getHistory(),
        count: count,
      );
      if (tracks.isNotEmpty && !_isForegroundDowngraded) {
        final toAdd = tracks.take(5).toList();
        await _queueHandler.addAutoSuggestions(toAdd);
        if (_queueHandler.hasNext) {
          await _queueHandler.preloadUpcomingTracks(_queueHandler.currentIndex);
        }
      }
    } catch (e) {
      debugPrint('[PlayerHandler] prefetchNextRecommendations error: $e');
    } finally {
      _isPrefetchingRecommendations = false;
    }
  }

  Future<void> handleAutoplayQueueEnd(Song current) async {
    try {
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      final tracks = await strategy.getUpcomingTracks(
        seedSong: current,
        queue: _queueHandler.queue,
        history: HistoryManager.getHistory(),
        count: 6,
      );
      if (tracks.isNotEmpty) {
        final toAdd = tracks.take(5).toList();
        await _queueHandler.addAutoSuggestions(toAdd);
        if (_queueHandler.hasNext) {
          await _queueHandler.preloadUpcomingTracks(_queueHandler.currentIndex);
          await _queueHandler.skipToNext(isUserInitiated: false);
          return;
        }
      }
    } catch (e) {
      debugPrint('[PlayerHandler] handleAutoplayQueueEnd error: $e');
    }
    _queueHandler.startIdleTimer();
  }

  Future<int> startSongRadio(Song seedSong) async {
    try {
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      strategy.resetSession(initialAnchor: seedSong);
      final tracks = await strategy.getUpcomingTracks(
        seedSong: seedSong,
        queue: [seedSong],
        history: HistoryManager.historyNotifier.value.map((e) => e.toSong()).toList(),
        count: 25,
      );
      if (tracks.isNotEmpty) {
        final radioQueue = [seedSong, ...tracks];
        await playSong(seedSong, queue: radioQueue);
        return radioQueue.length;
      }
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'startSongRadio with ${SettingsManager.nextTrackStrategy.name}');
    }
    return 0;
  }
}
