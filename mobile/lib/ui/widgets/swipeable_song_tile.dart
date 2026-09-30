import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/song.dart';
import '../../services/download_manager.dart';
import '../../services/player_handler.dart';
import 'add_to_playlist_dialog.dart';

class SwipeableSongTile extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int? index;
  final VoidCallback? onRemove;
  final String? removeTooltip;

  const SwipeableSongTile({
    Key? key,
    required this.song,
    required this.queue,
    this.index,
    this.onRemove,
    this.removeTooltip = 'Remove',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('swipe_${song.id}_${index ?? 0}'),
      direction: onRemove != null
          ? DismissDirection.horizontal
          : DismissDirection.startToEnd,
      // Swipe Right: Queue Next
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6366F1).withOpacity(0.85),
              const Color(0xFF8B5CF6).withOpacity(0.50),
            ],
          ),
        ),
        child: Row(
          children: const [
            Icon(Icons.playlist_play_rounded, color: Colors.white, size: 26),
            SizedBox(width: 8),
            Text(
              'Play Next',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
      // Swipe Left: Optional Delete / Remove
      secondaryBackground: onRemove != null
          ? Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              color: Colors.redAccent.withOpacity(0.85),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    removeTooltip ?? 'Remove',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                ],
              ),
            )
          : null,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe Right: Queue next with haptic feedback
          HapticFeedback.mediumImpact();
          audioHandler.insertNext(song);
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.queue_music_rounded, color: Color(0xFF818CF8), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Playing "${song.title}" next',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
          // Return false so item rebounds back into the list!
          return false;
        } else if (direction == DismissDirection.endToStart && onRemove != null) {
          HapticFeedback.lightImpact();
          onRemove?.call();
          return true;
        }
        return false;
      },
      child: ListTile(
        onTap: () => audioHandler.playSong(song, queue: queue),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index != null)
              SizedBox(
                width: 26,
                child: Text(
                  '${index! + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            if (index != null) const SizedBox(width: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: song.coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: song.coverUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
            ),
          ],
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                            color: const Color(0xFF6366F1),
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
                      onPressed: () => DownloadManager.downloadSong(song),
                    );
                  },
                );
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) {
                if (val == 'play_next') {
                  audioHandler.insertNext(song);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Playing "${song.title}" next')),
                  );
                } else if (val == 'start_radio') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Starting Radio for "${song.title}"...')),
                  );
                  audioHandler.startSongRadio(song);
                } else if (val == 'add_to_playlist') {
                  AddToPlaylistDialog.show(context, song);
                } else if (val == 'remove') {
                  onRemove?.call();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'start_radio',
                  child: Row(
                    children: [
                      Icon(Icons.radio_rounded, color: Color(0xFF818CF8), size: 20),
                      SizedBox(width: 10),
                      Text('Start Song Radio', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'play_next',
                  child: Row(
                    children: [
                      Icon(Icons.playlist_play_rounded, color: Colors.white70, size: 20),
                      SizedBox(width: 10),
                      Text('Play Next', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'add_to_playlist',
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add_rounded, color: Colors.white70, size: 20),
                      SizedBox(width: 10),
                      Text('Add to Playlist', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                if (onRemove != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Text(removeTooltip ?? 'Remove', style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      color: const Color(0xFF1E293B),
      child: const Icon(Icons.music_note, color: Colors.white30, size: 22),
    );
  }
}
