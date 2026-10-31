import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../services/search_history_manager.dart';
import '../../theme/app_theme.dart';
import '../spotify_import_dialog.dart';

class SearchPreContent extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final List<String> trendingArtists;
  final List<Map<String, dynamic>> browseCategories;
  final ValueChanged<String> onSelectQuery;
  final ValueChanged<String>? onSelectExactQuery;
  final void Function(Song song) onPlaySong;

  const SearchPreContent({
    super.key,
    required this.trendingArtists,
    required this.browseCategories,
    required this.onSelectQuery,
    this.onSelectExactQuery,
    required this.onPlaySong,
  });

  static const List<Map<String, dynamic>> _quickVibes = [
    {
      'title': '90s Melody',
      'query': '90s Tamil Melody Hits',
      'colors': [Color(0xFF0F766E), Color(0xFF14B8A6)],
      'icon': Icons.radio_rounded,
    },
    {
      'title': 'Anirudh Vibe',
      'query': 'Anirudh Ravichander Vibe Hits',
      'colors': [Color(0xFF7C3AED), Color(0xFFC026D3)],
      'icon': Icons.bolt_rounded,
    },
    {
      'title': 'Late Night Lo-Fi',
      'query': 'Late Night Lofi Chill Tamil',
      'colors': [Color(0xFF312E81), Color(0xFF6366F1)],
      'icon': Icons.nightlight_round,
    },
    {
      'title': 'Workout Kuthu',
      'query': 'High Energy Tamil Kuthu Bass',
      'colors': [Color(0xFFC2410C), Color(0xFFF97316)],
      'icon': Icons.fitness_center_rounded,
    },
    {
      'title': 'Instrumental / BGM',
      'query': 'Tamil Cinematic BGM Instrumental',
      'colors': [Color(0xFF0284C7), Color(0xFF06B6D4)],
      'icon': Icons.piano_rounded,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        // 1. Spotify Import Quick Action
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceBorderHighlight),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.neonViolet.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.album_rounded, color: AppColors.neonViolet, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Paste Spotify Link to Import',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                onPressed: () => SpotifyImportDialog.show(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonViolet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(48, 36),
                ),
                child: Text('Import', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),

        // 2. State A Instant Recall Chips (Last 8 searches: tap-to-fill, long-press-to-delete)
        ValueListenableBuilder<List<String>>(
          valueListenable: SearchHistoryManager.historyNotifier,
          builder: (context, recentQueries, _) {
            if (recentQueries.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Searches',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: () => SearchHistoryManager.clearAll(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(48, 32),
                      ),
                      child: Text('Clear', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recentQueries.length > 8 ? 8 : recentQueries.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final q = recentQueries[index];
                      final cleanDisplay = _unescape.convert(Song.sanitize(q));

                      return GestureDetector(
                        onLongPress: () {
                          HapticFeedback.lightImpact();
                          SearchHistoryManager.removeQuery(q);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              duration: const Duration(milliseconds: 1200),
                              backgroundColor: AppColors.surfaceElevated,
                              content: Text('Removed "$cleanDisplay" from history', style: const TextStyle(fontSize: 12)),
                            ),
                          );
                        },
                        child: ActionChip(
                          backgroundColor: AppColors.surfaceElevated,
                          avatar: const Icon(Icons.history_rounded, size: 14, color: AppColors.textSecondary),
                          label: Text(cleanDisplay, style: GoogleFonts.outfit(color: Colors.white, fontSize: 12)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: AppColors.surfaceBorder),
                          ),
                          onPressed: () => (onSelectExactQuery ?? onSelectQuery)(q),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
            );
          },
        ),

        // 3. Quick Vibe / Era Collections (Functional starting points)
        Text(
          'Quick Vibes & Eras',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 85,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _quickVibes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final vibe = _quickVibes[i];
              final colors = vibe['colors'] as List<Color>;

              return InkWell(
                onTap: () => onSelectQuery(vibe['query'] as String),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: colors.first.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          vibe['title'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Icon(
                          vibe['icon'] as IconData,
                          size: 32,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        // 4. Recently Played / Searched Songs
        ValueListenableBuilder<List<Song>>(
          valueListenable: SearchHistoryManager.recentSongsNotifier,
          builder: (context, recentSongs, _) {
            if (recentSongs.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recently Played',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...recentSongs.take(6).map((song) {
                  final cleanTitle = _unescape.convert(Song.sanitize(song.title));
                  final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                    ),
                    child: ListTile(
                      dense: true,
                      onTap: () => onPlaySong(song),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: CachedNetworkImage(
                            imageUrl: song.coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 120,
                            memCacheHeight: 120,
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceDark,
                              child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 20),
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        cleanTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        cleanArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11),
                      ),
                      trailing: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white38),
                          tooltip: 'Remove from history',
                          onPressed: () => SearchHistoryManager.removeSong(song.id),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],
            );
          },
        ),

        // 5. Trending Artists
        Text(
          'Trending Artists',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: trendingArtists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final artist = trendingArtists[i];
              return ActionChip(
                backgroundColor: AppColors.surfaceElevated,
                avatar: const Icon(Icons.person_rounded, size: 15, color: AppColors.electricCyan),
                label: Text(artist, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.surfaceBorder),
                ),
                onPressed: () => (onSelectExactQuery ?? onSelectQuery)(artist),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // 6. Browse All Category Tiles
        Text(
          'Browse All',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.7,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: browseCategories.length,
          itemBuilder: (context, index) {
            final cat = browseCategories[index];
            final colors = cat['colors'] as List<Color>;

            return InkWell(
              onTap: () => onSelectQuery(cat['query'] as String),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: colors.first.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        cat['title'] as String,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Transform.rotate(
                        angle: 0.25,
                        child: Icon(
                          cat['icon'] as IconData,
                          size: 44,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 120),
      ],
    );
  }
}
