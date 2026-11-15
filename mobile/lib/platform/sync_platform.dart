/// Clean Architecture Platform Sync Barrier.
/// Encapsulates multi-device Party Mode, LAN discovery, and mesh playback synchronization.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export '../services/party_sync_coordinator.dart';
export '../services/party_lan_accelerator.dart';
export '../services/device_connect_coordinator.dart';

/// Native Wi-Fi & Network Hardware Platform Barrier
class SyncPlatform {
  static const MethodChannel _channel = MethodChannel('com.tamilgaming.paatupadava/sync');

  /// Acquires Android Wi-Fi MulticastLock and low-latency/high-perf WifiLock.
  static Future<bool> acquireWifiLocks() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('acquireWifiLocks');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Releases Android Wi-Fi locks.
  static Future<bool> releaseWifiLocks() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('releaseWifiLocks');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Queries the active Wi-Fi broadcast address calculated from real subnet mask.
  static Future<String?> getWifiBroadcastAddress() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('getWifiBroadcastAddress');
    } catch (_) {
      return null;
    }
  }
}
