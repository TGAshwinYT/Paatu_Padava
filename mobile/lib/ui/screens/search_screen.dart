import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../domain/models/app_error.dart';
import '../../services/error_handler.dart';
import '../../services/player_handler.dart';
import '../../services/search_history_manager.dart';
import '../../services/settings_manager.dart';
import '../../services/fuzzy_search_service.dart';
import '../../services/search_service.dart';
import '../../data/repositories/song_repository.dart';
import '../../logic/stream_resolver.dart';
import '../../logic/search_query_planner.dart';
import '../../core/dsa/prefix_trie.dart';
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
import '../widgets/search/search_playlists_grid.dart';

class SearchResultsState {
  final Map<String, dynamic>? topResult;
  final List<Song> songs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> playlists;
  final List<Song> ytSongs;
  final List<Song> saavnSongs;
  final List<Song> audiusSongs;
  final String? didYouMean;

  final AppError? error;

  const SearchResultsState({
    this.topResult,
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.ytSongs = const [],
    this.saavnSongs = const [],
    this.audiusSongs = const [],
    this.didYouMean,
    this.error,
  });

  bool get isEmpty =>
      topResult == null &&
      songs.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty &&
      ytSongs.isEmpty &&
      saavnSongs.isEmpty &&
      audiusSongs.isEmpty;
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
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<bool> _isSearchActiveNotifier = ValueNotifier<bool>(false);
  Timer? _debounceTimer;
  int _searchRequestId = 0;

  // State isolation via ValueNotifiers: eliminates full-page rebuilds & refresh lag
  final ValueNotifier<String> _currentTabNotifier = ValueNotifier<String>('All');
  final ValueNotifier<String> _selectedLanguageNotifier = ValueNotifier<String>('All');
  final ValueNotifier<bool> _isSearchingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _hasSearchedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> _suggestionsNotifier = ValueNotifier<List<String>>([]);
  final ValueNotifier<FuzzyCorrectionResult?> _fuzzyCorrectionNotifier =
      ValueNotifier<FuzzyCorrectionResult?>(null);
  final ValueNotifier<SearchResultsState> _resultsNotifier =
      ValueNotifier<SearchResultsState>(const SearchResultsState());

  List<String> get _availableLanguages {
    final userLangs = SettingsManager.preferredLanguages;
    final defaults = ['All', 'Tamil', 'Hindi', 'Telugu', 'English', 'Malayalam', 'Kannada', 'Punjabi'];
    final list = <String>['All'];
    for (final l in userLangs) {
      final trimmed = l.trim();
      if (trimmed.isNotEmpty && !list.contains(trimmed)) {
        list.add(trimmed);
      }
    }
    for (final d in defaults) {
      if (!list.contains(d)) {
        list.add(d);
      }
    }
    return list;
  }

  // O(K) Prefix Trie for sub-millisecond instant autocomplete on keystroke
  final PrefixTrie<String> _localSearchTrie = PrefixTrie<String>();

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
      'title': 'Top Tamil Hits',
      'query': 'Top Tamil Hits',
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
  void initState() {
    super.initState();
    _populateLocalSearchTrie();
    SearchHistoryManager.historyNotifier.addListener(_updateTrieWithHistory);
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus && !_isSearchActiveNotifier.value) {
      _isSearchActiveNotifier.value = true;
    }
  }

  void _populateLocalSearchTrie() {
    for (int i = 0; i < _trendingArtists.length; i++) {
      _localSearchTrie.insert(_trendingArtists[i], weight: 100 - i);
    }
    for (int i = 0; i < _browseCategories.length; i++) {
      final title = _browseCategories[i]['title'] as String?;
      if (title != null) {
        _localSearchTrie.insert(title, weight: 80 - i);
      }
    }
    FuzzySearchService.registerCandidates(_trendingArtists);
    _updateTrieWithHistory();
  }

  void _updateTrieWithHistory() {
    final recent = SearchHistoryManager.historyNotifier.value;
    for (int i = 0; i < recent.length; i++) {
      _localSearchTrie.insert(recent[i], weight: 120 - i);
    }
    FuzzySearchService.registerCandidates(recent);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _isSearchActiveNotifier.dispose();
    SearchHistoryManager.historyNotifier.removeListener(_updateTrieWithHistory);
    _searchController.dispose();
    _debounceTimer?.cancel();
    _currentTabNotifier.dispose();
    _selectedLanguageNotifier.dispose();
    _isSearchingNotifier.dispose();
    _hasSearchedNotifier.dispose();
    _suggestionsNotifier.dispose();
    _fuzzyCorrectionNotifier.dispose();
    _resultsNotifier.dispose();
    super.dispose();
  }

  void _enterActiveSearch() {
    if (!_isSearchActiveNotifier.value) {
      _isSearchActiveNotifier.value = true;
    }
    _searchFocusNode.requestFocus();
  }

  void _exitActiveSearch() {
    _debounceTimer?.cancel();
    _searchFocusNode.unfocus();
    _searchController.clear();
    _isSearchActiveNotifier.value = false;
    _hasSearchedNotifier.value = false;
    _isSearchingNotifier.value = false;
    _selectedLanguageNotifier.value = 'All';
    _suggestionsNotifier.value = [];
    _fuzzyCorrectionNotifier.value = null;
    _resultsNotifier.value = const SearchResultsState();
  }

  void _onQueryChanged(String query) {
    if (!_isSearchActiveNotifier.value) {
      _isSearchActiveNotifier.value = true;
    }
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

    // Instant O(K) Trie Autocomplete Lookup (0ms local latency before network debouncing)
    final instantMatches = _localSearchTrie.findByPrefix(clean, limit: 6).map((m) => m.term).toList();
    if (instantMatches.isNotEmpty) {
      _suggestionsNotifier.value = instantMatches;
      _fuzzyCorrectionNotifier.value = null;
    } else {
      // Instant O(log N) BK-Tree Metric Fuzzy Typo Resolution
      final correction = FuzzySearchService.findCorrection(clean);
      if (correction != null) {
        _fuzzyCorrectionNotifier.value = correction;
        _suggestionsNotifier.value = [correction.corrected];
      } else {
        _fuzzyCorrectionNotifier.value = null;
      }
    }

    // Stage 1: Instant Debounced Typeahead (< 150ms)
    // Asynchronously queries YouTube and JioSaavn autocomplete in parallel
    SearchService.getTypeaheadSuggestions(clean, localTrie: _localSearchTrie, limit: 8).then((suggs) {
      if (mounted && _searchController.text.trim() == clean) {
        _suggestionsNotifier.value = suggs;
      }
    });

    // Stage 2: 350ms Debounce for Parallel Multi-Source Entity Fetch
    // Prevents heavy search requests while user is actively typing
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _executeSearch(clean, saveHistory: false);
    });
  }

  Future<void> _executeSearch(String query, {bool saveHistory = false}) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    if (!_isSearchActiveNotifier.value) {
      _isSearchActiveNotifier.value = true;
    }

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
    final selectedLang = _selectedLanguageNotifier.value;
    final effectiveLangFilter = (selectedLang == 'All' ? null : selectedLang);

    // Direct URL / Entity detection: Instant resolution for pasted YouTube URLs or Playlist links
    final directEntity = await SearchService.resolveDirectUrlOrEntity(clean);
    if (directEntity != null) {
      if (!mounted || currentRequestId != _searchRequestId) return;
      final tracks = (directEntity['tracks'] as List<Song>?) ?? <Song>[];
      _resultsNotifier.value = SearchResultsState(
        ytSongs: tracks,
        songs: tracks,
        topResult: {
          'type': directEntity['type'],
          'id': directEntity['id'],
          'title': directEntity['title'],
          'subtitle': directEntity['subtitle'],
          'image': directEntity['image'],
        },
      );
      _isSearchingNotifier.value = false;
      return;
    }

    try {
      if (tab == 'All') {
        await for (final unified in SearchService.searchProgressive(clean, language: effectiveLangFilter, limit: 25)) {
          if (!mounted || currentRequestId != _searchRequestId) return;
          _resultsNotifier.value = SearchResultsState(
            topResult: unified.topResult,
            songs: unified.songs,
            ytSongs: unified.ytSongs,
            saavnSongs: unified.saavnSongs,
            audiusSongs: unified.audiusSongs,
            albums: unified.albums,
            artists: unified.artists,
            playlists: unified.playlists,
            didYouMean: unified.didYouMean,
            error: unified.error,
          );
          if (unified.songs.isNotEmpty) {
            DefaultStreamResolver.prewarmSongs(unified.songs, limit: 3);
          }
        }
        if (mounted && currentRequestId == _searchRequestId) {
          _isSearchingNotifier.value = false;
        }
        return;
      } else if (tab == 'Playlists') {
        final playlists = await SearchService.searchPlaylists(clean, language: effectiveLangFilter, limit: 30);
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(playlists: playlists);
        _isSearchingNotifier.value = false;
        return;
      } else if (tab == 'Saavn' || tab == 'Songs') {
        final songs = await SearchService.searchSongsTab(clean, language: effectiveLangFilter, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(
          saavnSongs: songs,
          songs: songs,
        );
        _isSearchingNotifier.value = false;
        if (songs.isNotEmpty) {
          DefaultStreamResolver.prewarmSongs(songs, limit: 3);
        }
      } else if (tab == 'Albums') {
        final albums = await SearchService.searchAlbumsTab(clean, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(albums: albums);
        _isSearchingNotifier.value = false;
      } else if (tab == 'Artists') {
        final artists = await SearchService.searchArtistsTab(clean, language: effectiveLangFilter, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(artists: artists);
        _isSearchingNotifier.value = false;
      } else if (tab == 'YT Music' || tab == 'YouTube Music' || tab == 'YouTube') {
        final ytSongs = await SearchService.searchYtMusicTab(clean, language: effectiveLangFilter, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(ytSongs: ytSongs, songs: ytSongs);
        _isSearchingNotifier.value = false;
        if (ytSongs.isNotEmpty) {
          DefaultStreamResolver.prewarmSongs(ytSongs, limit: 3);
        }
      } else if (tab == 'Audius') {
        final audiusTracks = await SearchService.searchAudiusTab(clean, limit: 25);
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(audiusSongs: audiusTracks, songs: audiusTracks);
        _isSearchingNotifier.value = false;
        if (audiusTracks.isNotEmpty) {
          DefaultStreamResolver.prewarmSongs(audiusTracks, limit: 3);
        }
      }

      if (mounted && currentRequestId == _searchRequestId && _resultsNotifier.value.isEmpty && !_resultsNotifier.value.hasError && correction != null) {
        final fallbackSongs = await FuzzySearchService.executeFallbackSearch(clean, language: effectiveLangFilter ?? prefLang);
        if (fallbackSongs.isNotEmpty && mounted && currentRequestId == _searchRequestId) {
          final grouped = SongRepository.groupCanonicalSongs(fallbackSongs, preferredLanguage: effectiveLangFilter ?? prefLang);
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

  void _onLanguageChanged(String lang) {
    if (_selectedLanguageNotifier.value == lang) return;
    _selectedLanguageNotifier.value = lang;
    if (_searchController.text.isNotEmpty) {
      _executeSearch(_searchController.text, saveHistory: false);
    }
  }

  void _triggerCategorySearch(String query) {
    if (!_isSearchActiveNotifier.value) {
      _isSearchActiveNotifier.value = true;
    }
    final prefLang = SettingsManager.preferredLanguages.isNotEmpty
        ? SettingsManager.preferredLanguages.first
        : 'Tamil';
    final intent = SearchService.understandQuery(query);
    // Contextualize generic CATEGORY tiles with the user's preferred language to avoid cross-language leaks.
    // (Recent searches / artist chips must NOT use this path: see _searchExactQuery.)
    final effectiveQuery = SearchQueryPlanner.forCategory(
      query,
      preferredLanguage: prefLang,
      explicitLanguage: intent.explicitLanguage,
    );
    _searchController.text = effectiveQuery;
    _executeSearch(effectiveQuery, saveHistory: true);
  }

  /// Recent-search and trending-artist taps: search the text exactly as the user wrote it.
  /// No language is injected, the language chip stays on "All", and history is not polluted.
  void _searchExactQuery(String query) {
    final exact = SearchQueryPlanner.forExactQuery(query);
    if (exact.isEmpty) return;
    if (!_isSearchActiveNotifier.value) {
      _isSearchActiveNotifier.value = true;
    }
    _searchController.text = exact;
    _searchController.selection = TextSelection.collapsed(offset: exact.length);
    _executeSearch(exact, saveHistory: true);
  }

  void _recordSearchResultClick([Song? song]) {
    final clean = _searchController.text.trim();
    if (clean.isNotEmpty) {
      SearchHistoryManager.addQuery(clean);
    }
    if (song != null) {
      SearchHistoryManager.addSong(song);
      SearchService.recordSearchClick(song);
    }
  }

  void _showSongOptions(Song song) {
    SearchSongOptionsSheet.show(context, song);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSearchActiveNotifier.value && _searchController.text.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearchActiveNotifier.value || _searchController.text.isNotEmpty) {
          _exitActiveSearch();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        body: SafeArea(
          child: ValueListenableBuilder<bool>(
            valueListenable: _isSearchActiveNotifier,
            builder: (context, isSearchActive, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isSearchActive && _searchController.text.isEmpty) ...[
                    // Landing View Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      child: Text(
                        'Search',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: GestureDetector(
                        onTap: _enterActiveSearch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.surfaceBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search_rounded, color: AppColors.neonViolet, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'What do you want to play?',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.textSecondary,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Active Search View Header with Back button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                            tooltip: 'Back to Search',
                            onPressed: _exitActiveSearch,
                          ),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.surfaceBorderHighlight),
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: _onQueryChanged,
                                onSubmitted: (query) => _executeSearch(query, saveHistory: true),
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                                textInputAction: TextInputAction.search,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: 'Search songs, artists, albums...',
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
                        ],
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

                    // Search Multi-Entity Category Tabs (active mode only)
                    SizedBox(
                      height: 38,
                      child: ValueListenableBuilder<String>(
                        valueListenable: _currentTabNotifier,
                        builder: (context, currentTab, _) {
                          return ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            scrollDirection: Axis.horizontal,
                            children: ['All', 'Playlists', 'YT Music', 'Saavn', 'Albums', 'Artists', 'Audius'].map((tab) {
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
                    const SizedBox(height: 6),

                    // Dynamic Language Filter Chips (active mode only)
                    SizedBox(
                      height: 32,
                      child: ValueListenableBuilder<String>(
                        valueListenable: _selectedLanguageNotifier,
                        builder: (context, selectedLang, _) {
                          return ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            scrollDirection: Axis.horizontal,
                            children: _availableLanguages.map((lang) {
                              final isSelected = selectedLang == lang;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: ChoiceChip(
                                  label: Text(lang),
                                  selected: isSelected,
                                  selectedColor: AppColors.electricCyan.withValues(alpha: 0.25),
                                  backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.6),
                                  labelStyle: GoogleFonts.outfit(
                                    color: isSelected ? AppColors.electricCyan : AppColors.textSecondary,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: isSelected ? AppColors.electricCyan : AppColors.surfaceBorder,
                                    ),
                                  ),
                                  showCheckmark: false,
                                  onSelected: (_) => _onLanguageChanged(lang),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

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
              );
            },
          ),
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
            onSelectExactQuery: _searchExactQuery,
            onPlaySong: (song) {
              SearchHistoryManager.addSong(song);
              audioHandler.playSong(song);
            },
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

                if (state.hasError && state.isEmpty && !isSearching) {
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
                        onSongTap: (song) {
                          _recordSearchResultClick(song);
                          audioHandler.playSong(song, queue: state.songs);
                        },
                        onShowOptions: _showSongOptions,
                        onShowVersions: _showVersionsSheet,
                      );
                    } else if (currentTab == 'YT Music' || currentTab == 'YouTube Music' || currentTab == 'YouTube') {
                      var ytList = state.ytSongs.where((s) => s.source.toLowerCase().contains('youtube') || s.source.toLowerCase().contains('yt')).toList();
                      if (ytList.isEmpty && state.songs.isNotEmpty) {
                        ytList = state.songs.where((s) => s.source.toLowerCase().contains('youtube') || s.source.toLowerCase().contains('yt')).toList();
                      }
                      if (ytList.isEmpty && _searchController.text.trim().isNotEmpty && !_isSearchingNotifier.value) {
                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                          if (!mounted) return;
                          final tab = _currentTabNotifier.value;
                          if (tab == 'YT Music' || tab == 'YouTube Music' || tab == 'YouTube') {
                            final q = _searchController.text.trim();
                            if (q.isNotEmpty) {
                              _isSearchingNotifier.value = true;
                              final results = await SearchService.searchYtMusicTab(q, limit: 25);
                              if (mounted && _searchController.text.trim() == q) {
                                _resultsNotifier.value = SearchResultsState(ytSongs: results, songs: results);
                                _isSearchingNotifier.value = false;
                              }
                            }
                          }
                        });
                      }
                      return _buildSongsList(ytList);
                    } else if (currentTab == 'Saavn' || currentTab == 'Songs') {
                      final saavnList = state.saavnSongs.isNotEmpty
                          ? state.saavnSongs
                          : state.songs.where((s) => s.source == 'saavn').toList();
                      return _buildSongsList(saavnList);
                    } else if (currentTab == 'Audius') {
                      final audiusList = state.audiusSongs.isNotEmpty
                          ? state.audiusSongs
                          : state.songs.where((s) => s.source == 'audius').toList();
                      return _buildSongsList(audiusList);
                    } else if (currentTab == 'Playlists') {
                      return SearchPlaylistsGrid(
                        playlists: state.playlists,
                        query: _searchController.text,
                        onRecordClick: _recordSearchResultClick,
                      );
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
            audioHandler.playSong(song, queue: songList);
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
