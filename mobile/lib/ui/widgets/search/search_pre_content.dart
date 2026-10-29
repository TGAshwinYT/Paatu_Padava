import 'package:flutter/material.dart';
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
  final void Function(Song song) onPlaySong;

  const SearchPreContent({
    super.key,
    required this.trendingArtists,
    required this.browseCategories,
    required this.onSelectQuery,
    required this.onPlaySong,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        // Spotify Import Quick Action
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
                  'Paste a Spotify Link to Import',
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
                  minimumSize: Size.zero,
                ),
                child: Text('Import', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),

        // Recent Searched Songs (Spotify & Apple Music style)
        ValueListenableBuilder<List<Song>>(
          valueListenable: SearchHistoryManager.recentSongsNotifier,
          builder: (context, recentSongs, _) {
            return ValueListenableBuilder<List<String>>(
              valueListenable: SearchHistoryManager.historyNotifier,
              builder: (context, recentQueries, _) {
                final hasSongs = recentSongs.isNotEmpty;
                final hasQueries = recentQueries.isNotEmpty;
                if (!hasSongs && !hasQueries) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Searches',
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          child: Text('Clear All', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                          onPressed: () => SearchHistoryManager.clearAll(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Recent Songs Tiles
                    if (hasSongs)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: recentSongs.length > 8 ? 8 : recentSongs.length,
                        itemBuilder: (context, index) {
                          final song = recentSongs[index];
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
                                  child: song.coverUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: song.coverUrl,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 150,
                                          memCacheHeight: 150,
                                          errorWidget: (_, __, ___) => Container(
                                            color: AppColors.surfaceDark,
                                            child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 20),
                                          ),
                                        )
                                      : Container(
                                          color: AppColors.surfaceDark,
                                          child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 20),
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
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: song.source == 'youtube'
                                          ? AppColors.electricCyan.withValues(alpha: 0.2)
                                          : AppColors.neonViolet.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      song.source == 'youtube' ? 'YT' : '320K',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: song.source == 'youtube' ? AppColors.electricCyan : AppColors.neonViolet,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Song • $cleanArtist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11.5),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white38),
                                tooltip: 'Remove from history',
                                onPressed: () => SearchHistoryManager.removeSong(song.id),
                              ),
                            ),
                          );
                        },
                      ),

                    // Recent Queries Chips (if any exist)
                    if (hasQueries) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: recentQueries.take(6).map((q) {
                          final cleanDisplay = _unescape.convert(Song.sanitize(q));
                          return InputChip(
                            backgroundColor: AppColors.surfaceElevated,
                            avatar: const Icon(Icons.history_rounded, size: 14, color: AppColors.textSecondary),
                            label: Text(cleanDisplay, style: GoogleFonts.outfit(color: AppColors.textWhite, fontSize: 11.5)),
                            deleteIcon: const Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary),
                            onDeleted: () => SearchHistoryManager.removeQuery(q),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: AppColors.surfaceBorder),
                            ),
                            onPressed: () => onSelectQuery(q),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 22),
                  ],
                );
              },
            );
          },
        ),

        // Trending Artists
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
                onPressed: () => onSelectQuery(artist),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Browse All Category Tiles with Neon Theme Gradients
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
                          fontSize: 16,
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
