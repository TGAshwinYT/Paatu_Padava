import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../domain/models/history_entry.dart';
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

  Map<String, List<HistoryEntry>> _groupByDate(List<HistoryEntry> entries) {
    final Map<String, List<HistoryEntry>> groups = {};
    for (final entry in entries) {
      final section = entry.dateSection;
      groups.putIfAbsent(section, () => []).add(entry);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<HistoryEntry>>(
      valueListenable: HistoryManager.historyEntriesNotifier,
      builder: (context, historyEntries, _) {
        if (historyEntries.isEmpty) {
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
                    'Songs you stream or play offline for at least 30 seconds will automatically appear here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        final grouped = _groupByDate(historyEntries);

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
                      label: Text('Play Recent (${historyEntries.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        if (historyEntries.isNotEmpty) {
                          audioHandler.playTrack(historyEntries.first.track);
                        }
                      },
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

            // Date sections
            for (final group in grouped.entries) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Text(
                    group.key,
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF818CF8),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = group.value[index];
                    final song = entry.track.toSong();

                    return ListTile(
                      onTap: () => audioHandler.playTrack(entry.track),
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
                        '${song.artist} • ${entry.formattedTime}',
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
                  childCount: group.value.length,
                ),
              ),
            ],

            // Enforce bottom padding of 110 so widgets never hide behind MiniPlayer
            const SliverToBoxAdapter(
              child: SizedBox(height: 110),
            ),
          ],
        );
      },
    );
  }
}
