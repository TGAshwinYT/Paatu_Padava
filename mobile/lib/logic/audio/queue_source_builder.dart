part of '../audio_queue_handler.dart';

extension AudioQueueHandlerSourceBuilder on AudioQueueHandler {
  Future<void> preloadUpcomingTracks([int? fromIndex]) async {
    int? getSafeCurrentIndex() {
      try {
        return player.currentIndex;
      } catch (_) {
        return null;
      }
    }

    final next = nextTrack;
    if (next == null || _isDisposed) {
      final currentPlayingIdx = getSafeCurrentIndex() ?? 0;
      while (_playlistSource.length > currentPlayingIdx + 1) {
        try {
          await _playlistSource.removeAt(_playlistSource.length - 1);
        } catch (_) {
          break;
        }
      }
      return;
    }
    final token = _sessionToken;

    AppLogger.log('AudioQueueHandler', 'Preloading upcoming track: "${next.title}" [id=${next.id}]');

    final wasMissingOrExpired = next.streamUrl == null || next.streamUrl!.isEmpty || streamResolver.isExpired(next.id);
    if (wasMissingOrExpired) {
      final url = await _resolveStreamUrl(next.toSong());
      if (token != _sessionToken || _isDisposed) return;
      if (url != null && url.isNotEmpty) {
        _updateTrackStreamUrl(next.id, url);
      } else {
        AppLogger.log('AudioQueueHandler', 'Preload stream resolution failed for "${next.title}".');
        return;
      }
    }

    if (token != _sessionToken || _isDisposed) return;

    final song = next.toSong();
    final source = await _buildAudioSource(song, allowNetworkResolve: false);
    if (source == null || token != _sessionToken || _isDisposed) return;

    // 1. Trim played sources prior to currently playing index so window is always [playing, next]
    final currentPlaying = getSafeCurrentIndex() ?? 0;
    if (currentPlaying > 0 && _playlistSource.length > 1) {
      try {
        for (int i = 0; i < currentPlaying; i++) {
          if (_playlistSource.length > 1) {
            await _playlistSource.removeAt(0);
          }
        }
      } catch (e) {
        AppLogger.log('AudioQueueHandler', 'Safe catch during trimming played sources: $e');
      }
    }

    if (token != _sessionToken || _isDisposed) return;

    // 2. Target slot is always the slot strictly after the active playing one
    final activePlayingIndex = getSafeCurrentIndex() ?? 0;
    final targetPlayerIndex = activePlayingIndex + 1;
    _playlistBaseIndex = currentIndex;

    if (targetPlayerIndex < _playlistSource.length) {
      try {
        final existingTag = _playlistSource.sequence[targetPlayerIndex].tag;
        final existingId = (existingTag is MediaItem) ? existingTag.id : (existingTag is Song ? existingTag.id : null);
        if (existingId != next.id) {
          await _playlistSource.removeAt(targetPlayerIndex);
          await _playlistSource.insert(targetPlayerIndex, source);
        }
      } catch (e) {
        AppLogger.log('AudioQueueHandler', 'Safe catch during playlist source update: $e');
      }
    } else if (targetPlayerIndex == _playlistSource.length) {
      try {
        await _playlistSource.add(source);
      } catch (e) {
        AppLogger.log('AudioQueueHandler', 'Safe catch during playlist source add: $e');
      }
    }

    // Trim any trailing sources beyond the 2-track window [playing, next]
    while (_playlistSource.length > targetPlayerIndex + 1) {
      try {
        await _playlistSource.removeAt(_playlistSource.length - 1);
      } catch (_) {
        break;
      }
    }

    // Pre-resolve the 2nd upcoming track silently in background so sub-second playback is sustained
    final upcomingList = <TrackEntity>[];
    if (_userQueue.isNotEmpty) {
      upcomingList.addAll(_userQueue);
    }
    upcomingList.addAll(remainingContextTracks);

    if (upcomingList.length > 1) {
      final secondUpcoming = upcomingList[1];
      final needsResolve = secondUpcoming.streamUrl == null ||
          secondUpcoming.streamUrl!.isEmpty ||
          streamResolver.isExpired(secondUpcoming.id);
      if (needsResolve) {
        unawaited(() async {
          try {
            final url2 = await _resolveStreamUrl(secondUpcoming.toSong());
            if (url2 != null && url2.isNotEmpty && token == _sessionToken) {
              _updateTrackStreamUrl(secondUpcoming.id, url2);
              AppLogger.log('AudioQueueHandler', 'Pre-resolved 2nd upcoming track: "${secondUpcoming.title}" [id=${secondUpcoming.id}]');
            }
          } catch (e) {
            AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
          }
        }());
      }
    }
  }

  Future<void> _invalidateUpcomingPlaylistSource() async {
    _playlistBaseIndex = currentIndex;
    while (_playlistSource.length > 1) {
      try {
        await _playlistSource.removeAt(_playlistSource.length - 1);
      } catch (_) {
        break;
      }
    }
  }

  void _updateTrackStreamUrl(String trackId, String url, {String? source}) {
    if (_currentTrack?.id == trackId) {
      _currentTrack = _currentTrack!.copyWith(
        streamUrl: url,
        source: source ?? _currentTrack!.source,
      );
    }
    for (int i = 0; i < _userQueue.length; i++) {
      if (_userQueue[i].id == trackId) {
        _userQueue[i] = _userQueue[i].copyWith(
          streamUrl: url,
          source: source ?? _userQueue[i].source,
        );
      }
    }
    for (int i = 0; i < _contextQueue.length; i++) {
      if (_contextQueue[i].id == trackId) {
        _contextQueue[i] = _contextQueue[i].copyWith(
          streamUrl: url,
          source: source ?? _contextQueue[i].source,
        );
      }
    }
  }

  Future<AudioSource?> _buildAudioSource(
    Song song, {
    bool allowNetworkResolve = true,
    bool preserveBitrate = false,
  }) async {
    if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
      final enriched = song.copyWith(isDownloaded: true, source: 'offline');
      return AudioSource.file(song.localFilePath!, tag: enriched.toMediaItem());
    }
    if (DownloadManager.isDownloaded(song.id)) {
      final localAudio = DownloadManager.getLocalFilePath(song.id);
      final localCover = DownloadManager.getLocalCoverPath(song.id);
      if (localAudio != null && File(localAudio).existsSync()) {
        final enriched = song.copyWith(
          isDownloaded: true,
          localFilePath: localAudio,
          localCoverPath: localCover ?? song.localCoverPath,
          source: 'offline',
        );
        return AudioSource.file(localAudio, tag: enriched.toMediaItem());
      }
    }
    if (!SmartCacheService.instance.isDownloading(song.id)) {
      final smartCacheFile = SmartCacheService.instance.getCachedAudioFile(song.id);
      if (smartCacheFile != null && smartCacheFile.existsSync()) {
        return AudioSource.file(smartCacheFile.path, tag: song.toMediaItem());
      }
    }

    String? streamUrl = song.streamUrl;
    if ((streamUrl == null || streamUrl.isEmpty) && allowNetworkResolve) {
      streamUrl = await _resolveStreamUrl(song);
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      return null;
    }

    if (!preserveBitrate &&
        !_hasRetriedCurrentTrack &&
        !_hasDownscaledCurrentTrack &&
        (song.source == 'saavn' ||
            song.source == 'jiosaavn' ||
            streamUrl.contains('jiosaavn') ||
            streamUrl.contains('saavncdn.com'))) {
      final q = SettingsManager.effectiveStreamingQuality;
      streamUrl = SaavnBitrateHelper.toBitrate(streamUrl, q);
    }
    final uri = Uri.tryParse(streamUrl);
    final host = uri?.host.toLowerCase() ?? '';
    final isGoogleVideo = host.contains('googlevideo.com');

    // Headers are ONLY for googlevideo.com; Saavn and other hosts get none (headers: null).
    // Uses YouTubeClient.headersForUrl to guarantee User-Agent matches the client tag (c=)
    // on the googlevideo URL, preventing HTTP 403 Forbidden on playback start.
    final Map<String, String>? headers = isGoogleVideo
        ? YouTubeClient.headersForUrl(streamUrl)
        : null;
    song.streamUrl = streamUrl;

    try {
      final tempDir = await getTemporaryDirectory();
      final sanitizedId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final cacheFile = File('${tempDir.path}/audio_$sanitizedId.mp4');
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 100000) {
        return AudioSource.file(cacheFile.path, tag: song.toMediaItem());
      }
      return AudioSource.uri(
        Uri.parse(streamUrl),
        headers: headers,
        tag: song.toMediaItem(),
      );
    } catch (_) {
      return AudioSource.uri(
        Uri.parse(streamUrl),
        headers: headers,
        tag: song.toMediaItem(),
      );
    }
  }

  Future<String?> _resolveStreamUrl(Song song) async {
    return streamResolver.resolveStreamUrl(song);
  }
}
