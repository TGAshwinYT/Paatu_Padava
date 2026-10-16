import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/playlist_manager.dart';
import '../../services/player_handler.dart';
import '../widgets/join_playlist_dialog.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/library/create_blend_sheet.dart';
import '../widgets/mini_player.dart';
import 'playlist_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchActive = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCreatePlaylistDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Create New Playlist',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: GoogleFonts.outfit(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0A0E1A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1DB954), width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final title = textController.text.trim();
              if (title.isNotEmpty) {
                Navigator.pop(dialogCtx);
                final playlist = await PlaylistManager.createPlaylist(title);
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistScreen(playlistId: playlist.id),
                    ),
                  );
                }
              }
            },
            child: Text('Create', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

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

  Widget _buildBlendIcon() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Custom Sliver App Bar
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
                          hintText: 'Search playlists...',
                          hintStyle: GoogleFonts.outfit(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      )
                    : Text(
                        'Playlists',
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

              // Action Buttons Row: Create, Join, Blend, Spotify
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildActionButton(
                          label: 'Create',
                          icon: Icons.add_rounded,
                          color: const Color(0xFF1DB954),
                          onTap: _showCreatePlaylistDialog,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          label: 'Join Shared',
                          icon: Icons.group_add_rounded,
                          color: const Color(0xFF6366F1),
                          onTap: () => JoinPlaylistDialog.show(context),
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          label: 'Blend',
                          icon: Icons.auto_awesome_rounded,
                          color: const Color(0xFFEC4899),
                          onTap: () => CreateBlendSheet.show(context),
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          label: 'Import Spotify',
                          icon: Icons.album_rounded,
                          color: const Color(0xFF10B981),
                          onTap: () => SpotifyImportDialog.show(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Playlists Content
              ValueListenableBuilder<List<UserPlaylist>>(
                valueListenable: PlaylistManager.playlistsNotifier,
                builder: (context, playlists, _) {
                  final filtered = _searchQuery.isEmpty
                      ? playlists
                      : playlists.where((p) => p.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

                  if (filtered.isEmpty) {
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
                                  Icons.queue_music_rounded,
                                  size: 46,
                                  color: Color(0xFF818CF8),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _searchQuery.isEmpty ? 'No Playlists Yet' : 'No matching playlists',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'Create custom playlists, collaborate with friends, or blend your taste.'
                                    : 'Try searching for a different playlist title.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                              ),
                              if (_searchQuery.isEmpty) ...[
                                const SizedBox(height: 22),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1DB954),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  icon: const Icon(Icons.add_rounded, size: 20),
                                  label: Text(
                                    'Create Playlist',
                                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _showCreatePlaylistDialog,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final playlist = filtered[index];
                          final trackCount = playlist.tracks.length;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131B2E).withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: ListTile(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlaylistScreen(playlistId: playlist.id),
                                  ),
                                );
                              },
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: playlist.isBlend
                                      ? _buildBlendIcon()
                                      : (playlist.coverUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: playlist.coverUrl,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => _buildPlaylistIcon(),
                                            )
                                          : _buildPlaylistIcon()),
                                ),
                              ),
                              title: Text(
                                playlist.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  if (playlist.isBlend) ...[
                                    const Icon(Icons.auto_awesome_rounded, color: Color(0xFFEC4899), size: 13),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Blend • ${playlist.tasteMatchScore ?? 86}% Match • ',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFFEC4899),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ] else if (playlist.isCollaborative) ...[
                                    const Icon(Icons.group_rounded, color: Color(0xFF34D399), size: 13),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Shared • ',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFF34D399),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                      icon: const Icon(
                                        Icons.play_circle_filled_rounded,
                                        color: Color(0xFF1DB954),
                                        size: 28,
                                      ),
                                      tooltip: 'Play Playlist',
                                      onPressed: () => audioHandler.playSong(
                                        playlist.tracks.first,
                                        queue: playlist.tracks,
                                      ),
                                    ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                                    color: const Color(0xFF1E293B),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    onSelected: (val) {
                                      if (val == 'play_all' && trackCount > 0) {
                                        audioHandler.playSong(playlist.tracks.first, queue: playlist.tracks);
                                      } else if (val == 'add_to_queue' && trackCount > 0) {
                                        audioHandler.addAllToQueue(playlist.tracks);
                                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                const Icon(Icons.queue_music_rounded, color: Color(0xFF818CF8), size: 18),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    'Added "${playlist.title}" ($trackCount tracks) to queue',
                                                    style: const TextStyle(color: Colors.white),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: const Color(0xFF1E293B),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      } else if (val == 'delete') {
                                        PlaylistManager.deletePlaylist(playlist.id);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Deleted "${playlist.title}"')),
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (trackCount > 0) ...[
                                        const PopupMenuItem(
                                          value: 'play_all',
                                          child: Row(
                                            children: [
                                              Icon(Icons.play_arrow_rounded, color: Color(0xFF1DB954), size: 20),
                                              SizedBox(width: 10),
                                              Text('Play All', style: TextStyle(color: Colors.white, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'add_to_queue',
                                          child: Row(
                                            children: [
                                              Icon(Icons.queue_music_rounded, color: Colors.white70, size: 20),
                                              SizedBox(width: 10),
                                              Text('Add to Queue', style: TextStyle(color: Colors.white, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                            SizedBox(width: 10),
                                            Text('Delete Playlist', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
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
