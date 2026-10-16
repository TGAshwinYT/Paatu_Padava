import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../domain/models/home_feed_models.dart';
import '../../../services/player_handler.dart';
import '../../../services/settings_manager.dart';
import '../../theme/app_theme.dart';
import '../../../models/song.dart';

class NumberedChartView extends StatelessWidget {
  final List<RankedChartSong> charts;

  const NumberedChartView({
    Key? key,
    required this.charts,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (charts.isEmpty) return const SizedBox.shrink();

    final layout = SettingsManager.homeTop10ChartLayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.leaderboard_rounded, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Top 10 Official Charts',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        'Ranked live based on regional streams',
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
                onPressed: () {
                  final songs = charts.map((c) => c.song).toList();
                  audioHandler.playSong(songs.first, queue: songs);
                },
                child: Text(
                  'Play All',
                  style: GoogleFonts.outfit(
                    color: AppColors.electricCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (layout == 'horizontal')
          _buildHorizontalSlider(context)
        else
          _buildVerticalList(context),
      ],
    );
  }

  Widget _buildVerticalList(BuildContext context) {
    final songs = charts.map((c) => c.song).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: charts.map((chartItem) {
          return _buildChartRow(context, chartItem, songs);
        }).toList(),
      ),
    );
  }

  Widget _buildChartRow(BuildContext context, RankedChartSong item, List<Song> queue) {
    final song = item.song;
    final rank = item.rank;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rank == 1
              ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
          width: rank == 1 ? 1.2 : 0.8,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => audioHandler.playSong(song, queue: queue),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Rank number & movement badge
                SizedBox(
                  width: 38,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '#$rank',
                        style: GoogleFonts.outfit(
                          color: _getRankColor(rank),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      _buildRankChangeBadge(item),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Album Art
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: song.coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: song.coverUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceElevated,
                              child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 22),
                            ),
                          )
                        : Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 22),
                          ),
                  ),
                ),

                const SizedBox(width: 12),

                // Title & Artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Play action icon
                IconButton(
                  icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.neonViolet, size: 30),
                  onPressed: () => audioHandler.playSong(song, queue: queue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalSlider(BuildContext context) {
    final songs = charts.map((c) => c.song).toList();

    return SizedBox(
      height: 210,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: charts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = charts[index];
          final song = item.song;
          final rank = item.rank;

          return GestureDetector(
            onTap: () => audioHandler.playSong(song, queue: songs),
            child: Container(
              width: 140,
              decoration: BoxDecoration(
                color: const Color(0xFF131B2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: rank == 1
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: song.coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: song.coverUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                                )
                              : Container(color: AppColors.surfaceElevated),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _getRankColor(rank).withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '#$rank',
                            style: GoogleFonts.outfit(
                              color: _getRankColor(rank),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getRankColor(int rank) {
    if (rank == 1) return const Color(0xFFF59E0B); // Gold
    if (rank == 2) return const Color(0xFF38BDF8); // Cyan Silver
    if (rank == 3) return const Color(0xFFA855F7); // Violet Bronze
    return Colors.white70;
  }

  Widget _buildRankChangeBadge(RankedChartSong item) {
    if (item.isNew) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'NEW',
          style: GoogleFonts.outfit(
            color: const Color(0xFF10B981),
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    if (item.rankChange > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_drop_up_rounded, color: Color(0xFF10B981), size: 14),
          Text(
            '+${item.rankChange}',
            style: GoogleFonts.outfit(
              color: const Color(0xFF10B981),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    } else if (item.rankChange < 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFFEF4444), size: 14),
          Text(
            '${item.rankChange}',
            style: GoogleFonts.outfit(
              color: const Color(0xFFEF4444),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    } else {
      return const Text(
        '—',
        style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
      );
    }
  }
}
