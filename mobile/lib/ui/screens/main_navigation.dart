import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import '../widgets/mini_player.dart';
import '../../services/player_handler.dart';
import '../../services/connectivity_service.dart';
import '../../services/sync_manager.dart';
import '../../services/cache_manager.dart';
import '../../domain/models/app_error.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectivityService.init();
    audioHandler.playbackErrorNotifier.addListener(_onPlaybackError);
  }

  @override
  void dispose() {
    audioHandler.playbackErrorNotifier.removeListener(_onPlaybackError);
    ConnectivityService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onPlaybackError() {
    final err = audioHandler.playbackErrorNotifier.value;
    if (err == null || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                err.userMessage,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        duration: const Duration(seconds: 4),
        action: err.actionLabel != null
            ? SnackBarAction(
                label: err.actionLabel!,
                textColor: Colors.white,
                onPressed: () {
                  if (err.actionType == AppActionType.skipSong) {
                    audioHandler.skipToNext();
                  }
                },
              )
            : null,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[MainNavigation] App resumed cleanly. Triggering connection check, sync, and cache audit...');
      ConnectivityService.resumePolling();
      ConnectivityService.checkConnection();
      SyncManager.syncAll();
      CacheManager.autoEvictOldCache();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      ConnectivityService.pausePolling();
    }
  }

  Widget _buildOfflineBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOnline,
      builder: (context, isOnline, _) {
        if (isOnline) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFFDC2626),
          child: InkWell(
            onTap: () {
              setState(() => _currentIndex = 2); // Switch to Library / Downloads tab
            },
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: const [
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You're offline. Tap to view your downloaded songs.",
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // If not on Home tab, navigate back to Home instead of exiting app
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: Column(
          children: [
            _buildOfflineBanner(),
            Expanded(
              child: Stack(
                children: [
                  // IndexedStack maintains scroll & search state across tabs
                  IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),

                  // Docked / Floating Mini Player above Bottom Nav
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MiniPlayer(),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: const Color(0xFF6366F1),
            unselectedItemColor: const Color(0xFF64748B),
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
