import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';
import '../../screens/artist_screen.dart';

/// Horizontal carousel displaying verified popular artists on HomeScreen.
class HomePopularArtists extends StatelessWidget {
  final List<Map<String, dynamic>> artists;

  const HomePopularArtists({super.key, required this.artists});

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(AppDimensions.screenPadding(context), 20, AppDimensions.screenPadding(context), 10),
          child: Text(
            'Popular Artists',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        () {
          final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);
          final avatarSize = AppDimensions.isCompact(context) ? 62.0 : 68.0;
          final cardWidth = avatarSize + 16.0;
          final totalHeight = avatarSize + 8.0 + (18.0 * textScale) + 6.0;
          return SizedBox(
            height: totalHeight,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: AppDimensions.screenPadding(context)),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final art = artists[index];
                final name = Song.sanitize(art['name']?.toString() ?? 'Artist');
                final img = art['image']?.toString() ?? '';
                final id = art['id']?.toString() ?? '';

                return GestureDetector(
                  key: ValueKey(id.isNotEmpty ? id : '$name-$index'),
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
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.neonViolet.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: ClipOval(
                            child: SizedBox(
                              width: avatarSize,
                              height: avatarSize,
                              child: img.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: img,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 200,
                                      memCacheHeight: 200,
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppColors.surfaceElevated,
                                        child: const Center(
                                          child: Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 28),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: AppColors.surfaceElevated,
                                      child: const Center(
                                        child: Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 28),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
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
                  ),
                );
              },
            ),
          );
        }(),
      ],
    );
  }
}
