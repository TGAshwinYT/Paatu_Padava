import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../domain/models/search_results_state.dart';
export '../../domain/models/search_results_state.dart';
import '../../services/error_handler.dart';
import '../../services/player_handler.dart';
import '../../services/search_history_manager.dart';
import '../../services/favorites_manager.dart';
import '../../services/catalog_database.dart';
// import '../../services/settings_manager.dart';
import '../../services/fuzzy_search_service.dart';
import '../../services/search_service.dart';
import '../../logic/stream_resolver.dart';
import '../../logic/search_query_planner.dart';
import '../../core/dsa/prefix_trie.dart';
import '../theme/app_theme.dart';
import 'library_screen.dart';
import '../widgets/search/search_constants.dart';
import '../widgets/search/search_header_bar.dart';
import '../widgets/search/search_error_view.dart';
import '../widgets/search/search_pre_content.dart';
import '../widgets/search/search_active_typing_suggestions.dart';
import '../widgets/search/search_all_results_view.dart';
import '../widgets/search/search_song_options_sheet.dart';
import '../widgets/search/search_versions_sheet.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<bool> _isSearchActiveNotifier = ValueNotifier<bool>(false);
  Timer? _debounceTimer;
  Timer? _typeaheadDebounceTimer;
  int _searchRequestId = 0;

  // 3-State Progressive Search Notifiers
  final ValueNotifier<bool> _isSearchingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _hasSearchedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<Song>> _localMatchesNotifier = ValueNotifier<List<Song>>([]);
  final ValueNotifier<List<String>> _suggestionsNotifier = ValueNotifier<List<String>>([]);
  final ValueNotifier<SearchResultsState> _resultsNotifier = ValueNotifier<SearchResultsState>(const SearchResultsState());
  final PrefixTrie<String> _localSearchTrie = PrefixTrie<String>();
  String? _activeSearchQuery;

  @override
  void initState() {
    super.initState();
    _initTrie();
    SearchHistoryManager.historyNotifier.addListener(_updateTrieWithHistory);
    SearchHistoryManager.recentSongsNotifier.addListener(_updateTrieWithHistory);
    FavoritesManager.favoritesNotifier.addListener(_updateTrieWithHistory);
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && !_isSearchActiveNotifier.value) _isSearchActiveNotifier.value = true;
    });
  }

  void _initTrie() {
    FuzzySearchService.registerCandidates(SearchConstants.trendingArtists);
    _updateTrieWithHistory();
  }

  void _updateTrieWithHistory() {
    final recent = SearchHistoryManager.historyNotifier.value;
    _localSearchTrie.clear();
    for (int i = 0; i < SearchConstants.trendingArtists.length; i++) { _localSearchTrie.insert(SearchConstants.trendingArtists[i], weight: 100 - i); }
    for (int i = 0; i < SearchConstants.browseCategories.length; i++) {
      final t = SearchConstants.browseCategories[i]['title'] as String?;
      if (t != null) _localSearchTrie.insert(t, weight: 80 - i);
    }
    for (int i = 0; i < recent.length; i++) { _localSearchTrie.insert(recent[i], weight: 120 - i); }
    FuzzySearchService.registerCandidates(recent);
    final localSongs = [...SearchHistoryManager.recentSongsNotifier.value, ...FavoritesManager.favoritesNotifier.value];
    if (localSongs.isNotEmpty) FuzzySearchService.registerSongs(localSongs);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _isSearchActiveNotifier.dispose();
    SearchHistoryManager.historyNotifier.removeListener(_updateTrieWithHistory);
    SearchHistoryManager.recentSongsNotifier.removeListener(_updateTrieWithHistory);
    FavoritesManager.favoritesNotifier.removeListener(_updateTrieWithHistory);
    _searchController.dispose();
    _debounceTimer?.cancel();
    _typeaheadDebounceTimer?.cancel();
    for (final n in [_isSearchingNotifier, _hasSearchedNotifier, _localMatchesNotifier, _suggestionsNotifier, _resultsNotifier]) {
      n.dispose();
    }
    super.dispose();
  }

  void _resetSearchState() {
    ++_searchRequestId;
    _activeSearchQuery = null;
    _hasSearchedNotifier.value = _isSearchingNotifier.value = false;
    _localMatchesNotifier.value = [];
    _suggestionsNotifier.value = [];
    _resultsNotifier.value = const SearchResultsState();
  }

  void _exitActiveSearch() {
    _debounceTimer?.cancel();
    _typeaheadDebounceTimer?.cancel();
    ++_searchRequestId;
    _searchFocusNode.unfocus();
    _searchController.clear();
    _isSearchActiveNotifier.value = false;
    _resetSearchState();
  }

  void _onQueryChanged(String query) {
    if (!_isSearchActiveNotifier.value) _isSearchActiveNotifier.value = true;
    _debounceTimer?.cancel();
    _typeaheadDebounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      _resetSearchState();
      return;
    }

    _hasSearchedNotifier.value = false;

    // State B: Instant Local Song Matches (< 5ms) - Only match songs whose TITLE starts with or matches query
    final lower = clean.toLowerCase();
    final allLocal = [...SearchHistoryManager.recentSongsNotifier.value, ...FavoritesManager.favoritesNotifier.value];
    final matchedSongs = <Song>[];
    for (final s in allLocal) {
      final t = SearchQueryPlanner.cleanTitle(s.title).toLowerCase();
      if ((t.startsWith(lower) || t.split(RegExp(r'\s+')).any((w) => w.startsWith(lower))) && !matchedSongs.any((m) => m.id == s.id)) {
        matchedSongs.add(s);
        if (matchedSongs.length >= 3) break;
      }
    }
    _localMatchesNotifier.value = matchedSongs;

    // Supplement with Master Catalog matches only if song title genuinely matches
    if (matchedSongs.length < 3) {
      CatalogDatabase.searchCatalog(clean, limit: 5).then((catSongs) {
        if (!mounted || _searchController.text.trim() != clean || _hasSearchedNotifier.value) return;
        final current = List<Song>.from(_localMatchesNotifier.value);
        for (final cs in catSongs) {
          final ct = SearchQueryPlanner.cleanTitle(cs.title).toLowerCase();
          if ((ct.startsWith(lower) || ct.split(RegExp(r'\s+')).any((w) => w.startsWith(lower))) && !current.any((x) => x.id == cs.id) && current.length < 3) {
            current.add(cs);
          }
        }
        _localMatchesNotifier.value = current;
      });
    }

    // State B: Instant Prefix Trie Suggestions (smooth, no flash on empty)
    final instant = _localSearchTrie.findByPrefix(clean, limit: 5).map((m) => m.term).toList();
    if (instant.isNotEmpty) {
      _suggestionsNotifier.value = instant;
    } else {
      final retained = _suggestionsNotifier.value.where((s) => s.toLowerCase().contains(lower)).toList();
      if (retained.isNotEmpty) _suggestionsNotifier.value = retained;
    }

    // State B: Asynchronous Live Typeahead Fetch (< 120ms, debounced 150ms)
    _typeaheadDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      SearchService.getTypeaheadSuggestions(clean, localTrie: _localSearchTrie, limit: 5).then((suggs) {
        if (mounted && _searchController.text.trim() == clean && !_hasSearchedNotifier.value) {
          _suggestionsNotifier.value = suggs;
        }
      });
    });

    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _executeSearch(clean, commit: false, saveHistory: false);
    });
  }

  Future<void> _executeSearch(String query, {bool commit = true, bool saveHistory = false}) async {
    _debounceTimer?.cancel();
    _typeaheadDebounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) return;
    if (!_isSearchActiveNotifier.value) _isSearchActiveNotifier.value = true;

    if (saveHistory && clean.isNotEmpty) SearchHistoryManager.addQuery(clean);

    if (commit) {
      _searchFocusNode.unfocus();
      _hasSearchedNotifier.value = true;

      // If results for this query are already fetched, display instantly without wiping or spinner!
      if (_activeSearchQuery == clean && !_resultsNotifier.value.isEmpty) {
        _isSearchingNotifier.value = false;
        if (_resultsNotifier.value.songs.isNotEmpty) DefaultStreamResolver.prewarmSongs(_resultsNotifier.value.songs, limit: 3);
        return;
      }
      // If search for this exact query is already streaming, don't restart or wipe
      if (_activeSearchQuery == clean && _isSearchingNotifier.value) return;

      _resultsNotifier.value = const SearchResultsState();
      _isSearchingNotifier.value = true;
    }

    _activeSearchQuery = clean;
    final currentRequestId = ++_searchRequestId;

    try {
      final direct = await SearchService.resolveDirectUrlOrEntity(clean);
      if (direct != null) {
        if (!mounted || currentRequestId != _searchRequestId) return;
        final tracks = (direct['tracks'] as List<Song>?) ?? <Song>[];
        _resultsNotifier.value = SearchResultsState(
          ytSongs: tracks, songs: tracks,
          topResult: {'type': direct['type'], 'id': direct['id'], 'title': direct['title'], 'subtitle': direct['subtitle'], 'image': direct['image']},
        );
        _isSearchingNotifier.value = false;
        return;
      }

      await for (final unified in SearchService.searchProgressive(clean, language: null, limit: 25)) {
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(
          topResult: unified.topResult, songs: unified.songs, ytSongs: unified.ytSongs,
          saavnSongs: unified.saavnSongs, audiusSongs: unified.audiusSongs, albums: unified.albums,
          artists: unified.artists, playlists: unified.playlists, didYouMean: unified.didYouMean, error: unified.error,
        );

        if (commit && unified.songs.isNotEmpty) {
          DefaultStreamResolver.prewarmSongs(unified.songs, limit: 3);
        }
      }
      if (mounted && currentRequestId == _searchRequestId) _isSearchingNotifier.value = false;
    } catch (e, stack) {
      if (mounted && currentRequestId == _searchRequestId) {
        if (commit && _resultsNotifier.value.isEmpty) {
          final err = ErrorHandler.resolve(e, stackTrace: stack, context: 'SearchScreen._executeSearch');
          _resultsNotifier.value = SearchResultsState(error: err);
        }
        _isSearchingNotifier.value = false;
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
    if (song != null) {
      SearchHistoryManager.addSong(song);
      SearchService.recordSearchClick(song);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSearchActiveNotifier.value && _searchController.text.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearchActiveNotifier.value || _searchController.text.isNotEmpty) _exitActiveSearch();
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
                  Expanded(child: _buildBody()),
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
        final query = _searchController.text.trim();

        // State A: Zero-Query State (Before Typing)
        if (!hasSearched && query.isEmpty) {
          return SearchPreContent(
            trendingArtists: SearchConstants.trendingArtists,
            browseCategories: SearchConstants.browseCategories,
            onSelectQuery: _triggerCategorySearch,
            onSelectExactQuery: _searchExactQuery,
            onPlaySong: (song) {
              SearchHistoryManager.addSong(song);
              audioHandler.playSong(song);
            },
          );
        }

        // State B: Active Typing State (1..N characters, keyboard open)
        if (!hasSearched && query.isNotEmpty) {
          return ValueListenableBuilder<List<Song>>(
            valueListenable: _localMatchesNotifier,
            builder: (context, localMatches, _) {
              return ValueListenableBuilder<List<String>>(
                valueListenable: _suggestionsNotifier,
                builder: (context, completions, _) {
                  return SearchActiveTypingSuggestions(
                    localSongMatches: localMatches,
                    queryCompletions: completions,
                    onPlaySong: (song) { SearchHistoryManager.addSong(song); SearchService.recordSearchClick(song); audioHandler.playSong(song); },
                    onSelectQuery: _triggerCategorySearch,
                    onAppendQuery: (q) { _searchController.text = q; _searchController.selection = TextSelection.collapsed(offset: q.length); _onQueryChanged(q); },
                  );
                },
              );
            },
          );
        }

        // State C: Committed Results State (User paused or submitted)
        return ValueListenableBuilder<SearchResultsState>(
          valueListenable: _resultsNotifier,
          builder: (context, state, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _isSearchingNotifier,
              builder: (context, isSearching, _) {
                if (state.isEmpty && isSearching) return const Center(child: CircularProgressIndicator(color: AppColors.neonViolet));

                if (state.hasError && state.isEmpty && !isSearching) {
                  return SearchErrorView(
                    error: state.error!,
                    onRetry: () {
                      final q = _searchController.text.trim();
                      if (q.isNotEmpty) _executeSearch(q, saveHistory: false);
                    },
                    onOpenDownloads: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryScreen())),
                  );
                }

                return SearchAllResultsView(
                  state: state,
                  query: _searchController.text,
                  onDidYouMeanTap: (sug) {
                    _searchController.text = sug;
                    _executeSearch(sug, saveHistory: true);
                  },
                  onArtistRecordClick: () => _recordSearchResultClick(),
                  onRecordClick: ([song]) => _recordSearchResultClick(song),
                  onSongTap: (song) { _recordSearchResultClick(song); audioHandler.playSong(song, queue: state.songs); },
                  onShowOptions: (s) => SearchSongOptionsSheet.show(context, s),
                  onShowVersions: (s) => SearchVersionsSheet.show(context, s, onSelectSong: (v) { _recordSearchResultClick(v); audioHandler.playSong(v); }),
                );
              },
            );
          },
        );
      },
    );
  }
}
