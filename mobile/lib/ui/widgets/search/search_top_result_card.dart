import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';

class SearchTopResultCard extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final Map<String, dynamic> top;
  final VoidCallback onArtistClick;
  final VoidCallback onPlay;

  const SearchTopResultCard({
    super.key,
    required this.top,
    required this.onArtistClick,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final type = top['type']?.toString() ?? 'song';
    final title = _unescape.convert(Song.sanitize(top['title']?.toString() ?? top['name']?.toString() ?? ''));
    final artist = _unescape.convert(Song.sanitize(top['artist']?.toString() ?? top['subtitle']?.toString() ?? ''));
    final cover = top['cover_url']?.toString() ?? top['image']?.toString() ?? '';
    final isArtist = type.toLowerCase() == 'artist';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceBorderHighlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(isArtist ? 38 : 12),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                          memCacheHeight: 240,
                          errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
                        )
                      : Container(
                          color: AppColors.surfaceDark,
                          child: Icon(
                            isArtist ? Icons.person : Icons.music_note,
                            color: Colors.white38,
                            size: 32,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.neonViolet.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isArtist ? 'ARTIST' : 'TOP RESULT',
                        style: GoogleFonts.outfit(
                          color: AppColors.neonViolet,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (artist.isNotEmpty && !isArtist)
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: isArtist
                ? ElevatedButton.icon(
                    onPressed: onArtistClick,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonViolet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: Text('View Artist', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  )
                : FloatingActionButton.small(
                    heroTag: 'top_result_play',
                    backgroundColor: AppColors.neonViolet,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    onPressed: onPlay,
                    child: const Icon(Icons.play_arrow_rounded, size: 28),
                  ),
          ),
        ],
      ),
    );
  }
}
