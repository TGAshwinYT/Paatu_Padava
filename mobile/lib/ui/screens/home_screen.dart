import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/api_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../../services/favorites_manager.dart';
import '../../services/auth_manager.dart';
import '../../services/history_manager.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/auth_dialog.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'settings_screen.dart';
import 'liked_songs_screen.dart';
import 'onboarding_screen.dart';
import '../widgets/add_to_playlist_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Mode: 'studio' (320kbps Lossless JioSaavn CDN) or 'youtube' (YouTube Music)
  String _activeMode = 'studio';

  final List<String> _languages = ['Tamil', 'Telugu', 'Hindi', 'Malayalam', 'English', 'Kannada'];
  String _selectedLanguage = 'Tamil';

  List<Song> _forYouSongs = [];
  List<Song> _trendingSongs = [];
  List<Song> _youtubeTrendingSongs = [];
  List<Song> _recentHistory = [];
  List<Map<String, dynamic>> _topAlbums = [];
  List<Map<String, dynamic>> _topArtists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _loadHomeData() async {
    setState(() => _isLoading = true);

    try {
      if (_activeMode == 'studio') {
        final results = await Future.wait([
          SaavnClient.getTrending(language: _selectedLanguage),
          ApiClient.fetchForYou(),
          SaavnClient.searchAlbums('$_selectedLanguage Hit Albums', limit: 10),
          SaavnClient.searchArtists('Top $_selectedLanguage Artists', limit: 10),
          AuthManager.isLoggedIn ? ApiClient.fetchListenHistory() : Future.value(<Song>[]),
        ]);

        if (mounted) {
          setState(() {
            _trendingSongs = results[0] as List<Song>;
            _forYouSongs = results[1] as List<Song>;
            _topAlbums = results[2] as List<Map<String, dynamic>>;
            _topArtists = results[3] as List<Map<String, dynamic>>;
            _recentHistory = results[4] as List<Song>;
            _isLoading = false;
          });
        }
      } else {
        // YouTube Music Mode
        final ytSongs = await ApiClient.fetchYouTubeTrending();
        if (mounted) {
          setState(() {
            _youtubeTrendingSongs = ytSongs;
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onLanguageSelected(String lang) {
    if (_selectedLanguage == lang) return;
    setState(() => _selectedLanguage = lang);
    _loadHomeData();
  }

  void _switchMode(String mode) {
    if (_activeMode == mode) return;
    setState(() => _activeMode = mode);
    _loadHomeData();
  }

  Widget _buildShortcutTile({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF6366F1),
          backgroundColor: const Color(0xFF131B2E),
          onRefresh: _loadHomeData,
          child: CustomScrollView(
            slivers: [
              // Top Bar: Logo, Account Icon, and Mode Switcher
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Paatu Padava',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                _activeMode == 'studio' ? 'Lossless 320kbps • JioSaavn' : 'YouTube Music • Direct Stream',
                                style: TextStyle(
                                  color: _activeMode == 'studio' ? const Color(0xFF818CF8) : const Color(0xFFEF4444),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Action icons: Settings + Account Profile
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
                            tooltip: 'Settings & Equalizer',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SettingsScreen()),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          ValueListenableBuilder<AuthUser?>(
                            valueListenable: AuthManager.authNotifier,
                            builder: (context, user, _) {
                              final isUser = user != null && !user.isGuest;
                              return InkWell(
                                onTap: () => AuthDialog.show(context),
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isUser ? const Color(0xFF6366F1) : Colors.white24,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isUser ? const Color(0xFF6366F1) : const Color(0xFF131B2E),
                                    child: Text(
                                      (user != null && !user.isGuest && user.username.isNotEmpty)
                                          ? user.username[0].toUpperCase()
                                          : '👤',
                                      style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Dynamic Greeting
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                  child: ValueListenableBuilder<AuthUser?>(
                    valueListenable: AuthManager.authNotifier,
                    builder: (context, user, _) {
                      final name = (user != null && !user.isGuest && user.username.isNotEmpty)
                          ? user.username
                          : 'Music Lover';
                      return Text(
                        '${_getGreeting()}, $name',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Quick Shortcuts 2x3 Grid (Spotify style)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildShortcutTile(
                              title: 'Liked Songs',
                              icon: Icons.favorite_rounded,
                              iconColor: const Color(0xFFEC4899),
                              gradient: const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildShortcutTile(
                              title: 'Made For You',
                              icon: Icons.auto_awesome_rounded,
                              iconColor: const Color(0xFFFBBF24),
                              gradient: const [Color(0xFFBE185D), Color(0xFFE11D48)],
                              onTap: () {
                                if (_forYouSongs.isNotEmpty) {
                                  audioHandler.playSong(_forYouSongs.first, queue: _forYouSongs);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Building your recommendation mix...')),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildShortcutTile(
                              title: 'Import Spotify',
                              icon: Icons.album_rounded,
                              iconColor: const Color(0xFF1DB954),
                              gradient: const [Color(0xFF065F46), Color(0xFF047857)],
                              onTap: () => SpotifyImportDialog.show(context),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildShortcutTile(
                              title: 'Tune Taste',
                              icon: Icons.tune_rounded,
                              iconColor: const Color(0xFF38BDF8),
                              gradient: const [Color(0xFF0F766E), Color(0xFF0E7490)],
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OnboardingScreen(
                                      onCompleted: () {
                                        Navigator.pop(context);
                                        _loadHomeData();
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildShortcutTile(
                              title: 'Recently Played',
                              icon: Icons.history_rounded,
                              iconColor: const Color(0xFF818CF8),
                              gradient: const [Color(0xFF312E81), Color(0xFF4338CA)],
                              onTap: () {
                                final recents = HistoryManager.getRecentSongs();
                                if (recents.isNotEmpty) {
                                  audioHandler.playSong(recents.first, queue: recents);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('No recently played songs yet')),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildShortcutTile(
                              title: _activeMode == 'studio' ? 'YouTube Hits' : 'Studio 320k',
                              icon: _activeMode == 'studio' ? Icons.play_circle_filled_rounded : Icons.diamond_rounded,
                              iconColor: Colors.white,
                              gradient: _activeMode == 'studio'
                                  ? const [Color(0xFF991B1B), Color(0xFFDC2626)]
                                  : const [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                              onTap: () => _switchMode(_activeMode == 'studio' ? 'youtube' : 'studio'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // "Jump Back In" (Listen History - dynamically reactive)
              ValueListenableBuilder<List<Song>>(
                valueListenable: HistoryManager.historyNotifier,
                builder: (context, recentSongs, _) {
                  final displayHistory = recentSongs.isNotEmpty ? recentSongs : _recentHistory;
                  if (displayHistory.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

                  return SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.history_rounded, color: Color(0xFF818CF8), size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Jump Back In',
                                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              TextButton(
                                child: const Text('Play All', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                                onPressed: () => audioHandler.playSong(displayHistory.first, queue: displayHistory),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 185,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: displayHistory.length,
                            itemBuilder: (context, index) {
                              final song = displayHistory[index];
                              return _SongCard(
                                song: song,
                                onTap: () => audioHandler.playSong(song, queue: displayHistory),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Studio vs YouTube Music Pill Switcher
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _switchMode('studio'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _activeMode == 'studio' ? const Color(0xFF6366F1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.diamond_rounded, size: 16, color: _activeMode == 'studio' ? Colors.white : Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Studio 320k',
                                    style: TextStyle(
                                      color: _activeMode == 'studio' ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _switchMode('youtube'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _activeMode == 'youtube' ? const Color(0xFFEF4444) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_circle_filled_rounded, size: 16, color: _activeMode == 'youtube' ? Colors.white : Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    'YouTube Music',
                                    style: TextStyle(
                                      color: _activeMode == 'youtube' ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Spotify Quick Import Banner
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1DB954).withOpacity(0.18),
                          const Color(0xFF131B2E),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x331DB954)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.album_rounded, color: Color(0xFF1DB954), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Import Spotify Playlist',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                'Match & play your Spotify library in 320kbps',
                                style: TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => SpotifyImportDialog.show(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('Import', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Mode 1: Studio 320kbps View
              if (_activeMode == 'studio') ...[
                // Regional Language Chips
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      scrollDirection: Axis.horizontal,
                      itemCount: _languages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final lang = _languages[index];
                        final isSelected = lang == _selectedLanguage;
                        return ChoiceChip(
                          label: Text(lang),
                          selected: isSelected,
                          selectedColor: const Color(0xFF6366F1),
                          backgroundColor: const Color(0xFF131B2E),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF6366F1) : Colors.white.withOpacity(0.06),
                            ),
                          ),
                          onSelected: (_) => _onLanguageSelected(lang),
                        );
                      },
                    ),
                  ),
                ),

                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                    ),
                  )
                else ...[
                  // "Made For You" Collaborative Mix
                  if (_forYouSongs.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Made For You (AI Graph)',
                                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            TextButton(
                              child: const Text('Play All', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                              onPressed: () => audioHandler.playSong(_forYouSongs.first, queue: _forYouSongs),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 190,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: _forYouSongs.length,
                          itemBuilder: (context, index) {
                            final song = _forYouSongs[index];
                            return _SongCard(
                              song: song,
                              onTap: () => audioHandler.playSong(song, queue: _forYouSongs),
                            );
                          },
                        ),
                      ),
                    ),
                  ],

                  // "Top Artists" Avatars
                  if (_topArtists.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Text(
                          'Popular Artists',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 110,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: _topArtists.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final art = _topArtists[index];
                            final name = art['name']?.toString() ?? 'Artist';
                            final img = art['image']?.toString() ?? '';
                            final id = art['id']?.toString() ?? '';

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ArtistScreen(
                                      artistId: id,
                                      artistName: name,
                                      imageUrl: img,
                                    ),
                                  ),
                                );
                              },
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 36,
                                    backgroundColor: const Color(0xFF131B2E),
                                    backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: 76,
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],

                  // "Top Albums"
                  if (_topAlbums.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
                        child: Text(
                          'Featured Albums',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 180,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: _topAlbums.length,
                          itemBuilder: (context, index) {
                            final album = _topAlbums[index];
                            final id = album['id']?.toString() ?? '';
                            final title = album['title']?.toString() ?? 'Album';
                            final img = album['image']?.toString() ?? '';
                            final artist = album['artist']?.toString() ?? '';

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AlbumScreen(
                                      albumId: id,
                                      albumTitle: title,
                                      imageUrl: img,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                width: 130,
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: SizedBox(
                                        width: 130,
                                        height: 130,
                                        child: CachedNetworkImage(
                                          imageUrl: img,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],

                  // "Trending Now" Section Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '🔥 Trending $_selectedLanguage Tracks',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          if (_trendingSongs.isNotEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.play_circle_fill_rounded, size: 18, color: Color(0xFF6366F1)),
                              label: const Text('Play All', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                              onPressed: () => audioHandler.playSong(_trendingSongs.first, queue: _trendingSongs),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Trending Songs List
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _trendingSongs[index];
                        return _SongTile(
                          song: song,
                          onTap: () => audioHandler.playSong(song, queue: _trendingSongs),
                        );
                      },
                      childCount: _trendingSongs.length,
                    ),
                  ),
                ],
              ] else ...[
                // Mode 2: YouTube Music View
                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFFEF4444)),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.whatshot_rounded, color: Color(0xFFEF4444), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'YouTube Music Charts',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (_youtubeTrendingSongs.isNotEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.play_circle_fill_rounded, size: 18, color: Color(0xFFEF4444)),
                              label: const Text('Play All', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                              onPressed: () => audioHandler.playSong(_youtubeTrendingSongs.first, queue: _youtubeTrendingSongs),
                            ),
                        ],
                      ),
                    ),
                  ),

                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _youtubeTrendingSongs[index];
                        return _SongTile(
                          song: song,
                          onTap: () => audioHandler.playSong(song, queue: _youtubeTrendingSongs),
                        );
                      },
                      childCount: _youtubeTrendingSongs.length,
                    ),
                  ),
                ],
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }
}

void _showSongContextMenu(BuildContext context, Song song) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF131B2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded, color: Color(0xFF6366F1)),
            title: const Text('Play Next', style: TextStyle(color: Colors.white)),
            onTap: () {
              audioHandler.insertNext(song);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Playing "${song.title}" next')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_rounded, color: Colors.white70),
            title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
            onTap: () {
              audioHandler.addToQueue(song);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Added "${song.title}" to queue')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8)),
            title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              AddToPlaylistDialog.show(context, song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
            title: const Text('Download Offline', style: TextStyle(color: Colors.white)),
            onTap: () {
              DownloadManager.downloadSong(song);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border_rounded, color: Color(0xFFEC4899)),
            title: const Text('Like / Favorite', style: TextStyle(color: Colors.white)),
            onTap: () {
              FavoritesManager.toggleFavorite(song);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
  );
}

class _SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _SongCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showSongContextMenu(context, song),
      child: Container(
        width: 135,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 135,
                    height: 135,
                    child: CachedNetworkImage(
                      imageUrl: song.coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF6366F1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _SongTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;

        return ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: CachedNetworkImage(
                    imageUrl: song.coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                  ),
                ),
              ),
              if (isPlaying)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.equalizer_rounded, color: Color(0xFF6366F1), size: 24),
                ),
            ],
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying ? const Color(0xFF6366F1) : Colors.white,
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
            onPressed: () => _showSongContextMenu(context, song),
          ),
        );
      },
    );
  }
}
