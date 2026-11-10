import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/models/history_entry.dart';
import '../../domain/models/listening_session.dart';
import '../../services/history_manager.dart';
import '../../services/player_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/common/song_tile.dart';
import '../widgets/history/session_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _selectedTab = 0; // 0: Sessions, 1: All Tracks

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
          'This will permanently remove all listening history and continuous playback sessions from your device.',
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

  Map<String, List<HistoryEntry>> _groupByDate(List<HistoryEntry> entries) {
    final Map<String, List<HistoryEntry>> groups = {};
    for (final entry in entries) {
      final section = entry.dateSection;
      groups.putIfAbsent(section, () => []).add(entry);
    }
    return groups;
  }

  Widget _buildTabPill(String label, int index, IconData icon) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.neonViolet : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.surfaceBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
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
            Text(
              'No recently played tracks',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tracks you play will appear here and automatically cluster into Spotify-style continuous albums.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: Text(
          'Recently Played',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          ValueListenableBuilder<List<HistoryEntry>>(
            valueListenable: HistoryManager.historyEntriesNotifier,
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
      body: Stack(
        children: [
          ValueListenableBuilder<List<HistoryEntry>>(
            valueListenable: HistoryManager.historyEntriesNotifier,
            builder: (context, historyEntries, _) {
              return ValueListenableBuilder<List<ListeningSession>>(
                valueListenable: HistoryManager.historySessionsNotifier,
                builder: (context, sessions, _) {
                  if (historyEntries.isEmpty && sessions.isEmpty) {
                    return _buildEmptyState();
                  }

                  return CustomScrollView(
                    slivers: [
                      // Segmented Tab Filter
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                          child: Row(
                            children: [
                              _buildTabPill('Continuous Sessions', 0, Icons.queue_music_rounded),
                              const SizedBox(width: 10),
                              _buildTabPill('All Tracks', 1, Icons.history_rounded),
                            ],
                          ),
                        ),
                      ),

                      // VIEW 0: Continuous Sessions Tab (Spotify-style Album / Playlist clusters)
                      if (_selectedTab == 0) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'SESSIONS (${sessions.length})',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.electricCyan,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                if (sessions.isNotEmpty)
                                  Text(
                                    'Tap to open continuous album',
                                    style: GoogleFonts.outfit(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (sessions.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                              child: Center(
                                child: Text(
                                  'No continuous sessions formed yet. Play songs back-to-back to generate session albums.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final session = sessions[index];
                                return SessionCard(
                                  session: session,
                                  isHorizontalCard: false,
                                );
                              },
                              childCount: sessions.length,
                            ),
                          ),
                      ],

                      // VIEW 1: All Tracks Timeline Tab
                      if (_selectedTab == 1) ...[
                        // Recent Sessions Horizontal Carousel (if sessions exist)
                        if (sessions.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'CONTINUOUS SESSIONS',
                                    style: GoogleFonts.outfit(
                                      color: AppColors.electricCyan,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _selectedTab = 0),
                                    child: Text(
                                      'See all (${sessions.length})',
                                      style: GoogleFonts.outfit(
                                        color: AppColors.neonViolet,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 205,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: sessions.length,
                                itemBuilder: (context, index) {
                                  return SessionCard(
                                    session: sessions[index],
                                    isHorizontalCard: true,
                                  );
                                },
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(
                            child: Divider(color: AppColors.surfaceBorder, height: 28),
                          ),
                        ],

                        // Header Controls
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                            child: Row(
                              children: [
                                Text(
                                  '${historyEntries.length} tracks played',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    if (historyEntries.isNotEmpty) {
                                      audioHandler.playTrack(historyEntries.first.track);
                                    }
                                  },
                                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                  label: Text(
                                    'Play Recent',
                                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.neonViolet,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Date-Grouped Sections
                        for (final group in _groupByDate(historyEntries).entries) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                              child: Text(
                                group.key,
                                style: GoogleFonts.outfit(
                                  color: AppColors.electricCyan,
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

                                return SongTile(
                                  song: song,
                                  queue: group.value.map((e) => e.track.toSong()).toList(),
                                  index: index,
                                  playbackContext: const PlaybackContext(
                                    id: 'history',
                                    title: 'Listening History',
                                    type: 'history',
                                  ),
                                  onRemove: () {
                                    HistoryManager.removeSong(song.id);
                                  },
                                  removeTooltip: 'Remove',
                                );
                              },
                              childCount: group.value.length,
                            ),
                          ),
                        ],
                      ],

                      // Bottom clearance for MiniPlayer
                      SliverToBoxAdapter(
                        child: SizedBox(height: AppDimensions.bottomClearance(context, hasBottomNav: false)),
                      ),
                    ],
                  );
                },
              );
            },
          ),

          // Persistent MiniPlayer
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
    );
  }
}
