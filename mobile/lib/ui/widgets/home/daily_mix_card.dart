import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../domain/models/home_feed_models.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';

/// Spotify-Style Daily Mix Card featuring colored accent stripes,
/// artist clustering subtitle, and instant floating play button.
class DailyMixCard extends StatelessWidget {
  final DailyMix mix;
  final double width;

  const DailyMixCard({
    super.key,
    required this.mix,
    this.width = 150,
  });

  void _onPlayTapped() {
    HapticFeedback.mediumImpact();
    if (mix.tracks.isNotEmpty) {
      audioHandler.playSong(mix.tracks.first, queue: mix.tracks);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onPlayTapped,
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork Container with accent bottom bar and play button
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: width,
                    height: width,
                    color: AppColors.surfaceElevated,
                    child: mix.coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: mix.coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 260,
                            memCacheHeight: 260,
                            placeholder: (_, __) => Container(
                              color: AppColors.surfaceElevated,
                              child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 36),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceElevated,
                              child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 36),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [mix.accentColor.withValues(alpha: 0.7), Colors.black87],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Icon(Icons.album_rounded, color: Colors.white38, size: 48),
                          ),
                  ),
                ),

                // Spotify-style Colored Accent Bottom Stripe
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: mix.accentColor,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      boxShadow: [
                        BoxShadow(
                          color: mix.accentColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                          offset: const Offset(0, -1),
                        ),
                      ],
                    ),
                  ),
                ),

                // Spotify-style Mix Badge in Top-Left
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: mix.accentColor.withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: mix.accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'MIX ${mix.index}',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Floating circular Play Button on Bottom Right
                Positioned(
                  right: 8,
                  bottom: 12,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _onPlayTapped,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: mix.accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Mix Title
            Text(
              mix.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),

            // Artist Cluster Subtitle
            Text(
              mix.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
