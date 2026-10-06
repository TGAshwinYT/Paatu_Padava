import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/song.dart';
import '../../services/favorites_manager.dart';
import '../../services/download_manager.dart';
import '../../services/playlist_manager.dart';
import '../../services/player_handler.dart';
import '../../services/auth_manager.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/sync_status_indicator.dart';
import '../widgets/account_bar_button.dart';
import '../widgets/library/playlists_tab_view.dart';
import '../widgets/library/liked_songs_tab_view.dart';
import '../widgets/library/history_tab_view.dart';
import '../widgets/library/downloads_tab_view.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'listening_recap_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCreatePlaylistDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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

  void _showSongContextMenu(Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded, color: Color(0xFF6366F1)),
              title: const Text('Play Next', style: TextStyle(color: Colors.white)),
              onTap: () {
                audioHandler.insertNext(song);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Playing "${song.title}" next')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded, color: Colors.white70),
              title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
              onTap: () {
                audioHandler.addToQueue(song);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added "${song.title}" to queue')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8)),
              title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                AddToPlaylistDialog.show(context, song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
              title: const Text('Download Offline', style: TextStyle(color: Colors.white)),
              onTap: () {
                DownloadManager.downloadSong(song);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border_rounded, color: Color(0xFFEC4899)),
              title: const Text('Like / Favorite', style: TextStyle(color: Colors.white)),
              onTap: () {
                FavoritesManager.toggleFavorite(song);
                Navigator.pop(context);
              },
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
      body: SafeArea(
        child: Column(
          children: [
            // Screen Header with Settings & Auth Profile
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Library',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
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

            // Persistent Guest Mode Banner for Library
            ValueListenableBuilder<AuthUser?>(
              valueListenable: AuthManager.authNotifier,
              builder: (context, user, _) {
                if (user == null || user.isGuest) {
                  return Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                            'Guest Mode: Playlists are saved to this device only. Sign in to backup and sync across devices.',
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

            // Spotify Quick Import Banner in Library
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: InkWell(
                onTap: () => SpotifyImportDialog.show(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x331DB954)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.album_rounded, color: Color(0xFF1DB954), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Import Spotify Playlist',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Save Spotify playlists or play in 320kbps Lossless',
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

            // Paatu Recap Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ListeningRecapScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B0764), Color(0xFF1E1B4B)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA855F7).withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.auto_awesome, color: Color(0xFFC084FC), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Paatu Recap 2026',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Discover your top tracks, artists, and music persona',
                              style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11),
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

            // Tab Bar: 4 Tabs (Playlists, Liked, History, Offline)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF131B2E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF1DB954),
                  borderRadius: BorderRadius.circular(14),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.black,
                unselectedLabelColor: const Color(0xFF94A3B8),
                labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.queue_music_rounded, size: 17),
                    text: 'Playlists',
                  ),
                  Tab(
                    icon: Icon(Icons.favorite_rounded, size: 17),
                    text: 'Liked',
                  ),
                  Tab(
                    icon: Icon(Icons.history_rounded, size: 17),
                    text: 'History',
                  ),
                  Tab(
                    icon: Icon(Icons.download_done_rounded, size: 17),
                    text: 'Offline',
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  PlaylistsTabView(onCreatePlaylist: _showCreatePlaylistDialog),
                  LikedSongsTabView(onSongContextMenu: _showSongContextMenu),
                  HistoryTabView(onSongContextMenu: _showSongContextMenu),
                  const DownloadsTabView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
