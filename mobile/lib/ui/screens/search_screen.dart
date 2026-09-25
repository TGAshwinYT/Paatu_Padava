import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/youtube_client.dart';
import '../../services/api_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../../services/favorites_manager.dart';
import '../../services/search_history_manager.dart';
import '../../services/settings_manager.dart';
import '../../services/fuzzy_search_service.dart';
import '../../services/search_service.dart';
import '../../data/repositories/song_repository.dart';
import '../../presentation/theme/app_theme.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/add_to_playlist_dialog.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

class SearchResultsState {
  final Map<String, dynamic>? topResult;
  final List<Song> songs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> artists;
  final List<Song> ytSongs;

  const SearchResultsState({
    this.topResult,
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.ytSongs = const [],
  });

  bool get isEmpty =>
      topResult == null && songs.isEmpty && albums.isEmpty && artists.isEmpty && ytSongs.isEmpty;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static final HtmlUnescape _unescape = HtmlUnescape();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  // State isolation via ValueNotifiers: eliminates full-page rebuilds & refresh lag
  final ValueNotifier<String> _currentTabNotifier = ValueNotifier<String>('All');
  final ValueNotifier<bool> _isSearchingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _hasSearchedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> _suggestionsNotifier = ValueNotifier<List<String>>([]);
  final ValueNotifier<FuzzyCorrectionResult?> _fuzzyCorrectionNotifier =
      ValueNotifier<FuzzyCorrectionResult?>(null);
  final ValueNotifier<SearchResultsState> _resultsNotifier =
      ValueNotifier<SearchResultsState>(const SearchResultsState());

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
      'colors': [Color(0xFF7C3AED), Color(0xFF9333EA)],
      'icon': Icons.local_fire_department_rounded,
    },
    {
      'title': 'Telugu Beats',
      'query': 'Telugu Top Hits',
      'colors': [Color(0xFF0891B2), Color(0xFF0E7490)],
      'icon': Icons.bolt_rounded,
    },
    {
      'title': 'Hindi Top 50',
      'query': 'Hindi Top Songs',
      'colors': [Color(0xFF6366F1), Color(0xFF4F46E5)],
      'icon': Icons.trending_up_rounded,
    },
    {
      'title': 'Malayalam Chill',
      'query': 'Malayalam Melodies',
      'colors': [Color(0xFF0D9488), Color(0xFF0F766E)],
      'icon': Icons.nature_people_rounded,
    },
    {
      'title': 'English Pop',
      'query': 'English Pop Hits',
      'colors': [Color(0xFF9333EA), Color(0xFFA855F7)],
      'icon': Icons.star_rounded,
    },
    {
      'title': 'Indie & Folk',
      'query': 'Indian Indie Acoustic',
      'colors': [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
      'icon': Icons.music_note_rounded,
    },
    {
      'title': 'Romance & Love',
      'query': 'Love Romantic Songs',
      'colors': [Color(0xFFC026D3), Color(0xFFA21CAF)],
      'icon': Icons.favorite_rounded,
    },
    {
      'title': 'Workout Bass',
      'query': 'Workout Gym Bass Songs',
      'colors': [Color(0xFF06B6D4), Color(0xFF0284C7)],
      'icon': Icons.fitness_center_rounded,
    },
    {
      'title': '90s Classics',
      'query': '90s Tamil Classics',
      'colors': [Color(0xFF475569), Color(0xFF334155)],
      'icon': Icons.radio_rounded,
    },
    {
      'title': 'Dance & Party',
      'query': 'Party Dance Club Songs',
      'colors': [Color(0xFF6D28D9), Color(0xFF4C1D95)],
      'icon': Icons.nightlife_rounded,
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    _currentTabNotifier.dispose();
    _isSearchingNotifier.dispose();
    _hasSearchedNotifier.dispose();
    _suggestionsNotifier.dispose();
    _fuzzyCorrectionNotifier.dispose();
    _resultsNotifier.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      _suggestionsNotifier.value = [];
      _fuzzyCorrectionNotifier.value = null;
      _resultsNotifier.value = const SearchResultsState();
      _hasSearchedNotifier.value = false;
      _isSearchingNotifier.value = false;
      return;
    }

    // 400ms Debounce: strictly prevents API requests and rebuilds while typing
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      // Fetch suggestions only after user pauses typing for 400ms
      ApiClient.searchSuggestions(clean).then((suggs) {
        if (mounted && _searchController.text.trim() == clean) {
          _suggestionsNotifier.value = suggs;
        }
      });
      // CRITICAL FIX: NEVER save to search history in onChanged!
      _executeSearch(clean, saveHistory: false);
    });
  }

  Future<void> _executeSearch(String query, {bool saveHistory = false}) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    // Save to local search history ONLY if explicitly requested (e.g. onSubmitted or clicking results)
    if (saveHistory) {
      SearchHistoryManager.addQuery(clean);
    }

    // Typo evaluation: match against locally cached popular titles & tokens
    final correction = FuzzySearchService.findCorrection(clean);
    _fuzzyCorrectionNotifier.value = correction;

    _isSearchingNotifier.value = true;
    _hasSearchedNotifier.value = true;
    _suggestionsNotifier.value = [];

    final prefLang = SettingsManager.preferredLanguages.isNotEmpty
        ? SettingsManager.preferredLanguages.first
        : 'Tamil';
    final tab = _currentTabNotifier.value;

    try {
      if (tab == 'All') {
        final unified = await SearchService.searchUnified(clean, language: prefLang, limit: 25);
        if (mounted) {
          _resultsNotifier.value = SearchResultsState(
            topResult: unified.topResult,
            songs: unified.songs,
            ytSongs: unified.ytSongs,
            albums: unified.albums,
            artists: unified.artists,
          );
          _isSearchingNotifier.value = false;
          return;
        }
      } else if (tab == 'Songs') {
        final unified = await SearchService.searchUnified(clean, language: prefLang, limit: 25);
        if (mounted) {
          _resultsNotifier.value = SearchResultsState(songs: unified.songs);
          _isSearchingNotifier.value = false;
        }
      } else if (tab == 'Albums') {
        final albums = await SaavnClient.searchAlbums(clean, limit: 25);
        if (mounted) {
          _resultsNotifier.value = SearchResultsState(albums: albums);
          _isSearchingNotifier.value = false;
        }
      } else if (tab == 'Artists') {
        final artists = await SaavnClient.searchArtists(clean, limit: 25);
        if (mounted) {
          _resultsNotifier.value = SearchResultsState(artists: artists);
          _isSearchingNotifier.value = false;
        }
      } else if (tab == 'YouTube') {
        final biasedQuery = SearchService.buildLanguageBiasedQuery(clean, language: prefLang);
        final yt = await YouTubeClient.search(biasedQuery, limit: 25);
        if (mounted) {
          final cleanYt = SongRepository.deduplicateSongs(yt);
          _resultsNotifier.value = SearchResultsState(ytSongs: cleanYt);
          _isSearchingNotifier.value = false;
        }
      }

      // If zero results found due to a typo, attempt automatic fuzzy fallback search
      if (mounted && _resultsNotifier.value.isEmpty && correction != null) {
        final fallbackSongs = await FuzzySearchService.executeFallbackSearch(clean, language: prefLang);
        if (fallbackSongs.isNotEmpty && mounted) {
          final cleanFallback = SongRepository.deduplicateSongs(fallbackSongs);
          _resultsNotifier.value = SearchResultsState(songs: cleanFallback);
          FuzzySearchService.registerSongs(cleanFallback);
        }
      }
    } catch (_) {
      if (mounted) _isSearchingNotifier.value = false;
    }
  }

  void _onTabChanged(String tab) {
    if (_currentTabNotifier.value == tab) return;
    _currentTabNotifier.value = tab;
    if (_searchController.text.isNotEmpty) {
      _executeSearch(_searchController.text, saveHistory: false);
    }
  }

  void _triggerCategorySearch(String query) {
    _searchController.text = query;
    _executeSearch(query, saveHistory: true);
  }

  void _recordSearchResultClick() {
    final clean = _searchController.text.trim();
    if (clean.isNotEmpty) {
      SearchHistoryManager.addQuery(clean);
    }
  }

  void _showSongOptions(Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded, color: AppColors.neonViolet),
              title: const Text('Play Next', style: TextStyle(color: Colors.white)),
              onTap: () {
                audioHandler.insertNext(song);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Playing "${_unescape.convert(Song.sanitize(song.title))}" next')),
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
                  SnackBar(content: Text('Added "${_unescape.convert(Song.sanitize(song.title))}" to queue')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded, color: AppColors.electricCyan),
              title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                AddToPlaylistDialog.show(context, song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppColors.electricCyan),
              title: const Text('Download Offline', style: TextStyle(color: Colors.white)),
              onTap: () {
                DownloadManager.downloadSong(song);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border_rounded, color: AppColors.neonViolet),
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
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Field
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  onSubmitted: (query) => _executeSearch(query, saveHistory: true),
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums, or YouTube...',
                    hintStyle: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.neonViolet, size: 22),
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

            // Live Search Suggestions dropdown (isolated with ValueListenableBuilder)
            ValueListenableBuilder<bool>(
              valueListenable: _hasSearchedNotifier,
              builder: (context, hasSearched, _) {
                if (hasSearched) return const SizedBox.shrink();
                return ValueListenableBuilder<List<String>>(
                  valueListenable: _suggestionsNotifier,
                  builder: (context, suggestions, _) {
                    if (suggestions.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.surfaceBorderHighlight),
                      ),
                      child: Column(
                        children: suggestions.take(4).map((sug) {
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.search, color: AppColors.electricCyan, size: 18),
                            title: Text(
                              _unescape.convert(Song.sanitize(sug)),
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                            ),
                            trailing: const Icon(Icons.north_west, color: Colors.white38, size: 16),
                            onTap: () {
                              _searchController.text = sug;
                              _executeSearch(sug, saveHistory: true);
                            },
                          );
                        }).toList(),
                      ),
                    );
                  },
                );
              },
            ),

            // Typo-Tolerant "Did you mean?" Suggestion Banner
            ValueListenableBuilder<FuzzyCorrectionResult?>(
              valueListenable: _fuzzyCorrectionNotifier,
              builder: (context, correction, _) {
                if (correction == null) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.neonViolet.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.neonViolet.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_fix_high_rounded, color: AppColors.neonViolet, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                            children: [
                              const TextSpan(text: 'Did you mean: '),
                              TextSpan(
                                text: _unescape.convert(Song.sanitize(correction.corrected)),
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _searchController.text = correction.corrected;
                          _fuzzyCorrectionNotifier.value = null;
                          _executeSearch(correction.corrected, saveHistory: true);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Search',
                          style: GoogleFonts.outfit(
                            color: AppColors.electricCyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Search Multi-Entity Category Tabs (isolated with ValueListenableBuilder)
            SizedBox(
              height: 40,
              child: ValueListenableBuilder<String>(
                valueListenable: _currentTabNotifier,
                builder: (context, currentTab, _) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    children: ['All', 'Songs', 'Albums', 'Artists', 'YouTube'].map((tab) {
                      final isSelected = currentTab == tab;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(tab),
                          selected: isSelected,
                          selectedColor: AppColors.neonViolet,
                          backgroundColor: AppColors.surfaceElevated,
                          labelStyle: GoogleFonts.outfit(
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isSelected ? AppColors.neonViolet : AppColors.surfaceBorder,
                            ),
                          ),
                          onSelected: (_) => _onTabChanged(tab),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),

            // Non-blocking progress indicator: guarantees UI never locks or hides content during refreshes
            ValueListenableBuilder<bool>(
              valueListenable: _isSearchingNotifier,
              builder: (context, isSearching, _) {
                if (!isSearching) return const SizedBox(height: 2);
                return const LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.electricCyan,
                  backgroundColor: Colors.transparent,
                );
              },
            ),

            const SizedBox(height: 4),

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
    return ValueListenableBuilder<bool>(
      valueListenable: _hasSearchedNotifier,
      builder: (context, hasSearched, _) {
        if (!hasSearched) {
          return _buildPreSearchContent();
        }

        return ValueListenableBuilder<SearchResultsState>(
          valueListenable: _resultsNotifier,
          builder: (context, state, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _isSearchingNotifier,
              builder: (context, isSearching, _) {
                if (state.isEmpty && isSearching) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.neonViolet),
                  );
                }

                if (state.isEmpty && !isSearching) {
                  return Center(
                    child: Text(
                      'No results found for "${_searchController.text}"',
                      style: GoogleFonts.outfit(color: AppColors.textSecondary),
                    ),
                  );
                }

                return ValueListenableBuilder<String>(
                  valueListenable: _currentTabNotifier,
                  builder: (context, currentTab, _) {
                    if (currentTab == 'All') {
                      return _buildAllResults(state);
                    } else if (currentTab == 'Songs') {
                      return _buildSongsList(state.songs);
                    } else if (currentTab == 'Albums') {
                      return _buildAlbumsGrid(state.albums);
                    } else if (currentTab == 'Artists') {
                      return _buildArtistsList(state.artists);
                    } else if (currentTab == 'YouTube') {
                      return _buildSongsList(state.ytSongs);
                    }
                    return const SizedBox.shrink();
                  },
                );
              },
            );
          },
        );
      },
    );
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
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceBorderHighlight),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.neonViolet.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.album_rounded, color: AppColors.neonViolet, size: 20),
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
                  backgroundColor: AppColors.neonViolet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: Size.zero,
                ),
                child: Text('Import', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),

        // Recent Searches with strict deduplication & 12 item cap
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
                      child: Text('Clear All', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                      onPressed: () => SearchHistoryManager.clearAll(),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: history.map((q) {
                    final cleanDisplay = _unescape.convert(Song.sanitize(q));
                    return InputChip(
                      backgroundColor: AppColors.surfaceElevated,
                      label: Text(cleanDisplay, style: GoogleFonts.outfit(color: AppColors.textWhite, fontSize: 12)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                      onDeleted: () => SearchHistoryManager.removeQuery(q),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.surfaceBorder),
                      ),
                      onPressed: () {
                        _searchController.text = q;
                        _executeSearch(q, saveHistory: true);
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
                backgroundColor: AppColors.surfaceElevated,
                avatar: const Icon(Icons.person_rounded, size: 15, color: AppColors.electricCyan),
                label: Text(artist, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.surfaceBorder),
                ),
                onPressed: () => _triggerCategorySearch(artist),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Browse All Category Tiles with Neon Theme Gradients
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
                      color: colors.first.withOpacity(0.25),
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

  Widget _buildTopResultCard(Map<String, dynamic> top, List<Song> queue) {
    final type = top['type']?.toString() ?? 'song';
    final title = _unescape.convert(Song.sanitize(top['title']?.toString() ?? top['name']?.toString() ?? ''));
    final artist = _unescape.convert(Song.sanitize(top['artist']?.toString() ?? top['subtitle']?.toString() ?? ''));
    final cover = top['cover_url']?.toString() ?? top['image']?.toString() ?? '';
    final isArtist = type.toLowerCase() == 'artist';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceBorderHighlight),
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
                          errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
                        )
                      : Container(
                          color: AppColors.surfaceDark,
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
                        color: AppColors.neonViolet.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isArtist ? 'ARTIST' : 'TOP RESULT',
                        style: GoogleFonts.outfit(
                          color: AppColors.neonViolet,
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
                          color: AppColors.textSecondary,
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
                      _recordSearchResultClick();
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
                      backgroundColor: AppColors.neonViolet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: Text('View Artist', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  )
                : FloatingActionButton.small(
                    heroTag: 'top_result_play',
                    backgroundColor: AppColors.neonViolet,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    onPressed: () {
                      _recordSearchResultClick();
                      if (queue.isNotEmpty) {
                        audioHandler.playSong(queue.first, queue: queue);
                      }
                    },
                    child: const Icon(Icons.play_arrow_rounded, size: 28),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllResults(SearchResultsState state) {
    if (state.songs.isEmpty && state.albums.isEmpty && state.artists.isEmpty && state.topResult == null) {
      return Center(
        child: Text(
          'No results found for "${_searchController.text}"',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        // Top Result Hero Card
        if (state.topResult != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(
              'Top Result',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          _buildTopResultCard(state.topResult!, state.songs),
        ],

        // Top Artists Row
        if (state.artists.isNotEmpty) ...[
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
              itemCount: state.artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final art = state.artists[index];
                final id = art['id']?.toString() ?? '';
                final name = _unescape.convert(Song.sanitize(art['name']?.toString() ?? ''));
                final img = art['image']?.toString() ?? '';

                return GestureDetector(
                  onTap: () {
                    _recordSearchResultClick();
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
                        backgroundColor: AppColors.surfaceElevated,
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
        if (state.albums.isNotEmpty) ...[
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
              itemCount: state.albums.length,
              itemBuilder: (context, index) {
                final album = state.albums[index];
                final id = album['id']?.toString() ?? '';
                final title = _unescape.convert(Song.sanitize(album['title']?.toString() ?? ''));
                final img = album['image']?.toString() ?? '';

                return GestureDetector(
                  onTap: () {
                    _recordSearchResultClick();
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
                              errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
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
        if (state.songs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              'Songs',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ...state.songs.map((song) => _buildSongItem(song, state.songs)),
        ],
      ],
    );
  }

  Widget _buildSongsList(List<Song> songList) {
    if (songList.isEmpty) {
      return Center(
        child: Text(
          'No songs found for "${_searchController.text}"',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
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
        final cleanTitle = _unescape.convert(Song.sanitize(song.title));
        final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

        return ListTile(
          onTap: () {
            // Save search term ONLY when user clicks a result
            _recordSearchResultClick();
            audioHandler.playSong(song, queue: queue);
          },
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
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
                  ),
                ),
              ),
              if (isPlaying)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.equalizer_rounded, color: AppColors.electricCyan, size: 24),
                ),
            ],
          ),
          title: Text(
            cleanTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: isPlaying ? AppColors.neonViolet : Colors.white,
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
                      ? AppColors.electricCyan.withOpacity(0.2)
                      : AppColors.neonViolet.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  song.source == 'youtube' ? 'YT' : '320K',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: song.source == 'youtube' ? AppColors.electricCyan : AppColors.neonViolet,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  cleanArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
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
                      color: isFav ? AppColors.neonViolet : AppColors.textSecondary,
                    ),
                    onPressed: () => FavoritesManager.toggleFavorite(song),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
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
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
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
        final title = _unescape.convert(Song.sanitize(album['title']?.toString() ?? ''));
        final artist = _unescape.convert(Song.sanitize(album['artist']?.toString() ?? ''));
        final img = album['image']?.toString() ?? '';

        return GestureDetector(
          onTap: () {
            _recordSearchResultClick();
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
              color: AppColors.surfaceElevated,
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
                        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
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
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11),
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
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final art = artists[index];
        final id = art['id']?.toString() ?? '';
        final name = _unescape.convert(Song.sanitize(art['name']?.toString() ?? ''));
        final img = art['image']?.toString() ?? '';

        return ListTile(
          onTap: () {
            _recordSearchResultClick();
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
            backgroundColor: AppColors.surfaceElevated,
            backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
          ),
          title: Text(
            name,
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text('Artist', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
        );
      },
    );
  }
}
