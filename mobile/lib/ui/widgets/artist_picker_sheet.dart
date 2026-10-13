import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/song.dart';
import '../../services/artist_sanitizer.dart';
import '../screens/artist_screen.dart';

/// Spotify-style multi-artist picker modal sheet and navigation coordinator.
/// When a song has a single artist, navigates directly to that artist's page.
/// When a song has multiple collaborating artists (e.g. "Anirudh Ravichander, Sai Abhyankkar"),
/// presents a clean modal bottom sheet letting the user choose which artist to explore.
class ArtistPickerSheet {
  /// Navigates directly to an artist screen
  static void navigateToArtist(
    BuildContext context, {
    required String artistName,
    String? artistId,
    String? imageUrl,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArtistScreen(
          artistId: artistId ?? '',
          artistName: artistName,
          imageUrl: imageUrl ?? '',
        ),
      ),
    );
  }

  /// Handles tap on an artist label or area.
  /// If single artist -> opens directly.
  /// If multiple artists -> opens Spotify-style modal bottom sheet.
  static void show(
    BuildContext context, {
    required Song song,
  }) {
    final artists = ArtistSanitizer.extractAllGenuineArtists(song.artist);

    if (artists.length <= 1) {
      final targetArtist = artists.isNotEmpty ? artists.first : song.artist;
      navigateToArtist(
        context,
        artistName: targetArtist,
        artistId: song.artistId,
        imageUrl: song.coverUrl,
      );
      return;
    }

    // Spotify-style "Go to artist" selection bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      barrierColor: Colors.black.withValues(alpha: 0.65),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top drag indicator
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_pin_rounded,
                          color: Color(0xFF818CF8),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Go to artist',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Select an artist to view their full catalog',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                const SizedBox(height: 8),

                // Artist List
                ...artists.map((artist) {
                  final isPrimary = artist.toLowerCase() == song.primaryArtist.toLowerCase();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF6366F1).withValues(alpha: 0.8),
                            const Color(0xFF3B82F6).withValues(alpha: 0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          artist.isNotEmpty ? artist[0].toUpperCase() : 'A',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      artist,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      isPrimary ? 'Primary Artist' : 'Collaborating Artist',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF64748B),
                      size: 14,
                    ),
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      navigateToArtist(
                        context,
                        artistName: artist,
                        artistId: isPrimary ? song.artistId : '',
                        imageUrl: song.coverUrl,
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
