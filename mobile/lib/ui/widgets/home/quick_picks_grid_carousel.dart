import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';

class QuickPicksGridCarousel extends StatelessWidget {
  final List<Song> songs;
  final String title;

  const QuickPicksGridCarousel({
    Key? key,
    required this.songs,
    this.title = 'Quick Picks',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    // Group songs into chunks of 4 rows per column
    final List<List<Song>> columns = [];
    for (int i = 0; i < songs.length; i += 4) {
      columns.add(songs.sublist(i, (i + 4 > songs.length) ? songs.length : i + 4));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final columnWidth = (screenWidth * 0.84).clamp(280.0, 360.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0033).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.flash_on_rounded, color: Color(0xFFFF0033), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        'Start radio or jump in',
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              TextButton(
                onPressed: () => audioHandler.playSong(songs.first, queue: songs),
                child: Text(
                  'Play All',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFFF0033),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 240, // 4 rows * ~56px + padding
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: columns.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, colIndex) {
              final columnSongs = columns[colIndex];
              return SizedBox(
                width: columnWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: columnSongs.map((song) {
                    return _buildSongRow(song);
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSongRow(Song song) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => audioHandler.playSong(song, queue: songs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: song.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: song.coverUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 150,
                          memCacheHeight: 150,
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 20),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceElevated,
                          child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 20),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 24),
                onPressed: () => audioHandler.playSong(song, queue: songs),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
