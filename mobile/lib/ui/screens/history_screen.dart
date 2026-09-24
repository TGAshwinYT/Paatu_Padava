import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/history_manager.dart';
import '../../services/player_handler.dart';
import '../../services/favorites_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_dialog.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  void _showClearConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorderHighlight),
        ),
        title: const Text(
          'Clear Listening History?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will remove all recently played tracks from your device history.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              HistoryManager.clearHistory();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: song.coverUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(Icons.music_note),
                        )
                      : const Icon(Icons.music_note),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const Divider(color: AppColors.surfaceBorder),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: AppColors.neonViolet),
                title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  AddToPlaylistDialog.show(context, song);
                },
              ),
              ValueListenableBuilder<List<Song>>(
                valueListenable: FavoritesManager.favoritesNotifier,
                builder: (context, _, __) {
                  final isFav = FavoritesManager.isFavorite(song.id);
                  return ListTile(
                    leading: Icon(
                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFav ? const Color(0xFFEC4899) : Colors.white70,
                    ),
                    title: Text(
                      isFav ? 'Remove from Liked Songs' : 'Save to Liked Songs',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      FavoritesManager.toggleFavorite(song);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                title: const Text('Remove from History', style: TextStyle(color: Color(0xFFEF4444))),
                onTap: () {
                  HistoryManager.removeSong(song.id);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text(
          'Recently Played',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          ValueListenableBuilder<List<Song>>(
            valueListenable: HistoryManager.historyNotifier,
            builder: (context, history, _) {
              if (history.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.textSecondary),
                tooltip: 'Clear History',
                onPressed: () => _showClearConfirm(context),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Song>>(
        valueListenable: HistoryManager.historyNotifier,
        builder: (context, history, _) {
          if (history.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      size: 56,
                      color: AppColors.neonViolet,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'No recently played tracks',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tracks you listen to will appear here automatically',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              // Play All Header Banner
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [
                      Text(
                        '${history.length} tracks',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () {
                          audioHandler.playSong(history.first, queue: history);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                        label: const Text(
                          'Play All',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonViolet,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // History Tracks List
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = history[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: song.isDownloaded && song.localFilePath != null && File(song.localFilePath!).existsSync()
                            ? Image.file(
                                File(song.localFilePath!),
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              )
                            : (song.coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: song.coverUrl,
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      width: 52,
                                      height: 52,
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(Icons.music_note, color: Colors.white38),
                                    ),
                                  )
                                : Container(
                                    width: 52,
                                    height: 52,
                                    color: AppColors.surfaceElevated,
                                    child: const Icon(Icons.music_note, color: Colors.white38),
                                  )),
                      ),
                      title: Text(
                        Song.sanitize(song.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          if (song.source == 'saavn')
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.neonViolet.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '320K',
                                style: TextStyle(
                                  color: AppColors.neonViolet,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (song.source == 'youtube')
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.electricCyan.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YT',
                                style: TextStyle(
                                  color: AppColors.electricCyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              Song.sanitize(song.artist),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                        onPressed: () => _showSongOptions(context, song),
                      ),
                      onTap: () {
                        audioHandler.playSong(song, queue: history);
                      },
                    );
                  },
                  childCount: history.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }
}
