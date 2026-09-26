import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/favorites_manager.dart';
import '../../services/download_manager.dart';
import '../../services/playlist_manager.dart';
import '../../services/player_handler.dart';
import '../../services/history_manager.dart';
import '../../services/auth_manager.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/sync_status_indicator.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'liked_songs_screen.dart';

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
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
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
                      ValueListenableBuilder<AuthUser?>(
                        valueListenable: AuthManager.authNotifier,
                        builder: (context, user, _) {
                          final isUser = user != null && !user.isGuest;
                          return OutlinedButton.icon(
                            onPressed: () => AuthDialog.show(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: isUser ? const Color(0xFF1DB954) : Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            icon: Icon(
                              isUser ? Icons.person_rounded : Icons.login_rounded,
                              size: 16,
                              color: isUser ? const Color(0xFF1DB954) : Colors.white70,
                            ),
                            label: Text(
                              (user != null && !user.isGuest) ? user.username : 'Sign In',
                              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
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
                          color: const Color(0xFF1DB954).withOpacity(0.2),
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
                  _buildPlaylistsTab(),
                  _buildLikedSongsTab(),
                  _buildHistoryTab(),
                  _buildDownloadsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 1. Playlists Tab ================= //

  Widget _buildPlaylistsTab() {
    return ValueListenableBuilder<List<UserPlaylist>>(
      valueListenable: PlaylistManager.playlistsNotifier,
      builder: (context, playlists, _) {
        return CustomScrollView(
          slivers: [
            // Create Playlist Banner Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: InkWell(
                  onTap: _showCreatePlaylistDialog,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1DB954).withOpacity(0.18),
                          const Color(0xFF131B2E),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1DB954).withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 18,
                          backgroundColor: Color(0xFF1DB954),
                          child: Icon(Icons.add_rounded, color: Colors.black, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create New Playlist',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Custom collections saved locally & synced to cloud',
                              style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
                      subtitle: Text(
                        '$trackCount ${trackCount == 1 ? "track" : "tracks"}',
                        style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
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

  // ================= 2. Liked Songs Tab ================= //

  Widget _buildLikedSongsTab() {
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
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
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
                          onPressed: () => _showSongContextMenu(song),
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

  // ================= 3. History Tab ================= //

  Widget _buildHistoryTab() {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: HistoryManager.historyNotifier,
      builder: (context, history, _) {
        if (history.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history_rounded, size: 48, color: Color(0xFF64748B)),
                  const SizedBox(height: 14),
                  Text(
                    'No Listening History Yet',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Songs you stream or play offline will automatically appear here.',
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text('Play All (${history.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      onPressed: () => audioHandler.playSong(history.first, queue: history),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.clear_all_rounded, size: 18, color: Color(0xFF64748B)),
                      label: Text('Clear', style: GoogleFonts.outfit(color: const Color(0xFF64748B))),
                      onPressed: () => HistoryManager.clear(),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = history[index];
                  return ListTile(
                    onTap: () => audioHandler.playSong(song, queue: history),
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
                          onPressed: () => AddToPlaylistDialog.show(context, song),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B), size: 20),
                          onPressed: () => _showSongContextMenu(song),
                        ),
                      ],
                    ),
                  );
                },
                childCount: history.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }

  // ================= 4. Downloads Tab ================= //

  Widget _buildDownloadsTab() {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: DownloadManager.downloadedSongsNotifier,
      builder: (context, downloadedSongs, _) {
        if (downloadedSongs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.offline_pin_outlined, size: 48, color: Color(0xFF64748B)),
                  const SizedBox(height: 14),
                  Text(
                    'No Offline Songs',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Download any track to enjoy seamless 320kbps offline playback with zero internet!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        final totalSizeStr = DownloadManager.getFormattedTotalSize();

        return CustomScrollView(
          slivers: [
            // Storage Summary Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.offline_pin_rounded, size: 16, color: Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                Text(
                                  '${downloadedSongs.length} Tracks Offline',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Storage: $totalSizeStr on device',
                              style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text('Play Offline', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        onPressed: () => audioHandler.playSong(downloadedSongs.first, queue: downloadedSongs),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Downloaded Songs List
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = downloadedSongs[index];
                  return Dismissible(
                    key: Key('offline_${song.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.redAccent.withOpacity(0.8),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) async {
                      await DownloadManager.deleteSong(song.id);
                    },
                    child: ListTile(
                      onTap: () => audioHandler.playSong(song, queue: downloadedSongs),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: (song.localFilePath != null && File(song.localFilePath!).existsSync())
                              ? Image.file(File(song.localFilePath!), fit: BoxFit.cover)
                              : (song.coverUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: song.coverUrl,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                                    )
                                  : Container(color: const Color(0xFF1E293B))),
                        ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Row(
                        children: [
                          const Icon(Icons.offline_pin_rounded, size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8), size: 20),
                            onPressed: () => AddToPlaylistDialog.show(context, song),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 20),
                            onPressed: () async {
                              await DownloadManager.deleteSong(song.id);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: downloadedSongs.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }
}
