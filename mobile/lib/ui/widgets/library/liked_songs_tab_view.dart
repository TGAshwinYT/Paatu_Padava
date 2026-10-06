import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/song.dart';
import '../../../services/favorites_manager.dart';
import '../../../services/player_handler.dart';
import '../add_to_playlist_dialog.dart';
import '../../screens/liked_songs_screen.dart';

class LikedSongsTabView extends StatelessWidget {
  final void Function(Song song) onSongContextMenu;

  const LikedSongsTabView({
    super.key,
    required this.onSongContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: FavoritesManager.favoritesNotifier,
      builder: (context, favorites, _) {
        if (favorites.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite_border_rounded, size: 48, color: Color(0xFF64748B)),
                  const SizedBox(height: 14),
                  Text(
                    'No Liked Songs Yet',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Heart songs while listening to save them to your personal favorites library!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        return CustomScrollView(
          slivers: [
            // Prominent Full-Screen Link
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Open Full Liked Songs Experience',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Play All & Shuffle Actions
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: Text('Play All (${favorites.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      onPressed: () => audioHandler.playSong(favorites.first, queue: favorites),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: Text('Shuffle', style: GoogleFonts.outfit()),
                      onPressed: () {
                        final shuffled = List<Song>.from(favorites)..shuffle();
                        audioHandler.playSong(shuffled.first, queue: shuffled);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Favorites List
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = favorites[index];
                  return ListTile(
                    onTap: () => audioHandler.playSong(song, queue: favorites),
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
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8), size: 22),
                          tooltip: 'Add to Playlist',
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
                childCount: favorites.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }
}
