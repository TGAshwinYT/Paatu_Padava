import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../domain/models/home_feed_models.dart';
import '../../../services/player_handler.dart';
import '../../../services/recent_containers_manager.dart';
import '../../screens/liked_songs_screen.dart';
import '../../screens/history_screen.dart';
import '../../screens/album_screen.dart';
import '../../screens/remote_playlist_screen.dart';
import '../../screens/daily_mix_detail_screen.dart';
import '../../theme/app_theme.dart';

/// Flagship Spotify-Style Dynamic 2x3 Quick Tiles Grid with instant 1-tap playback.
/// Dynamically grows from 1 to 6 items as albums/playlists are played,
/// hoists played containers to [0][0], and evicts the oldest [3][2] container.
class QuickGridSection extends StatelessWidget {
  final List<HomeQuickTile>? tiles;

  const QuickGridSection({
    super.key,
    this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<HomeQuickTile>>(
      valueListenable: RecentContainersManager.containersNotifier,
      builder: (context, recentContainers, _) {
        final displayTiles = (tiles != null && tiles!.isNotEmpty)
            ? tiles!
            : recentContainers;

        // If user hasn't clicked/played any container yet, keep the home screen clean
        if (displayTiles.isEmpty) return const SizedBox.shrink();

        final activeTiles = displayTiles.take(6).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            children: [
              for (int r = 0; r < (activeTiles.length / 2).ceil(); r++) ...[
                if (r > 0) const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _QuickTileItem(tile: activeTiles[r * 2]),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: (r * 2 + 1 < activeTiles.length)
                          ? _QuickTileItem(tile: activeTiles[r * 2 + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QuickTileItem extends StatelessWidget {
  final HomeQuickTile tile;

  const _QuickTileItem({required this.tile});

  IconData _getFallbackIcon() {
    switch (tile.type) {
      case 'liked':
        return Icons.favorite_rounded;
      case 'history':
        return Icons.history_rounded;
      case 'album':
        return Icons.album_rounded;
      case 'playlist':
        return Icons.queue_music_rounded;
      case 'hits':
        return Icons.local_fire_department_rounded;
      case 'decade':
        return Icons.radio_rounded;
      default:
        return Icons.queue_music_rounded;
    }
  }

  void _onTileTapped(BuildContext context) {
    HapticFeedback.lightImpact();
    if (tile.type == 'liked') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
      );
    } else if (tile.type == 'history') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HistoryScreen()),
      );
    } else if (tile.type == 'album') {
      final albId = tile.id.startsWith('album_') ? tile.id.substring(6) : tile.id;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlbumScreen(
            albumId: albId,
            albumTitle: tile.title,
            imageUrl: tile.coverUrl,
          ),
        ),
      );
    } else if (tile.type == 'playlist') {
      final plId = tile.id.startsWith('playlist_') ? tile.id.substring(9) : tile.id;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RemotePlaylistScreen(
            playlistId: plId,
            playlistTitle: tile.title,
            imageUrl: tile.coverUrl,
          ),
        ),
      );
    } else if (tile.type == 'mix') {
      final mixIndex = int.tryParse(tile.id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
      final mix = DailyMix(
        index: mixIndex,
        title: tile.title,
        subtitle: tile.subtitle ?? 'Your Daily Mix',
        coverUrl: tile.coverUrl,
        accentColor: tile.gradient.isNotEmpty ? tile.gradient.last : const Color(0xFF10B981),
        tracks: tile.tracks,
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DailyMixDetailScreen(mix: mix)),
      );
    } else if (tile.tracks.isNotEmpty) {
      audioHandler.playSong(tile.tracks.first, queue: tile.tracks);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening ${tile.title}...'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _onPlayTapped(BuildContext context) {
    HapticFeedback.mediumImpact();
    if (tile.tracks.isNotEmpty) {
      RecentContainersManager.recordContainer(
        id: tile.id,
        title: tile.title,
        subtitle: tile.subtitle,
        coverUrl: tile.coverUrl,
        type: tile.type,
        gradient: tile.gradient,
        tracks: tile.tracks,
      );
      audioHandler.playSong(tile.tracks.first, queue: tile.tracks);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Starting ${tile.title}...'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCover = tile.coverUrl.isNotEmpty;

    return InkWell(
      onTap: () => _onTileTapped(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.surfaceBorder, width: 0.8),
        ),
        child: Row(
          children: [
            // Left 56x56 square thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
              child: SizedBox(
                width: 56,
                height: 56,
                child: hasCover
                    ? CachedNetworkImage(
                        imageUrl: tile.coverUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 120,
                        memCacheHeight: 120,
                        placeholder: (_, __) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: tile.gradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(_getFallbackIcon(), color: Colors.white70, size: 24),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: tile.gradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(_getFallbackIcon(), color: Colors.white70, size: 24),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: tile.gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(_getFallbackIcon(), color: Colors.white, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 8),

            // Middle: Title & Subtitle
            Expanded(
              child: Text(
                tile.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -0.2,
                ),
              ),
            ),

            // Right: Instant 1-tap play button
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _onPlayTapped(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.neonViolet.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonViolet.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
