import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';
import '../../screens/remote_playlist_screen.dart';

class SearchPlaylistsGrid extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final List<Map<String, dynamic>> playlists;
  final String query;
  final VoidCallback onRecordClick;
  final void Function(Map<String, dynamic> playlist)? onPlaylistTap;

  const SearchPlaylistsGrid({
    super.key,
    required this.playlists,
    required this.query,
    required this.onRecordClick,
    this.onPlaylistTap,
  });

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return Center(
        child: Text(
          'No playlists found for "$query"',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.76,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final item = playlists[index];
        final id = item['id']?.toString() ?? '';
        final title = _unescape.convert(Song.sanitize(item['title']?.toString() ?? ''));
        final subtitle = _unescape.convert(item['subtitle']?.toString() ?? '');
        final img = item['image']?.toString() ?? '';
        final source = item['source']?.toString() ?? 'saavn';
        final isYoutube = source == 'youtube';
        final isAutoAlbum = source == 'auto_album';

        return GestureDetector(
          onTap: () {
            onRecordClick();
            if (onPlaylistTap != null) {
              onPlaylistTap!(item);
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RemotePlaylistScreen(
                  playlistId: id,
                  playlistTitle: title,
                  imageUrl: img,
                  subtitle: subtitle,
                  source: source,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                          child: img.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: img,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 350,
                                  memCacheHeight: 350,
                                  errorWidget: (_, __, ___) => Container(
                                    color: AppColors.surfaceDark,
                                    child: const Icon(Icons.queue_music_rounded, color: Colors.white24, size: 40),
                                  ),
                                )
                              : Container(
                                  color: AppColors.surfaceDark,
                                  child: const Icon(Icons.queue_music_rounded, color: Colors.white24, size: 40),
                                ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isYoutube
                                  ? AppColors.electricCyan.withValues(alpha: 0.6)
                                  : (isAutoAlbum
                                      ? Colors.amberAccent.withValues(alpha: 0.6)
                                      : AppColors.neonViolet.withValues(alpha: 0.6)),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            isYoutube ? 'YT' : (isAutoAlbum ? 'Mix' : 'Saavn'),
                            style: GoogleFonts.outfit(
                              color: isYoutube
                                  ? AppColors.electricCyan
                                  : (isAutoAlbum ? Colors.amberAccent : AppColors.neonViolet),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.isNotEmpty ? subtitle : (isYoutube ? 'YouTube Music' : 'JioSaavn Playlist'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
