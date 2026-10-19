/// Clean Architecture Platform Audio Barrier.
/// Encapsulates OS-level background playback services, hardware volume, equalizers, and power managers.
library;

export '../services/player_handler.dart';
export '../services/smart_gapless_precacher.dart';
export '../services/equalizer_service.dart';
export '../services/sleep_timer_service.dart';
export '../services/battery_optimization_service.dart';
