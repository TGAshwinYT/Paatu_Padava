import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';
import '../../screens/album_screen.dart';

/// Horizontal carousel displaying featured studio albums on HomeScreen.
class HomeFeaturedAlbums extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();
  final List<Map<String, dynamic>> albums;
  final double cardWidth;
  final double carouselHeight;

  const HomeFeaturedAlbums({
    super.key,
    required this.albums,
    required this.cardWidth,
    required this.carouselHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Text(
            'Featured Albums',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: carouselHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              final id = album['id']?.toString() ?? '';
              final title = _unescape.convert(Song.sanitize(album['title']?.toString() ?? 'Album'));
              final img = album['image']?.toString() ?? '';
              final artist = _unescape.convert(Song.sanitize(album['artist']?.toString() ?? ''));

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlbumScreen(
                        albumId: id,
                        albumTitle: title,
                        imageUrl: img,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: cardWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: cardWidth,
                          height: cardWidth,
                          child: CachedNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            memCacheWidth: 300,
                            memCacheHeight: 300,
                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
