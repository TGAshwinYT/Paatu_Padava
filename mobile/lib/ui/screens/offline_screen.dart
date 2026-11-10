import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/song.dart';
import '../../services/download_manager.dart';
import '../../services/player_handler.dart';
import '../theme/app_dimensions.dart';
import '../widgets/mini_player.dart';
import '../widgets/common/song_tile.dart';

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchActive = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Top App Bar
              SliverAppBar(
                backgroundColor: const Color(0xFF0A0E1A),
                pinned: true,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: _isSearchActive
                    ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Search offline songs...',
                          hintStyle: GoogleFonts.outfit(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      )
                    : Text(
                        'Offline Music',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                actions: [
                  IconButton(
                    icon: Icon(
                      _isSearchActive ? Icons.close_rounded : Icons.search_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_isSearchActive) {
                          _searchQuery = '';
                          _searchController.clear();
                        }
                        _isSearchActive = !_isSearchActive;
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ),

              // Storage & Quick Play Hero Card
              ValueListenableBuilder<List<Song>>(
                valueListenable: DownloadManager.downloadedSongsNotifier,
                builder: (context, downloadedSongs, _) {
                  if (downloadedSongs.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF131B2E),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: const Icon(
                                  Icons.offline_pin_outlined,
                                  size: 46,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'No Offline Songs',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Download any track or album to enjoy seamless 320kbps offline playback without internet!',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Explore Music',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final totalSizeStr = DownloadManager.getFormattedTotalSize();
                  final filtered = _searchQuery.isEmpty
                      ? downloadedSongs
                      : downloadedSongs.where((s) =>
                          s.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                          s.artist.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

                  return SliverMainAxisGroup(
                    slivers: [
                      // Storage Header Banner
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF064E3B), Color(0xFF0F172A)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.offline_pin_rounded, color: Color(0xFF34D399), size: 24),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${downloadedSongs.length} Tracks Ready',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Using $totalSizeStr storage on device • Lossless 320kbps',
                                            style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 11),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        ),
                                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                                        label: Text(
                                          'Play All',
                                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () => audioHandler.playSong(downloadedSongs.first, queue: downloadedSongs),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white70,
                                          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                          padding: const EdgeInsets.symmetric(vertical: 11),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        ),
                                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                                        label: Text('Shuffle', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                                        onPressed: () {
                                          final shuffled = List<Song>.from(downloadedSongs)..shuffle();
                                          audioHandler.playSong(shuffled.first, queue: shuffled);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Tracks List
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          AppDimensions.bottomClearance(context, hasBottomNav: false),
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final song = filtered[index];
                              return SongTile(
                                song: song,
                                queue: downloadedSongs,
                                index: index,
                                playbackContext: const PlaybackContext(
                                  id: 'offline',
                                  title: 'Downloaded Music',
                                  type: 'downloads',
                                ),
                                onRemove: () async {
                                  await DownloadManager.deleteSong(song.id);
                                },
                                removeTooltip: 'Delete',
                              );
                            },
                            childCount: filtered.length,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),

          // Docked Mini Player
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
