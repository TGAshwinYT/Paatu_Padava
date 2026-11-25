part of '../audio_queue_handler.dart';

extension AudioQueueHandlerErrorRecovery on AudioQueueHandler {
  /// Centralized playback error recovery & diagnostic logger (Bloomee model).
  /// Single entry point for all playback errors (both setAudioSource failures and playbackEventStream runtime errors).
  /// Captures underlying ExoPlayer HTTP status (403, 416, SSL, Cleartext) and attempts Saavn fallback recovery ONCE.
  Future<void> handlePlaybackError(dynamic error, StackTrace? stackTrace, {required String context}) async {
    final current = currentSong;
    if (current == null || _isDisposed) return;

    if (_isRecovering) {
      AppLogger.log('AudioQueueHandler', '[$context] Recovery already in progress for "${current.title}", ignoring duplicate error');
      return;
    }

    // 1. Ignore abort / connection aborted errors (superseded by newer load or seek)
    final errorStr = error.toString().toLowerCase();
    final isAbort = errorStr.contains('abort') ||
        (error is PlatformException &&
            (error.code.toLowerCase() == 'abort' ||
                (error.message != null && error.message!.toLowerCase().contains('abort'))));
    if (isAbort) {
      AppLogger.log('AudioQueueHandler', '[$context] Ignoring aborted load (superseded by newer load): $error');
      return;
    }

    // 2. Attribute errors by playlist slot index:
    // If the error carries {index: 1} or non-playing index, drop the failing preloaded source ONLY.
    // Never blame, reload, or disrupt the healthy playing track!
    int? errorIndex;
    if (error is PlatformException && error.details is Map) {
      final idx = (error.details as Map)['index'];
      if (idx is int) {
        errorIndex = idx;
      }
    }
    if (errorIndex == null) {
      final match = RegExp(r'\{index:\s*(\d+)\}').firstMatch(error.toString());
      if (match != null) {
        errorIndex = int.tryParse(match.group(1)!);
      }
    }

    int? getSafeCurrentIndex() {
      try {
        return player.currentIndex;
      } catch (_) {
        return null;
      }
    }

    final currentPlayingIndex = getSafeCurrentIndex() ?? 0;
    if (errorIndex != null && errorIndex != currentPlayingIndex) {
      AppLogger.log(
        'AudioQueueHandler',
        '[$context] Playback error on non-playing preloaded slot $errorIndex (active playing index is $currentPlayingIndex). Dropping preloaded source without disrupting active playback.',
      );
      if (errorIndex < _playlistSource.length) {
        try {
          await _playlistSource.removeAt(errorIndex);
        } catch (e) {
          AppLogger.log('AudioQueueHandler', 'Safe catch removing preloaded error source: $e');
        }
      }
      final next = nextTrack;
      if (next != null) {
        streamResolver.invalidate(next.id);
        _updateTrackStreamUrl(next.id, '');
      }
      return;
    }

    final token = _sessionToken;
    _isRecovering = true;

    try {
      // 1. Capture and log the real underlying error
      final diagnostic = await AudioQueueHandler.diagnosePlaybackError(current, error, stackTrace);
      if (token != _sessionToken || _isDisposed) {
        AppLogger.log('AudioQueueHandler', '[$context] Stale error: session token changed during diagnosis, aborting recovery');
        return;
      }
      AppLogger.log('ExoPlayerDiagnostic', '[$context] Real Error for "${current.title}" (${current.id}) [${current.source}]: $diagnostic');

      final failingUrl = current.streamUrl;
      final isSaavnCdn = current.source == 'saavn' ||
          current.source == 'jiosaavn' ||
          (failingUrl != null && failingUrl.contains('saavncdn.com'));

      // Invalidate stream cache so stale/expired/403 URL is never reused
      streamResolver.invalidate(current.id);
      current.streamUrl = null;

      // 2. Retry handling with Bitrate Fallback + Cross-Provider Fallback
      if (!_hasRetriedCurrentTrack && !_isDisposed && token == _sessionToken) {
        _hasRetriedCurrentTrack = true;

        // STEP 2A: If a Saavn stream failed (e.g. 320kbps 404/403 on CDN), try Bitrate Fallback (160kbps, then 96kbps)
        if (isSaavnCdn && failingUrl != null) {
          final fallbackUrl = SaavnBitrateHelper.getNextFallbackUrl(failingUrl);
          if (fallbackUrl != null && !_isDisposed && token == _sessionToken) {
            AppLogger.log('AudioQueueHandler', 'Saavn bitrate fallback for "${current.title}": switching to lower bitrate $fallbackUrl');
            current.streamUrl = fallbackUrl;
            _updateTrackStreamUrl(current.id, fallbackUrl, source: 'saavn');
            final fallbackSource = await _buildAudioSource(current, allowNetworkResolve: false, preserveBitrate: true);
            if (token != _sessionToken || _isDisposed) return;
            if (fallbackSource != null) {
              try {
                _playlistSource = ConcatenatingAudioSource(
                  children: [fallbackSource],
                  useLazyPreparation: true,
                );
                await player.setAudioSource(_playlistSource);
                if (token != _sessionToken || _isDisposed) return;
                await _ensureAudioSessionActive();
                if (token != _sessionToken || _isDisposed) return;
                player.play().catchError((e, st) => AppLogger.recordError(e, st, context: 'saavn bitrate fallback play'));
                if (token != _sessionToken || _isDisposed) return;
                final targetNorm = getEffectiveVolumeForSong(current);
                await player.setVolume(targetNorm);
                _startVolumeWatchdog(current);
                _consecutivePlaybackErrors = 0;
                preloadUpcomingTracks();
                AppLogger.log('AudioQueueHandler', 'Saavn bitrate fallback successful: "${current.title}" playing at reduced bitrate');
                return;
              } catch (bitrateErr, bitrateStack) {
                final bDiag = await AudioQueueHandler.diagnosePlaybackError(current, bitrateErr, bitrateStack);
                AppLogger.log('ExoPlayerDiagnostic', 'Saavn bitrate fallback failed for "${current.title}": $bDiag');
              }
            }
          }
        }

        if (token != _sessionToken || _isDisposed) return;

        // STEP 2B: Cross-source resolution fallback
        AppLogger.log('AudioQueueHandler', 'Single-pass fallback: resolving fallback stream for "${current.title}"');
        current.streamUrl = null;
        final freshUrl = await streamResolver.resolve(
          current,
          forceSaavnFallback: !isSaavnCdn,
          forceYouTubeFallback: isSaavnCdn,
        );
        if (token != _sessionToken || _isDisposed) return;
        if (freshUrl != null && freshUrl.isNotEmpty) {
          final resolvedSource = freshUrl.contains('saavncdn.com') ? 'saavn' : 'youtube';
          current.streamUrl = freshUrl;
          current.source = resolvedSource;
          _updateTrackStreamUrl(current.id, freshUrl, source: resolvedSource);

          final freshSource = await _buildAudioSource(current, allowNetworkResolve: false, preserveBitrate: true);
          if (token != _sessionToken || _isDisposed) return;
          if (freshSource != null) {
            try {
              _playlistSource = ConcatenatingAudioSource(
                children: [freshSource],
                useLazyPreparation: true,
              );
              await player.setAudioSource(_playlistSource);
              if (token != _sessionToken || _isDisposed) return;
              await _ensureAudioSessionActive();
              if (token != _sessionToken || _isDisposed) return;
              player.play().catchError((e, st) => AppLogger.recordError(e, st, context: 'fallback recovery play'));
              if (token != _sessionToken || _isDisposed) return;
              final targetNorm = getEffectiveVolumeForSong(current);
              await player.setVolume(targetNorm);
              _startVolumeWatchdog(current);
              _consecutivePlaybackErrors = 0;
              preloadUpcomingTracks();
              AppLogger.log('AudioQueueHandler', 'Fallback recovery successful: "${current.title}" now playing via $resolvedSource');
              return;
            } catch (recoveryErr, recoveryStack) {
              final recDiag = await AudioQueueHandler.diagnosePlaybackError(current, recoveryErr, recoveryStack);
              AppLogger.log('ExoPlayerDiagnostic', 'Fallback play failed for "${current.title}": $recDiag');
            }
          }
        }
      }

      if (token != _sessionToken || _isDisposed) {
        AppLogger.log('AudioQueueHandler', '[$context] Stale error: user transitioned or token expired, bypassing circuit breaker increment');
        return;
      }

      // 3. If fallback failed or track was already retried once:
      _consecutivePlaybackErrors++;
      if (_consecutivePlaybackErrors >= AudioQueueHandler._maxConsecutivePlaybackErrors) {
        AppLogger.log('AudioQueueHandler', 'Circuit breaker tripped: $_consecutivePlaybackErrors consecutive playback failures. Halting auto-skip storm.');
        _consecutivePlaybackErrors = 0;
        await player.stop();
        final haltErr = AppError(
          category: AppErrorCategory.unknown,
          userMessage: 'Playback paused after multiple track errors. Please check your connection or choose another song.',
          errorCode: 'ERR_PLAYBACK_LOOP_HALTED',
          actionLabel: 'Dismiss',
          actionType: AppActionType.none,
        );
        errorNotifier.value = haltErr;
        onError?.call(haltErr);
        if (isAudioHandlerInitialized) {
          audioHandler.playbackErrorNotifier.value = haltErr;
        }
        return;
      }

      final isNetworkFault = !ConnectivityService.currentIsOnline || ConnectivityService.isNetworkError(error);
      if (isNetworkFault && _currentTrack != null && !DownloadManager.isDownloaded(_currentTrack!.id)) {
        _wasStalledByNetwork = true;
        if (player.position > Duration.zero) {
          _networkStallOffset = player.position;
        }
        ConnectivityService.reportTransportFailure(error);
        _consecutivePlaybackErrors = 0; // Prevent network dropouts from tripping circuit breaker
        AppLogger.log('AudioQueueHandler', 'Network offline during playback error. Cached stall offset ${_networkStallOffset.inSeconds}s for automatic zero-touch recovery.');
      }

      final appErr = ErrorHandler.resolve(error, stackTrace: stackTrace, context: 'Playback error on ${current.title}');
      errorNotifier.value = appErr;
      onError?.call(appErr);
      if (isAudioHandlerInitialized) {
        audioHandler.playbackErrorNotifier.value = appErr;
      }

      // If stalled by network, HOLD position rather than auto-skipping and tripping circuit breaker
      if (_wasStalledByNetwork) {
        AppLogger.log('AudioQueueHandler', 'Holding playback on network-stalled track "${current.title}". Awaiting connection recovery...');
        try {
          player.pause();
        } catch (e) {
          AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
        }
        return;
      }

      if (hasNext && !_isDisposed && token == _sessionToken) {
        AppLogger.log('AudioQueueHandler', 'Advancing to next track after failure on "${current.title}"');
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!_isDisposed && queue.isNotEmpty && _sessionToken == token) skipToNext(isUserInitiated: false);
        });
      }
    } finally {
      _isRecovering = false;
    }
  }
}
