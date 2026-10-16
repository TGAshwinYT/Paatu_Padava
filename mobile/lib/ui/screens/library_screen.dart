import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/models/history_entry.dart';
import '../../models/song.dart';
import '../../services/favorites_manager.dart';
import '../../services/download_manager.dart';
import '../../services/playlist_manager.dart';
import '../../services/history_manager.dart';
import '../../services/player_handler.dart';
import '../../services/auth_manager.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/sync_status_indicator.dart';
import '../widgets/account_bar_button.dart';
import 'playlists_screen.dart';
import 'liked_songs_screen.dart';
import 'history_screen.dart';
import 'offline_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'listening_recap_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
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

  Widget _buildBentoCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
              ],
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCover(UserPlaylist playlist) {
    if (playlist.isBlend) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
      );
    }
    if (playlist.coverUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: playlist.coverUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _buildFallbackPlaylistCover(),
      );
    }
    return _buildFallbackPlaylistCover();
  }

  Widget _buildFallbackPlaylistCover() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.queue_music_rounded, color: Colors.white54, size: 22),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top App Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Library',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SyncStatusIndicator(showLabel: true),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
                          tooltip: 'Settings & Equalizer',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        const AccountBarButton(),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Persistent Guest Mode Banner
            SliverToBoxAdapter(
              child: ValueListenableBuilder<AuthUser?>(
                valueListenable: AuthManager.authNotifier,
                builder: (context, user, _) {
                  if (user == null || user.isGuest) {
                    return Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131B2E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF9333EA).withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: Color(0xFF9333EA), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Guest Mode: Library is saved to this device. Sign in to sync across devices.',
                              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => AuthDialog.show(context),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF9333EA),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            child: Text('Sign In', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),

            // Bento Grid of 4 Hub Boxes (Playlists, Liked Songs, History, Offline)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        // Box 1: Playlists (No Liked Songs)
                        SizedBox(
                          width: itemWidth,
                          child: ValueListenableBuilder<List<UserPlaylist>>(
                            valueListenable: PlaylistManager.playlistsNotifier,
                            builder: (context, playlists, _) {
                              return _buildBentoCard(
                                title: 'Playlists',
                                subtitle: '${playlists.length} ${playlists.length == 1 ? "playlist" : "playlists"}',
                                icon: Icons.queue_music_rounded,
                                gradientColors: const [Color(0xFF2563EB), Color(0xFF1E3A8A)],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
                                  );
                                },
                              );
                            },
                          ),
                        ),

                        // Box 2: Liked Songs
                        SizedBox(
                          width: itemWidth,
                          child: ValueListenableBuilder<List<Song>>(
                            valueListenable: FavoritesManager.favoritesNotifier,
                            builder: (context, favs, _) {
                              return _buildBentoCard(
                                title: 'Liked Songs',
                                subtitle: '${favs.length} ${favs.length == 1 ? "track" : "tracks"}',
                                icon: Icons.favorite_rounded,
                                gradientColors: const [Color(0xFF7C3AED), Color(0xFFEC4899)],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                                  );
                                },
                              );
                            },
                          ),
                        ),

                        // Box 3: History
                        SizedBox(
                          width: itemWidth,
                          child: ValueListenableBuilder<List<HistoryEntry>>(
                            valueListenable: HistoryManager.historyEntriesNotifier,
                            builder: (context, history, _) {
                              return _buildBentoCard(
                                title: 'History',
                                subtitle: '${history.length} played',
                                icon: Icons.history_rounded,
                                gradientColors: const [Color(0xFF0284C7), Color(0xFF0F172A)],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                                  );
                                },
                              );
                            },
                          ),
                        ),

                        // Box 4: Offline / Downloaded
                        SizedBox(
                          width: itemWidth,
                          child: ValueListenableBuilder<List<Song>>(
                            valueListenable: DownloadManager.downloadedSongsNotifier,
                            builder: (context, downloads, _) {
                              return _buildBentoCard(
                                title: 'Offline',
                                subtitle: '${downloads.length} downloaded',
                                icon: Icons.download_done_rounded,
                                gradientColors: const [Color(0xFF059669), Color(0xFF064E3B)],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const OfflineScreen()),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // Paatu Recap 2026 Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ListeningRecapScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B0764), Color(0xFF1E1B4B)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.35)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA855F7).withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFC084FC), size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Paatu Recap 2026',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Discover your top tracks, artists, and music persona',
                                style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFC084FC), size: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Spotify Quick Import Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                child: InkWell(
                  onTap: () => SpotifyImportDialog.show(context),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x331DB954)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.album_rounded, color: Color(0xFF1DB954), size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Import Spotify Playlist',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Sync your Spotify playlists with 320kbps Lossless audio',
                                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Shelf Header: "Your Playlists" & "See All"
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Playlists',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF818CF8),
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        children: [
                          Text('See All', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 11),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Playlists List (NO Liked Songs!)
            ValueListenableBuilder<List<UserPlaylist>>(
              valueListenable: PlaylistManager.playlistsNotifier,
              builder: (context, playlists, _) {
                if (playlists.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131B2E).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.queue_music_rounded, color: Color(0xFF64748B), size: 36),
                          const SizedBox(height: 10),
                          Text(
                            'No Playlists Created Yet',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Create your first playlist or import from Spotify.',
                            style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1DB954),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(
                              'Create Playlist',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            onPressed: _showCreatePlaylistDialog,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Show top user playlists
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final playlist = playlists[index];
                        final trackCount = playlist.tracks.length;

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2E).withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
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
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: _buildPlaylistCover(playlist),
                              ),
                            ),
                            title: Text(
                              playlist.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                if (playlist.isBlend) ...[
                                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFFEC4899), size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Blend • ',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFFEC4899),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ] else if (playlist.isCollaborative) ...[
                                  const Icon(Icons.group_rounded, color: Color(0xFF34D399), size: 12),
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
                                      size: 26,
                                    ),
                                    onPressed: () => audioHandler.playSong(
                                      playlist.tracks.first,
                                      queue: playlist.tracks,
                                    ),
                                  ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: playlists.length > 5 ? 5 : playlists.length,
                    ),
                  ),
                );
              },
            ),

            // Bottom space for MiniPlayer
            const SliverToBoxAdapter(
              child: SizedBox(height: 110),
            ),
          ],
        ),
      ),
    );
  }
}
