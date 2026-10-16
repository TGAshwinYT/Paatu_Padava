import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../domain/models/home_feed_models.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';

class TopHitsHeroCard extends StatelessWidget {
  final HeroShowcase showcase;

  const TopHitsHeroCard({
    Key? key,
    required this.showcase,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (showcase.tracks.isEmpty) return const SizedBox.shrink();

    final firstSong = showcase.tracks.first;
    final cover = showcase.coverUrl.isNotEmpty ? showcase.coverUrl : firstSong.coverUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GestureDetector(
        onTap: () {
          audioHandler.playSong(firstSong, queue: showcase.tracks);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: showcase.gradientColors.first.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // Dynamic gradient background
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: showcase.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),

                // Dark vignette overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.black.withValues(alpha: 0.3),
                          Colors.black.withValues(alpha: 0.65),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),

                // Subtle mesh overlay
                Positioned.fill(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),

                // Content Row
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      // Text Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Pill badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_rounded, color: AppColors.electricCyan, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'SPOTIFY EDITORIAL • TOP 50',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Main Title
                            Text(
                              showcase.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Subtitle
                            Text(
                              showcase.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Track Count & Master Badge
                            Row(
                              children: [
                                Text(
                                  '${showcase.tracks.length} tracks • Master Audio',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.electricCyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 14),

                      // Right side: Stacked cover with Floating Play Button
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 105,
                            height: 105,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: cover.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: cover,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppColors.surfaceElevated,
                                        child: const Icon(Icons.music_note_rounded, color: Colors.white54, size: 36),
                                      ),
                                    )
                                  : Container(
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(Icons.music_note_rounded, color: Colors.white54, size: 36),
                                    ),
                            ),
                          ),

                          // Play Button Overlay
                          Positioned(
                            bottom: -6,
                            right: -6,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [AppColors.electricCyan, AppColors.neonViolet],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.electricCyan.withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 24,
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
        ),
      ),
    );
  }
}
