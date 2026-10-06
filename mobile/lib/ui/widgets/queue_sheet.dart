import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../logic/smart_shuffle_controller.dart';
import '../../models/song.dart';
import '../../services/favorites_manager.dart';
import '../../services/player_handler.dart';

class QueueSheet extends StatefulWidget {
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
        heightFactor: 0.88,
        child: QueueSheet(),
      ),
    );
  }

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  bool _isPlayedExpanded = false;

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
              color: Colors.white.withValues(alpha: 0.2),
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
                        'Playback Queue',
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
                              ? const Color(0xFF1DB954).withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: mode == SmartShuffleMode.smart
                              ? Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.3))
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

        // Queue Body
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

                  // 1. Played tracks (indices < currentIndex), auto-trimmed to last 10
                  final hasPlayed = currentIndex > 0;
                  final playedStartIndex = (currentIndex - 10).clamp(0, currentIndex);
                  final playedTracks = hasPlayed ? playlist.sublist(playedStartIndex, currentIndex) : <Song>[];

                  // 2. Now Playing track
                  final nowPlaying = (currentIndex >= 0 && currentIndex < playlist.length)
                      ? playlist[currentIndex]
                      : null;

                  // 3. Upcoming tracks (indices > currentIndex)
                  final upcomingTracks = (currentIndex + 1 < playlist.length)
                      ? playlist.sublist(currentIndex + 1)
                      : <Song>[];

                  // Partition into User Enqueued (Stack) vs Auto-Suggestions / Context
                  final userQueueTracks = <MapEntry<int, Song>>[];
                  final suggestedTracks = <MapEntry<int, Song>>[];
                  for (int i = 0; i < upcomingTracks.length; i++) {
                    final song = upcomingTracks[i];
                    final actualIdx = currentIndex + 1 + i;
                    if (song.isUserEnqueued) {
                      userQueueTracks.add(MapEntry(actualIdx, song));
                    } else {
                      suggestedTracks.add(MapEntry(actualIdx, song));
                    }
                  }

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 90, top: 8),
                    children: [
                      // SECTION 1: PLAYED (COLLAPSED & AUTO-TRIMMED TO LAST 10)
                      if (hasPlayed) ...[
                        _buildPlayedSectionHeader(currentIndex, playedTracks.length),
                        if (_isPlayedExpanded)
                          ...playedTracks.asMap().entries.map((entry) {
                            final actualIdx = playedStartIndex + entry.key;
                            return _buildSongTile(
                              song: entry.value,
                              index: actualIdx,
                              isCurrent: false,
                              isPlayed: true,
                              canDismiss: true,
                            );
                          }),
                        const Divider(color: Colors.white10, height: 16),
                      ],

                      // SECTION 2: NOW PLAYING (PROMINENT HIGHLIGHTED CARD)
                      if (nowPlaying != null) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                          child: Row(
                            children: const [
                              Icon(Icons.equalizer_rounded, color: Color(0xFF818CF8), size: 16),
                              SizedBox(width: 8),
                              Text(
                                'NOW PLAYING',
                                style: TextStyle(
                                  color: Color(0xFF818CF8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildNowPlayingCard(nowPlaying, currentIndex),
                        const Divider(color: Colors.white10, height: 20),
                      ],

                      // SECTION 3: USER QUEUE (STACK PRIORITY)
                      if (userQueueTracks.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.layers_rounded, color: Color(0xFF818CF8), size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'NEXT IN QUEUE • USER STACK (${userQueueTracks.length})',
                                    style: const TextStyle(
                                      color: Color(0xFF818CF8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.clear_all_rounded, size: 16, color: Color(0xFF94A3B8)),
                                label: const Text(
                                  'Clear',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                onPressed: () {
                                  audioHandler.clearUserQueue();
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Cleared user queue'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: userQueueTracks.length,
                          onReorder: (oldIdx, newIdx) {
                            final actualOld = currentIndex + 1 + oldIdx;
                            final actualNew = currentIndex + 1 + newIdx;
                            audioHandler.reorderQueue(actualOld, actualNew);
                          },
                          itemBuilder: (context, idx) {
                            final entry = userQueueTracks[idx];
                            final song = entry.value;
                            final actualIdx = entry.key;
                            return _buildSongTile(
                              key: ValueKey('user_q_${song.id}_${song.canonicalSongKey}'),
                              song: song,
                              index: actualIdx,
                              dragIndex: idx,
                              isCurrent: false,
                              isPlayed: false,
                              canDismiss: false,
                            );
                          },
                        ),
                        const Divider(color: Colors.white10, height: 24),
                      ],

                      // SECTION 4: UP NEXT • AUTO-SUGGESTIONS & PLAYLIST
                      if (suggestedTracks.isEmpty && userQueueTracks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                          child: Center(
                            child: Text(
                              'No tracks up next',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            ),
                          ),
                        )
                      else if (suggestedTracks.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'UP NEXT • AUTO-SUGGESTIONS (${suggestedTracks.length})',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              Row(
                                children: const [
                                  Icon(Icons.auto_awesome_rounded, color: Color(0xFF1DB954), size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Auto-Suggested',
                                    style: TextStyle(
                                      color: Color(0xFF1DB954),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: suggestedTracks.length,
                          onReorder: (oldIdx, newIdx) {
                            final baseOffset = currentIndex + 1 + userQueueTracks.length;
                            final actualOld = baseOffset + oldIdx;
                            final actualNew = baseOffset + newIdx;
                            audioHandler.reorderQueue(actualOld, actualNew);
                          },
                          itemBuilder: (context, idx) {
                            final entry = suggestedTracks[idx];
                            final song = entry.value;
                            final actualIdx = entry.key;
                            return _buildSongTile(
                              key: ValueKey('sug_q_${song.id}_${song.canonicalSongKey}'),
                              song: song,
                              index: actualIdx,
                              dragIndex: idx,
                              isCurrent: false,
                              isPlayed: false,
                              canDismiss: false,
                            );
                          },
                        ),
                      ],
                    ],
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
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
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

  // ================= Played Section Header ================= //

  Widget _buildPlayedSectionHeader(int totalPlayed, int shownCount) {
    return InkWell(
      onTap: () {
        setState(() {
          _isPlayedExpanded = !_isPlayedExpanded;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.history_rounded, color: Color(0xFF64748B), size: 18),
            const SizedBox(width: 8),
            Text(
              'Played Tracks ($totalPlayed)',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            if (totalPlayed > 10)
              Text(
                '(showing last $shownCount)',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            const Spacer(),
            Icon(
              _isPlayedExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: const Color(0xFF94A3B8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ================= Now Playing Card ================= //

  Widget _buildNowPlayingCard(Song song, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Glowing Equalizer Indicator
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.equalizer_rounded,
              color: Color(0xFF818CF8),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),

          // Artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 48,
              height: 48,
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
          const SizedBox(width: 12),

          // Title & Artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: song.source == 'youtube'
                            ? const Color(0xFF06B6D4).withValues(alpha: 0.2)
                            : const Color(0xFF6366F1).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        song.source == 'youtube' ? 'YT' : '320K',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: song.source == 'youtube'
                              ? const Color(0xFF06B6D4)
                              : const Color(0xFF818CF8),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Favorite Button
          ValueListenableBuilder<List<Song>>(
            valueListenable: FavoritesManager.favoritesNotifier,
            builder: (context, _, __) {
              final isFav = FavoritesManager.isFavorite(song.id);
              return IconButton(
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? const Color(0xFFEC4899) : Colors.white60,
                  size: 22,
                ),
                onPressed: () => FavoritesManager.toggleFavorite(song),
              );
            },
          ),
        ],
      ),
    );
  }

  // ================= Generic Song Tile ================= //

  Widget _buildSongTile({
    Key? key,
    required Song song,
    required int index,
    int? dragIndex,
    required bool isCurrent,
    required bool isPlayed,
    required bool canDismiss,
  }) {
    final isSmart = song.isSmartRecommended;
    final isUser = song.isUserEnqueued;

    Widget content = Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isPlayed
            ? Colors.white.withValues(alpha: 0.02)
            : (isUser
                ? const Color(0xFF6366F1).withValues(alpha: 0.08)
                : (isSmart
                    ? const Color(0xFF1DB954).withValues(alpha: 0.08)
                    : Colors.transparent)),
        border: Border.all(
          color: isUser
              ? const Color(0xFF6366F1).withValues(alpha: 0.3)
              : (isSmart
                  ? const Color(0xFF1DB954).withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.04)),
          width: 1,
        ),
      ),
      child: ListTile(
        onTap: () {
          audioHandler.jumpToIndex(index);
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isPlayed ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                  fontSize: 12,
                ),
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
            if (isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.layers_rounded, size: 11, color: Color(0xFF818CF8)),
                    SizedBox(width: 4),
                    Text(
                      'User Queue • Stack',
                      style: TextStyle(
                        color: Color(0xFF818CF8),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              )
            else if (isSmart)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.auto_awesome, size: 11, color: Color(0xFF1DB954)),
                    SizedBox(width: 4),
                    Text(
                      'Auto-Suggested',
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
                color: isPlayed ? Colors.white60 : Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isPlayed ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            fontSize: 12,
          ),
        ),
        trailing: isPlayed
            ? const Icon(Icons.history_rounded, color: Color(0xFF475569), size: 18)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 18),
                    tooltip: 'Remove',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      audioHandler.removeAt(index);
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Removed "${song.title}" from queue'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  ReorderableDragStartListener(
                    index: dragIndex ?? (index - (audioHandler.currentIndex + 1)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                      child: Icon(Icons.drag_handle_rounded, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
      ),
    );

    if (isPlayed && canDismiss) {
      return Dismissible(
        key: key ?? ValueKey('dismiss_played_${song.id}_$index'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.redAccent.withValues(alpha: 0.85),
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
              content: Text('Removed "${song.title}" from history'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: content,
      );
    }

    return KeyedSubtree(
      key: key ?? ValueKey('tile_${song.id}_${song.canonicalSongKey}'),
      child: content,
    );
  }
}
