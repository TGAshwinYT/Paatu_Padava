import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/auth_manager.dart';
import 'services/download_manager.dart';
import 'services/favorites_manager.dart';
import 'services/search_history_manager.dart';
import 'services/settings_manager.dart';
import 'services/playlist_manager.dart';
import 'services/player_handler.dart';
import 'services/history_manager.dart';
import 'presentation/theme/app_theme.dart';
import 'ui/screens/main_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style (dark status bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F172A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

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
  } catch (e) {
    debugPrint('Storage init warning: $e');
  }

  // Initialize background AudioService engine
  try {
    audioHandler = await AudioService.init(
      builder: () => PaatuAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.paatupaadava.music.channel.audio',
        androidNotificationChannelName: 'Paatu Padava Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  } catch (e) {
    debugPrint('AudioService init warning: $e');
  }

  runApp(const PaatuPadavaApp());
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
