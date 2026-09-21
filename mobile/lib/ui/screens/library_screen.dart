import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/favorites_manager.dart';
import '../../services/download_manager.dart';
import '../../services/playlist_manager.dart';
import '../../services/player_handler.dart';
import '../../services/auth_manager.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/add_to_playlist_dialog.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Create New Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0A0E1A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
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
            child: const Text('Create'),
          ),
        ],
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
                  const Text(
                    'Your Library',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                              side: BorderSide(color: isUser ? const Color(0xFF6366F1) : Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            icon: Icon(
                              isUser ? Icons.person_rounded : Icons.login_rounded,
                              size: 16,
                              color: isUser ? const Color(0xFF6366F1) : Colors.white70,
                            ),
                            label: Text(
                              (user != null && !user.isGuest) ? user.username : 'Sign In',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Import Spotify Playlist',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Save Spotify playlists or play in 320kbps Lossless',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
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

            // Tab Bar: 3 Tabs (Playlists, Liked Songs, Downloads)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF131B2E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF94A3B8),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: InkWell(
                  onTap: _showCreatePlaylistDialog,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6366F1).withOpacity(0.25),
                          const Color(0xFF131B2E),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                    ),
                    child: const Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Color(0xFF6366F1),
                          child: Icon(Icons.add_rounded, color: Colors.white, size: 22),
                        ),
                        SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create New Playlist',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Custom collections saved locally & synced to cloud',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (playlists.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.queue_music_rounded, size: 48, color: Color(0xFF64748B)),
                        SizedBox(height: 14),
                        Text(
                          'No Custom Playlists Yet',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Tap "Create New Playlist" above or import playlists from Spotify!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                      ],
                    ),
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
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        '$trackCount ${trackCount == 1 ? "track" : "tracks"}',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (trackCount > 0)
                            IconButton(
                              icon: const Icon(Icons.play_circle_filled_rounded, color: Color(0xFF6366F1), size: 28),
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
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border_rounded, size: 48, color: Color(0xFF64748B)),
                  SizedBox(height: 14),
                  Text(
                    'No Liked Songs Yet',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Heart songs while listening to save them to your personal favorites library!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        return CustomScrollView(
          slivers: [
            // Play All & Shuffle Actions
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: Text('Play All (${favorites.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      label: const Text('Shuffle'),
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
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
                          icon: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF64748B), size: 22),
                          onPressed: () => DownloadManager.downloadSong(song),
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

  // ================= 3. Downloads Tab ================= //

  Widget _buildDownloadsTab() {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: DownloadManager.downloadedSongsNotifier,
      builder: (context, downloadedSongs, _) {
        if (downloadedSongs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.offline_pin_outlined, size: 48, color: Color(0xFF64748B)),
                  SizedBox(height: 14),
                  Text(
                    'No Offline Songs',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Download any track to enjoy seamless 320kbps offline playback with zero internet!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
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
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Storage: $totalSizeStr on device',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
                        label: const Text('Play Offline', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
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
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
