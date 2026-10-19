/// Master Services Barrier for Paatu Padava Mobile.
/// Provides categorized exports across Remote Sources, Local Persistence, Platform Audio, and Core Utilities.
library;

export '../data/datasources/remote_datasources.dart';
export '../data/datasources/local_datasources.dart';
export '../platform/audio_platform.dart';
export '../platform/sync_platform.dart';

// Core domain services and utilities
export 'app_logger.dart';
export 'artist_sanitizer.dart';
export 'auth_manager.dart';
export 'collaborative_playlist_service.dart';
export 'connectivity_service.dart';
export 'des_decrypt.dart';
export 'error_handler.dart';
export 'fuzzy_search_service.dart';
export 'queue_cooldown_manager.dart';
export 'radio_engine.dart';
export 'recap_service.dart';
export 'search_service.dart';
export 'sync_manager.dart';
