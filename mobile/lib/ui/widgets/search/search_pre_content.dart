import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  const SearchPreContent({
    super.key,
    required this.trendingArtists,
    required this.browseCategories,
    required this.onSelectQuery,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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

        // Recent Searches with strict deduplication & 12 item cap
        ValueListenableBuilder<List<String>>(
          valueListenable: SearchHistoryManager.historyNotifier,
          builder: (context, history, _) {
            if (history.isEmpty) return const SizedBox.shrink();

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
                      child: Text('Clear All', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                      onPressed: () => SearchHistoryManager.clearAll(),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: history.map((q) {
                    final cleanDisplay = _unescape.convert(Song.sanitize(q));
                    return InputChip(
                      backgroundColor: AppColors.surfaceElevated,
                      label: Text(cleanDisplay, style: GoogleFonts.outfit(color: AppColors.textWhite, fontSize: 12)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                      onDeleted: () => SearchHistoryManager.removeQuery(q),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.surfaceBorder),
                      ),
                      onPressed: () => onSelectQuery(q),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],
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
