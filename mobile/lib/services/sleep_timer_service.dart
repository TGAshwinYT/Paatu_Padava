import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'player_handler.dart';
import 'app_logger.dart';

/// BloomeeTunes Sleep Timer Engine:
/// Singleton service managing custom sleep timer duration countdown,
/// smooth 5-second volume fade-out before pause, "+5 min" extensions,
/// and "stop at end of track" mode.
class SleepTimerService extends ChangeNotifier {
  static final SleepTimerService _instance = SleepTimerService._internal();
  static SleepTimerService get instance => _instance;
  SleepTimerService._internal();

  Timer? _timer;
  Duration _remainingTime = Duration.zero;
  Duration _initialDuration = Duration.zero;
  bool _isActive = false;
  bool _stopAtEndOfTrack = false;
  bool _isFadingOut = false;
  double? _preFadeVolume;
  StreamSubscription<PlayerState>? _playerStateSub;

  Duration get remainingTime => _remainingTime;
  Duration get initialDuration => _initialDuration;
  bool get isActive => _isActive;
  bool get stopAtEndOfTrack => _stopAtEndOfTrack;
  bool get isFadingOut => _isFadingOut;

  /// Returns remaining progress from 1.0 (just started) down to 0.0 (finished)
  double get progressFraction {
    if (_stopAtEndOfTrack || _initialDuration.inSeconds <= 0) return 1.0;
    return (_remainingTime.inSeconds / _initialDuration.inSeconds).clamp(0.0, 1.0);
  }

  /// Formatted duration as HH:MM:SS (or MM:SS if under 1 hour)
  String get formattedRemaining {
    if (_stopAtEndOfTrack) return 'End of Track';
    final h = _remainingTime.inHours;
    final m = _remainingTime.inMinutes.remainder(60);
    final s = _remainingTime.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Compact formatted duration MM:SS for top bar / chip displays
  String get formattedRemainingShort {
    if (_stopAtEndOfTrack) return 'End';
    final m = _remainingTime.inMinutes;
    final s = _remainingTime.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Sets sleep timer with custom duration or sets "Stop at end of track"
  void setTimer(Duration duration, {bool stopAtEnd = false}) {
    cancel();

    if (stopAtEnd) {
      _stopAtEndOfTrack = true;
      _isActive = true;
      _initialDuration = Duration.zero;
      _remainingTime = Duration.zero;
      _listenForEndOfTrack();
      _syncNotificationRemaining();
      notifyListeners();
      AppLogger.log('SleepTimerService', 'Sleep timer armed: Stop at end of current track');
      return;
    }

    if (duration <= Duration.zero) return;

    _stopAtEndOfTrack = false;
    _isActive = true;
    _initialDuration = duration;
    _remainingTime = duration;
    _syncNotificationRemaining();
    notifyListeners();
    AppLogger.log('SleepTimerService', 'Sleep timer set: ${duration.inMinutes}m ${duration.inSeconds % 60}s');

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isActive) {
        timer.cancel();
        return;
      }

      if (_remainingTime.inSeconds <= 1) {
        _remainingTime = Duration.zero;
        _syncNotificationRemaining();
        notifyListeners();
        timer.cancel();
        await _triggerSleep();
      } else {
        _remainingTime = Duration(seconds: _remainingTime.inSeconds - 1);

        // Smooth 5-second fade out when 5 seconds remaining
        if (_remainingTime.inSeconds <= 5 && !_isFadingOut) {
          _startSmoothFadeOut();
        }

        _syncNotificationRemaining();
        notifyListeners();
      }
    });
  }

  /// Extends active timer duration (e.g. +5 minutes)
  void addTime(Duration extra) {
    if (!_isActive) {
      setTimer(extra);
      return;
    }

    _stopAtEndOfTrack = false;
    _initialDuration = _initialDuration + extra;
    _remainingTime = _remainingTime + extra;
    _isFadingOut = false;

    // Restore volume if extended while fading out
    if (_preFadeVolume != null && isAudioHandlerInitialized) {
      try {
        audioHandler.player.setVolume(_preFadeVolume!);
      } catch (_) {}
    }

    _syncNotificationRemaining();
    notifyListeners();
    AppLogger.log('SleepTimerService', 'Added ${extra.inMinutes}m to sleep timer. Remaining: ${_remainingTime.inMinutes}m');
  }

  /// Cancels any active sleep timer and restores volume if mid-fade
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _playerStateSub?.cancel();
    _playerStateSub = null;

    if (_isFadingOut && _preFadeVolume != null && isAudioHandlerInitialized) {
      try {
        audioHandler.player.setVolume(_preFadeVolume!);
      } catch (_) {}
    }

    _isActive = false;
    _stopAtEndOfTrack = false;
    _isFadingOut = false;
    _preFadeVolume = null;
    _initialDuration = Duration.zero;
    _remainingTime = Duration.zero;

    if (isAudioHandlerInitialized) {
      audioHandler.sleepTimerRemainingNotifier.value = null;
    }
    notifyListeners();
    AppLogger.log('SleepTimerService', 'Sleep timer cancelled');
  }

  void _listenForEndOfTrack() {
    _playerStateSub?.cancel();
    if (!isAudioHandlerInitialized) return;
    _playerStateSub = audioHandler.player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _triggerSleep();
      }
    });
  }

  /// Smooth 5-second linear volume fade-out before stopping playback
  Future<void> _startSmoothFadeOut() async {
    if (_isFadingOut || !isAudioHandlerInitialized) return;
    _isFadingOut = true;

    try {
      final player = audioHandler.player;
      _preFadeVolume ??= player.volume;
      final startVol = player.volume;

      const int steps = 10;
      const stepDuration = Duration(milliseconds: 500);

      for (int i = 1; i <= steps; i++) {
        if (!_isActive || !_isFadingOut) break;
        final vol = startVol * (1.0 - (i / steps));
        try {
          await player.setVolume(vol.clamp(0.0, 1.0));
        } catch (_) {}
        await Future.delayed(stepDuration);
      }
    } catch (e) {
      AppLogger.log('SleepTimerService', 'Fade out notice: $e');
    }
  }

  Future<void> _triggerSleep() async {
    AppLogger.log('SleepTimerService', 'Sleep timer elapsed. Pausing playback and resetting volume.');
    final restoreVol = _preFadeVolume;
    cancel();

    try {
      if (isAudioHandlerInitialized) {
        await audioHandler.pause();
        if (restoreVol != null) {
          await audioHandler.player.setVolume(restoreVol);
        }
      }
    } catch (e) {
      AppLogger.log('SleepTimerService', 'Trigger sleep pause notice: $e');
    }
  }

  void _syncNotificationRemaining() {
    if (isAudioHandlerInitialized) {
      audioHandler.sleepTimerRemainingNotifier.value =
          _stopAtEndOfTrack ? Duration.zero : _remainingTime;
    }
  }
}
