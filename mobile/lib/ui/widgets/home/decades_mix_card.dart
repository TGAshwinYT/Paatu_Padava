import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../domain/models/home_feed_models.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';

/// Decades & Golden Era Mix Card with retro gradient and 1-tap play.
class DecadesMixCard extends StatelessWidget {
  final DecadeMix mix;
  final double width;

  const DecadesMixCard({
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
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: width,
                    height: width,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: mix.gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: mix.coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: mix.coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 260,
                            memCacheHeight: 260,
                            placeholder: (_, __) => Container(
                              color: AppColors.surfaceElevated,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceElevated,
                            ),
                          )
                        : null,
                  ),
                ),

                // Dark vignette overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),

                // Retro Era Badge
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: Text(
                      mix.decade.toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),

                // Floating circular Play Button
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _onPlayTapped,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.electricCyan,
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

            // Era Title
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

            // Subtitle
            Text(
              mix.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
