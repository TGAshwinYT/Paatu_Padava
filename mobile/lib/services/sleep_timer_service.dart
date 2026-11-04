import 'dart:async';
import 'package:flutter/foundation.dart';
import 'player_handler.dart';
import 'app_logger.dart';

/// BloomeeTunes / Paatu Padava Sleep Timer Engine:
/// Singleton service managing custom sleep timer duration countdown backed by
/// true wall-clock timestamps (immune to Android background Doze/timer throttling),
/// smooth 5-second volume fade-out before pause, "+5 min" extensions,
/// "stop at end of track", and "stop at end of queue" modes.
class SleepTimerService extends ChangeNotifier {
  static final SleepTimerService _instance = SleepTimerService._internal();
  static SleepTimerService get instance => _instance;
  SleepTimerService._internal();

  Timer? _timer;
  DateTime? _targetEndTime;
  Duration _remainingTime = Duration.zero;
  Duration _initialDuration = Duration.zero;
  bool _isActive = false;
  bool _stopAtEndOfTrack = false;
  bool _stopAtEndOfQueue = false;
  bool _isFadingOut = false;
  double? _preFadeVolume;

  Duration get remainingTime => _remainingTime;
  Duration get initialDuration => _initialDuration;
  bool get isActive => _isActive;
  bool get stopAtEndOfTrack => _stopAtEndOfTrack;
  bool get stopAtEndOfQueue => _stopAtEndOfQueue;
  bool get isFadingOut => _isFadingOut;
  DateTime? get targetEndTime => _targetEndTime;

  /// Returns true if an active timed sleep timer has passed its wall-clock end time
  bool get hasExpired {
    if (!_isActive || _stopAtEndOfTrack || _stopAtEndOfQueue) return false;
    final end = _targetEndTime;
    if (end == null) return false;
    return DateTime.now().isAfter(end);
  }

  /// Returns remaining progress from 1.0 (just started) down to 0.0 (finished)
  double get progressFraction {
    if (_stopAtEndOfTrack || _stopAtEndOfQueue || _initialDuration.inSeconds <= 0) return 1.0;
    return (_remainingTime.inSeconds / _initialDuration.inSeconds).clamp(0.0, 1.0);
  }

  /// Formatted duration as HH:MM:SS (or MM:SS if under 1 hour)
  String get formattedRemaining {
    if (_stopAtEndOfTrack) return 'End of Track';
    if (_stopAtEndOfQueue) return 'End of Queue';
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
    if (_stopAtEndOfTrack) return 'Track';
    if (_stopAtEndOfQueue) return 'Queue';
    final m = _remainingTime.inMinutes;
    final s = _remainingTime.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Sets sleep timer with custom duration or sets "Stop at end of track/queue"
  void setTimer(Duration duration, {bool stopAtEnd = false, bool stopAtEndOfQueue = false}) {
    cancel();

    if (stopAtEndOfQueue) {
      _stopAtEndOfQueue = true;
      _stopAtEndOfTrack = false;
      _isActive = true;
      _targetEndTime = null;
      _initialDuration = Duration.zero;
      _remainingTime = Duration.zero;
      _syncNotificationRemaining();
      notifyListeners();
      AppLogger.log('SleepTimerService', 'Sleep timer armed: Stop at end of queue');
      return;
    }

    if (stopAtEnd) {
      _stopAtEndOfTrack = true;
      _stopAtEndOfQueue = false;
      _isActive = true;
      _targetEndTime = null;
      _initialDuration = Duration.zero;
      _remainingTime = Duration.zero;
      _syncNotificationRemaining();
      notifyListeners();
      AppLogger.log('SleepTimerService', 'Sleep timer armed: Stop at end of current track');
      return;
    }

    if (duration <= Duration.zero) return;

    _stopAtEndOfTrack = false;
    _stopAtEndOfQueue = false;
    _isActive = true;
    _initialDuration = duration;
    _remainingTime = duration;
    _targetEndTime = DateTime.now().add(duration);
    _syncNotificationRemaining();
    notifyListeners();
    AppLogger.log('SleepTimerService', 'Sleep timer set: ${duration.inMinutes}m (ends at $_targetEndTime)');

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isActive) {
        timer.cancel();
        return;
      }

      final end = _targetEndTime;
      if (end == null) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final diff = end.difference(now);

      if (diff <= Duration.zero) {
        _remainingTime = Duration.zero;
        _syncNotificationRemaining();
        notifyListeners();
        timer.cancel();
        await triggerSleepNow();
      } else {
        _remainingTime = diff;

        // Smooth 5-second fade out when <= 5 seconds remaining
        if (diff.inSeconds <= 5 && !_isFadingOut) {
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
    _stopAtEndOfQueue = false;
    _initialDuration += extra;
    if (_targetEndTime != null) {
      _targetEndTime = _targetEndTime!.add(extra);
      _remainingTime = _targetEndTime!.difference(DateTime.now());
    } else {
      _targetEndTime = DateTime.now().add(extra);
      _remainingTime = extra;
    }
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

    if (_isFadingOut && _preFadeVolume != null && isAudioHandlerInitialized) {
      try {
        audioHandler.player.setVolume(_preFadeVolume!);
      } catch (_) {}
    }

    _isActive = false;
    _stopAtEndOfTrack = false;
    _stopAtEndOfQueue = false;
    _isFadingOut = false;
    _preFadeVolume = null;
    _targetEndTime = null;
    _initialDuration = Duration.zero;
    _remainingTime = Duration.zero;

    if (isAudioHandlerInitialized) {
      audioHandler.sleepTimerRemainingNotifier.value = null;
    }
    notifyListeners();
    AppLogger.log('SleepTimerService', 'Sleep timer cancelled');
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

  /// Executes immediate playback pause and shutdown when timer expires or trigger is reached
  Future<void> triggerSleepNow() async {
    AppLogger.log('SleepTimerService', 'triggerSleepNow executed: pausing playback and disarming timer.');
    final restoreVol = _preFadeVolume;
    cancel();

    try {
      if (isAudioHandlerInitialized) {
        await audioHandler.pause();
        // Fully stop the audio source so wake locks and audio focus are safely surrendered
        try {
          await audioHandler.player.pause();
        } catch (_) {}
        if (restoreVol != null) {
          try {
            await audioHandler.player.setVolume(restoreVol);
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger.log('SleepTimerService', 'triggerSleepNow notice: $e');
    }
  }

  void _syncNotificationRemaining() {
    if (isAudioHandlerInitialized) {
      audioHandler.sleepTimerRemainingNotifier.value =
          (_stopAtEndOfTrack || _stopAtEndOfQueue) ? Duration.zero : _remainingTime;
    }
  }
}
