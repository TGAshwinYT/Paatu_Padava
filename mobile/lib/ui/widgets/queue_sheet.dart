import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../logic/smart_shuffle_controller.dart';
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
        heightFactor: 0.85,
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

        // Header with 3-State Smart Shuffle & Clear Actions
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
                        '${playlist.length} Tracks • Drag to reorder • Swipe to remove',
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
                  // 3-State Spotify Smart Shuffle Button
                  ValueListenableBuilder<SmartShuffleMode>(
                    valueListenable: audioHandler.shuffleModeNotifier,
                    builder: (context, mode, _) {
                      IconData icon;
                      Color color;
                      String tooltip;

                      switch (mode) {
                        case SmartShuffleMode.off:
                          icon = Icons.shuffle_rounded;
                          color = const Color(0xFF64748B);
                          tooltip = 'Shuffle: Off (Tap to enable Standard)';
                          break;
                        case SmartShuffleMode.standard:
                          icon = Icons.shuffle_rounded;
                          color = const Color(0xFF6366F1);
                          tooltip = 'Shuffle: Standard (User Tracks, Tap for Smart)';
                          break;
                        case SmartShuffleMode.smart:
                          icon = Icons.auto_awesome_rounded;
                          color = const Color(0xFF1DB954);
                          tooltip = 'Smart Shuffle: Active (Recommendations Interleaved)';
                          break;
                      }

                      return Container(
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: mode == SmartShuffleMode.smart
                              ? const Color(0xFF1DB954).withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: mode == SmartShuffleMode.smart
                              ? Border.all(color: const Color(0xFF1DB954).withOpacity(0.3))
                              : null,
                        ),
                        child: IconButton(
                          icon: Icon(icon, color: color, size: 22),
                          tooltip: tooltip,
                          onPressed: () {
                            audioHandler.toggleSmartShuffle();
                            final newMode = audioHandler.smartShuffleController.mode;
                            final msg = newMode == SmartShuffleMode.smart
                                ? '✨ Smart Shuffle Enabled: Recommendations will interleave'
                                : (newMode == SmartShuffleMode.standard
                                    ? '🔀 Standard Shuffle Enabled'
                                    : '➡️ Sequential Playback (Shuffle Off)');
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
                            );
                          },
                        ),
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

        // Reorderable Song List with Sparkle Badges & Swipe-to-Dismiss
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
                      final isSmart = song.isSmartRecommended;

                      return Dismissible(
                        key: ValueKey('queue_${song.id}_$index'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.redAccent.withOpacity(0.85),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: const [
                              Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              SizedBox(width: 8),
                              Icon(Icons.delete_outline_rounded, color: Colors.white),
                            ],
                          ),
                        ),
                        onDismissed: (_) {
                          audioHandler.removeAt(index);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Removed "${song.title}" from queue'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: isCurrent
                                ? const Color(0xFF6366F1).withOpacity(0.14)
                                : (isSmart
                                    ? const Color(0xFF1DB954).withOpacity(0.08)
                                    : Colors.transparent),
                            gradient: isSmart && !isCurrent
                                ? LinearGradient(
                                    colors: [
                                      const Color(0xFF1DB954).withOpacity(0.12),
                                      const Color(0xFF6366F1).withOpacity(0.06),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            border: Border.all(
                              color: isCurrent
                                  ? const Color(0xFF6366F1).withOpacity(0.4)
                                  : (isSmart
                                      ? const Color(0xFF1DB954).withOpacity(0.3)
                                      : Colors.white.withOpacity(0.03)),
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            onTap: () {
                              audioHandler.jumpToIndex(index);
                            },
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 26,
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
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isSmart)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.auto_awesome, size: 11, color: Color(0xFF1DB954)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Added by Smart Shuffle',
                                          style: TextStyle(
                                            color: Color(0xFF1DB954),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent ? const Color(0xFF6366F1) : Colors.white,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
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
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.drag_handle_rounded, color: Color(0xFF64748B)),
                              ),
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
