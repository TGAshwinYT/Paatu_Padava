import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../domain/models/search_results_state.dart';
export '../../domain/models/search_results_state.dart';
import '../../services/app_logger.dart';
import '../../services/error_handler.dart';
import '../../services/player_handler.dart';
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
  Timer? _typeaheadDebounceTimer;
  int _searchRequestId = 0;

  // 3-State Progressive Search Notifiers
  final ValueNotifier<bool> _isSearchingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _hasSearchedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<Song>> _localMatchesNotifier = ValueNotifier<List<Song>>([]);
  final ValueNotifier<List<String>> _suggestionsNotifier = ValueNotifier<List<String>>([]);
  final ValueNotifier<SearchResultsState> _resultsNotifier = ValueNotifier<SearchResultsState>(const SearchResultsState());
  final PrefixTrie<String> _localSearchTrie = PrefixTrie<String>();

  @override
  void initState() {
    super.initState();
    _initTrie();
    for (final l in [SearchHistoryManager.historyNotifier, SearchHistoryManager.recentSongsNotifier, FavoritesManager.favoritesNotifier, DownloadManager.downloadedSongsNotifier]) {
      l.addListener(_updateTrieWithHistory);
    }
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
    if (allLocal.isNotEmpty) FuzzySearchService.registerSongs(allLocal);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _isSearchActiveNotifier.dispose();
    for (final l in [SearchHistoryManager.historyNotifier, SearchHistoryManager.recentSongsNotifier, FavoritesManager.favoritesNotifier, DownloadManager.downloadedSongsNotifier]) {
      l.removeListener(_updateTrieWithHistory);
    }
    _searchController.dispose();
    _typeaheadDebounceTimer?.cancel();
    for (final n in [_isSearchingNotifier, _hasSearchedNotifier, _localMatchesNotifier, _suggestionsNotifier, _resultsNotifier]) {
      n.dispose();
    }
    super.dispose();
  }

  void _resetSearchState() {
    ++_searchRequestId;
    _hasSearchedNotifier.value = _isSearchingNotifier.value = false;
    _localMatchesNotifier.value = [];
    _suggestionsNotifier.value = [];
    _resultsNotifier.value = const SearchResultsState();
  }

  void _exitActiveSearch() {
    _typeaheadDebounceTimer?.cancel();
    ++_searchRequestId;
    _searchFocusNode.unfocus();
    _searchController.clear();
    _isSearchActiveNotifier.value = false;
    _resetSearchState();
  }

  void _onQueryChanged(String query) {
    if (!_isSearchActiveNotifier.value) _isSearchActiveNotifier.value = true;
    _typeaheadDebounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      _resetSearchState();
      return;
    }

    _hasSearchedNotifier.value = false;

    // State B: Instant Local Song Matches (< 5ms) - Only match songs whose TITLE starts with or matches query
    final lower = clean.toLowerCase();
    final allLocal = [...DownloadManager.downloadedSongsNotifier.value, ...FavoritesManager.favoritesNotifier.value, ...SearchHistoryManager.recentSongsNotifier.value];
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
      }).catchError((e, stack) => AppLogger.log('SearchScreen', 'Catalog query error: $e', level: LogLevel.warn));
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
    _resultsNotifier.value = const SearchResultsState();
    _isSearchingNotifier.value = true;

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
        if (tracks.isNotEmpty) DefaultStreamResolver.prewarmSongs(tracks, limit: 3);
        return;
      }

      await for (final unified in SearchService.searchProgressive(clean, language: null, limit: 25)) {
        if (!mounted || currentRequestId != _searchRequestId) return;
        _resultsNotifier.value = SearchResultsState(
          topResult: unified.topResult, songs: unified.songs, ytSongs: unified.ytSongs,
          saavnSongs: unified.saavnSongs, audiusSongs: unified.audiusSongs, albums: unified.albums,
          artists: unified.artists, playlists: unified.playlists, didYouMean: unified.didYouMean, error: unified.error,
        );
      }
      if (mounted && currentRequestId == _searchRequestId) {
        _isSearchingNotifier.value = false;
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
    return ListenableBuilder(
      listenable: Listenable.merge([_isSearchActiveNotifier, _hasSearchedNotifier, _searchController]),
      builder: (context, _) {
        final hasActiveSearch = _isSearchActiveNotifier.value ||
            _hasSearchedNotifier.value ||
            _searchController.text.isNotEmpty;
        return PopScope(
          canPop: !hasActiveSearch,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (hasActiveSearch) _exitActiveSearch();
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
      },
    );
  }

  Widget _buildBody() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchController,
      builder: (context, textValue, _) {
        final query = textValue.text.trim();
        return ValueListenableBuilder<bool>(
          valueListenable: _hasSearchedNotifier,
          builder: (context, hasSearched, _) {

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

        // State C: Committed Results State (Explicitly submitted or suggestion selected)
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
      },
    );
  }
}
