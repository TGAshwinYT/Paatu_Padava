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
  static int _lastLatencyMs = 50;
  static String _networkType = 'unknown';

  static ValueListenable<bool> get isOnline => isOnlineNotifier;
  static bool get currentIsOnline => isOnlineNotifier.value;
  static int get lastLatencyMs => _lastLatencyMs;
  static String get networkType => _networkType;

  /// Visible for testing: inject synthetic network conditions
  @visibleForTesting
  static void setMockConditions({int? latencyMs, String? networkType, bool? isOnline}) {
    if (latencyMs != null) _lastLatencyMs = latencyMs;
    if (networkType != null) _networkType = networkType;
    if (isOnline != null) isOnlineNotifier.value = isOnline;
  }

  /// Calculates the recommended audio streaming bitrate based on network type and latency.
  /// - Wi-Fi / Low latency (<250ms) -> 320kbps (Lossless studio audio)
  /// - Cellular / Moderate latency (250-400ms) -> 160kbps (High quality, zero stutter)
  /// - Weak network / High latency (>400ms) / Offline -> 96kbps (Data saver / instant play)
  static String get recommendedStreamingQuality {
    if (!isOnlineNotifier.value) return '96kbps';
    if (_networkType == 'cellular') {
      return _lastLatencyMs > 400 ? '96kbps' : '160kbps';
    }
    if (_networkType == 'wifi' || _networkType == 'ethernet') {
      return _lastLatencyMs > 600 ? '160kbps' : '320kbps';
    }
    // Unknown interface: determine purely from round-trip ping / lookup latency
    if (_lastLatencyMs > 400) return '96kbps';
    if (_lastLatencyMs > 250) return '160kbps';
    return '320kbps';
  }

  /// Probes network interfaces to detect Wi-Fi vs Cellular connection
  static Future<bool> isWifi() async {
    final t = await detectNetworkType();
    return t == 'wifi' || t == 'ethernet';
  }

  static Future<String> detectNetworkType() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (iface.addresses.any((a) => !a.isLoopback)) {
          if (name.contains('wlan') ||
              name.contains('wi-fi') ||
              name.contains('wifi') ||
              name.contains('eth')) {
            return 'wifi';
          }
          if (name.contains('rmnet') ||
              name.contains('ccmni') ||
              name.contains('pdp') ||
              name.contains('wwan') ||
              name.contains('cell')) {
            return 'cellular';
          }
        }
      }
    } catch (_) {}
    return 'unknown';
  }

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
      final sw = Stopwatch()..start();

      // Detect network interface
      _networkType = await detectNetworkType();

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

      sw.stop();
      if (reachable) {
        _lastLatencyMs = sw.elapsedMilliseconds;
      }

      if (isOnlineNotifier.value != reachable) {
        debugPrint('[ConnectivityService] Network state changed: ${reachable ? "ONLINE" : "OFFLINE"} (type: $_networkType, latency: ${_lastLatencyMs}ms)');
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

