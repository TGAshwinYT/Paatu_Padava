import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/models/home_feed_models.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/batch_download_button.dart';
import '../widgets/common/song_tile.dart';

/// Spotify-Style Daily Mix Detail Screen displaying the mix cover,
/// artist clustering subtitle, and the full scrollable track list.
class DailyMixDetailScreen extends StatefulWidget {
  final DailyMix mix;

  const DailyMixDetailScreen({
    super.key,
    required this.mix,
  });

  @override
  State<DailyMixDetailScreen> createState() => _DailyMixDetailScreenState();
}

class _DailyMixDetailScreenState extends State<DailyMixDetailScreen> {
  void _playAll({bool shuffle = false}) {
    if (widget.mix.tracks.isEmpty) return;
    final playbackCtx = PlaybackContext(
      id: 'daily_mix_${widget.mix.index}',
      title: widget.mix.title,
      subtitle: widget.mix.subtitle,
      coverUrl: widget.mix.coverUrl,
      type: 'mix',
    );

    final queue = List<Song>.from(widget.mix.tracks);
    if (shuffle) {
      queue.shuffle();
    }
    audioHandler.playSong(queue.first, queue: queue, context: playbackCtx);
  }

  @override
  Widget build(BuildContext context) {
    final mix = widget.mix;
    final accent = mix.accentColor;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Vibrant Spotify Header with gradient matching the mix accent
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: AppColors.bgDark,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  title: Text(
                    mix.title,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Gradient background
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.6),
                              AppColors.bgDark,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      // Center Artwork
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40, bottom: 40),
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: mix.coverUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: mix.coverUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
                                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                                          )
                                        : Container(color: accent),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(height: 5, color: accent),
                                  ),
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'MIX ${mix.index}',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Mix Description & Action Buttons
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mix.subtitle,
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${mix.tracks.length} tracks • Made for you by Paatu Padava',
                        style: GoogleFonts.outfit(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: Text(
                              'Play All',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                            ),
                            onPressed: () => _playAll(shuffle: false),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            icon: const Icon(Icons.shuffle_rounded, size: 18),
                            label: Text(
                              'Shuffle',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                            ),
                            onPressed: () => _playAll(shuffle: true),
                          ),
                          const Spacer(),
                          BatchDownloadButton(songs: mix.tracks),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Tracks List
              SliverPadding(
                padding: EdgeInsets.only(
                  top: 8,
                  bottom: AppDimensions.bottomClearance(context, hasBottomNav: false),
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = mix.tracks[index];
                      return SongTile(
                        song: song,
                        queue: mix.tracks,
                        index: index,
                        playbackContext: PlaybackContext(
                          id: 'daily_mix_${widget.mix.index}',
                          title: widget.mix.title,
                          subtitle: widget.mix.subtitle,
                          coverUrl: widget.mix.coverUrl,
                          type: 'mix',
                        ),
                      );
                    },
                    childCount: mix.tracks.length,
                  ),
                ),
              ),
            ],
          ),

          // Persistent Mini Player clearance
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
