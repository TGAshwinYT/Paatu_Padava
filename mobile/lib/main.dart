import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/app_logger.dart';
import 'services/auth_manager.dart';
import 'services/download_manager.dart';
import 'services/favorites_manager.dart';
import 'services/search_history_manager.dart';
import 'services/settings_manager.dart';
import 'services/playlist_manager.dart';
import 'services/player_handler.dart';
import 'services/history_manager.dart';
import 'services/supabase_service.dart';
import 'services/cache_manager.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/main_navigation.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Initialize persistent disk logger for crash and lifecycle tracing
    await AppLogger.init();

    // 2. Catch framework-level errors (widget build, layout assertions)
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      AppLogger.recordError(details.exception, details.stack, context: 'FlutterError.onError');
    };

    // 3. Catch uncaught platform / isolate errors
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      AppLogger.recordError(error, stack, context: 'PlatformDispatcher.onError');
      return true; // Mark as handled to prevent abrupt native teardown where possible
    };

    // Set system UI overlay style (dark status bar)
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0F172A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Initialize Supabase client for cloud auth & user taste sync
    await SupabaseService.init();

    // Initialize offline Hive storage for songs, favorites, auth session, history, and search history
    try {
      await Hive.initFlutter();
      await SettingsManager.init();
      await AuthManager.init();
      await DownloadManager.init();
      await FavoritesManager.init();
      await HistoryManager.init();
      await PlaylistManager.init();
      await SearchHistoryManager.init();
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'Storage init');
    }

    // Run automatic audio cache cleaner in background (>400MB or >7 days old) after settings are initialized
    CacheManager.autoEvictOldCache();

    // Initialize background AudioService engine
    Object? audioInitError;
    try {
      audioHandler = await AudioService.init(
        builder: () => PaatuAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.paatupaadava.music.channel.audio',
          androidNotificationChannelName: 'Paatu Padava Playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'drawable/ic_notification',
        ),
      );
      AppLogger.log('Main', 'AudioService initialized successfully.');
    } catch (e, stack) {
      audioInitError = e;
      AppLogger.recordError(e, stack, context: 'AudioService.init');
    }

    if (audioInitError != null) {
      runApp(AudioFatalErrorApp(error: audioInitError));
      return;
    }

    runApp(const PaatuPadavaApp());
  }, (error, stack) {
    AppLogger.recordError(error, stack, context: 'runZonedGuarded');
  });
}

class AudioFatalErrorApp extends StatelessWidget {
  final Object error;
  const AudioFatalErrorApp({Key? key, required this.error}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paatu Padava',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.music_off_rounded,
                    size: 56,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Audio Engine Error',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'The background audio playback service failed to initialize:\n$error',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => main(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Restart App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaatuPadavaApp extends StatelessWidget {
  const PaatuPadavaApp({Key? key}) : super(key: key);

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Paatu Padava',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      home: const MainNavigation(),
    );
  }
}
