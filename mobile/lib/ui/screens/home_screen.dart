import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/api_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../../services/favorites_manager.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> _languages = ['Tamil', 'Telugu', 'Hindi', 'Malayalam', 'English', 'Kannada'];
  String _selectedLanguage = 'Tamil';

  List<Song> _forYouSongs = [];
  List<Song> _trendingSongs = [];
  List<Map<String, dynamic>> _topAlbums = [];
  List<Map<String, dynamic>> _topArtists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    setState(() => _isLoading = true);

    try {
      // Load in parallel
      final results = await Future.wait([
        SaavnClient.getTrending(language: _selectedLanguage),
        ApiClient.fetchForYou(),
        SaavnClient.searchAlbums('$_selectedLanguage Hit Albums', limit: 10),
        SaavnClient.searchArtists('Top $_selectedLanguage Artists', limit: 10),
      ]);

      if (mounted) {
        setState(() {
          _trendingSongs = results[0] as List<Song>;
          _forYouSongs = results[1] as List<Song>;
          _topAlbums = results[2] as List<Map<String, dynamic>>;
          _topArtists = results[3] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onLanguageSelected(String lang) {
    if (_selectedLanguage == lang) return;
    setState(() => _selectedLanguage = lang);
    _loadHomeData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF6366F1),
          backgroundColor: const Color(0xFF131B2E),
          onRefresh: _loadHomeData,
          child: CustomScrollView(
            slivers: [
              // Top Bar Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Paatu Padava',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                'Lossless 320kbps • Client Player',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Smart Radio Button
                      InkWell(
                        onTap: () async {
                          if (_trendingSongs.isNotEmpty) {
                            final first = _trendingSongs.first;
                            await audioHandler.playSong(first, queue: _trendingSongs);
                            audioHandler.addRadioMix();
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2E),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.radio_rounded, color: Color(0xFF6366F1), size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Radio',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Regional Language Chips
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    scrollDirection: Axis.horizontal,
                    itemCount: _languages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final lang = _languages[index];
                      final isSelected = lang == _selectedLanguage;
                      return ChoiceChip(
                        label: Text(lang),
                        selected: isSelected,
                        selectedColor: const Color(0xFF6366F1),
                        backgroundColor: const Color(0xFF131B2E),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF6366F1) : Colors.white.withOpacity(0.06),
                          ),
                        ),
                        onSelected: (_) => _onLanguageSelected(lang),
                      );
                    },
                  ),
                ),
              ),

              // Loading Spinner
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                  ),
                )
              else ...[
                // "Made For You" Collaborative Mix
                if (_forYouSongs.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Made For You (AI Graph)',
                                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          TextButton(
                            child: const Text('Play All', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                            onPressed: () => audioHandler.playSong(_forYouSongs.first, queue: _forYouSongs),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 190,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: _forYouSongs.length,
                        itemBuilder: (context, index) {
                          final song = _forYouSongs[index];
                          return _SongCard(
                            song: song,
                            onTap: () => audioHandler.playSong(song, queue: _forYouSongs),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // "Top Artists" Avatars
                if (_topArtists.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
                      child: Text(
                        'Popular Artists',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 110,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: _topArtists.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          final art = _topArtists[index];
                          final name = art['name']?.toString() ?? 'Artist';
                          final img = art['image']?.toString() ?? '';
                          final id = art['id']?.toString() ?? '';

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArtistScreen(
                                    artistId: id,
                                    artistName: name,
                                    imageUrl: img,
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 36,
                                  backgroundColor: const Color(0xFF131B2E),
                                  backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // "Top Albums"
                if (_topAlbums.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Text(
                        'Featured Albums',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 180,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: _topAlbums.length,
                        itemBuilder: (context, index) {
                          final album = _topAlbums[index];
                          final id = album['id']?.toString() ?? '';
                          final title = album['title']?.toString() ?? 'Album';
                          final img = album['image']?.toString() ?? '';
                          final artist = album['artist']?.toString() ?? '';

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AlbumScreen(
                                    albumId: id,
                                    albumTitle: title,
                                    imageUrl: img,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: 130,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: SizedBox(
                                      width: 130,
                                      height: 130,
                                      child: CachedNetworkImage(
                                        imageUrl: img,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // "Trending Now" Section Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '🔥 Trending $_selectedLanguage Tracks',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (_trendingSongs.isNotEmpty)
                          TextButton.icon(
                            icon: const Icon(Icons.play_circle_fill_rounded, size: 18, color: Color(0xFF6366F1)),
                            label: const Text('Play All', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                            onPressed: () => audioHandler.playSong(_trendingSongs.first, queue: _trendingSongs),
                          ),
                      ],
                    ),
                  ),
                ),

                // Trending Songs List
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = _trendingSongs[index];
                      return _SongTile(
                        song: song,
                        onTap: () => audioHandler.playSong(song, queue: _trendingSongs),
                      );
                    },
                    childCount: _trendingSongs.length,
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _SongCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 135,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 135,
                    height: 135,
                    child: CachedNetworkImage(
                      imageUrl: song.coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF6366F1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _SongTile({required this.song, required this.onTap});

  void _showContextMenu(BuildContext context) {
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
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;

        return ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
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
              if (isPlaying)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.equalizer_rounded, color: Color(0xFF6366F1), size: 24),
                ),
            ],
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying ? const Color(0xFF6366F1) : Colors.white,
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
            onPressed: () => _showContextMenu(context),
          ),
        );
      },
    );
  }
}
