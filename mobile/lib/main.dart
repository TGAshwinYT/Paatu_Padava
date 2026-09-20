import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/download_manager.dart';
import 'services/player_handler.dart';
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

  // Initialize offline Hive storage for songs
  await DownloadManager.init();

  // Initialize background AudioService engine
  audioHandler = await AudioService.init(
    builder: () => PaatuAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.paatupaadava.music.channel.audio',
      androidNotificationChannelName: 'Paatu Padava Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  runApp(const PaatuPadavaApp());
}

class PaatuPadavaApp extends StatelessWidget {
  const PaatuPadavaApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paatu Padava',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        primaryColor: const Color(0xFF6366F1),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFEC4899),
          surface: Color(0xFF1E293B),
          background: Color(0xFF0B0F19),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}
