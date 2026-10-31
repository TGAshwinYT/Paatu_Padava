import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final bool isResolving;

  const SearchSongTile({
    super.key,
    required this.song,
    required this.onTap,
    required this.onShowOptions,
    this.onShowVersions,
    this.isResolving = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAudioHandlerInitialized) {
      return _buildDismissibleTile(context, isPlaying: false);
    }

    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;
        return _buildDismissibleTile(context, isPlaying: isPlaying);
      },
    );
  }

  Widget _buildDismissibleTile(BuildContext context, {required bool isPlaying}) {
    return Dismissible(
      key: ValueKey('search_tile_${song.id}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.electricCyan.withValues(alpha: 0.85),
              AppColors.neonViolet.withValues(alpha: 0.50),
            ],
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.playlist_play_rounded, color: Colors.white, size: 26),
            SizedBox(width: 8),
            Text(
              'Play Next',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.lightImpact();
          if (isAudioHandlerInitialized) {
            audioHandler.insertNext(song);
          }
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(milliseconds: 1600),
              backgroundColor: AppColors.surfaceElevated,
              content: Row(
                children: [
                  const Icon(Icons.playlist_add_check_rounded, color: AppColors.electricCyan, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Added to Play Next: ${_unescape.convert(Song.sanitize(song.title))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return false;
      },
      child: _buildTileContent(context, isPlaying: isPlaying),
    );
  }

  Widget _buildTileContent(BuildContext context, {required bool isPlaying}) {
    final cleanTitle = _unescape.convert(Song.sanitize(song.title));
    final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

    return ListTile(
      onTap: () {
        FocusScope.of(context).unfocus();
        onTap();
      },
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
                memCacheWidth: 120,
                memCacheHeight: 120,
                errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
              ),
            ),
          ),
          if (isResolving)
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.electricCyan,
                  ),
                ),
              ),
            )
          else if (isPlaying)
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: AppColors.neonViolet.withValues(alpha: 0.2),
                  border: Border.all(color: AppColors.neonViolet.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 10, color: AppColors.neonViolet),
                    const SizedBox(width: 3),
                    Text(
                      '+${song.versions.length} Mixes ▾',
                      style: GoogleFonts.outfit(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
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
              return SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  icon: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 20,
                    color: isFav ? AppColors.neonViolet : AppColors.textSecondary,
                  ),
                  onPressed: () => FavoritesManager.toggleFavorite(song),
                ),
              );
            },
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
              onPressed: onShowOptions,
            ),
          ),
        ],
      ),
    );
  }
}
