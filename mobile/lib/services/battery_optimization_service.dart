import 'dart:io';
import 'package:flutter/services.dart';
import 'package:audio_session/audio_session.dart';
import 'app_logger.dart';

/// Service to detect device OEM (e.g. OnePlus / OxygenOS) and manage
/// battery optimization exemptions for uninterrupted background playback.
class BatteryOptimizationService {
  static const MethodChannel _channel = MethodChannel('com.tamilgaming.paatupadava/battery');

  /// Requests POST_NOTIFICATIONS runtime permission on Android 13+ (API 33+)
  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return granted ?? true;
    } catch (e) {
      AppLogger.log('BatteryOpt', 'Failed to request notification permission: $e');
      return true;
    }
  }

  /// Gets the hardware manufacturer (e.g. "OnePlus", "samsung", "Xiaomi")
  static Future<String> getDeviceManufacturer() async {
    if (!Platform.isAndroid) return '';
    try {
      final mfg = await _channel.invokeMethod<String>('getDeviceManufacturer');
      return mfg ?? '';
    } catch (e) {
      AppLogger.log('BatteryOpt', 'Failed to get manufacturer: $e');
      return '';
    }
  }

  /// Checks if the app is currently exempt from battery optimization ("Unrestricted")
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final isIgnoring = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return isIgnoring ?? true;
    } catch (e) {
      AppLogger.log('BatteryOpt', 'Failed to check battery optimization state: $e');
      return true;
    }
  }

  /// Launches Android system battery optimization settings for the app
  static Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final success = await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
      return success ?? false;
    } catch (e) {
      AppLogger.log('BatteryOpt', 'Failed to open battery optimization settings: $e');
      return false;
    }
  }

  /// Returns true if the device is a OnePlus, Oppo, or Realme phone which
  /// enforces aggressive background killing policies.
  static Future<bool> isAggressiveBatteryOEM() async {
    final mfg = (await getDeviceManufacturer()).toLowerCase();
    return mfg.contains('oneplus') || mfg.contains('oppo') || mfg.contains('realme');
  }

  /// Explicitly detaches foreground service notification during prolonged pauses
  static Future<bool> detachForeground() async {
    if (!Platform.isAndroid) return false;
    try {
      final success = await _channel.invokeMethod<bool>('detachForeground');
      return success ?? false;
    } catch (e) {
      AppLogger.log('BatteryOpt', 'detachForeground error: $e');
      return false;
    }
  }

  /// Explicitly releases native CPU WakeLocks by deactivating audio session
  static Future<void> releaseWakeLock() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
      AppLogger.log('BatteryOpt', 'Explicitly released CPU WakeLock & audio focus');
    } catch (e) {
      AppLogger.log('BatteryOpt', 'releaseWakeLock notice: $e');
    }
  }

  /// Re-acquires native CPU WakeLocks upon explicit play or resume
  static Future<void> acquireWakeLock() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      AppLogger.log('BatteryOpt', 'Re-acquired CPU WakeLock & audio session');
    } catch (e) {
      AppLogger.log('BatteryOpt', 'acquireWakeLock notice: $e');
    }
  }
}
