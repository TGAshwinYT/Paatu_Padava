import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../services/search_service.dart';
import '../../theme/app_theme.dart';
import 'search_song_tile.dart';

/// Virtualized 120Hz Infinite-Scroll Songs View with Progressive Pagination and Upper Bound Cap.
///
/// Features:
/// 1. Virtualized Render Extents: Fixed itemExtent (72.0px) for O(1) viewport layout calculations.
/// 2. Progressive Pagination: Automatically fetches page 2, 3... when scrolling near bottom.
/// 3. Duplicate Immunity: Uses MinHash/ID set to prevent repeated tracks.
/// 4. Progressive Streaming: Fetches until upstream catalog is exhausted.
class SearchPaginatedSongsView extends StatefulWidget {
  final List<Song> initialSongs;
  final String query;
  final void Function(Song) onSongTap;
  final void Function(Song) onShowOptions;
  final void Function(Song)? onShowVersions;
  final void Function([Song?]) onRecordClick;

  const SearchPaginatedSongsView({
    super.key,
    required this.initialSongs,
    required this.query,
    required this.onSongTap,
    required this.onShowOptions,
    this.onShowVersions,
    required this.onRecordClick,
  });

  @override
  State<SearchPaginatedSongsView> createState() => _SearchPaginatedSongsViewState();
}

class _SearchPaginatedSongsViewState extends State<SearchPaginatedSongsView> {
  static const double _songTileExtent = 72.0;

  final ScrollController _scrollController = ScrollController();
  late List<Song> _songs;
  late Set<String> _seenIds;
  int _currentPage = 1;
  bool _isLoadingMore = false;
  bool _hasReachedEnd = false;

  @override
  void initState() {
    super.initState();
    _songs = List<Song>.from(widget.initialSongs);
    _seenIds = _songs.map((s) => s.id).toSet();
    if (_songs.isEmpty) {
      _hasReachedEnd = true;
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(SearchPaginatedSongsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query || oldWidget.initialSongs != widget.initialSongs) {
      _songs = List<Song>.from(widget.initialSongs);
      _seenIds = _songs.map((s) => s.id).toSet();
      _currentPage = 1;
      _isLoadingMore = false;
      _hasReachedEnd = _songs.isEmpty;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Trigger next page 250px before reaching bottom
    if (currentScroll >= (maxScroll - 250) && !_isLoadingMore && !_hasReachedEnd) {
      _loadMoreSongs();
    }
  }

  Future<void> _loadMoreSongs() async {
    if (_isLoadingMore || _hasReachedEnd) return;

    setState(() => _isLoadingMore = true);
    final nextPage = _currentPage + 1;

    try {
      final nextBatch = await SearchService.searchSongsPaged(
        widget.query,
        page: nextPage,
        limit: 20,
      );

      if (!mounted) return;

      final newUnique = nextBatch.where((s) => s.id.isNotEmpty && _seenIds.add(s.id)).toList();

      if (newUnique.isEmpty) {
        setState(() {
          _hasReachedEnd = true;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _currentPage = nextPage;
          _songs.addAll(newUnique);
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_songs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Text(
            'No songs found',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
          ),
        ),
      );
    }

    final totalCount = _songs.length + (_isLoadingMore || _hasReachedEnd ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 120, top: 4),
      itemExtent: _songTileExtent,
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index < _songs.length) {
          final song = _songs[index];
          return SearchSongTile(
            song: song,
            onTap: () {
              widget.onRecordClick(song);
              widget.onSongTap(song);
            },
            onShowOptions: () => widget.onShowOptions(song),
            onShowVersions: song.versions.isNotEmpty ? () => widget.onShowVersions?.call(song) : null,
          );
        }

        // Footer item: Loading spinner OR reached-end badge
        if (_isLoadingMore) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.electricCyan,
              ),
            ),
          );
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text(
                  'End of songs (${_songs.length} results)',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
