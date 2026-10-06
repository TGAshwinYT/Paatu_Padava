import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/song.dart';
import '../../../services/download_manager.dart';
import '../../../services/player_handler.dart';
import '../add_to_playlist_dialog.dart';

class DownloadsTabView extends StatelessWidget {
  const DownloadsTabView({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: DownloadManager.downloadedSongsNotifier,
      builder: (context, downloadedSongs, _) {
        if (downloadedSongs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.offline_pin_outlined, size: 48, color: Color(0xFF64748B)),
                  const SizedBox(height: 14),
                  Text(
                    'No Offline Songs',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Download any track to enjoy seamless 320kbps offline playback with zero internet!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        final totalSizeStr = DownloadManager.getFormattedTotalSize();

        return CustomScrollView(
          slivers: [
            // Storage Summary Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.offline_pin_rounded, size: 16, color: Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                Text(
                                  '${downloadedSongs.length} Tracks Offline',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Storage: $totalSizeStr on device',
                              style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text('Play Offline', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        onPressed: () => audioHandler.playSong(downloadedSongs.first, queue: downloadedSongs),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Downloaded Songs List
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = downloadedSongs[index];
                  return Dismissible(
                    key: Key('offline_${song.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) async {
                      await DownloadManager.deleteSong(song.id);
                    },
                    child: ListTile(
                      onTap: () => audioHandler.playSong(song, queue: downloadedSongs),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: (song.localFilePath != null && File(song.localFilePath!).existsSync())
                              ? Image.file(File(song.localFilePath!), fit: BoxFit.cover)
                              : (song.coverUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: song.coverUrl,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                                    )
                                  : Container(color: const Color(0xFF1E293B))),
                        ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Row(
                        children: [
                          const Icon(Icons.offline_pin_rounded, size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8), size: 20),
                            onPressed: () => AddToPlaylistDialog.show(context, song),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 20),
                            onPressed: () async {
                              await DownloadManager.deleteSong(song.id);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: downloadedSongs.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }
}
