import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/auth_manager.dart';
import '../../services/history_manager.dart';
import '../../logic/home_feed_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/sync_status_indicator.dart';
import '../widgets/account_bar_button.dart';
import '../widgets/home/home_song_card.dart';
import '../widgets/home/guest_mode_banner.dart';
import '../widgets/home/home_error_view.dart';
import '../widgets/home/quick_grid_section.dart';
import '../widgets/home/home_category_pills.dart';
import '../widgets/home/home_song_shelf.dart';
import '../widgets/home/daily_mixes_shelf.dart';
import '../widgets/home/decades_mixes_shelf.dart';
import '../widgets/home/home_popular_artists.dart';
import '../widgets/home/home_featured_albums.dart';
import '../widgets/common/song_tile.dart';

import 'settings_screen.dart';
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
            final cardWidth = AppDimensions.homeCardWidth(context);
            final carouselHeight = AppDimensions.homeCarouselHeight(context, cardWidth);

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
                                tooltip: 'Settings',
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

                  // Dynamic Greeting
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
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

                  // Spotify-Style Top Category Filter Pills (All, Playlists, Made For You, Moods)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 6),
                      child: HomeCategoryPills(),
                    ),
                  ),

                  // Flagship Spotify-Style 2x3 Quick Tiles Grid with instant 1-tap playback
                  if (feedState.homeFilter == 'all' || feedState.homeFilter == 'for_you')
                    const SliverToBoxAdapter(
                      child: QuickGridSection(),
                    ),

                  // YouTube Music Style Feeling & Activity Chips Bar (shown when filtering by Moods)
                  if (feedState.homeFilter == 'moods')
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 6, bottom: 4),
                        child: FeelingChipsBar(),
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
                    // Spotify-Style Clustered Daily Mixes Carousel
                    if ((feedState.homeFilter == 'all' || feedState.homeFilter == 'playlists' || feedState.homeFilter == 'for_you') &&
                        feedState.dailyMixes.isNotEmpty)
                      SliverToBoxAdapter(
                        child: DailyMixesShelf(mixes: feedState.dailyMixes),
                      ),

                    // Decades & Golden Era Collections Carousel
                    if ((feedState.homeFilter == 'all' || feedState.homeFilter == 'playlists') &&
                        feedState.decadeMixes.isNotEmpty)
                      SliverToBoxAdapter(
                        child: DecadesMixesShelf(mixes: feedState.decadeMixes),
                      ),

                    // Flagship Spotify-Style Editorial Showcase Hero Banner
                    if (feedState.homeFilter == 'all' && feedState.heroShowcase != null && feedState.heroShowcase!.tracks.isNotEmpty)
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
                    if (feedState.homeFilter == 'all' && feedState.top10Charts.isNotEmpty)
                      SliverToBoxAdapter(
                        child: NumberedChartView(charts: feedState.top10Charts),
                      ),

                    // YouTube Music Style Quick Picks 4-Row Column Grid
                    if ((feedState.homeFilter == 'all' || feedState.homeFilter == 'for_you') &&
                        SettingsManager.isHomeShowQuickPicksEnabled &&
                        feedState.quickPicks.isNotEmpty)
                      SliverToBoxAdapter(
                        child: QuickPicksGridCarousel(songs: feedState.quickPicks),
                      ),

                    // Apple Music Style Mood & Activity Stations Carousel
                    if ((feedState.homeFilter == 'all' || feedState.homeFilter == 'moods') &&
                        feedState.feelingMixes.isNotEmpty) ...[
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
                    if (feedState.homeFilter == 'all' || feedState.homeFilter == 'for_you')
                      ValueListenableBuilder<List<Song>>(
                        valueListenable: HistoryManager.historyNotifier,
                        builder: (context, recentSongs, _) {
                          final displayHistory = recentSongs.isNotEmpty ? recentSongs : feedState.recentHistory;
                          if (displayHistory.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

                          return SliverToBoxAdapter(
                            child: HomeSongShelf(
                              title: 'Jump Back In',
                              icon: Icons.history_rounded,
                              iconColor: AppColors.electricCyan,
                              songs: displayHistory,
                              cardWidth: cardWidth,
                              carouselHeight: carouselHeight,
                              onSeeAll: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                                );
                              },
                            ),
                          );
                        },
                      ),

                    // "Made For You" (User taste / history-based mix)
                    if ((feedState.homeFilter == 'all' || feedState.homeFilter == 'for_you') &&
                        feedState.madeForYou.isNotEmpty)
                      SliverToBoxAdapter(
                        child: HomeSongShelf(
                          title: 'Made For You',
                          icon: Icons.auto_awesome_rounded,
                          iconColor: AppColors.neonViolet,
                          songs: feedState.madeForYou,
                          cardWidth: cardWidth,
                          carouselHeight: carouselHeight,
                          onPlayAll: () => audioHandler.playSong(feedState.madeForYou.first, queue: feedState.madeForYou),
                        ),
                      ),

                    // "Trending Across JioSaavn & YouTube" Carousel
                    if (feedState.homeFilter == 'all' && feedState.trendingMerged.isNotEmpty)
                      SliverToBoxAdapter(
                        child: HomeSongShelf(
                          title: 'Trending Across JioSaavn & YouTube',
                          icon: Icons.local_fire_department_rounded,
                          iconColor: AppColors.electricCyan,
                          songs: feedState.trendingMerged,
                          cardWidth: cardWidth,
                          carouselHeight: carouselHeight,
                          onPlayAll: () => audioHandler.playSong(feedState.trendingMerged.first, queue: feedState.trendingMerged),
                        ),
                      ),

                    // "YouTube Music Trending" Carousel
                    if (feedState.homeFilter == 'all' && feedState.youtubeTrending.isNotEmpty)
                      SliverToBoxAdapter(
                        child: HomeSongShelf(
                          title: 'YouTube Music Trending',
                          icon: Icons.play_circle_filled_rounded,
                          iconColor: const Color(0xFFFF0033),
                          songs: feedState.youtubeTrending,
                          cardWidth: cardWidth,
                          carouselHeight: carouselHeight,
                          onPlayAll: () => audioHandler.playSong(feedState.youtubeTrending.first, queue: feedState.youtubeTrending),
                        ),
                      ),

                    // "Popular Artists" (High-Res Verified Avatars)
                    if ((feedState.homeFilter == 'all' || feedState.homeFilter == 'playlists') &&
                        feedState.popularArtists.isNotEmpty)
                      SliverToBoxAdapter(
                        child: HomePopularArtists(artists: feedState.popularArtists),
                      ),

                    // "New Releases" Carousel
                    if ((feedState.homeFilter == 'all' || feedState.homeFilter == 'playlists') &&
                        feedState.newReleases.isNotEmpty)
                      SliverToBoxAdapter(
                        child: HomeSongShelf(
                          title: 'New $currentLang Releases',
                          icon: Icons.new_releases_rounded,
                          iconColor: AppColors.neonViolet,
                          songs: feedState.newReleases,
                          cardWidth: cardWidth,
                          carouselHeight: carouselHeight,
                          onPlayAll: () => audioHandler.playSong(feedState.newReleases.first, queue: feedState.newReleases),
                        ),
                      ),

                    // "Featured Albums"
                    if ((feedState.homeFilter == 'all' || feedState.homeFilter == 'playlists') &&
                        feedState.featuredAlbums.isNotEmpty)
                      SliverToBoxAdapter(
                        child: HomeFeaturedAlbums(
                          albums: feedState.featuredAlbums,
                          cardWidth: cardWidth,
                          carouselHeight: carouselHeight,
                        ),
                      ),

                    // Bottom Feed: Trending Tracks List
                    if (feedState.homeFilter == 'all' && feedState.trendingMerged.isNotEmpty) ...[
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
                            return SongTile(
                              song: song,
                              queue: feedState.trendingMerged,
                              index: index,
                              showRank: true,
                              playbackContext: PlaybackContext(
                                id: 'popular_hits',
                                title: 'Popular Hits in $currentLang',
                                type: 'trending',
                              ),
                            );
                          },
                          childCount: feedState.trendingMerged.length > 20 ? 20 : feedState.trendingMerged.length,
                        ),
                      ),
                    ],
                  ],

                  SliverToBoxAdapter(
                    child: SizedBox(height: AppDimensions.bottomClearance(context, hasBottomNav: true)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
