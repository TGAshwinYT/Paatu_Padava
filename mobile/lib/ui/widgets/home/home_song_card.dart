import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../../services/download_manager.dart';
import '../../../services/favorites_manager.dart';
import '../../theme/app_theme.dart';
import '../add_to_playlist_dialog.dart';

void showHomeSongContextMenu(BuildContext context, Song song) {
  final unescape = HtmlUnescape();
  final cleanTitle = unescape.convert(Song.sanitize(song.title));

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.radio_rounded, color: AppColors.neonViolet),
            title: const Text('Start Song Radio', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              audioHandler.startSongRadio(song);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Starting radio for "$cleanTitle"...')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded, color: AppColors.neonViolet),
            title: const Text('Play Next', style: TextStyle(color: Colors.white)),
            onTap: () {
              audioHandler.insertNext(song);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Playing "$cleanTitle" next')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_rounded, color: Colors.white70),
            title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
            onTap: () {
              audioHandler.addToQueue(song);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Added "$cleanTitle" to queue')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded, color: AppColors.electricCyan),
            title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              AddToPlaylistDialog.show(context, song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded, color: AppColors.electricCyan),
            title: const Text('Download Offline', style: TextStyle(color: Colors.white)),
            onTap: () {
              DownloadManager.downloadSong(song);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border_rounded, color: AppColors.neonViolet),
            title: const Text('Like / Favorite', style: TextStyle(color: Colors.white)),
            onTap: () {
              FavoritesManager.toggleFavorite(song);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
  );
}

class HomeSongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final double? width;
  static final HtmlUnescape _unescape = HtmlUnescape();

  const HomeSongCard({
    super.key,
    required this.song,
    required this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cleanTitle = _unescape.convert(Song.sanitize(song.title));
    final cleanArtist = _unescape.convert(Song.sanitize(song.artist));
    final cardWidth = width ?? (MediaQuery.of(context).size.width * 0.36).clamp(130.0, 180.0);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => showHomeSongContextMenu(context, song),
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: cardWidth,
                    height: cardWidth,
                    child: CachedNetworkImage(
                      imageUrl: song.coverUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      memCacheHeight: 200,
                      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: AppColors.neonGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonViolet.withValues(alpha: 0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              cleanTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              cleanArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
