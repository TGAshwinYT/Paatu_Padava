import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/song.dart';
import '../../../services/playlist_manager.dart';
import '../../../services/favorites_manager.dart';
import '../../../services/player_handler.dart';
import '../join_playlist_dialog.dart';
import '../../screens/playlist_screen.dart';
import '../../screens/liked_songs_screen.dart';

class PlaylistsTabView extends StatelessWidget {
  final VoidCallback onCreatePlaylist;

  const PlaylistsTabView({
    super.key,
    required this.onCreatePlaylist,
  });

  Widget _buildPlaylistIcon() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.queue_music_rounded, color: Colors.white54, size: 24),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<UserPlaylist>>(
      valueListenable: PlaylistManager.playlistsNotifier,
      builder: (context, playlists, _) {
        return CustomScrollView(
          slivers: [
            // Create Playlist & Join Shared Buttons
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onCreatePlaylist,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF1DB954).withValues(alpha: 0.18),
                                const Color(0xFF131B2E),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 16,
                                backgroundColor: Color(0xFF1DB954),
                                child: Icon(Icons.add_rounded, color: Colors.black, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Create Playlist',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => JoinPlaylistDialog.show(context),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF6366F1).withValues(alpha: 0.18),
                                const Color(0xFF131B2E),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 16,
                                backgroundColor: Color(0xFF6366F1),
                                child: Icon(Icons.group_add_rounded, color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Join Shared',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Pinned Spotify-style "Liked Songs" Playlist Row
            SliverToBoxAdapter(
              child: ValueListenableBuilder<List<Song>>(
                valueListenable: FavoritesManager.favoritesNotifier,
                builder: (context, favs, _) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                        );
                      },
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 26),
                      ),
                      title: Text(
                        'Liked Songs',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Text(
                        '${favs.length} ${favs.length == 1 ? "song" : "songs"} • Auto playlist',
                        style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (favs.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.play_circle_filled_rounded, color: Color(0xFF1DB954), size: 28),
                              onPressed: () => audioHandler.playSong(favs.first, queue: favs),
                            ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            if (playlists.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.queue_music_rounded, size: 48, color: Color(0xFF64748B)),
                      const SizedBox(height: 14),
                      Text(
                        'No Custom Playlists Yet',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap "Create New Playlist" above or import playlists from Spotify!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final playlist = playlists[index];
                    final trackCount = playlist.tracks.length;

                    return ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlaylistScreen(playlistId: playlist.id),
                          ),
                        );
                      },
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: playlist.coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: playlist.coverUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _buildPlaylistIcon(),
                                )
                              : _buildPlaylistIcon(),
                        ),
                      ),
                      title: Text(
                        playlist.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Row(
                        children: [
                          if (playlist.isCollaborative) ...[
                            const Icon(Icons.group_rounded, color: Color(0xFF34D399), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Shared • ',
                              style: GoogleFonts.outfit(color: const Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                          Text(
                            '$trackCount ${trackCount == 1 ? "track" : "tracks"}',
                            style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (trackCount > 0)
                            IconButton(
                              icon: const Icon(Icons.play_circle_filled_rounded, color: Color(0xFF1DB954), size: 28),
                              onPressed: () => audioHandler.playSong(playlist.tracks.first, queue: playlist.tracks),
                            ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
                        ],
                      ),
                    );
                  },
                  childCount: playlists.length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }
}
