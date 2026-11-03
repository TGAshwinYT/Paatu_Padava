import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../domain/models/search_results_state.dart';
export '../../domain/models/search_results_state.dart';
import '../../services/app_logger.dart';
import '../../services/error_handler.dart';
import '../../services/search_history_manager.dart';
import '../../services/favorites_manager.dart';
import '../../services/catalog_database.dart';
import '../../services/download_manager.dart';
import '../../services/fuzzy_search_service.dart';
import '../../services/search_service.dart';
import '../../logic/stream_resolver.dart';
import '../../logic/search_query_planner.dart';
import '../../core/dsa/prefix_trie.dart';
import '../theme/app_theme.dart';
import '../widgets/search/search_constants.dart';
import '../widgets/search/search_header_bar.dart';
import '../widgets/search/search_body_content.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<bool> _isSearchActiveNotifier = ValueNotifier<bool>(false);
  Timer? _typeaheadDebounceTimer;
  Timer? _libraryDebounceTimer;
  int _searchRequestId = 0;

  // 3-State Progressive Search Notifiers
  final ValueNotifier<bool> _isSearchingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isInitialLoadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _hasSearchedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _canPopNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<List<Song>> _localMatchesNotifier = ValueNotifier<List<Song>>([]);
  final ValueNotifier<List<String>> _suggestionsNotifier = ValueNotifier<List<String>>([]);
  final ValueNotifier<SearchResultsState> _resultsNotifier = ValueNotifier<SearchResultsState>(const SearchResultsState());
  final PrefixTrie<String> _localSearchTrie = PrefixTrie<String>();

  void _updateCanPop() {
    final hasActiveSearch = _isSearchActiveNotifier.value || _hasSearchedNotifier.value || _searchController.text.isNotEmpty;
    final canPop = !hasActiveSearch;
    if (_canPopNotifier.value != canPop) _canPopNotifier.value = canPop;
  }

  @override
  void initState() {
    super.initState();
    _initTrie();
    SearchHistoryManager.historyNotifier.addListener(_onHistoryQueryAdded);
    for (final l in [SearchHistoryManager.recentSongsNotifier, FavoritesManager.favoritesNotifier, DownloadManager.downloadedSongsNotifier]) {
      l.addListener(_scheduleLibrarySync);
    }
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && !_isSearchActiveNotifier.value) {
        _isSearchActiveNotifier.value = true;
        _updateCanPop();
      }
    });
  }

  void _scheduleLibrarySync() {
    _libraryDebounceTimer?.cancel();
    _libraryDebounceTimer = Timer(const Duration(milliseconds: 250), () { if (mounted) _updateTrieWithLibrary(); });
  }

  void _initTrie() {
    FuzzySearchService.registerCandidates(SearchConstants.trendingArtists);
    _updateTrieWithLibrary();
  }

  int _lastHistoryCount = 0;

  void _onHistoryQueryAdded() {
    final recent = SearchHistoryManager.historyNotifier.value;
    if (recent.length < _lastHistoryCount || recent.isEmpty) {
      _lastHistoryCount = recent.length;
      _updateTrieWithLibrary();
      return;
    }
    _lastHistoryCount = recent.length;
    if (recent.isNotEmpty) {
      final latest = recent.first;
      final clean = SearchQueryPlanner.cleanTitle(latest).trim();
      if (clean.length >= 2) {
        _localSearchTrie.insert(clean, weight: 130);
        FuzzySearchService.registerCandidates([latest]);
      }
      SearchService.clearTypeaheadCache();
    }
  }

  void _updateTrieWithLibrary() {
    final recent = SearchHistoryManager.historyNotifier.value;
    _lastHistoryCount = recent.length;
    _localSearchTrie.clear();
    final seen = <String>{};
    void addTerm(String? term, int weight) {
      if (term == null) return;
      final clean = SearchQueryPlanner.cleanTitle(term).trim();
      if (clean.length >= 2 && seen.add(clean.toLowerCase())) _localSearchTrie.insert(clean, weight: weight);
    }

    final saved = [...DownloadManager.downloadedSongsNotifier.value, ...FavoritesManager.favoritesNotifier.value];
    for (int i = 0; i < saved.length; i++) { addTerm(saved[i].title, 150 - (i % 20)); addTerm(saved[i].primaryArtist, 140 - (i % 20)); }
    for (int i = 0; i < recent.length; i++) { addTerm(recent[i], 130 - i); }
    final recentSongs = SearchHistoryManager.recentSongsNotifier.value;
    for (int i = 0; i < recentSongs.length; i++) { addTerm(recentSongs[i].title, 110 - i); }
    for (int i = 0; i < SearchConstants.trendingArtists.length; i++) { addTerm(SearchConstants.trendingArtists[i], 90 - i); }
    for (int i = 0; i < SearchConstants.browseCategories.length; i++) { addTerm(SearchConstants.browseCategories[i]['title'] as String?, 70 - i); }

    FuzzySearchService.registerCandidates(recent);
    final allLocal = [...saved, ...recentSongs];
    if (allLocal.isNotEmpty) FuzzySearchService.registerSongs(allLocal, isLibrary: true);
    SearchService.clearTypeaheadCache();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _isSearchActiveNotifier.dispose();
    _canPopNotifier.dispose();
    SearchHistoryManager.historyNotifier.removeListener(_onHistoryQueryAdded);
    for (final l in [SearchHistoryManager.recentSongsNotifier, FavoritesManager.favoritesNotifier, DownloadManager.downloadedSongsNotifier]) {
      l.removeListener(_scheduleLibrarySync);
    }
    _searchController.dispose();
    _typeaheadDebounceTimer?.cancel();
    _libraryDebounceTimer?.cancel();
    for (final n in [_isSearchingNotifier, _isInitialLoadingNotifier, _hasSearchedNotifier, _localMatchesNotifier, _suggestionsNotifier, _resultsNotifier]) {
      n.dispose();
    }
    super.dispose();
  }

  void _resetSearchState() {
    ++_searchRequestId;
    _hasSearchedNotifier.value = _isSearchingNotifier.value = _isInitialLoadingNotifier.value = false;
    _localMatchesNotifier.value = [];
    _suggestionsNotifier.value = [];
    _resultsNotifier.value = const SearchResultsState();
    _updateCanPop();
  }

  void _exitActiveSearch() {
    _typeaheadDebounceTimer?.cancel();
    ++_searchRequestId;
    _searchFocusNode.unfocus();
    _searchController.clear();
    _isSearchActiveNotifier.value = false;
    _resetSearchState();
    _updateCanPop();
  }

  void _onQueryChanged(String query) {
    if (!_isSearchActiveNotifier.value) _isSearchActiveNotifier.value = true;
    _updateCanPop();
    _typeaheadDebounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      _resetSearchState();
      return;
    }

    _hasSearchedNotifier.value = false;

    // State B: Instant Local Song Matches (< 5ms) - Uses FuzzySearchService for title, artist, album, and typo tolerance
    final allLocal = [...DownloadManager.downloadedSongsNotifier.value, ...FavoritesManager.favoritesNotifier.value, ...SearchHistoryManager.recentSongsNotifier.value];
    final matchedSongs = <Song>[];
    for (final s in allLocal) {
      if (FuzzySearchService.matchesSong(s, clean) && !matchedSongs.any((m) => m.id == s.id)) {
        matchedSongs.add(s);
        if (matchedSongs.length >= 3) break;
      }
    }
    _localMatchesNotifier.value = matchedSongs;

    // Supplement with Master Catalog matches
    if (matchedSongs.length < 3) {
      CatalogDatabase.searchCatalog(clean, limit: 5).then((catSongs) {
        if (!mounted || _searchController.text.trim() != clean || _hasSearchedNotifier.value) return;
        final current = List<Song>.from(_localMatchesNotifier.value);
        for (final cs in catSongs) {
          if (FuzzySearchService.matchesSong(cs, clean) && !current.any((x) => x.id == cs.id) && current.length < 3) {
            current.add(cs);
          }
        }
        _localMatchesNotifier.value = current;
      }).catchError((e, stack) => AppLogger.log('SearchScreen', 'Catalog query error: $e', level: LogLevel.warn));
    }

    // State B: Instant Prefix Trie Suggestions (smooth, no ghost completions)
    final lower = clean.toLowerCase();
    final instant = _localSearchTrie.findByPrefix(clean, limit: 5).map((m) => m.term).toList();
    if (instant.isNotEmpty) {
      _suggestionsNotifier.value = instant;
    } else {
      final retained = _suggestionsNotifier.value.where((s) => s.toLowerCase().contains(lower)).toList();
      _suggestionsNotifier.value = retained;
    }

    // State B: Asynchronous Live Typeahead Fetch (debounced 250ms, progressive merge)
    _typeaheadDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      SearchService.getTypeaheadSuggestions(
        clean,
        localTrie: _localSearchTrie,
        limit: 5,
        onPartialResults: (suggs) {
          if (mounted && _searchController.text.trim() == clean && !_hasSearchedNotifier.value) {
            _suggestionsNotifier.value = suggs;
          }
        },
      ).then((suggs) {
        if (mounted && _searchController.text.trim() == clean && !_hasSearchedNotifier.value) {
          _suggestionsNotifier.value = suggs;
        }
      }).catchError((e, stack) => AppLogger.log('SearchScreen', 'Typeahead fetch error: $e', level: LogLevel.warn));
    });
  }

  Future<void> _executeSearch(String query, {bool saveHistory = true}) async {
    _typeaheadDebounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) return;
    if (!_isSearchActiveNotifier.value) _isSearchActiveNotifier.value = true;

    if (saveHistory && clean.isNotEmpty) SearchHistoryManager.addQuery(clean);

    _searchFocusNode.unfocus();
    _hasSearchedNotifier.value = true;
    _updateCanPop();

    // SWR Instant Cache Check: Immediately render cached results if present (0ms flash-free)
    final cached = SearchCache.get(clean);
    if (cached != null) {
      _resultsNotifier.value = SearchResultsState(
        topResult: cached.topResult, songs: cached.songs, ytSongs: cached.ytSongs,
        saavnSongs: cached.saavnSongs, audiusSongs: cached.audiusSongs, albums: cached.albums,
        artists: cached.artists, playlists: cached.playlists, didYouMean: cached.didYouMean, error: cached.error,
      );
      _isInitialLoadingNotifier.value = false;
    } else {
      _resultsNotifier.value = const SearchResultsState();
      _isInitialLoadingNotifier.value = true;
    }
    _isSearchingNotifier.value = true;

    final currentRequestId = ++_searchRequestId;

    try {
      final isLikelyUrl = clean.startsWith('http://') || clean.startsWith('https://') ||
          clean.contains('youtu.be') || clean.contains('youtube.com') || clean.contains('saavn.com');

      if (isLikelyUrl) {
        final direct = await SearchService.resolveDirectUrlOrEntity(clean);
        if (direct != null) {
          if (!mounted || currentRequestId != _searchRequestId) return;
          final tracks = (direct['tracks'] as List<Song>?) ?? <Song>[];
          _resultsNotifier.value = SearchResultsState(
            ytSongs: tracks, songs: tracks,
            topResult: {'type': direct['type'], 'id': direct['id'], 'title': direct['title'], 'subtitle': direct['subtitle'], 'image': direct['image']},
          );
          _isSearchingNotifier.value = false;
          _isInitialLoadingNotifier.value = false;
          if (tracks.isNotEmpty) DefaultStreamResolver.prewarmSongs(tracks, limit: 3);
          return;
        }
      }

      final hasCachedResults = cached != null && cached.songs.isNotEmpty;

      await for (final unified in SearchService.searchProgressive(clean, language: null, limit: 25)) {
        if (!mounted || currentRequestId != _searchRequestId) return;
        // Anti-Flicker SWR Gate: Hold cached list until the final emission arrives
        if (hasCachedResults && !unified.isFinal) {
          continue;
        }
        _resultsNotifier.value = SearchResultsState(
          topResult: unified.topResult, songs: unified.songs, ytSongs: unified.ytSongs,
          saavnSongs: unified.saavnSongs, audiusSongs: unified.audiusSongs, albums: unified.albums,
          artists: unified.artists, playlists: unified.playlists, didYouMean: unified.didYouMean, error: unified.error,
        );
        if (unified.songs.isNotEmpty || unified.albums.isNotEmpty || unified.artists.isNotEmpty) {
          _isInitialLoadingNotifier.value = false;
        }
      }
      if (mounted && currentRequestId == _searchRequestId) {
        _isSearchingNotifier.value = false;
        _isInitialLoadingNotifier.value = false;
        if (_resultsNotifier.value.songs.isNotEmpty) {
          DefaultStreamResolver.prewarmSongs(_resultsNotifier.value.songs, limit: 3);
        }
      }
    } catch (e, stack) {
      if (mounted && currentRequestId == _searchRequestId) {
        if (_resultsNotifier.value.isEmpty) {
          final err = ErrorHandler.resolve(e, stackTrace: stack, context: 'SearchScreen._executeSearch');
          _resultsNotifier.value = SearchResultsState(error: err);
        }
        _isSearchingNotifier.value = false;
        _isInitialLoadingNotifier.value = false;
      }
    }
  }
  void _triggerCategorySearch(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;
    if (!_isSearchActiveNotifier.value) _isSearchActiveNotifier.value = true;
    _searchController.text = clean;
    _searchController.selection = TextSelection.collapsed(offset: clean.length);
    _executeSearch(clean, saveHistory: true);
  }

  void _searchExactQuery(String query) => _triggerCategorySearch(SearchQueryPlanner.forExactQuery(query));

  void _recordSearchResultClick([Song? song]) {
    final clean = _searchController.text.trim();
    if (clean.isNotEmpty) SearchHistoryManager.addQuery(clean);
    if (song != null) { SearchHistoryManager.addSong(song); SearchService.recordSearchClick(song); }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _canPopNotifier,
      builder: (context, canPop, _) {
        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (!canPop) _exitActiveSearch();
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
                      SearchHeaderBar(
                        isSearchActive: isSearchActive,
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onEnterActiveSearch: () {
                          if (!_isSearchActiveNotifier.value) _isSearchActiveNotifier.value = true;
                          _searchFocusNode.requestFocus();
                          _updateCanPop();
                        },
                        onExitActiveSearch: _exitActiveSearch,
                        onChanged: _onQueryChanged,
                        onSubmitted: (q) => _executeSearch(q, saveHistory: true),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _hasSearchedNotifier,
                        builder: (context, hasSearched, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: _isSearchingNotifier,
                            builder: (context, isSearching, _) {
                              if (!isSearching || !hasSearched) return const SizedBox(height: 2);
                              return const LinearProgressIndicator(minHeight: 2, color: AppColors.electricCyan, backgroundColor: Colors.transparent);
                            },
                          );
                        },
                      ),
                      Expanded(
                        child: SearchBodyContent(
                          searchController: _searchController,
                          hasSearchedNotifier: _hasSearchedNotifier,
                          isInitialLoadingNotifier: _isInitialLoadingNotifier,
                          localMatchesNotifier: _localMatchesNotifier,
                          suggestionsNotifier: _suggestionsNotifier,
                          resultsNotifier: _resultsNotifier,
                          onTriggerCategorySearch: _triggerCategorySearch,
                          onSearchExactQuery: _searchExactQuery,
                          onQueryChanged: _onQueryChanged,
                          onExecuteSearch: _executeSearch,
                          onRecordSearchResultClick: _recordSearchResultClick,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
