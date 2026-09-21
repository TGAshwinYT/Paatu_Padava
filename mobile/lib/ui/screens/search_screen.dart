import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/youtube_client.dart';
import '../../services/api_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../../services/favorites_manager.dart';
import '../../services/search_history_manager.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/add_to_playlist_dialog.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  String _currentTab = 'All'; // 'All', 'Songs', 'Albums', 'Artists', 'YouTube'

  Map<String, dynamic>? _topResult;
  List<Song> _songs = [];
  List<Map<String, dynamic>> _albums = [];
  List<Map<String, dynamic>> _artists = [];
  List<Song> _ytSongs = [];
  List<String> _suggestions = [];

  bool _isSearching = false;
  bool _hasSearched = false;

  final List<String> _trendingArtists = [
    'Anirudh Ravichander',
    'A.R. Rahman',
    'Harris Jayaraj',
    'Yuvan Shankar Raja',
    'Sid Sriram',
    'Ilaiyaraaja',
    'Hiphop Tamizha',
    'Santhosh Narayanan',
  ];

  final List<Map<String, dynamic>> _browseCategories = [
    {
      'title': 'Tamil Hits',
      'query': 'Tamil Top Hits',
      'colors': [Color(0xFFE11D48), Color(0xFFBE185D)],
      'icon': Icons.local_fire_department_rounded,
    },
    {
      'title': 'Telugu Beats',
      'query': 'Telugu Top Hits',
      'colors': [Color(0xFFD97706), Color(0xFFB45309)],
      'icon': Icons.bolt_rounded,
    },
    {
      'title': 'Hindi Top 50',
      'query': 'Hindi Top Songs',
      'colors': [Color(0xFF2563EB), Color(0xFF1D4ED8)],
      'icon': Icons.trending_up_rounded,
    },
    {
      'title': 'Malayalam Chill',
      'query': 'Malayalam Melodies',
      'colors': [Color(0xFF059669), Color(0xFF047857)],
      'icon': Icons.nature_people_rounded,
    },
    {
      'title': 'English Pop',
      'query': 'English Pop Hits',
      'colors': [Color(0xFF7C3AED), Color(0xFF6D28D9)],
      'icon': Icons.star_rounded,
    },
    {
      'title': 'Indie & Folk',
      'query': 'Indian Indie Acoustic',
      'colors': [Color(0xFFDB2777), Color(0xFFBE185D)],
      'icon': Icons.music_note_rounded,
    },
    {
      'title': 'Romance & Love',
      'query': 'Love Romantic Songs',
      'colors': [Color(0xFFEA580C), Color(0xFFC2410C)],
      'icon': Icons.favorite_rounded,
    },
    {
      'title': 'Workout Bass',
      'query': 'Workout Gym Bass Songs',
      'colors': [Color(0xFF0891B2), Color(0xFF0E7490)],
      'icon': Icons.fitness_center_rounded,
    },
    {
      'title': '90s Classics',
      'query': '90s Tamil Classics',
      'colors': [Color(0xFF4B5563), Color(0xFF374151)],
      'icon': Icons.radio_rounded,
    },
    {
      'title': 'Dance & Party',
      'query': 'Party Dance Club Songs',
      'colors': [Color(0xFFCA8A04), Color(0xFFA16207)],
      'icon': Icons.nightlife_rounded,
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() {
        _topResult = null;
        _songs = [];
        _albums = [];
        _artists = [];
        _ytSongs = [];
        _suggestions = [];
        _hasSearched = false;
        _isSearching = false;
      });
      return;
    }

    // Fetch instant suggestions in background
    ApiClient.searchSuggestions(clean).then((suggs) {
      if (mounted && _searchController.text.trim() == clean) {
        setState(() => _suggestions = suggs);
      }
    });

    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _executeSearch(clean);
    });
  }

  Future<void> _executeSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    // Save to local search history
    SearchHistoryManager.addQuery(clean);

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _suggestions = [];
    });

    try {
      if (_currentTab == 'All') {
        final bundle = await ApiClient.searchGlobal(clean);
        if (bundle != null && mounted) {
          setState(() {
            _topResult = bundle.topResult;
            _songs = bundle.songs;
            _artists = bundle.artists;
            _albums = bundle.albums;
            _isSearching = false;
          });
          return;
        }

        // Direct fallback
        final results = await Future.wait([
          SaavnClient.search(clean, limit: 15),
          SaavnClient.searchAlbums(clean, limit: 8),
          SaavnClient.searchArtists(clean, limit: 8),
        ]);
        if (mounted) {
          final s = results[0] as List<Song>;
          setState(() {
            _topResult = s.isNotEmpty
                ? {
                    'type': 'song',
                    'id': s.first.id,
                    'title': s.first.title,
                    'artist': s.first.artist,
                    'cover_url': s.first.coverUrl,
                    'duration': s.first.duration,
                  }
                : null;
            _songs = s;
            _albums = results[1] as List<Map<String, dynamic>>;
            _artists = results[2] as List<Map<String, dynamic>>;
            _isSearching = false;
          });
        }
      } else if (_currentTab == 'Songs') {
        final songs = await SaavnClient.search(clean, limit: 30);
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
        final yt = await YouTubeClient.search(clean, limit: 25);
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

  void _triggerCategorySearch(String query) {
    _searchController.text = query;
    _executeSearch(query);
  }

  void _showSongOptions(Song song) {
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
            // Search Input Field
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums, or YouTube...',
                    hintStyle: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF1DB954), size: 24),
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

            // Live Search Suggestions dropdown
            if (_suggestions.isNotEmpty && !_hasSearched)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: _suggestions.take(4).map((sug) {
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.search, color: Colors.white38, size: 18),
                      title: Text(
                        sug,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                      ),
                      trailing: const Icon(Icons.north_west, color: Colors.white38, size: 16),
                      onTap: () {
                        _searchController.text = sug;
                        _executeSearch(sug);
                      },
                    );
                  }).toList(),
                ),
              ),

            // Search Multi-Entity Category Tabs
            SizedBox(
              height: 40,
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
                      selectedColor: const Color(0xFF1DB954),
                      backgroundColor: const Color(0xFF131B2E),
                      labelStyle: GoogleFonts.outfit(
                        color: isSelected ? Colors.black : const Color(0xFF94A3B8),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF1DB954) : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      onSelected: (_) => _onTabChanged(tab),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),

            // Search Body
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
        child: CircularProgressIndicator(color: Color(0xFF1DB954)),
      );
    }

    if (!_hasSearched) {
      return _buildPreSearchContent();
    }

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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
              Expanded(
                child: Text(
                  'Paste a Spotify Link to Import',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                onPressed: () => SpotifyImportDialog.show(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: Size.zero,
                ),
                child: Text('Import', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
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
                    Text(
                      'Recent Searches',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      child: Text('Clear All', style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 12)),
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
                      label: Text(q, style: GoogleFonts.outfit(color: const Color(0xFFCBD5E1), fontSize: 12)),
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
                const SizedBox(height: 20),
              ],
            );
          },
        ),

        // Trending Artists
        Text(
          'Trending Artists',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _trendingArtists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final artist = _trendingArtists[i];
              return ActionChip(
                backgroundColor: const Color(0xFF131B2E),
                avatar: const Icon(Icons.person_rounded, size: 15, color: Color(0xFF1DB954)),
                label: Text(artist, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
                onPressed: () => _triggerCategorySearch(artist),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Spotify-style "Browse All" Category Tiles
        Text(
          'Browse All',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.7,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _browseCategories.length,
          itemBuilder: (context, index) {
            final cat = _browseCategories[index];
            final colors = cat['colors'] as List<Color>;

            return InkWell(
              onTap: () => _triggerCategorySearch(cat['query'] as String),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: colors.first.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        cat['title'] as String,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Transform.rotate(
                        angle: 0.25,
                        child: Icon(
                          cat['icon'] as IconData,
                          size: 44,
                          color: Colors.white.withOpacity(0.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildTopResultCard(Map<String, dynamic> top) {
    final type = top['type']?.toString() ?? 'song';
    final title = top['title']?.toString() ?? top['name']?.toString() ?? '';
    final artist = top['artist']?.toString() ?? top['subtitle']?.toString() ?? '';
    final cover = top['cover_url']?.toString() ?? top['image']?.toString() ?? '';
    final isArtist = type.toLowerCase() == 'artist';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(isArtist ? 38 : 12),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                        )
                      : Container(
                          color: const Color(0xFF1E293B),
                          child: Icon(
                            isArtist ? Icons.person : Icons.music_note,
                            color: Colors.white38,
                            size: 32,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isArtist ? 'ARTIST' : 'TOP RESULT',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF1DB954),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (artist.isNotEmpty && !isArtist)
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: isArtist
                ? ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ArtistScreen(
                            artistId: top['id']?.toString() ?? '',
                            artistName: title,
                            imageUrl: cover,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: Text('View Artist', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  )
                : FloatingActionButton.small(
                    heroTag: 'top_result_play',
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.black,
                    elevation: 4,
                    onPressed: () {
                      if (_songs.isNotEmpty) {
                        audioHandler.playSong(_songs.first, queue: _songs);
                      }
                    },
                    child: const Icon(Icons.play_arrow_rounded, size: 28),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllResults() {
    if (_songs.isEmpty && _albums.isEmpty && _artists.isEmpty && _topResult == null) {
      return Center(
        child: Text(
          'No results found for "${_searchController.text}"',
          style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        // Top Result Spotify Hero Card
        if (_topResult != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(
              'Top Result',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          _buildTopResultCard(_topResult!),
        ],

        // Top Artists Row
        if (_artists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Text(
              'Artists',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 110,
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
                        width: 74,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Text(
              'Albums',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // Songs Header & List
        if (_songs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              'Songs',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ..._songs.map((song) => _buildSongItem(song, _songs)),
        ],
      ],
    );
  }

  Widget _buildSongsList(List<Song> songList) {
    if (songList.isEmpty) {
      return Center(
        child: Text(
          'No songs found for "${_searchController.text}"',
          style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
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
                  child: const Icon(Icons.equalizer_rounded, color: Color(0xFF1DB954), size: 24),
                ),
            ],
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: isPlaying ? const Color(0xFF1DB954) : Colors.white,
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
                  style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
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
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                onPressed: () => _showSongOptions(song),
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
          style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
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
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 11),
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
          style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
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
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text('Artist', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF64748B)),
        );
      },
    );
  }
}
