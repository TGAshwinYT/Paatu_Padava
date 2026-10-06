import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../domain/models/app_error.dart';
import '../../services/error_handler.dart';
import '../../services/saavn_client.dart';
import '../../services/youtube_client.dart';
import '../../services/api_client.dart';
import '../../services/player_handler.dart';
import '../../services/search_history_manager.dart';
import '../../services/settings_manager.dart';
import '../../services/fuzzy_search_service.dart';
import '../../services/search_service.dart';
import '../../data/repositories/song_repository.dart';
import '../theme/app_theme.dart';
import 'library_screen.dart';
import '../widgets/search/search_error_view.dart';
import '../widgets/search/search_pre_content.dart';
import '../widgets/search/search_song_tile.dart';
import '../widgets/search/search_albums_grid.dart';
import '../widgets/search/search_artists_list.dart';
import '../widgets/search/search_all_results_view.dart';
import '../widgets/search/search_song_options_sheet.dart';
import '../widgets/search/search_versions_sheet.dart';

class SearchResultsState {
  final Map<String, dynamic>? topResult;
  final List<Song> songs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> artists;
  final List<Song> ytSongs;
  final String? didYouMean;

  final AppError? error;

  const SearchResultsState({
    this.topResult,
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.ytSongs = const [],
    this.didYouMean,
    this.error,
  });

  bool get isEmpty =>
      topResult == null && songs.isEmpty && albums.isEmpty && artists.isEmpty && ytSongs.isEmpty;
  bool get hasError => error != null;
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
  int _searchRequestId = 0;

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
      ApiClient.searchSuggestions(clean).then((suggs) {
        if (mounted && _searchController.text.trim() == clean) {
          _suggestionsNotifier.value = suggs;
        }
      });
      _executeSearch(clean, saveHistory: false);
    });
  }

  Future<void> _executeSearch(String query, {bool saveHistory = false}) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    final currentRequestId = ++_searchRequestId;

    if (saveHistory) {
      SearchHistoryManager.addQuery(clean);
    }

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
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(
          topResult: unified.topResult,
          songs: unified.songs,
          ytSongs: unified.ytSongs,
          albums: unified.albums,
          artists: unified.artists,
          didYouMean: unified.didYouMean,
          error: unified.error,
        );
        _isSearchingNotifier.value = false;
        return;
      } else if (tab == 'Songs') {
        final unified = await SearchService.searchUnified(clean, language: prefLang, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(
          songs: unified.songs,
          didYouMean: unified.didYouMean,
          error: unified.error,
        );
        _isSearchingNotifier.value = false;
      } else if (tab == 'Albums') {
        final albums = await SaavnClient.searchAlbums(clean, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        final labeled = albums.map((alb) {
          final songCount = int.tryParse(alb['song_count']?.toString() ?? '0') ?? 0;
          final title = (alb['title'] ?? '').toString().toLowerCase();
          final isSingle = songCount == 1 || title.contains('single');
          return {
            ...alb,
            'type': isSingle ? 'Single' : 'Album',
          };
        }).toList();
        _resultsNotifier.value = SearchResultsState(albums: labeled);
        _isSearchingNotifier.value = false;
      } else if (tab == 'Artists') {
        final artists = await SaavnClient.searchArtists(clean, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(artists: artists);
        _isSearchingNotifier.value = false;
      } else if (tab == 'YouTube') {
        final yt = await YouTubeClient.search(clean, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        final groupedYt = SongRepository.groupCanonicalSongs(yt, preferredLanguage: prefLang);
        final cleanYt = SongRepository.deduplicateSongs(groupedYt);
        _resultsNotifier.value = SearchResultsState(ytSongs: cleanYt);
        _isSearchingNotifier.value = false;
      }

      if (mounted && currentRequestId == _searchRequestId && _resultsNotifier.value.isEmpty && !_resultsNotifier.value.hasError && correction != null) {
        final fallbackSongs = await FuzzySearchService.executeFallbackSearch(clean, language: prefLang);
        if (fallbackSongs.isNotEmpty && mounted && currentRequestId == _searchRequestId) {
          final grouped = SongRepository.groupCanonicalSongs(fallbackSongs, preferredLanguage: prefLang);
          final cleanFallback = SongRepository.deduplicateSongs(grouped);
          _resultsNotifier.value = SearchResultsState(songs: cleanFallback);
          FuzzySearchService.registerSongs(cleanFallback);
        }
      }
    } catch (e, stack) {
      if (mounted && currentRequestId == _searchRequestId) {
        final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'SearchScreen._executeSearch');
        _resultsNotifier.value = SearchResultsState(error: appErr);
        _isSearchingNotifier.value = false;
      }
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

  void _recordSearchResultClick([Song? song]) {
    final clean = _searchController.text.trim();
    if (clean.isNotEmpty) {
      SearchHistoryManager.addQuery(clean);
    }
    if (song != null) {
      ApiClient.recordSearchClick(song);
    }
  }

  void _showSongOptions(Song song) {
    SearchSongOptionsSheet.show(context, song);
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
                    color: AppColors.neonViolet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.neonViolet.withValues(alpha: 0.3)),
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
          return SearchPreContent(
            trendingArtists: _trendingArtists,
            browseCategories: _browseCategories,
            onSelectQuery: _triggerCategorySearch,
          );
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

                if (state.hasError && !isSearching) {
                  return SearchErrorView(
                    error: state.error!,
                    onRetry: () {
                      final query = _searchController.text.trim();
                      if (query.isNotEmpty) {
                        _executeSearch(query, saveHistory: false);
                      }
                    },
                    onOpenDownloads: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LibraryScreen()),
                      );
                    },
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
                      return SearchAllResultsView(
                        state: state,
                        query: _searchController.text,
                        onDidYouMeanTap: (suggestion) {
                          _searchController.text = suggestion;
                          _executeSearch(suggestion, saveHistory: true);
                        },
                        onArtistRecordClick: () => _recordSearchResultClick(),
                        onRecordClick: ([song]) => _recordSearchResultClick(song),
                        onSongTap: (song) => audioHandler.playSong(song),
                        onShowOptions: _showSongOptions,
                        onShowVersions: _showVersionsSheet,
                      );
                    } else if (currentTab == 'Songs') {
                      return _buildSongsList(state.songs);
                    } else if (currentTab == 'Albums') {
                      return SearchAlbumsGrid(
                        albums: state.albums,
                        query: _searchController.text,
                        onRecordClick: _recordSearchResultClick,
                      );
                    } else if (currentTab == 'Artists') {
                      return SearchArtistsList(
                        artists: state.artists,
                        query: _searchController.text,
                        onRecordClick: _recordSearchResultClick,
                      );
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
        final song = songList[index];
        return SearchSongTile(
          song: song,
          onTap: () {
            _recordSearchResultClick(song);
            audioHandler.playSong(song);
          },
          onShowOptions: () => _showSongOptions(song),
          onShowVersions: song.versions.isNotEmpty ? () => _showVersionsSheet(song) : null,
        );
      },
    );
  }

  void _showVersionsSheet(Song primary) {
    SearchVersionsSheet.show(
      context,
      primary,
      onSelectSong: (v) {
        _recordSearchResultClick(v);
        audioHandler.playSong(v);
      },
    );
  }
}
