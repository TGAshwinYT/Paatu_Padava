import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';
import 'home_song_card.dart';

/// Reusable, highly responsive horizontal song carousel shelf for HomeScreen.
/// Standardizes title typography, card sizing, horizontal snap physics,
/// and instant 1-tap playback across all home feed sections.
class HomeSongShelf extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badgeText;
  final Color? badgeColor;
  final IconData icon;
  final Color iconColor;
  final List<Song> songs;
  final double cardWidth;
  final double carouselHeight;
  final VoidCallback? onPlayAll;
  final VoidCallback? onSeeAll;

  const HomeSongShelf({
    super.key,
    required this.title,
    this.subtitle,
    this.badgeText,
    this.badgeColor,
    required this.icon,
    this.iconColor = AppColors.neonViolet,
    required this.songs,
    required this.cardWidth,
    required this.carouselHeight,
    this.onPlayAll,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    final screenPadding = AppDimensions.screenPadding(context);
    final textScaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25);
    final effectiveBadgeColor = badgeColor ?? iconColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shelf Header: Bloomee Icon Container + Title + Subtitle/Badge + Action Button
        Padding(
          padding: EdgeInsets.fromLTRB(screenPadding, 18, screenPadding, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    // Bloomee-Style Tinted Icon Container
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(icon, color: iconColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: textScaler,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              if (badgeText != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: effectiveBadgeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: effectiveBadgeColor.withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    badgeText!,
                                    style: GoogleFonts.outfit(
                                      color: effectiveBadgeColor,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onPlayAll != null)
                TextButton(
                  onPressed: onPlayAll,
                  style: TextButton.styleFrom(
                    foregroundColor: iconColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Play All',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                )
              else if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: iconColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'See All',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),

        // Horizontal Carousel with RepaintBoundary
        SizedBox(
          height: carouselHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 280.0,
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return RepaintBoundary(
                key: ValueKey(song.id),
                child: HomeSongCard(
                  song: song,
                  width: cardWidth,
                  onTap: () => audioHandler.playSong(song, queue: songs),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
