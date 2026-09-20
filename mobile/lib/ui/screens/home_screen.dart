import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> _languages = ['Tamil', 'Telugu', 'Hindi', 'Malayalam', 'English', 'Kannada'];
  String _selectedLanguage = 'Tamil';

  List<Song> _trendingSongs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTrending();
  }

  Future<void> _fetchTrending() async {
    setState(() => _isLoading = true);
    final songs = await SaavnClient.getTrending(language: _selectedLanguage);
    if (mounted) {
      setState(() {
        _trendingSongs = songs;
        _isLoading = false;
      });
    }
  }

  void _onLanguageSelected(String lang) {
    if (_selectedLanguage == lang) return;
    setState(() => _selectedLanguage = lang);
    _fetchTrending();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF6366F1),
          backgroundColor: const Color(0xFF1E293B),
          onRefresh: _fetchTrending,
          child: CustomScrollView(
            slivers: [
              // Custom Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                              borderRadius: BorderRadius.circular(12),
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
                                'Lossless 320kbps • Client Stream',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Offline indicator icon badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.bolt_rounded, color: Color(0xFF10B981), size: 16),
                            SizedBox(width: 4),
                            Text(
                              'P2P Fast',
                              style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Language Horizontal Selector Chips
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
                        backgroundColor: const Color(0xFF1E293B),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF6366F1) : Colors.white.withOpacity(0.05),
                          ),
                        ),
                        onSelected: (_) => _onLanguageSelected(lang),
                      );
                    },
                  ),
                ),
              ),

              // Horizontal Spotlight Cards (Top 5 songs)
              if (!_isLoading && _trendingSongs.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '🔥 Trending $_selectedLanguage',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_trendingSongs.length} Tracks',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _trendingSongs.take(8).length,
                      itemBuilder: (context, index) {
                        final song = _trendingSongs[index];
                        return _FeaturedSongCard(
                          song: song,
                          onTap: () => audioHandler.playSong(song, queue: _trendingSongs),
                        );
                      },
                    ),
                  ),
                ),
              ],

              // Vertical Song List Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Top Recommended',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_trendingSongs.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.play_circle_fill_rounded, size: 18, color: Color(0xFF6366F1)),
                          label: const Text(
                            'Play All',
                            style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            if (_trendingSongs.isNotEmpty) {
                              audioHandler.playSong(_trendingSongs.first, queue: _trendingSongs);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),

              // Loading State or Songs List
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                  ),
                )
              else if (_trendingSongs.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.music_off_rounded, size: 48, color: Color(0xFF64748B)),
                        const SizedBox(height: 12),
                        const Text(
                          'No songs found. Pull down to refresh.',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _fetchTrending,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = _trendingSongs[index];
                      return _SongTile(
                        index: index + 1,
                        song: song,
                        onTap: () => audioHandler.playSong(song, queue: _trendingSongs),
                      );
                    },
                    childCount: _trendingSongs.length,
                  ),
                ),

              // Bottom Padding for MiniPlayer
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedSongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _FeaturedSongCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: song.coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: song.coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF1E293B),
                              child: const Icon(Icons.music_note_rounded, color: Colors.white24),
                            ),
                          )
                        : Container(color: const Color(0xFF1E293B)),
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
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final int index;
  final Song song;
  final VoidCallback onTap;

  const _SongTile({
    required this.index,
    required this.song,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;

        return ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: song.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: song.coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF1E293B),
                            child: const Icon(Icons.music_note_rounded, color: Colors.white24),
                          ),
                        )
                      : Container(color: const Color(0xFF1E293B)),
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
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
          trailing: _DownloadButton(song: song),
        );
      },
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final Song song;
  const _DownloadButton({required this.song});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: DownloadManager.activeDownloads,
      builder: (context, activeDownloads, _) {
        final isDownloaded = DownloadManager.isDownloaded(song.id);
        final isDownloading = activeDownloads.containsKey(song.id);
        final progress = activeDownloads[song.id] ?? 0.0;

        if (isDownloaded) {
          return const IconButton(
            icon: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
            onPressed: null,
          );
        }

        if (isDownloading) {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                color: const Color(0xFF6366F1),
                strokeWidth: 2,
              ),
            ),
          );
        }

        return IconButton(
          icon: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF64748B), size: 22),
          onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading "${song.title}"...'),
                duration: const Duration(seconds: 1),
              ),
            );
            await DownloadManager.downloadSong(song);
          },
        );
      },
    );
  }
}
