import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';
import '../../screens/artist_screen.dart';

class SearchArtistsList extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final List<Map<String, dynamic>> artists;
  final String query;
  final VoidCallback onRecordClick;

  const SearchArtistsList({
    super.key,
    required this.artists,
    required this.query,
    required this.onRecordClick,
  });

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return Center(
        child: Text(
          'No artists found for "$query"',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final art = artists[index];
        final id = art['id']?.toString() ?? '';
        final name = _unescape.convert(Song.sanitize(art['name']?.toString() ?? ''));
        final img = art['image']?.toString() ?? '';

        return ListTile(
          onTap: () {
            onRecordClick();
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.surfaceElevated,
            backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img, maxWidth: 150, maxHeight: 150) : null,
          ),
          title: Text(
            name,
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text('Artist', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
        );
      },
    );
  }
}
