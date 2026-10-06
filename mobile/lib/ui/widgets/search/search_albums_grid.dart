import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';
import '../../screens/album_screen.dart';

class SearchAlbumsGrid extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final List<Map<String, dynamic>> albums;
  final String query;
  final VoidCallback onRecordClick;

  const SearchAlbumsGrid({
    super.key,
    required this.albums,
    required this.query,
    required this.onRecordClick,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          'No albums found for "$query"',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final id = album['id']?.toString() ?? '';
        final title = _unescape.convert(Song.sanitize(album['title']?.toString() ?? ''));
        final artist = _unescape.convert(Song.sanitize(album['artist']?.toString() ?? ''));
        final img = album['image']?.toString() ?? '';

        return GestureDetector(
          onTap: () {
            onRecordClick();
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
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: img,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (album['type'] == 'Single' || album['is_single'] == true)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.electricCyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'SINGLE',
                          style: GoogleFonts.outfit(
                            color: AppColors.electricCyan,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
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
    );
  }
}
