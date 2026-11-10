import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';
import '../../screens/artist_screen.dart';

/// Horizontal carousel displaying verified popular artists on HomeScreen.
class HomePopularArtists extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();
  final List<Map<String, dynamic>> artists;

  const HomePopularArtists({super.key, required this.artists});

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            'Popular Artists',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 115,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: artists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final art = artists[index];
              final name = _unescape.convert(Song.sanitize(art['name']?.toString() ?? 'Artist'));
              final img = art['image']?.toString() ?? '';
              final id = art['id']?.toString() ?? '';

              return GestureDetector(
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
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.neonViolet.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: ClipOval(
                        child: SizedBox(
                          width: 68,
                          height: 68,
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
                    SizedBox(
                      width: 76,
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
              );
            },
          ),
        ),
      ],
    );
  }
}
