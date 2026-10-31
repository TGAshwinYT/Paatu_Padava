import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../logic/track_quality_filter.dart';
import '../../../domain/models/clustered_track_result.dart';
import '../../theme/app_theme.dart';
import '../../screens/artist_screen.dart';
import '../../screens/album_screen.dart';
import '../../screens/remote_playlist_screen.dart';
import 'search_top_result_card.dart';
import 'search_song_tile.dart';

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

  static const List<String> _filters = [
    'All',
    'Official Songs',
    'Mixes & BGM',
    'Artists',
    'Albums',
    'Playlists',
  ];

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final List<Song> allSongs = (state.songs as List<dynamic>?)?.cast<Song>() ?? <Song>[];
    final List<Map<String, dynamic>> albums = (state.albums as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final List<Map<String, dynamic>> artists = (state.artists as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final List<Map<String, dynamic>> playlists = (state.playlists as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    if (allSongs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && state.topResult == null) {
      return Center(
        child: Text(
          'No results found for "${widget.query}"',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
      );
    }

    // In-memory 0ms filter splitting
    final officialSongs = allSongs.where((s) {
      final cls = TrackQualityFilter.classifyTrack(
        title: s.title,
        durationSec: s.duration,
        source: s.source,
        artist: s.artist,
      );
      return cls == ContentClassification.officialTrack;
    }).toList();

    final fanMixes = <Song>[];
    for (final s in allSongs) {
      final cls = TrackQualityFilter.classifyTrack(
        title: s.title,
        durationSec: s.duration,
        source: s.source,
        artist: s.artist,
      );
      if (cls == ContentClassification.fanMixOrVersion) {
        fanMixes.add(s);
      }
      for (final v in s.versions) {
        if (!fanMixes.any((m) => m.id == v.id)) {
          fanMixes.add(v);
        }
      }
    }

    final isWide = MediaQuery.of(context).size.width >= 720;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sticky Intent Filter Bar (0ms switching)
        Container(
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = _filters[i];
              final isSel = _selectedFilter == f;

              return ChoiceChip(
                label: Text(f),
                selected: isSel,
                selectedColor: AppColors.neonViolet,
                backgroundColor: AppColors.surfaceElevated,
                labelStyle: GoogleFonts.outfit(
                  color: isSel ? Colors.white : AppColors.textSecondary,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSel ? AppColors.neonViolet : AppColors.surfaceBorder,
                  ),
                ),
                onSelected: (_) => setState(() => _selectedFilter = f),
              );
            },
          ),
        ),

        // Results Scroll View
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              // Typo / Did You Mean Banner
              if (state.didYouMean != null && _selectedFilter == 'All')
                _buildDidYouMeanBanner(state.didYouMean!),

              // Filter: All
              if (_selectedFilter == 'All') ...[
                if (state.topResult != null) _buildTopResult(state.topResult!),
                if (artists.isNotEmpty) _buildArtistsSection(artists),
                if (albums.isNotEmpty) _buildAlbumsSection(albums),
                if (playlists.isNotEmpty) _buildPlaylistsSection(playlists),
                if (allSongs.isNotEmpty) _buildSongsSection('Songs', allSongs),
              ],

              // Filter: Official Songs
              if (_selectedFilter == 'Official Songs')
                _buildSongsSection('Official Studio Tracks', officialSongs.isNotEmpty ? officialSongs : allSongs),

              // Filter: Mixes & BGM
              if (_selectedFilter == 'Mixes & BGM')
                _buildSongsSection('Remixes, Mashups & BGMs', fanMixes),

              // Filter: Artists
              if (_selectedFilter == 'Artists')
                _buildArtistsFullList(artists),

              // Filter: Albums
              if (_selectedFilter == 'Albums')
                _buildAlbumsFullGrid(albums),

              // Filter: Playlists
              if (_selectedFilter == 'Playlists')
                _buildPlaylistsFullGrid(playlists),
            ],
          ),
        ),
      ],
    );

    if (isWide) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildDidYouMeanBanner(String suggestion) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.neonViolet.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonViolet.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.help_outline_rounded, color: AppColors.neonViolet, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                children: [
                  const TextSpan(text: 'Showing results. Did you mean: '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () => widget.onDidYouMeanTap(suggestion),
                      child: Text(
                        _unescape.convert(Song.sanitize(suggestion)),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopResult(Map<String, dynamic> top) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
          child: Text(
            'Top Result',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        SearchTopResultCard(
          top: top,
          onArtistClick: () {
            widget.onArtistRecordClick();
            final title = _unescape.convert(Song.sanitize(top['title']?.toString() ?? top['name']?.toString() ?? ''));
            final cover = top['cover_url']?.toString() ?? top['image']?.toString() ?? '';
            final type = (top['type']?.toString() ?? '').toLowerCase();
            if (type == 'album') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlbumScreen(albumId: top['id']?.toString() ?? '', albumTitle: title, imageUrl: cover),
                ),
              );
            } else {
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
            }
          },
          onPlay: () {
            final List<Song> songs = (widget.state.songs as List<dynamic>?)?.cast<Song>() ?? [];
            final songToPlay = songs.isNotEmpty ? songs.first : null;
            widget.onRecordClick(songToPlay);
            if (songToPlay != null) {
              widget.onSongTap(songToPlay);
            }
          },
        ),
      ],
    );
  }

  Widget _buildArtistsSection(List<Map<String, dynamic>> artists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
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
            itemCount: artists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final art = artists[index];
              final id = art['id']?.toString() ?? '';
              final name = _unescape.convert(Song.sanitize(art['name']?.toString() ?? ''));
              final img = art['image']?.toString() ?? '';

              return GestureDetector(
                onTap: () {
                  widget.onRecordClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArtistScreen(artistId: id, artistName: name, imageUrl: img),
                    ),
                  );
                },
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: AppColors.surfaceElevated,
                      backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                      child: img.isEmpty
                          ? const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 28)
                          : null,
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
    );
  }

  Widget _buildAlbumsSection(List<Map<String, dynamic>> albums) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            'Albums',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 155,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              final id = album['id']?.toString() ?? '';
              final title = _unescape.convert(Song.sanitize(album['title']?.toString() ?? ''));
              final img = album['image']?.toString() ?? '';

              return GestureDetector(
                onTap: () {
                  widget.onRecordClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlbumScreen(albumId: id, albumTitle: title, imageUrl: img),
                    ),
                  );
                },
                child: Container(
                  width: 115,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 115,
                          height: 115,
                          child: CachedNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            memCacheHeight: 200,
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
    );
  }

  Widget _buildPlaylistsSection(List<Map<String, dynamic>> playlists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            'Playlists',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 155,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final id = playlist['id']?.toString() ?? '';
              final title = _unescape.convert(Song.sanitize(playlist['title']?.toString() ?? ''));
              final subtitle = _unescape.convert(playlist['subtitle']?.toString() ?? '');
              final img = playlist['image']?.toString() ?? '';
              final source = playlist['source']?.toString() ?? 'saavn';

              return GestureDetector(
                onTap: () {
                  widget.onRecordClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RemotePlaylistScreen(
                        playlistId: id,
                        playlistTitle: title,
                        imageUrl: img,
                        subtitle: subtitle,
                        source: source,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 115,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 115,
                          height: 115,
                          child: img.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: img,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 200,
                                  memCacheHeight: 200,
                                  errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
                                )
                              : Container(color: AppColors.surfaceDark),
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
    );
  }

  Widget _buildSongsSection(String header, List<Song> songs) {
    if (songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('No tracks found in this category', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            header,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ...songs.map((song) => SearchSongTile(
          song: song,
          onTap: () {
            widget.onRecordClick(song);
            widget.onSongTap(song);
          },
          onShowOptions: () => widget.onShowOptions(song),
          onShowVersions: song.versions.isNotEmpty ? () => widget.onShowVersions(song) : null,
        )),
      ],
    );
  }

  Widget _buildArtistsFullList(List<Map<String, dynamic>> artists) {
    if (artists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('No artists found', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
        ),
      );
    }

    return Column(
      children: artists.map((art) {
        final id = art['id']?.toString() ?? '';
        final name = _unescape.convert(Song.sanitize(art['name']?.toString() ?? ''));
        final img = art['image']?.toString() ?? '';

        return ListTile(
          onTap: () {
            widget.onRecordClick();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ArtistScreen(artistId: id, artistName: name, imageUrl: img)),
            );
          },
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.surfaceElevated,
            backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
            child: img.isEmpty ? const Icon(Icons.person, color: AppColors.textSecondary) : null,
          ),
          title: Text(name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
        );
      }).toList(),
    );
  }

  Widget _buildAlbumsFullGrid(List<Map<String, dynamic>> albums) {
    if (albums.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('No albums found', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.82,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final alb = albums[i];
        final id = alb['id']?.toString() ?? '';
        final title = _unescape.convert(Song.sanitize(alb['title']?.toString() ?? ''));
        final img = alb['image']?.toString() ?? '';

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            widget.onRecordClick();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AlbumScreen(albumId: id, albumTitle: title, imageUrl: img)),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    memCacheWidth: 240,
                    memCacheHeight: 240,
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaylistsFullGrid(List<Map<String, dynamic>> playlists) {
    if (playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('No playlists found', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.82,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, i) {
        final pl = playlists[i];
        final id = pl['id']?.toString() ?? '';
        final title = _unescape.convert(Song.sanitize(pl['title']?.toString() ?? ''));
        final subtitle = _unescape.convert(pl['subtitle']?.toString() ?? '');
        final img = pl['image']?.toString() ?? '';
        final source = pl['source']?.toString() ?? 'saavn';

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            widget.onRecordClick();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RemotePlaylistScreen(
                  playlistId: id,
                  playlistTitle: title,
                  imageUrl: img,
                  subtitle: subtitle,
                  source: source,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    memCacheWidth: 240,
                    memCacheHeight: 240,
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }
}
