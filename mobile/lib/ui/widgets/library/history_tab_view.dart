import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/song.dart';
import '../../../services/history_manager.dart';
import '../../../services/player_handler.dart';
import '../add_to_playlist_dialog.dart';

class HistoryTabView extends StatelessWidget {
  final void Function(Song song) onSongContextMenu;

  const HistoryTabView({
    super.key,
    required this.onSongContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: HistoryManager.historyNotifier,
      builder: (context, history, _) {
        if (history.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history_rounded, size: 48, color: Color(0xFF64748B)),
                  const SizedBox(height: 14),
                  Text(
                    'No Listening History Yet',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Songs you stream or play offline will automatically appear here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text('Play All (${history.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      onPressed: () => audioHandler.playSong(history.first, queue: history),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.clear_all_rounded, size: 18, color: Color(0xFF64748B)),
                      label: Text('Clear', style: GoogleFonts.outfit(color: const Color(0xFF64748B))),
                      onPressed: () => HistoryManager.clear(),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = history[index];
                  return ListTile(
                    onTap: () => audioHandler.playSong(song, queue: history),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 50,
                        height: 50,
                        child: CachedNetworkImage(
                          imageUrl: song.coverUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                        ),
                      ),
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8), size: 22),
                          onPressed: () => AddToPlaylistDialog.show(context, song),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B), size: 20),
                          onPressed: () => onSongContextMenu(song),
                        ),
                      ],
                    ),
                  );
                },
                childCount: history.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }
}
