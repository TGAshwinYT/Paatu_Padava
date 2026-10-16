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
import 'services/battery_optimization_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/innertube_config_service.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/main_navigation.dart';

Future<void> _initFirebase() async {
  try {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      final options = DefaultFirebaseOptions.currentPlatform;
      final future = options.apiKey.isNotEmpty
          ? Firebase.initializeApp(options: options)
          : Firebase.initializeApp();
      await future.timeout(const Duration(seconds: 1));
      AppLogger.log('AppInit', 'Firebase successfully connected');
    }
  } catch (e, stack) {
    AppLogger.recordError(e, stack, context: 'Firebase.initializeApp');
  }
}

Future<void> _initSupabase() async {
  try {
    await SupabaseService.init().timeout(const Duration(seconds: 1));
  } catch (e, stack) {
    AppLogger.recordError(e, stack, context: 'SupabaseService.init');
  }
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Catch framework-level errors (widget build, layout assertions)
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      AppLogger.recordError(details.exception, details.stack, context: 'FlutterError.onError');
    };

    // 2. Catch uncaught platform / isolate errors
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      AppLogger.recordError(error, stack, context: 'PlatformDispatcher.onError');
      return true; // Mark as handled to prevent abrupt native teardown where possible
    };

    // Set system UI overlay style (dark status bar and harmonized navigation bar)
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0D0B14),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // 3. Fast local startup: only await local Hive engine and critical settings preferences
    try {
      await Hive.initFlutter();
      await SettingsManager.init();
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'SettingsManager.init');
    }

    // 4. Initialize background AudioService engine
    Object? audioInitError;
    try {
      audioHandler = await AudioService.init(
        builder: () => PaatuAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.paatupaadava.music.channel.audio',
          androidNotificationChannelName: 'Paatu Padava Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
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

    // 5. Run non-dependent initializations concurrently via Future.wait() with a 2-second safety timeout
    try {
      await Future.wait([
        AppLogger.init(),
        AuthManager.init(),
        DownloadManager.init(),
        FavoritesManager.init(),
        HistoryManager.init(),
        PlaylistManager.init(),
        SearchHistoryManager.init(),
        Hive.openBox('home_feed_cache'),
        InnerTubeConfigService.initialize(),
        _initFirebase(),
        _initSupabase(),
      ]).timeout(const Duration(seconds: 2), onTimeout: () {
        AppLogger.log('AppInit', 'Non-dependent services initialization completed with 2s safety timeout');
        return [];
      });
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'Non-critical init');
    }

    // Run automatic audio cache cleaner in background (>400MB or >7 days old) after settings are initialized
    CacheManager.autoEvictOldCache();

    // Request Android 13+ POST_NOTIFICATIONS runtime permission for reliable media notifications
    unawaited(BatteryOptimizationService.requestNotificationPermission());

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
    return ValueListenableBuilder<String>(
      valueListenable: SettingsManager.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Paatu Padava',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: AppTheme.getTheme(themeMode),
          home: const MainNavigation(),
        );
      },
    );
  }
}
