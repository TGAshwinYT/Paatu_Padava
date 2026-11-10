import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../../services/download_manager.dart';
import '../../../services/favorites_manager.dart';
import '../../theme/app_theme.dart';
import '../cover_art_image.dart';
import 'song_options_sheet.dart';

/// Flagship unified SongTile for Paatu Padava.
/// Delivers Spotify-grade smoothness, active track visual highlighting,
/// configurable swipe gestures, and universal context options sheet.
class SongTile extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final Song song;
  final List<Song>? queue;
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String? removeTooltip;
  final PlaybackContext? playbackContext;
  final bool enableSwipe;
  final bool showRank;
  final bool showDownload;
  final Widget? customTrailing;

  const SongTile({
    super.key,
    required this.song,
    this.queue,
    this.index,
    this.onTap,
    this.onRemove,
    this.removeTooltip,
    this.playbackContext,
    this.enableSwipe = true,
    this.showRank = false,
    this.showDownload = true,
    this.customTrailing,
  });

  void _handleTap(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    audioHandler.playSong(
      song,
      queue: queue,
      context: playbackContext,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanTitle = _unescape.convert(Song.sanitize(song.title));
    final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

    final tile = ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlayingThis = currentSong?.id == song.id;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          onTap: () => _handleTap(context),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showRank && index != null) ...[
                SizedBox(
                  width: 24,
                  child: Text(
                    '${index! + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isPlayingThis ? AppColors.neonViolet : const Color(0xFF64748B),
                      fontWeight: isPlayingThis ? FontWeight.w900 : FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Stack(
                alignment: Alignment.center,
                children: [
                  CoverArtImage(
                    song: song,
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(10),
                    memCacheWidth: 150,
                    memCacheHeight: 150,
                    errorWidget: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 22),
                    ),
                  ),
                  if (isPlayingThis)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.equalizer_rounded,
                        color: AppColors.neonViolet,
                        size: 24,
                      ),
                    ),
                ],
              ),
            ],
          ),
          title: Text(
            cleanTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlayingThis ? AppColors.neonViolet : Colors.white,
              fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Row(
            children: [
              Flexible(
                child: Text(
                  cleanArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlayingThis ? AppColors.neonViolet.withValues(alpha: 0.8) : const Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ),
              if (song.addedBy != null && song.addedBy!.trim().isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.35), width: 0.5),
                  ),
                  child: Text(
                    'Added by ${song.addedBy}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF818CF8),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          trailing: customTrailing ?? _buildTrailing(context, cleanTitle),
        );
      },
    );

    if (!enableSwipe) return tile;

    return Dismissible(
      key: ValueKey('song_tile_swipe_${song.id}_${index ?? 0}'),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6366F1).withValues(alpha: 0.85),
              const Color(0xFF8B5CF6).withValues(alpha: 0.50),
            ],
          ),
        ),
        child: Row(
          children: const [
            Icon(Icons.playlist_play_rounded, color: Colors.white, size: 26),
            SizedBox(width: 8),
            Text('Play Next', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
      secondaryBackground: onRemove != null
          ? Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              color: Colors.redAccent.withValues(alpha: 0.85),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(removeTooltip ?? 'Remove', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                ],
              ),
            )
          : Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFF43F5E).withValues(alpha: 0.50),
                    const Color(0xFFE11D48).withValues(alpha: 0.90),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [
                  Text('Like Song', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  SizedBox(width: 8),
                  Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
                ],
              ),
            ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.mediumImpact();
          audioHandler.insertNext(song);
          _showToast(context, 'Playing "$cleanTitle" next');
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if (onRemove != null) {
            HapticFeedback.lightImpact();
            onRemove!();
            return true;
          } else {
            HapticFeedback.mediumImpact();
            final wasLiked = await FavoritesManager.toggleFavorite(song);
            if (context.mounted) {
              _showToast(context, wasLiked ? 'Added "$cleanTitle" to Liked Songs' : 'Removed from Liked Songs');
            }
            return false;
          }
        }
        return false;
      },
      child: tile,
    );
  }

  Widget _buildTrailing(BuildContext context, String cleanTitle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDownload)
          ValueListenableBuilder<List<Song>>(
            valueListenable: DownloadManager.downloadedSongsNotifier,
            builder: (context, _, __) {
              return ValueListenableBuilder<Map<String, double>>(
                valueListenable: DownloadManager.activeDownloads,
                builder: (context, activeDownloads, __) {
                  final isDownloaded = DownloadManager.isDownloaded(song.id);
                  final isDownloading = activeDownloads.containsKey(song.id);
                  final isQueued = DownloadManager.isQueuedOrDownloading(song.id) && !isDownloading && !isDownloaded;

                  if (isDownloading) {
                    final p = activeDownloads[song.id] ?? 0.0;
                    return SizedBox(
                      width: 32,
                      height: 32,
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: CircularProgressIndicator(
                          value: p > 0 ? p : null,
                          strokeWidth: 2,
                          color: AppColors.electricCyan,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                    );
                  }
                  if (isQueued) {
                    return const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.hourglass_empty_rounded, color: Color(0xFF818CF8), size: 18),
                    );
                  }
                  if (isDownloaded) {
                    return const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                    );
                  }
                  return IconButton(
                    icon: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF64748B), size: 20),
                    onPressed: () {
                      DownloadManager.downloadSong(song);
                      _showToast(context, 'Downloading "$cleanTitle"...');
                    },
                  );
                },
              );
            },
          ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
          onPressed: () => SongOptionsSheet.show(
            context,
            song,
            onRemove: onRemove,
            removeLabel: removeTooltip,
          ),
        ),
      ],
    );
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
