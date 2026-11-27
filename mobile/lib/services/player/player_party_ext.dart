part of '../player_handler.dart';

extension PlayerPartyExt on PaatuAudioHandler {
  void _onActiveTrackChangedImpl(Song song) {
    if (BlacklistManager.isBlacklisted(song)) {
      AppLogger.log('PlayerHandler', 'Active track is blacklisted: "${song.title}". Auto-skipping.');
      skipToNext();
      return;
    }
    AppLogger.log('PlayerHandler', 'Active track changed: "${song.title}" (${song.artist}) [id=${song.id}]');
    mediaItem.add(song.toMediaItem());
    _syncWidgetState(song: song);

    _cachedFavSongId = song.id;
    _cachedIsFav = FavoritesManager.isFavorite(song.id);
    _smartShuffleController.recordRecentlyPlayed(song);

    _hasRecordedHistory = false;
    _hasRecordedListen = false;
    lyricsOffsetMsNotifier.value = 0;
    LyricsClient.instance.getLyricsOffset(song.id).then((savedOffset) {
      if (currentSong?.id == song.id) {
        lyricsOffsetMsNotifier.value = savedOffset;
      }
    });

    if (isKaraokeModeNotifier.value && vocalAttenuationNotifier.value > 0.0) {
      EqualizerService.setVocalAttenuation(vocalAttenuationNotifier.value);
    } else {
      EqualizerService.setVocalAttenuation(0.0);
    }

    _lyricsDebounceTimer?.cancel();
    _lyricsDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (currentSong?.id == song.id) {
        reloadLyrics(targetSong: song);
      }
    });

    SmartCacheService.instance.onQueueUpdated(song, _queueHandler.queue, preloadCount: 2);

    if (PartySyncCoordinator.isHost && !_queueHandler.isPartyDrivenLoad) {
      PartySyncCoordinator.notifyHostTrackTransition(
        song,
        queue: _queueHandler.queue,
        currentIndex: _queueHandler.currentIndex,
      );
    }

    _broadcastState();
  }
}
