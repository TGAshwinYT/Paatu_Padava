import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/favorites_manager.dart';
import '../../services/download_manager.dart';
import '../../services/player_handler.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Song> _downloadedSongs = [];
  String _totalStorageSize = '0 MB';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDownloads();
  }

  void _loadDownloads() {
    setState(() {
      _downloadedSongs = DownloadManager.getDownloadedSongs();
      _totalStorageSize = DownloadManager.getFormattedTotalSize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Column(
          children: [
            // Screen Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'Your Library',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Tab Bar: Liked Songs / Offline Downloads
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
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.favorite_rounded, size: 18),
                    text: 'Liked Songs',
                  ),
                  Tab(
                    icon: Icon(Icons.download_done_rounded, size: 18),
                    text: 'Offline Downloads',
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
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
                children: const [
                  Icon(Icons.favorite_border_rounded, size: 48, color: Color(0xFF64748B)),
                  SizedBox(height: 14),
                  Text(
                    'No Liked Songs Yet',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tap the heart icon on any song to save it to your personal favorites collection!',
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
            // Action Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text('Play All (${favorites.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => audioHandler.playSong(favorites.first, queue: favorites),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

            // Liked Songs List
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
                          icon: const Icon(Icons.favorite_rounded, color: Color(0xFFEC4899), size: 22),
                          onPressed: () => FavoritesManager.toggleFavorite(song),
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

  Widget _buildDownloadsTab() {
    if (_downloadedSongs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
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

    return RefreshIndicator(
      color: const Color(0xFF6366F1),
      backgroundColor: const Color(0xFF131B2E),
      onRefresh: () async => _loadDownloads(),
      child: CustomScrollView(
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
                                '${_downloadedSongs.length} Tracks Offline',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Storage: $_totalStorageSize on device',
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
                      onPressed: () => audioHandler.playSong(_downloadedSongs.first, queue: _downloadedSongs),
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
                final song = _downloadedSongs[index];
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
                    _loadDownloads();
                  },
                  child: ListTile(
                    onTap: () => audioHandler.playSong(song, queue: _downloadedSongs),
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
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 20),
                      onPressed: () async {
                        await DownloadManager.deleteSong(song.id);
                        _loadDownloads();
                      },
                    ),
                  ),
                );
              },
              childCount: _downloadedSongs.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}
