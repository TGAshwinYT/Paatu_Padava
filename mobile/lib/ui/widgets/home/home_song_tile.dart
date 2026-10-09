import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';
import 'home_song_card.dart';

class HomeSongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  static final HtmlUnescape _unescape = HtmlUnescape();

  const HomeSongTile({
    super.key,
    required this.song,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cleanTitle = _unescape.convert(Song.sanitize(song.title));
    final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;

        return ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: CachedNetworkImage(
                    imageUrl: song.coverUrl,
                    memCacheWidth: 150,
                    memCacheHeight: 150,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                  ),
                ),
              ),
              if (isPlaying)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.equalizer_rounded, color: AppColors.electricCyan, size: 24),
                ),
            ],
          ),
          title: Text(
            cleanTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: isPlaying ? AppColors.neonViolet : Colors.white,
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: song.source == 'youtube'
                      ? AppColors.electricCyan.withValues(alpha: 0.2)
                      : AppColors.neonViolet.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  song.source == 'youtube' ? 'YT' : '320K',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: song.source == 'youtube' ? AppColors.electricCyan : AppColors.neonViolet,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  cleanArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
            onPressed: () => showHomeSongContextMenu(context, song),
          ),
        );
      },
    );
  }
}
