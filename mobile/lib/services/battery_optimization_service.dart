import 'dart:io';
import 'package:flutter/services.dart';
import 'app_logger.dart';

/// Service to detect device OEM (e.g. OnePlus / OxygenOS) and manage
/// battery optimization exemptions for uninterrupted background playback.
class BatteryOptimizationService {
  static const MethodChannel _channel = MethodChannel('com.tamilgaming.paatupadava/battery');

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
}
