import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({Key? key}) : super(key: key);

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.80,
        child: QueueSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Drag indicator handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ValueListenableBuilder<List<Song>>(
                valueListenable: audioHandler.playlistNotifier,
                builder: (context, playlist, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Up Next in Queue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${playlist.length} Tracks • Drag to reorder',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
              Row(
                children: [
                  // Smart Shuffle button
                  ValueListenableBuilder<bool>(
                    valueListenable: audioHandler.isSmartShuffleNotifier,
                    builder: (context, isSmartShuffle, _) {
                      return IconButton(
                        icon: Icon(
                          Icons.auto_awesome_rounded,
                          color: isSmartShuffle ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                        ),
                        tooltip: 'Smart Shuffle (Recommendation Graph)',
                        onPressed: () => audioHandler.toggleSmartShuffle(),
                      );
                    },
                  ),
                  // Clear queue button
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70),
                    tooltip: 'Clear Queue',
                    onPressed: () {
                      audioHandler.clearQueue();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Reorderable Song List
        Expanded(
          child: ValueListenableBuilder<List<Song>>(
            valueListenable: audioHandler.playlistNotifier,
            builder: (context, playlist, _) {
              return ValueListenableBuilder<int>(
                valueListenable: audioHandler.currentIndexNotifier,
                builder: (context, currentIndex, _) {
                  if (playlist.isEmpty) {
                    return const Center(
                      child: Text(
                        'Queue is empty',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    );
                  }

                  return ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 80, top: 8),
                    itemCount: playlist.length,
                    onReorder: (oldIndex, newIndex) {
                      audioHandler.reorderQueue(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final song = playlist[index];
                      final isCurrent = index == currentIndex;

                      return Dismissible(
                        key: ValueKey('queue_${song.id}_$index'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.redAccent.withOpacity(0.8),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          audioHandler.removeAt(index);
                        },
                        child: Container(
                          color: isCurrent ? const Color(0xFF6366F1).withOpacity(0.12) : Colors.transparent,
                          child: ListTile(
                            onTap: () {
                              audioHandler.jumpToIndex(index);
                            },
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: isCurrent
                                      ? const Icon(Icons.equalizer_rounded, color: Color(0xFF6366F1), size: 20)
                                      : Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                        ),
                                ),
                                const SizedBox(width: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: (song.localFilePath != null && File(song.localFilePath!).existsSync())
                                        ? Image.file(File(song.localFilePath!), fit: BoxFit.cover)
                                        : (song.coverUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: song.coverUrl,
                                                fit: BoxFit.cover,
                                                placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                                                errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                                              )
                                            : Container(color: const Color(0xFF1E293B))),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? const Color(0xFF6366F1) : Colors.white,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle_rounded, color: Color(0xFF64748B)),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),

        // Bottom Add Radio Mix Action
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.radio_rounded, size: 20),
                    label: const Text(
                      'Auto-Add Similar Tracks (Radio Mix)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () async {
                      final added = await audioHandler.addRadioMix();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(added > 0 ? 'Added $added similar tracks to queue!' : 'No new recommendations found.'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
