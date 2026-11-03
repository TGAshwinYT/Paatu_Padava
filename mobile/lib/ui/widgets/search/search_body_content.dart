import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../domain/models/search_results_state.dart';
import '../../../services/player_handler.dart';
import '../../../services/search_history_manager.dart';
import '../../../services/search_service.dart';
import '../../screens/library_screen.dart';
import 'search_constants.dart';
import 'search_pre_content.dart';
import 'search_active_typing_suggestions.dart';
import 'search_all_results_view.dart';
import 'search_skeleton_view.dart';
import 'search_error_view.dart';
import 'search_song_options_sheet.dart';
import 'search_versions_sheet.dart';

/// 3-State progressive body for the Search Screen:
/// State A (Zero Query), State B (Active Typing Suggestions), State C (Committed Results & Skeletons).
class SearchBodyContent extends StatelessWidget {
  final TextEditingController searchController;
  final ValueNotifier<bool> hasSearchedNotifier;
  final ValueNotifier<bool> isInitialLoadingNotifier;
  final ValueNotifier<List<Song>> localMatchesNotifier;
  final ValueNotifier<List<Map<String, dynamic>>>? matchingAlbumsNotifier;
  final ValueNotifier<List<String>> suggestionsNotifier;
  final ValueNotifier<SearchResultsState> resultsNotifier;
  final void Function(String) onTriggerCategorySearch;
  final void Function(String) onSearchExactQuery;
  final void Function(String) onQueryChanged;
  final void Function(String, {bool saveHistory}) onExecuteSearch;
  final void Function([Song?]) onRecordSearchResultClick;

  const SearchBodyContent({
    super.key,
    required this.searchController,
    required this.hasSearchedNotifier,
    required this.isInitialLoadingNotifier,
    required this.localMatchesNotifier,
    this.matchingAlbumsNotifier,
    required this.suggestionsNotifier,
    required this.resultsNotifier,
    required this.onTriggerCategorySearch,
    required this.onSearchExactQuery,
    required this.onQueryChanged,
    required this.onExecuteSearch,
    required this.onRecordSearchResultClick,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: searchController,
      builder: (context, textValue, _) {
        final query = textValue.text.trim();
        return ValueListenableBuilder<bool>(
          valueListenable: hasSearchedNotifier,
          builder: (context, hasSearched, _) {
            // State A: Zero-Query State (Before Typing)
            if (!hasSearched && query.isEmpty) {
              return SearchPreContent(
                trendingArtists: SearchConstants.trendingArtists,
                browseCategories: SearchConstants.browseCategories,
                onSelectQuery: onTriggerCategorySearch,
                onSelectExactQuery: onSearchExactQuery,
                onPlaySong: (song) {
                  SearchHistoryManager.addSong(song);
                  audioHandler.playSong(song);
                },
              );
            }

            // State B: Active Typing State (1..N characters, keyboard open)
            if (!hasSearched && query.isNotEmpty) {
              return ValueListenableBuilder<List<Song>>(
                valueListenable: localMatchesNotifier,
                builder: (context, localMatches, _) {
                  return ValueListenableBuilder<List<String>>(
                    valueListenable: suggestionsNotifier,
                    builder: (context, completions, _) {
                      Widget buildSuggestions(List<Map<String, dynamic>> matchingAlbums) {
                        return SearchActiveTypingSuggestions(
                          query: query,
                          localSongMatches: localMatches,
                          matchingAlbums: matchingAlbums,
                          queryCompletions: completions,
                          onPlaySong: (song) {
                            SearchHistoryManager.addSong(song);
                            SearchService.recordSearchClick(song);
                            audioHandler.playSong(song);
                          },
                          onSelectQuery: onTriggerCategorySearch,
                          onAppendQuery: (q) {
                            searchController.text = q;
                            searchController.selection = TextSelection.collapsed(offset: q.length);
                            onQueryChanged(q);
                          },
                          onShowOptions: (s) => SearchSongOptionsSheet.show(context, s),
                        );
                      }

                      if (matchingAlbumsNotifier != null) {
                        return ValueListenableBuilder<List<Map<String, dynamic>>>(
                          valueListenable: matchingAlbumsNotifier!,
                          builder: (context, albums, _) => buildSuggestions(albums),
                        );
                      }
                      return buildSuggestions(const []);
                    },
                  );
                },
              );
            }

            // State C: Committed Results State (Explicitly submitted or suggestion selected)
            return ValueListenableBuilder<SearchResultsState>(
              valueListenable: resultsNotifier,
              builder: (context, state, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: isInitialLoadingNotifier,
                  builder: (context, isInitialLoading, _) {
                    if (state.isEmpty && isInitialLoading) {
                      return const SearchSkeletonView();
                    }

                    if (state.hasError && state.isEmpty && !isInitialLoading) {
                      return SearchErrorView(
                        error: state.error!,
                        onRetry: () {
                          final q = searchController.text.trim();
                          if (q.isNotEmpty) onExecuteSearch(q, saveHistory: false);
                        },
                        onOpenDownloads: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LibraryScreen()),
                        ),
                      );
                    }

                    return SearchAllResultsView(
                      state: state,
                      query: searchController.text,
                      onDidYouMeanTap: (sug) {
                        searchController.text = sug;
                        onExecuteSearch(sug, saveHistory: true);
                      },
                      onArtistRecordClick: () => onRecordSearchResultClick(),
                      onRecordClick: ([song]) => onRecordSearchResultClick(song),
                      onSongTap: (song) {
                        onRecordSearchResultClick(song);
                        audioHandler.playSong(song, queue: state.songs);
                      },
                      onShowOptions: (s) => SearchSongOptionsSheet.show(context, s),
                      onShowVersions: (s) => SearchVersionsSheet.show(
                        context,
                        s,
                        onSelectSong: (v) {
                          onRecordSearchResultClick(v);
                          audioHandler.playSong(v);
                        },
                      ),
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
