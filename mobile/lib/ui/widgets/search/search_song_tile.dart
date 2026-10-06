import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../../services/favorites_manager.dart';
import '../../theme/app_theme.dart';

class SearchSongTile extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final Song song;
  final VoidCallback onTap;
  final VoidCallback onShowOptions;
  final VoidCallback? onShowVersions;

  const SearchSongTile({
    super.key,
    required this.song,
    required this.onTap,
    required this.onShowOptions,
    this.onShowVersions,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;
        final cleanTitle = _unescape.convert(Song.sanitize(song.title));
        final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

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
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
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
              if (song.versions.isNotEmpty && onShowVersions != null)
                GestureDetector(
                  onTap: onShowVersions,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      border: Border.all(color: AppColors.surfaceBorderHighlight),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${song.versions.length + 1} ver',
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<List<Song>>(
                valueListenable: FavoritesManager.favoritesNotifier,
                builder: (context, _, __) {
                  final isFav = FavoritesManager.isFavorite(song.id);
                  return IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 20,
                      color: isFav ? AppColors.neonViolet : AppColors.textSecondary,
                    ),
                    onPressed: () => FavoritesManager.toggleFavorite(song),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                onPressed: onShowOptions,
              ),
            ],
          ),
        );
      },
    );
  }
}
