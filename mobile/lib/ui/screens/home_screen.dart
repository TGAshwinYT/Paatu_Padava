import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../../services/favorites_manager.dart';
import '../../services/auth_manager.dart';
import '../../services/history_manager.dart';
import '../../logic/home_feed_provider.dart';
import '../../presentation/theme/app_theme.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/add_to_playlist_dialog.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'settings_screen.dart';
import 'liked_songs_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final HtmlUnescape _unescape = HtmlUnescape();
  final List<String> _languages = ['Tamil', 'Telugu', 'Hindi', 'Malayalam', 'English', 'Kannada'];

  @override
  void initState() {
    super.initState();
    HomeFeedProvider.instance.init();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
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
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceBorder),
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
                style: GoogleFonts.outfit(
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
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: HomeFeedProvider.instance,
          builder: (context, _) {
            final feedProvider = HomeFeedProvider.instance;
            final feedState = feedProvider.state;
            final currentLang = feedProvider.currentLanguage;

            return RefreshIndicator(
              color: AppColors.neonViolet,
              backgroundColor: AppColors.surfaceElevated,
              onRefresh: () => feedProvider.loadFeed(forceRefresh: true),
              child: CustomScrollView(
                slivers: [
                  // Top Bar: Glowing Logo, Title, Settings & Profile
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
                                      color: AppColors.neonViolet.withOpacity(0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: AppColors.electricCyan.withOpacity(0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
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
                                  Text(
                                    'Paatu Padava',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: AppColors.electricCyan,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Lossless Studio & YouTube Stream',
                                        style: GoogleFonts.outfit(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
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
                                          color: isUser ? AppColors.neonViolet : Colors.white24,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: isUser ? AppColors.neonViolet : AppColors.surfaceElevated,
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
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: ValueListenableBuilder<AuthUser?>(
                        valueListenable: AuthManager.authNotifier,
                        builder: (context, user, _) {
                          final name = (user != null && !user.isGuest && user.username.isNotEmpty)
                              ? user.username
                              : 'Music Lover';
                          return Text(
                            '${_getGreeting()}, $name',
                            style: GoogleFonts.outfit(
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

                  // Quick Shortcuts 2x2 Grid (Neon Violet & Cyan Theme)
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
                                  iconColor: Colors.white,
                                  gradient: const [AppColors.deepPurple, AppColors.neonViolet],
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
                                  title: 'Recently Played',
                                  icon: Icons.history_rounded,
                                  iconColor: Colors.white,
                                  gradient: const [Color(0xFF0E7490), AppColors.electricCyan],
                                  onTap: () {
                                    // CRITICAL FIX: Push to HistoryScreen() instead of auto-playing track
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
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
                                  title: 'Made For You',
                                  icon: Icons.auto_awesome_rounded,
                                  iconColor: Colors.white,
                                  gradient: const [Color(0xFF7C3AED), Color(0xFF06B6D4)],
                                  onTap: () {
                                    if (feedState.madeForYou.isNotEmpty) {
                                      audioHandler.playSong(feedState.madeForYou.first, queue: feedState.madeForYou);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Building your recommendation mix...')),
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildShortcutTile(
                                  title: 'Import Spotify',
                                  icon: Icons.album_rounded,
                                  iconColor: Colors.white,
                                  gradient: const [Color(0xFF4C1D95), AppColors.deepPurple],
                                  onTap: () => SpotifyImportDialog.show(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Language Chips Bar
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
                          final isSelected = lang.toLowerCase() == currentLang.toLowerCase();
                          return ChoiceChip(
                            label: Text(lang),
                            selected: isSelected,
                            selectedColor: AppColors.neonViolet,
                            backgroundColor: AppColors.surfaceElevated,
                            labelStyle: GoogleFonts.outfit(
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? AppColors.neonViolet : AppColors.surfaceBorder,
                              ),
                            ),
                            onSelected: (_) => feedProvider.setLanguage(lang),
                          );
                        },
                      ),
                    ),
                  ),

                  // Loading State Indicator
                  if (feedState.isLoading)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.neonViolet),
                      ),
                    )
                  else ...[
                    // "Jump Back In" (Recent History Carousel if available)
                    ValueListenableBuilder<List<Song>>(
                      valueListenable: HistoryManager.historyNotifier,
                      builder: (context, recentSongs, _) {
                        final displayHistory = recentSongs.isNotEmpty ? recentSongs : feedState.recentHistory;
                        if (displayHistory.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

                        return SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.history_rounded, color: AppColors.electricCyan, size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Jump Back In',
                                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    TextButton(
                                      child: Text(
                                        'See All',
                                        style: GoogleFonts.outfit(color: AppColors.electricCyan, fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const HistoryScreen()),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 190,
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

                    // "Made For You" (User taste / history-based mix)
                    if (feedState.madeForYou.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome_rounded, color: AppColors.neonViolet, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Made For You',
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              TextButton(
                                child: Text('Play All', style: GoogleFonts.outfit(color: AppColors.neonViolet, fontWeight: FontWeight.bold)),
                                onPressed: () => audioHandler.playSong(feedState.madeForYou.first, queue: feedState.madeForYou),
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
                            itemCount: feedState.madeForYou.length,
                            itemBuilder: (context, index) {
                              final song = feedState.madeForYou[index];
                              return _SongCard(
                                song: song,
                                onTap: () => audioHandler.playSong(song, queue: feedState.madeForYou),
                              );
                            },
                          ),
                        ),
                      ),
                    ],

                    // "Trending Across JioSaavn & YouTube" Carousel
                    if (feedState.trendingMerged.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.local_fire_department_rounded, color: AppColors.electricCyan, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Trending Across JioSaavn & YouTube',
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              TextButton(
                                child: Text('Play All', style: GoogleFonts.outfit(color: AppColors.electricCyan, fontWeight: FontWeight.bold)),
                                onPressed: () => audioHandler.playSong(feedState.trendingMerged.first, queue: feedState.trendingMerged),
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
                            itemCount: feedState.trendingMerged.length,
                            itemBuilder: (context, index) {
                              final song = feedState.trendingMerged[index];
                              return _SongCard(
                                song: song,
                                onTap: () => audioHandler.playSong(song, queue: feedState.trendingMerged),
                              );
                            },
                          ),
                        ),
                      ),
                    ],

                    // "Popular Artists" (High-Res Verified Avatars)
                    if (feedState.popularArtists.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                          child: Text(
                            'Popular Artists',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 115,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            scrollDirection: Axis.horizontal,
                            itemCount: feedState.popularArtists.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 16),
                            itemBuilder: (context, index) {
                              final art = feedState.popularArtists[index];
                              final name = _unescape.convert(Song.sanitize(art['name']?.toString() ?? 'Artist'));
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
                                    Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.neonViolet.withOpacity(0.4),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 34,
                                        backgroundColor: AppColors.surfaceElevated,
                                        backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: 76,
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
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

                    // "New Releases" Carousel
                    if (feedState.newReleases.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.new_releases_rounded, color: AppColors.neonViolet, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    'New $currentLang Releases',
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              TextButton(
                                child: Text('Play All', style: GoogleFonts.outfit(color: AppColors.neonViolet, fontWeight: FontWeight.bold)),
                                onPressed: () => audioHandler.playSong(feedState.newReleases.first, queue: feedState.newReleases),
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
                            itemCount: feedState.newReleases.length,
                            itemBuilder: (context, index) {
                              final song = feedState.newReleases[index];
                              return _SongCard(
                                song: song,
                                onTap: () => audioHandler.playSong(song, queue: feedState.newReleases),
                              );
                            },
                          ),
                        ),
                      ),
                    ],

                    // "Featured Albums"
                    if (feedState.featuredAlbums.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                          child: Text(
                            'Featured Albums',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 180,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: feedState.featuredAlbums.length,
                            itemBuilder: (context, index) {
                              final album = feedState.featuredAlbums[index];
                              final id = album['id']?.toString() ?? '';
                              final title = _unescape.convert(Song.sanitize(album['title']?.toString() ?? 'Album'));
                              final img = album['image']?.toString() ?? '';
                              final artist = _unescape.convert(Song.sanitize(album['artist']?.toString() ?? ''));

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
                                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11),
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

                    // Bottom Feed: Trending Tracks List
                    if (feedState.trendingMerged.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: Text(
                            'Popular Hits in $currentLang',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final song = feedState.trendingMerged[index];
                            return _SongTile(
                              song: song,
                              onTap: () => audioHandler.playSong(song, queue: feedState.trendingMerged),
                            );
                          },
                          childCount: feedState.trendingMerged.length > 20 ? 20 : feedState.trendingMerged.length,
                        ),
                      ),
                    ],
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

void _showSongContextMenu(BuildContext context, Song song) {
  final unescape = HtmlUnescape();
  final cleanTitle = unescape.convert(Song.sanitize(song.title));

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded, color: AppColors.neonViolet),
            title: const Text('Play Next', style: TextStyle(color: Colors.white)),
            onTap: () {
              audioHandler.insertNext(song);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Playing "$cleanTitle" next')),
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
                SnackBar(content: Text('Added "$cleanTitle" to queue')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded, color: AppColors.electricCyan),
            title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              AddToPlaylistDialog.show(context, song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded, color: AppColors.electricCyan),
            title: const Text('Download Offline', style: TextStyle(color: Colors.white)),
            onTap: () {
              DownloadManager.downloadSong(song);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border_rounded, color: AppColors.neonViolet),
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
  static final HtmlUnescape _unescape = HtmlUnescape();

  const _SongCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cleanTitle = _unescape.convert(Song.sanitize(song.title));
    final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

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
                      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: AppColors.neonGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonViolet.withOpacity(0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              cleanTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              cleanArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11),
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
  static final HtmlUnescape _unescape = HtmlUnescape();

  const _SongTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cleanTitle = _unescape.convert(Song.sanitize(song.title));
    final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

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
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                  ),
                ),
              ),
              if (isPlaying)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.equalizer_rounded, color: AppColors.electricCyan, size: 24),
                ),
            ],
          ),
          title: Text(
            cleanTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: isPlaying ? AppColors.neonViolet : Colors.white,
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: song.source == 'youtube'
                      ? AppColors.electricCyan.withOpacity(0.2)
                      : AppColors.neonViolet.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  song.source == 'youtube' ? 'YT' : '320K',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: song.source == 'youtube' ? AppColors.electricCyan : AppColors.neonViolet,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  cleanArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
            onPressed: () => _showSongContextMenu(context, song),
          ),
        );
      },
    );
  }
}
