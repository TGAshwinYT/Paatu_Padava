import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/youtube_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../../services/favorites_manager.dart';
import '../../services/search_history_manager.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/add_to_playlist_dialog.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  String _currentTab = 'All'; // 'All', 'Songs', 'Albums', 'Artists', 'YouTube'

  List<Song> _songs = [];
  List<Map<String, dynamic>> _albums = [];
  List<Map<String, dynamic>> _artists = [];
  List<Song> _ytSongs = [];

  bool _isSearching = false;
  bool _hasSearched = false;

  final List<String> _trendingArtists = [
    'Anirudh Ravichander',
    'A.R. Rahman',
    'Harris Jayaraj',
    'Yuvan Shankar Raja',
    'Sid Sriram',
    'Ilayaraja',
    'Hiphop Tamizha',
    'G.V. Prakash',
  ];

  final List<String> _genrePills = [
    '🔥 Tamil Hits',
    '⚡ Telugu Beats',
    '🌙 Chill Melodies',
    '💪 Workout Bass',
    '📻 90s Classics',
    '🎸 Indie Acoustics',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _songs = [];
        _albums = [];
        _artists = [];
        _ytSongs = [];
        _hasSearched = false;
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    // Save to recent search history
    SearchHistoryManager.addQuery(clean);

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      if (_currentTab == 'All') {
        final results = await Future.wait([
          SaavnClient.search(clean, limit: 15),
          SaavnClient.searchAlbums(clean, limit: 8),
          SaavnClient.searchArtists(clean, limit: 8),
        ]);
        if (mounted) {
          setState(() {
            _songs = results[0] as List<Song>;
            _albums = results[1] as List<Map<String, dynamic>>;
            _artists = results[2] as List<Map<String, dynamic>>;
            _isSearching = false;
          });
        }
      } else if (_currentTab == 'Songs') {
        final songs = await SaavnClient.search(clean, limit: 25);
        if (mounted) {
          setState(() {
            _songs = songs;
            _isSearching = false;
          });
        }
      } else if (_currentTab == 'Albums') {
        final albums = await SaavnClient.searchAlbums(clean, limit: 20);
        if (mounted) {
          setState(() {
            _albums = albums;
            _isSearching = false;
          });
        }
      } else if (_currentTab == 'Artists') {
        final artists = await SaavnClient.searchArtists(clean, limit: 20);
        if (mounted) {
          setState(() {
            _artists = artists;
            _isSearching = false;
          });
        }
      } else if (_currentTab == 'YouTube') {
        final yt = await YouTubeClient.search(clean, limit: 20);
        if (mounted) {
          setState(() {
            _ytSongs = yt;
            _isSearching = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onTabChanged(String tab) {
    if (_currentTab == tab) return;
    setState(() => _currentTab = tab);
    if (_searchController.text.isNotEmpty) {
      _executeSearch(_searchController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Field
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  onSubmitted: _executeSearch,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums, or YT...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6366F1), size: 24),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),

            // Search Multi-Entity Category Tabs
            SizedBox(
              height: 38,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                children: ['All', 'Songs', 'Albums', 'Artists', 'YouTube'].map((tab) {
                  final isSelected = _currentTab == tab;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(tab),
                      selected: isSelected,
                      selectedColor: const Color(0xFF6366F1),
                      backgroundColor: const Color(0xFF131B2E),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF6366F1) : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      onSelected: (_) => _onTabChanged(tab),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),

            // Search Body (Results or Empty/Suggestions)
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
      );
    }

    if (!_hasSearched) {
      return _buildPreSearchContent();
    }

    // Tab-specific rendering
    if (_currentTab == 'All') {
      return _buildAllResults();
    } else if (_currentTab == 'Songs') {
      return _buildSongsList(_songs);
    } else if (_currentTab == 'Albums') {
      return _buildAlbumsGrid(_albums);
    } else if (_currentTab == 'Artists') {
      return _buildArtistsList(_artists);
    } else if (_currentTab == 'YouTube') {
      return _buildSongsList(_ytSongs);
    }

    return const SizedBox.shrink();
  }

  Widget _buildPreSearchContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // Spotify Import Quick Action
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x331DB954)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.album_rounded, color: Color(0xFF1DB954), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Paste a Spotify Link to Import',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                onPressed: () => SpotifyImportDialog.show(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: Size.zero,
                ),
                child: const Text('Import', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
        ),

        // Recent Searches
        ValueListenableBuilder<List<String>>(
          valueListenable: SearchHistoryManager.historyNotifier,
          builder: (context, history, _) {
            if (history.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Searches',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      child: const Text('Clear All', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                      onPressed: () => SearchHistoryManager.clearAll(),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: history.map((q) {
                    return InputChip(
                      backgroundColor: const Color(0xFF131B2E),
                      label: Text(q, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                      onDeleted: () => SearchHistoryManager.removeQuery(q),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.white.withOpacity(0.06)),
                      ),
                      onPressed: () {
                        _searchController.text = q;
                        _executeSearch(q);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),

        // Trending Artists
        const Text(
          'Trending Artists',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: _trendingArtists.map((artist) {
            return ActionChip(
              backgroundColor: const Color(0xFF131B2E),
              avatar: const Icon(Icons.person_rounded, size: 16, color: Color(0xFF6366F1)),
              label: Text(artist, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
              onPressed: () {
                _searchController.text = artist;
                _executeSearch(artist);
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Top Genres & Moods
        const Text(
          'Browse Categories',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: _genrePills.map((genre) {
            return ActionChip(
              backgroundColor: const Color(0xFF131B2E),
              label: Text(genre, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
              onPressed: () {
                final clean = genre.substring(2).trim();
                _searchController.text = clean;
                _executeSearch(clean);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAllResults() {
    if (_songs.isEmpty && _albums.isEmpty && _artists.isEmpty) {
      return Center(
        child: Text(
          'No results found for "${_searchController.text}"',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        // Top Artists Row
        if (_artists.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Text(
              'Artists',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 105,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final art = _artists[index];
                final id = art['id']?.toString() ?? '';
                final name = art['name']?.toString() ?? '';
                final img = art['image']?.toString() ?? '';

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
                        radius: 34,
                        backgroundColor: const Color(0xFF131B2E),
                        backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 70,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],

        // Top Albums Row
        if (_albums.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Text(
              'Albums',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 160,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _albums.length,
              itemBuilder: (context, index) {
                final album = _albums[index];
                final id = album['id']?.toString() ?? '';
                final title = album['title']?.toString() ?? '';
                final img = album['image']?.toString() ?? '';

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
                    width: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 120,
                            height: 120,
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
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // Songs Header
        if (_songs.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Songs',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ..._songs.map((song) => _buildSongItem(song, _songs)).toList(),
        ],
      ],
    );
  }

  Widget _buildSongsList(List<Song> songList) {
    if (songList.isEmpty) {
      return Center(
        child: Text(
          'No songs found for "${_searchController.text}"',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: songList.length,
      itemBuilder: (context, index) {
        return _buildSongItem(songList[index], songList);
      },
    );
  }

  Widget _buildSongItem(Song song, List<Song> queue) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;

        return ListTile(
          onTap: () => audioHandler.playSong(song, queue: queue),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
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
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: song.source == 'youtube'
                      ? Colors.redAccent.withOpacity(0.2)
                      : const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  song.source == 'youtube' ? 'YT' : '320K',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: song.source == 'youtube' ? Colors.redAccent : const Color(0xFF10B981),
                  ),
                ),
              ),
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
              ValueListenableBuilder<List<Song>>(
                valueListenable: FavoritesManager.favoritesNotifier,
                builder: (context, _, __) {
                  final isFav = FavoritesManager.isFavorite(song.id);
                  return IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 20,
                      color: isFav ? const Color(0xFFEC4899) : const Color(0xFF64748B),
                    ),
                    onPressed: () => FavoritesManager.toggleFavorite(song),
                  );
                },
              ),
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
    );
  }

  Widget _buildAlbumsGrid(List<Map<String, dynamic>> albums) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          'No albums found for "${_searchController.text}"',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final id = album['id']?.toString() ?? '';
        final title = album['title']?.toString() ?? '';
        final artist = album['artist']?.toString() ?? '';
        final img = album['image']?.toString() ?? '';

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
            decoration: BoxDecoration(
              color: const Color(0xFF131B2E),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: img,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
    );
  }

  Widget _buildArtistsList(List<Map<String, dynamic>> artists) {
    if (artists.isEmpty) {
      return Center(
        child: Text(
          'No artists found for "${_searchController.text}"',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final art = artists[index];
        final id = art['id']?.toString() ?? '';
        final name = art['name']?.toString() ?? '';
        final img = art['image']?.toString() ?? '';

        return ListTile(
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF131B2E),
            backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
          ),
          title: Text(
            name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: const Text('Artist', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF64748B)),
        );
      },
    );
  }
}
