import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/app_config.dart';

/// Connection reachability monitor.
/// Surfaces live online/offline states to ensure graceful offline degradation
/// and automatic recovery when network transitions occur.
class ConnectivityService {
  static final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  static Timer? _heartbeatTimer;
  static bool _isChecking = false;
  static bool _isPaused = false;

  static ValueListenable<bool> get isOnline => isOnlineNotifier;
  static bool get currentIsOnline => isOnlineNotifier.value;

  /// Initializes reachability check and begins background-safe polling
  static void init() {
    _heartbeatTimer?.cancel();
    _isPaused = false;
    checkConnection();
    _startTimer();
  }

  static void _startTimer() {
    _heartbeatTimer?.cancel();
    // Poll every 60s while in the foreground to conserve battery and radio wakeups
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_isPaused) {
        checkConnection();
      }
    });
  }

  /// Pauses polling when the app goes into the background
  static void pausePolling() {
    _isPaused = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Resumes polling and immediately checks connection state when resumed
  static void resumePolling() {
    if (!_isPaused && _heartbeatTimer != null) return;
    _isPaused = false;
    checkConnection();
    _startTimer();
  }

  /// Explicitly checks internet reachability against our backend and fallback hosts
  static Future<bool> checkConnection() async {
    if (_isChecking) return isOnlineNotifier.value;
    _isChecking = true;

    try {
      bool reachable = false;

      // 1. Primary check: Our own backend host
      final backendHost = Uri.tryParse(AppConfig.backendUrl)?.host;
      if (backendHost != null && backendHost.isNotEmpty) {
        try {
          final lookup = await InternetAddress.lookup(backendHost)
              .timeout(const Duration(seconds: 3));
          if (lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty) {
            reachable = true;
          }
        } catch (_) {
          // Backend unreachable or DNS error, fallback to public resolvers
        }
      }

      // 2. Secondary fallback: Cloudflare & Google DNS
      if (!reachable) {
        for (final fallbackHost in const ['1.1.1.1', 'dns.google']) {
          try {
            final lookup = await InternetAddress.lookup(fallbackHost)
                .timeout(const Duration(seconds: 2));
            if (lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty) {
              reachable = true;
              break;
            }
          } catch (_) {}
        }
      }

      if (isOnlineNotifier.value != reachable) {
        debugPrint('[ConnectivityService] Network state changed: ${reachable ? "ONLINE" : "OFFLINE"}');
        isOnlineNotifier.value = reachable;
      }
      _isChecking = false;
      return reachable;
    } catch (_) {
      if (isOnlineNotifier.value != false) {
        debugPrint('[ConnectivityService] Network state changed: OFFLINE');
        isOnlineNotifier.value = false;
      }
      _isChecking = false;
      return false;
    }
  }

  /// Cancels polling timer
  static void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isPaused = true;
  }
}

