import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Connection reachability monitor.
/// Surfaces live online/offline states to ensure graceful offline degradation
/// and automatic recovery when network transitions occur.
class ConnectivityService {
  static final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  static Timer? _heartbeatTimer;
  static bool _isChecking = false;

  static ValueListenable<bool> get isOnline => isOnlineNotifier;
  static bool get currentIsOnline => isOnlineNotifier.value;

  /// Initializes periodic reachability checks
  static void init() {
    _heartbeatTimer?.cancel();
    checkConnection();
    // Periodically verify network health every 15 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      checkConnection();
    });
  }

  /// Explicitly checks internet reachability via DNS lookup
  static Future<bool> checkConnection() async {
    if (_isChecking) return isOnlineNotifier.value;
    _isChecking = true;

    try {
      final lookup = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 3));
      final online = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
      if (isOnlineNotifier.value != online) {
        debugPrint('[ConnectivityService] Network state changed: ${online ? "ONLINE" : "OFFLINE"}');
        isOnlineNotifier.value = online;
      }
      _isChecking = false;
      return online;
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
  }
}
