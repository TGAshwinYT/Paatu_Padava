import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/auth_manager.dart';
import '../../services/history_manager.dart';
import '../../logic/home_feed_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/sync_status_indicator.dart';
import '../widgets/account_bar_button.dart';
import '../widgets/home/home_song_card.dart';
import '../widgets/home/home_song_tile.dart';
import '../widgets/home/guest_mode_banner.dart';
import '../widgets/home/home_error_view.dart';
import '../widgets/home/home_shortcut_tile.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'settings_screen.dart';
import 'liked_songs_screen.dart';
import 'history_screen.dart';
import '../../services/settings_manager.dart';
import '../widgets/home/feeling_chips_bar.dart';
import '../widgets/home/top_hits_hero_card.dart';
import '../widgets/home/numbered_chart_view.dart';
import '../widgets/home/quick_picks_grid_carousel.dart';
import '../widgets/home/mood_station_card.dart';

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
            final screenWidth = MediaQuery.of(context).size.width;
            final cardWidth = (screenWidth * 0.36).clamp(130.0, 180.0);
            final carouselHeight = cardWidth + 58.0;

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
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.neonViolet.withValues(alpha: 0.4),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                      BoxShadow(
                                        color: AppColors.electricCyan.withValues(alpha: 0.2),
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
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Paatu Padava',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 20,
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
                                          Flexible(
                                            child: Text(
                                              'Lossless Studio & YouTube Stream',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.outfit(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Action icons: Cloud Sync + Settings + Account Profile
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SyncStatusIndicator(),
                              const SizedBox(width: 2),
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                padding: const EdgeInsets.all(6),
                                icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
                                tooltip: 'Settings & Equalizer',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                                  );
                                },
                              ),
                              const SizedBox(width: 2),
                              const AccountBarButton(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Persistent Guest Mode Banner for Home Screen
                  SliverToBoxAdapter(
                    child: ValueListenableBuilder<AuthUser?>(
                      valueListenable: AuthManager.authNotifier,
                      builder: (context, user, _) {
                        if (user == null || user.isGuest) {
                          return const GuestModeBanner();
                        }
                        return const SizedBox.shrink();
                      },
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

                  // YouTube Music Style Feeling & Activity Chips Bar
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 6, bottom: 4),
                      child: FeelingChipsBar(),
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
                                child: HomeShortcutTile(
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
                                child: HomeShortcutTile(
                                  title: 'Recently Played',
                                  icon: Icons.history_rounded,
                                  iconColor: Colors.white,
                                  gradient: const [Color(0xFF0E7490), AppColors.electricCyan],
                                  onTap: () {
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
                                child: HomeShortcutTile(
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
                                child: HomeShortcutTile(
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

                  // 3-Tier Loading State Machine: LoadingSkeleton -> PartialSuccess -> FullSuccess
                  if (feedState.isLoading && feedState.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.neonViolet),
                      ),
                    )
                  else if (feedState.appError != null && feedState.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: HomeErrorView(
                        error: feedState.appError!,
                        onRetry: () => HomeFeedProvider.instance.loadFeed(forceRefresh: true),
                      ),
                    )
                  else ...[
                    // Flagship Spotify-Style Editorial Showcase Hero Banner
                    if (feedState.heroShowcase != null && feedState.heroShowcase!.tracks.isNotEmpty)
                      SliverToBoxAdapter(
                        child: TopHitsHeroCard(showcase: feedState.heroShowcase!),
                      ),

                    // Active Mood / Feeling Focused Section (if user chose a mood other than 'all')
                    if (feedState.activeFeeling != 'all') ...[
                      () {
                        final activeMix = feedState.feelingMixes
                            .where((m) => m.feelingId == feedState.activeFeeling)
                            .firstOrNull;
                        if (activeMix == null || activeMix.songs.isEmpty) {
                          return const SliverToBoxAdapter(child: SizedBox.shrink());
                        }
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
                                        Text(activeMix.icon, style: const TextStyle(fontSize: 20)),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              activeMix.title,
                                              style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.4,
                                              ),
                                            ),
                                            Text(
                                              activeMix.subtitle,
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
                                    TextButton(
                                      child: Text(
                                        'Play Mix',
                                        style: GoogleFonts.outfit(
                                          color: AppColors.electricCyan,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: () => audioHandler.playSong(activeMix.songs.first, queue: activeMix.songs),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: carouselHeight,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  scrollDirection: Axis.horizontal,
                                  itemCount: activeMix.songs.length,
                                  itemBuilder: (context, index) {
                                    final song = activeMix.songs[index];
                                    return HomeSongCard(
                                      song: song,
                                      width: cardWidth,
                                      onTap: () => audioHandler.playSong(song, queue: activeMix.songs),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }(),
                    ],

                    // Spotify & Billboard Style Top 10 Official Ranked Charts
                    if (feedState.top10Charts.isNotEmpty)
                      SliverToBoxAdapter(
                        child: NumberedChartView(charts: feedState.top10Charts),
                      ),

                    // YouTube Music Style Quick Picks 4-Row Column Grid
                    if (SettingsManager.isHomeShowQuickPicksEnabled && feedState.quickPicks.isNotEmpty)
                      SliverToBoxAdapter(
                        child: QuickPicksGridCarousel(songs: feedState.quickPicks),
                      ),

                    // Apple Music Style Mood & Activity Stations Carousel
                    if (feedState.feelingMixes.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.radio_rounded, color: Colors.white, size: 16),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Mood & Activity Stations',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  Text(
                                    'Curated soundscapes for any moment',
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
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 140,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: feedState.feelingMixes.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final mix = feedState.feelingMixes[index];
                              return MoodStationCard(mix: mix);
                            },
                          ),
                        ),
                      ),
                    ],
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
                                height: carouselHeight,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  scrollDirection: Axis.horizontal,
                                  itemCount: displayHistory.length,
                                  itemBuilder: (context, index) {
                                    final song = displayHistory[index];
                                    return HomeSongCard(
                                      song: song,
                                      width: cardWidth,
                                      onTap: () => audioHandler.playSong(song),
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
                          height: carouselHeight,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: feedState.madeForYou.length,
                            itemBuilder: (context, index) {
                              final song = feedState.madeForYou[index];
                              return HomeSongCard(
                                song: song,
                                width: cardWidth,
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
                          height: carouselHeight,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: feedState.trendingMerged.length,
                            itemBuilder: (context, index) {
                              final song = feedState.trendingMerged[index];
                              return HomeSongCard(
                                song: song,
                                width: cardWidth,
                                onTap: () => audioHandler.playSong(song, queue: feedState.trendingMerged),
                              );
                            },
                          ),
                        ),
                      ),
                    ],

                    // "YouTube Music Trending" Carousel
                    if (feedState.youtubeTrending.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.play_circle_filled_rounded, color: Color(0xFFFF0033), size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    'YouTube Music Trending',
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              TextButton(
                                child: Text('Play All', style: GoogleFonts.outfit(color: const Color(0xFFFF0033), fontWeight: FontWeight.bold)),
                                onPressed: () => audioHandler.playSong(feedState.youtubeTrending.first, queue: feedState.youtubeTrending),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: carouselHeight,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: feedState.youtubeTrending.length,
                            itemBuilder: (context, index) {
                              final song = feedState.youtubeTrending[index];
                              return HomeSongCard(
                                song: song,
                                width: cardWidth,
                                onTap: () => audioHandler.playSong(song, queue: feedState.youtubeTrending),
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
                                          color: AppColors.neonViolet.withValues(alpha: 0.4),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 34,
                                        backgroundColor: AppColors.surfaceElevated,
                                        backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                                        child: img.isEmpty
                                            ? const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 28)
                                            : null,
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
                          height: carouselHeight,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: feedState.newReleases.length,
                            itemBuilder: (context, index) {
                              final song = feedState.newReleases[index];
                              return HomeSongCard(
                                song: song,
                                width: cardWidth,
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
                          height: carouselHeight,
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
                                  width: cardWidth,
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: SizedBox(
                                          width: cardWidth,
                                          height: cardWidth,
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
                            return HomeSongTile(
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
