import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/favorites_manager.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/mini_player.dart';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({Key? key}) : super(key: key);

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: song.coverUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: Colors.white10, child: const Icon(Icons.music_note)),
                  ),
                ),
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: Colors.white70),
                title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  AddToPlaylistDialog.show(context, song);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded, color: Colors.white70),
                title: const Text('Play Next', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  audioHandler.insertNext(song);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Playing "${song.title}" next!'), backgroundColor: const Color(0xFF6366F1)),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined, color: Colors.white70),
                title: const Text('Download Offline', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  DownloadManager.downloadSong(song);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Downloading "${song.title}"...'), backgroundColor: const Color(0xFF10B981)),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite_rounded, color: Color(0xFFEC4899)),
                title: const Text('Remove from Liked Songs', style: TextStyle(color: Color(0xFFEC4899))),
                onTap: () {
                  Navigator.pop(ctx);
                  FavoritesManager.toggleFavorite(song);
                },
              ),
            ],
          ),
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
          ValueListenableBuilder<List<Song>>(
            valueListenable: FavoritesManager.favoritesNotifier,
            builder: (context, favorites, _) {
              final filtered = _filterQuery.isEmpty
                  ? favorites
                  : favorites.where((s) =>
                      s.title.toLowerCase().contains(_filterQuery.toLowerCase()) ||
                      s.artist.toLowerCase().contains(_filterQuery.toLowerCase())).toList();

              return CustomScrollView(
                slivers: [
                  // Spotify-Style Gradient Header
                  SliverAppBar(
                    expandedHeight: 280,
                    pinned: true,
                    backgroundColor: const Color(0xFF1E1B4B),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF4338CA),
                              Color(0xFF312E81),
                              Color(0xFF0A0E1A),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 70, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF4F46E5), Color(0xFFEC4899)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFEC4899).withOpacity(0.35),
                                          blurRadius: 20,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 44),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'PLAYLIST',
                                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Liked Songs',
                                          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${favorites.length} songs',
                                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Actions & Filter Bar
                  if (favorites.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Big Spotify Green Play Button
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1DB954),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                elevation: 6,
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
                              label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                              onPressed: () => audioHandler.playSong(favorites.first, queue: favorites),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.shuffle_rounded, color: Colors.white70, size: 24),
                                  tooltip: 'Shuffle Play',
                                  onPressed: () {
                                    final shuffled = List<Song>.from(favorites)..shuffle();
                                    audioHandler.playSong(shuffled.first, queue: shuffled);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.download_for_offline_outlined, color: Colors.white70, size: 24),
                                  tooltip: 'Download All',
                                  onPressed: () {
                                    for (final s in favorites) {
                                      DownloadManager.downloadSong(s);
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Downloading ${favorites.length} liked songs...'), backgroundColor: const Color(0xFF10B981)),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Filter search input
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: TextField(
                            controller: _filterController,
                            onChanged: (val) => setState(() => _filterQuery = val.trim()),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search in liked songs...',
                              hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                              suffixIcon: _filterQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                                      onPressed: () {
                                        _filterController.clear();
                                        setState(() => _filterQuery = '');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Empty State
                  if (favorites.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF131B2E),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                                ),
                                child: const Icon(Icons.favorite_outline_rounded, size: 52, color: Color(0xFFEC4899)),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'No liked songs yet',
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Tap the heart icon on any track to save it here for instant access anytime.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Explore Music', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    // Songs List
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final song = filtered[index];
                            return ValueListenableBuilder<Song?>(
                              valueListenable: audioHandler.currentSongNotifier,
                              builder: (context, currentPlaying, _) {
                                final isPlaying = currentPlaying?.id == song.id;
                                return ListTile(
                                  onTap: () => audioHandler.playSong(song, queue: filtered),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  leading: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: song.coverUrl,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Container(
                                            width: 48,
                                            height: 48,
                                            color: Colors.white10,
                                            child: const Icon(Icons.music_note, color: Colors.white38),
                                          ),
                                        ),
                                      ),
                                      if (isPlaying)
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.55),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.equalizer_rounded, color: Color(0xFF1DB954), size: 22),
                                        ),
                                    ],
                                  ),
                                  title: Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isPlaying ? const Color(0xFF1DB954) : Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.favorite_rounded, color: Color(0xFFEC4899), size: 20),
                                        onPressed: () => FavoritesManager.toggleFavorite(song),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                                        onPressed: () => _showSongOptions(context, song),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                ],
              );
            },
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
