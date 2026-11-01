import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../logic/track_quality_filter.dart';
import '../../../domain/models/clustered_track_result.dart';
import '../../theme/app_theme.dart';
import 'search_song_tile.dart';
import 'search_entity_tiles.dart';
import 'search_filter_bar.dart';

/// Clean Spotify-style unified vertical list search results view
class SearchAllResultsView extends StatefulWidget {
  final dynamic state; // SearchResultsState
  final String query;
  final void Function(String) onDidYouMeanTap;
  final VoidCallback onArtistRecordClick;
  final void Function([Song?]) onRecordClick;
  final void Function(Song) onSongTap;
  final void Function(Song) onShowOptions;
  final void Function(Song) onShowVersions;

  const SearchAllResultsView({
    super.key,
    required this.state,
    required this.query,
    required this.onDidYouMeanTap,
    required this.onArtistRecordClick,
    required this.onRecordClick,
    required this.onSongTap,
    required this.onShowOptions,
    required this.onShowVersions,
  });

  @override
  State<SearchAllResultsView> createState() => _SearchAllResultsViewState();
}

class _SearchAllResultsViewState extends State<SearchAllResultsView> {
  static final HtmlUnescape _unescape = HtmlUnescape();
  String _selectedFilter = 'All';

  // Memoized collections precomputed on state change (NOT on every build frame)
  List<Song> _fanMixes = const [];

  static final RegExp _mixOrBgmRegex = RegExp(
    r'\b(bgm|theme|ost|score|instrumental|remix|mashup|lo[\s\-]?fi|slowed|reverb|acoustic|reprise|extended|mix|version|soundtrack)\b',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _computeFilteredCollections();
  }

  @override
  void didUpdateWidget(covariant SearchAllResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != oldWidget.state) {
      _computeFilteredCollections();
    }
  }

  void _computeFilteredCollections() {
    final List<Song> allSongs = (widget.state.songs as List<dynamic>?)?.cast<Song>() ?? <Song>[];

    final mixes = <Song>[];

    for (final s in allSongs) {
      final cls = TrackQualityFilter.classifyTrack(
        title: s.title,
        durationSec: s.duration,
        source: s.source,
        artist: s.artist,
      );

      final isMix = cls == ContentClassification.fanMixOrVersion || _mixOrBgmRegex.hasMatch(s.title);
      if (isMix && !mixes.any((m) => m.id == s.id)) {
        mixes.add(s);
      }

      for (final v in s.versions) {
        if (!mixes.any((m) => m.id == v.id)) {
          mixes.add(v);
        }
      }
    }

    _fanMixes = mixes;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final List<Song> allSongs = (state.songs as List<dynamic>?)?.cast<Song>() ?? <Song>[];
    final List<Map<String, dynamic>> albums = (state.albums as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final List<Map<String, dynamic>> artists = (state.artists as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final List<Map<String, dynamic>> playlists = (state.playlists as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    if (allSongs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Text(
            'No results found for "${widget.query}"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 720;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Spotify-style Filter Pills Bar
        SearchFilterBar(
          selectedFilter: _selectedFilter,
          onFilterSelected: (filter) {
            setState(() => _selectedFilter = filter);
          },
        ),

        // 2. Main Vertical Unified Results List
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              // Typo / Did You Mean Banner
              if (state.didYouMean != null && _selectedFilter == 'All')
                _buildDidYouMeanBanner(state.didYouMean!),

              // Tab: All
              if (_selectedFilter == 'All') ...[
                if (allSongs.isNotEmpty) ...[
                  _buildSectionHeader('Songs', onSeeAll: allSongs.length > 5 ? () => setState(() => _selectedFilter = 'Songs') : null),
                  ...allSongs.take(5).map((song) => _buildSongTile(song)),
                ],
                if (albums.isNotEmpty) ...[
                  _buildSectionHeader('Albums', onSeeAll: albums.length > 4 ? () => setState(() => _selectedFilter = 'Albums') : null),
                  ...albums.take(4).map((alb) => SearchAlbumTile(album: alb, onRecordClick: widget.onRecordClick)),
                ],
                if (playlists.isNotEmpty) ...[
                  _buildSectionHeader('Playlists', onSeeAll: playlists.length > 4 ? () => setState(() => _selectedFilter = 'Playlists') : null),
                  ...playlists.take(4).map((pl) => SearchPlaylistTile(playlist: pl, onRecordClick: widget.onRecordClick)),
                ],
                if (artists.isNotEmpty) ...[
                  _buildSectionHeader('Artists', onSeeAll: artists.length > 4 ? () => setState(() => _selectedFilter = 'Artists') : null),
                  ...artists.take(4).map((art) => SearchArtistTile(artist: art, onRecordClick: widget.onArtistRecordClick)),
                ],
              ],

              // Tab: Songs
              if (_selectedFilter == 'Songs') ...[
                _buildSectionHeader('Songs'),
                ...allSongs.map((song) => _buildSongTile(song)),
              ],

              // Tab: Mixes & BGM
              if (_selectedFilter == 'Mixes & BGM') ...[
                if (_fanMixes.isEmpty)
                  _buildEmptyCategoryNotice('No remixes, BGMs, or fan versions found')
                else ...[
                  _buildSectionHeader('Remixes, Mashups & BGMs'),
                  ..._fanMixes.map((song) => _buildSongTile(song)),
                ],
              ],

              // Tab: Albums
              if (_selectedFilter == 'Albums') ...[
                if (albums.isEmpty)
                  _buildEmptyCategoryNotice('No albums found')
                else ...[
                  _buildSectionHeader('Albums'),
                  ...albums.map((alb) => SearchAlbumTile(album: alb, onRecordClick: widget.onRecordClick)),
                ],
              ],

              // Tab: Artists
              if (_selectedFilter == 'Artists') ...[
                if (artists.isEmpty)
                  _buildEmptyCategoryNotice('No artists found')
                else ...[
                  _buildSectionHeader('Artists'),
                  ...artists.map((art) => SearchArtistTile(artist: art, onRecordClick: widget.onArtistRecordClick)),
                ],
              ],

              // Tab: Playlists
              if (_selectedFilter == 'Playlists') ...[
                if (playlists.isEmpty)
                  _buildEmptyCategoryNotice('No playlists found')
                else ...[
                  _buildSectionHeader('Playlists'),
                  ...playlists.map((pl) => SearchPlaylistTile(playlist: pl, onRecordClick: widget.onRecordClick)),
                ],
              ],
            ],
          ),
        ),
      ],
    );

    if (isWide) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildSongTile(Song song) {
    return SearchSongTile(
      song: song,
      onTap: () {
        widget.onRecordClick(song);
        widget.onSongTap(song);
      },
      onShowOptions: () => widget.onShowOptions(song),
      onShowVersions: song.versions.isNotEmpty ? () => widget.onShowVersions(song) : null,
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'See all',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyCategoryNotice(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        ),
      ),
    );
  }

  Widget _buildDidYouMeanBanner(String suggestion) {
    final cleanSuggestion = _unescape.convert(Song.sanitize(suggestion));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.neonViolet, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onDidYouMeanTap(cleanSuggestion),
              child: Text.rich(
                TextSpan(
                  text: 'Did you mean: ',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  children: [
                    TextSpan(
                      text: cleanSuggestion,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
