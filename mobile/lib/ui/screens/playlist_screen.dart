import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/playlist_manager.dart';
import '../../services/download_manager.dart';
import '../widgets/mini_player.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/batch_download_button.dart';

class PlaylistScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistScreen({
    Key? key,
    required this.playlistId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<UserPlaylist>>(
      valueListenable: PlaylistManager.playlistsNotifier,
      builder: (context, playlists, child) {
        UserPlaylist? playlist;
        try {
          playlist = playlists.firstWhere((p) => p.id == playlistId);
        } catch (_) {
          playlist = PlaylistManager.getPlaylist(playlistId);
        }

        if (playlist == null) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A0E1A),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0F172A),
              title: const Text('Playlist', style: TextStyle(color: Colors.white)),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: const Center(
              child: Text('Playlist not found or deleted', style: TextStyle(color: Colors.white70)),
            ),
          );
        }

        final tracks = playlist.tracks;
        final hasCover = playlist.coverUrl.isNotEmpty;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0E1A),
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 260.0,
                    pinned: true,
                    backgroundColor: const Color(0xFF0F172A),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        tooltip: 'Delete Playlist',
                        onPressed: () => _confirmDelete(context, playlist!),
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        playlist.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (hasCover)
                            CachedNetworkImage(
                              imageUrl: playlist.coverUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _buildPlaceholderCover(),
                            )
                          else
                            _buildPlaceholderCover(),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFF0A0E1A).withOpacity(0.85),
                                  const Color(0xFF0A0E1A),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Header Info & Controls
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tracks.length} ${tracks.length == 1 ? "track" : "tracks"}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (tracks.isNotEmpty)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                                    label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () => audioHandler.playSong(tracks.first, queue: tracks),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                                    label: const Text('Shuffle'),
                                    onPressed: () {
                                      final shuffled = List<Song>.from(tracks)..shuffle();
                                      audioHandler.playSong(shuffled.first, queue: shuffled);
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  BatchDownloadButton(songs: tracks, label: 'Download All'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Track list
                  if (tracks.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'This playlist is empty.\nSearch songs and use "Add to Playlist".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.5),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = tracks[index];
                          return Dismissible(
                            key: Key('${song.id}_$index'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red.withOpacity(0.2),
                              child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            ),
                            onDismissed: (_) {
                              PlaylistManager.removeSongFromPlaylist(playlistId, song.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Removed "${song.title}" from playlist'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            child: ListTile(
                              onTap: () => audioHandler.playSong(song, queue: tracks),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: song.coverUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: song.coverUrl,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => _buildTrackPlaceholder(),
                                      )
                                    : _buildTrackPlaceholder(),
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
                                      if (val == 'remove') {
                                        PlaylistManager.removeSongFromPlaylist(playlistId, song.id);
                                      } else if (val == 'add_to_other') {
                                        AddToPlaylistDialog.show(context, song);
                                      } else if (val == 'play_next') {
                                        audioHandler.insertNext(song);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Playing "${song.title}" next')),
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'play_next',
                                        child: Row(
                                          children: [
                                            Icon(Icons.playlist_play_rounded, color: Colors.white70, size: 18),
                                            SizedBox(width: 10),
                                            Text('Play Next', style: TextStyle(color: Colors.white, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'add_to_other',
                                        child: Row(
                                          children: [
                                            Icon(Icons.playlist_add_rounded, color: Colors.white70, size: 18),
                                            SizedBox(width: 10),
                                            Text('Add to Another Playlist', style: TextStyle(color: Colors.white, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                            SizedBox(width: 10),
                                            Text('Remove from Playlist', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: tracks.length,
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),

              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MiniPlayer(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.queue_music_rounded, size: 72, color: Colors.white30),
      ),
    );
  }

  Widget _buildTrackPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      color: const Color(0xFF1E293B),
      child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 20),
    );
  }

  void _confirmDelete(BuildContext context, UserPlaylist playlist) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "${playlist.title}"? This cannot be undone.',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(dialogCtx);
              PlaylistManager.deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
