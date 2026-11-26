/// Clean Architecture Platform Audio Barrier.
/// Encapsulates OS-level background playback services, hardware volume, equalizers, and power managers.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export '../services/player_handler.dart';
export '../services/smart_gapless_precacher.dart';
export '../services/equalizer_service.dart';
export '../services/sleep_timer_service.dart';
export '../services/battery_optimization_service.dart';

/// Native DSP Audio Platform Barrier
class AudioPlatform {
  static const MethodChannel _channel = MethodChannel('com.tamilgaming.paatupadava/equalizer');

  /// Sets native DSP center-channel vocal cancellation attenuation (0.0 = full vocals, 1.0 = cancel vocals).
  static Future<bool> setVocalCancellation(double attenuation) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final bool? success = await _channel.invokeMethod<bool>('setVocalCancellation', {
        'attenuation': attenuation.clamp(0.0, 1.0),
      });
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if native DSP vocal cancellation is available on this device/platform.
  static Future<bool> isDspAvailable() async {
    final status = await getDspStatus();
    return status['attached'] == true;
  }

  /// Queries the active native DSP status (attached, active, attenuation, mode, channelCount).
  static Future<Map<String, dynamic>> getDspStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return {'attached': false, 'active': false, 'attenuation': 0.0, 'mode': 'none'};
    }
    try {
      final Map<dynamic, dynamic>? status = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDspStatus');
      if (status != null) {
        return Map<String, dynamic>.from(status);
      }
      return {'attached': false, 'active': false, 'attenuation': 0.0, 'mode': 'none'};
    } catch (_) {
      return {'attached': false, 'active': false, 'attenuation': 0.0, 'mode': 'none'};
    }
  }

  /// Sets Left/Right stereo channel balance (-1.0 = Left favored, 0.0 = Center, +1.0 = Right favored).
  static Future<bool> setStereoBalance(double balance) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final bool? success = await _channel.invokeMethod<bool>('setStereoBalance', {
        'balance': balance.clamp(-1.0, 1.0),
      });
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Queries the actual hardware band count supported by the device equalizer.
  static Future<int> getBandCount() async {
    if (defaultTargetPlatform != TargetPlatform.android) return 5;
    try {
      final int? count = await _channel.invokeMethod<int>('getBandCount');
      return count ?? 5;
    } catch (_) {
      return 5;
    }
  }
}
