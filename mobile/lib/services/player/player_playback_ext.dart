part of '../player_handler.dart';

extension PlayerPlaybackExt on PaatuAudioHandler {
  Future<void> _loadTrackImpl(TrackEntity track, {bool autoPlay = true}) async {
    final currentRequestId = ++_loadRequestId;
    final token = ++_activeLoadToken;
    _isPreparing = true;

    try {
      final song = track.toSong();

      String? url = song.streamUrl;
      if (url == null || url.isEmpty || _streamResolver.isExpired(track.id)) {
        url = await _streamResolver.resolveStreamUrl(song);
      }

      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        final host = uri?.host.toLowerCase() ?? '';
        final isGoogleVideo = host.contains('googlevideo.com');

        final Map<String, String>? headers = isGoogleVideo
            ? YouTubeClient.headersForUrl(url)
            : null;
        song.streamUrl = url;
        try {
          final source = AudioSource.uri(
            Uri.parse(url),
            headers: headers,
            tag: track.toMediaItem(),
          );
          await _player.setAudioSource(source);
          if (currentRequestId != _loadRequestId || token != _activeLoadToken) return;
          if (_player.duration != null && _player.duration!.inMilliseconds > 0) {
            track.durationMs = _player.duration!.inMilliseconds;
            song.duration = _player.duration!.inSeconds;
            if (mediaItem.value != null) {
              mediaItem.add(mediaItem.value!.copyWith(duration: _player.duration));
            }
            _broadcastState();
          }
          if (autoPlay) {
            await play();
          }
        } catch (e, stack) {
          AppLogger.recordError(e, stack, context: 'PlayerHandler.loadTrack ExoPlayer source error');
          await _queueHandler.handlePlaybackError(e, stack, context: 'PlayerHandler.loadTrack');
        }
      } else {
        await _queueHandler.handlePlaybackError(
          Exception('Unable to resolve playable stream for "${song.title}"'),
          null,
          context: 'PlayerHandler.loadTrack',
        );
      }
    } finally {
      if (token == _activeLoadToken) {
        _isPreparing = false;
      }
    }
  }

  Future<void> _playTrackImpl(TrackEntity track) async {
    final currentRequestId = ++_loadRequestId;
    final song = track.toSong();
    String? url = song.streamUrl;
    if (url == null || url.isEmpty || _streamResolver.isExpired(track.id)) {
      url = await _streamResolver.resolveStreamUrl(song);
    }
    if (currentRequestId != _loadRequestId) return;
    if (url != null && url.isNotEmpty) {
      song.streamUrl = url;
    }
    await playSong(song, preserveUserQueue: true);
  }

  Future<void> _playSongImpl(
    Song song, {
    List<Song>? queue,
    bool preserveUserQueue = false,
    PlaybackContext? context,
    bool isPartySyncInternal = false,
    bool autoPlay = true,
  }) async {
    if (PartySyncCoordinator.role == PartyRole.joiner && !isPartySyncInternal) {
      if (PartySyncCoordinator.onJoinerManualPlayAttempted != null) {
        PartySyncCoordinator.onJoinerManualPlayAttempted!(song);
        return;
      }
      await PartySyncCoordinator.leaveParty();
    }
    if (context != null) {
      currentContextNotifier.value = context;
      RecentContainersManager.recordContainer(
        id: context.id,
        title: context.title,
        subtitle: context.subtitle ?? context.type.toUpperCase(),
        coverUrl: context.coverUrl ?? song.coverUrl,
        type: context.type,
      );
    }
    final reqId = ++_playSongRequestId;
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      AppLogger.debug('PaatuAudioHandler', 'AudioSession setActive(true) error on playSong: $e');
    }
    if (reqId != _playSongRequestId) return;
    _isForegroundDowngraded = false;
    _queueHandler.cancelIdleTimer();

    final hasValidStream = song.streamUrl != null && song.streamUrl!.isNotEmpty;
    if (!hasValidStream || _streamResolver.isExpired(song.id)) {
      final resolved = await _streamResolver.resolveStreamUrl(song);
      if (reqId != _playSongRequestId) return;
      if (resolved != null && resolved.isNotEmpty) {
        song.streamUrl = resolved;
      }
    }
    if (reqId != _playSongRequestId) return;

    final isNewSingleQueue = queue == null || (queue.length == 1 && queue.first.id == song.id);
    final initialIndex = queue != null ? queue.indexWhere((s) => s.id == song.id) : 0;
    final targetIndex = initialIndex != -1 ? initialIndex : 0;

    await _queueHandler.loadQueue(
      queue ?? [song],
      initialIndex: targetIndex,
      autoPlay: autoPlay,
      isPartyDriven: isPartySyncInternal,
      preserveUserQueue: isNewSingleQueue || preserveUserQueue,
    );

    await applyVolumeNormalization(song);
  }
}
