import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';
import 'home_song_card.dart';

/// Reusable, highly responsive horizontal song carousel shelf for HomeScreen.
/// Standardizes title typography, card sizing, horizontal snap physics,
/// and instant 1-tap playback across all home feed sections.
class HomeSongShelf extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Song> songs;
  final double cardWidth;
  final double carouselHeight;
  final VoidCallback? onPlayAll;
  final VoidCallback? onSeeAll;

  const HomeSongShelf({
    super.key,
    required this.title,
    required this.icon,
    this.iconColor = AppColors.neonViolet,
    required this.songs,
    required this.cardWidth,
    required this.carouselHeight,
    this.onPlayAll,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shelf Header: Icon + Title + Action Button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: iconColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onPlayAll != null)
                TextButton(
                  onPressed: onPlayAll,
                  style: TextButton.styleFrom(
                    foregroundColor: iconColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Play All',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                )
              else if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: iconColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'See All',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),

        // Horizontal Carousel
        SizedBox(
          height: carouselHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return HomeSongCard(
                song: song,
                width: cardWidth,
                onTap: () => audioHandler.playSong(song, queue: songs),
              );
            },
          ),
        ),
      ],
    );
  }
}
