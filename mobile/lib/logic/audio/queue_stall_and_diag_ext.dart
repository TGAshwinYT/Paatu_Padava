part of '../audio_queue_handler.dart';

extension QueueStallAndDiagExt on AudioQueueHandler {
  void _startBufferStallWatchdog() {
    _bufferStallTimer?.cancel();
    if (_hasDownscaledCurrentTrack || _isDisposed || _isAdvancing || _isRecovering) return;

    _bufferStallTimer = Timer(const Duration(milliseconds: 3500), () async {
      if (_isDisposed || _isAdvancing || _isRecovering) return;
      final current = currentSong;
      if (current == null || !player.playing || player.processingState != ProcessingState.buffering) return;
      if (DownloadManager.isDownloaded(current.id)) return;

      final currentUrl = current.streamUrl;
      if (currentUrl == null || currentUrl.isEmpty) return;

      final fallbackUrl = SaavnBitrateHelper.getNextFallbackUrl(currentUrl);
      if (fallbackUrl != null && fallbackUrl != currentUrl && !_isDisposed) {
        _hasDownscaledCurrentTrack = true;
        final currentPos = player.position;
        AppLogger.log(
          'AudioQueueHandler',
          'Buffer stall dynamic rescue: stream stalled >3.5s for "${current.title}". Downscaling to $fallbackUrl at ${currentPos.inSeconds}s.',
        );
        current.streamUrl = fallbackUrl;
        _updateTrackStreamUrl(current.id, fallbackUrl);

        final downscaledSource = await _buildAudioSource(current, allowNetworkResolve: false, preserveBitrate: true);
        if (downscaledSource != null && !_isDisposed) {
          try {
            _playlistSource = ConcatenatingAudioSource(
              children: [downscaledSource],
              useLazyPreparation: true,
            );
            await player.setAudioSource(_playlistSource, initialPosition: currentPos);
            await _ensureAudioSessionActive();
            player.play().catchError((e, st) => AppLogger.recordError(e, st, context: 'stall rescue play'));
            final targetNorm = getEffectiveVolumeForSong(current);
            await player.setVolume(targetNorm);
            _startVolumeWatchdog(current);
            preloadUpcomingTracks();
          } catch (e) {
            AppLogger.log('AudioQueueHandler', 'Buffer stall dynamic rescue notice: $e');
          }
        }
      }
    });
  }

  void _cancelBufferStallWatchdog() {
    _bufferStallTimer?.cancel();
    _bufferStallTimer = null;
  }
}

Future<String> _diagnosePlaybackErrorImpl(Song song, dynamic error, StackTrace? stack) async {
  final errStr = error.toString();
  final detailsStr = (error is PlatformException) ? (error.details?.toString() ?? '') : '';
  final combined = '$errStr $detailsStr ${stack?.toString() ?? ''}'.toLowerCase();

  if (combined.contains('403') || combined.contains('response code: 403')) {
    return 'ExoPlayer HTTP 403 Forbidden: Google CDN or host rejected the stream token/headers.';
  }
  if (combined.contains('416') || combined.contains('response code: 416')) {
    return 'ExoPlayer HTTP 416 Range Not Satisfiable: conflicting byte range requested.';
  }
  if (combined.contains('cleartext') || combined.contains('cleartextnotpermitted')) {
    return 'ExoPlayer CleartextNotPermittedException: Insecure HTTP cleartext blocked by Android Network Security Config.';
  }
  if (combined.contains('ssl') || combined.contains('handshake') || combined.contains('certpath')) {
    return 'ExoPlayer SSLHandshakeException: TLS/SSL certificate or handshake negotiation failed.';
  }

  final url = song.streamUrl;
  if (url != null && url.startsWith('http')) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      final isGoogleVideo = host.contains('googlevideo.com');
      final probeHeaders = <String, String>{
        if (isGoogleVideo) 'User-Agent': YouTubeClient.vrUserAgent,
        'Range': 'bytes=0-1024',
        'Accept': '*/*',
      };

      final response = await http.get(uri, headers: probeHeaders).timeout(const Duration(seconds: 3));
      if (response.statusCode == 403) {
        return 'ExoPlayer HTTP 403 Forbidden: Google CDN rejected request (confirmed via live probe on $host).';
      } else if (response.statusCode == 416) {
        return 'ExoPlayer HTTP 416 Range Not Satisfiable: Byte range invalid (confirmed via live probe on $host).';
      } else if (response.statusCode >= 400) {
        return 'ExoPlayer HTTP ${response.statusCode}: Stream server returned error status on $host.';
      } else {
        return 'ExoPlayer probe returned HTTP ${response.statusCode} OK on $host (underlying issue is player decoding/codec or buffer stall, not HTTP rejection).';
      }
    } on SocketException catch (se) {
      return 'ExoPlayer SocketException: Failed to reach stream host: ${se.message}';
    } on HandshakeException catch (he) {
      return 'ExoPlayer SSLHandshakeException: TLS/SSL handshake failed on stream host: ${he.message}';
    } catch (probeErr) {
      final pStr = probeErr.toString().toLowerCase();
      if (pStr.contains('cleartext')) {
        return 'ExoPlayer CleartextNotPermittedException: Non-HTTPS traffic blocked by Android.';
      }
      return 'PlatformException(0, Source error) [Probe failed: $probeErr]';
    }
  }

  return (error is PlatformException)
      ? 'PlatformException(${error.code}, ${error.message}, details: ${error.details})'
      : errStr;
}
