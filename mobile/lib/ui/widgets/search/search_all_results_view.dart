import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';
import '../../screens/artist_screen.dart';
import '../../screens/album_screen.dart';
import 'search_top_result_card.dart';
import 'search_song_tile.dart';

class SearchAllResultsView extends StatelessWidget {
  final dynamic state; // SearchResultsState
  final String query;
  final void Function(String) onDidYouMeanTap;
  final VoidCallback onArtistRecordClick;
  final void Function([Song?]) onRecordClick;
  final void Function(Song) onSongTap;
  final void Function(Song) onShowOptions;
  final void Function(Song) onShowVersions;
  static final HtmlUnescape _unescape = HtmlUnescape();

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
  Widget build(BuildContext context) {
    if (state.songs.isEmpty && state.albums.isEmpty && state.artists.isEmpty && state.topResult == null) {
      return Center(
        child: Text(
          'No results found for "$query"',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 720;

    final content = ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        if (state.didYouMean != null)
          Container(
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
                            onTap: () => onDidYouMeanTap(state.didYouMean!),
                            child: Text(
                              _unescape.convert(Song.sanitize(state.didYouMean!)),
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
          ),

        // Top Result Hero Card
        if (state.topResult != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(
              'Top Result',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          SearchTopResultCard(
            top: state.topResult!,
            onArtistClick: () {
              onArtistRecordClick();
              final top = state.topResult!;
              final title = _unescape.convert(Song.sanitize(top['title']?.toString() ?? top['name']?.toString() ?? ''));
              final cover = top['cover_url']?.toString() ?? top['image']?.toString() ?? '';
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
            onPlay: () {
              final songToPlay = state.songs.isNotEmpty ? state.songs.first : null;
              onRecordClick(songToPlay);
              if (songToPlay != null) {
                onSongTap(songToPlay);
              }
            },
          ),
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
                    onRecordClick();
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
                    onRecordClick();
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

      // Songs Header & List
      if (state.songs.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            'Songs',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ...state.songs.map((Song song) => SearchSongTile(
          song: song,
          onTap: () {
            onRecordClick(song);
            onSongTap(song);
          },
          onShowOptions: () => onShowOptions(song),
          onShowVersions: song.versions.isNotEmpty ? () => onShowVersions(song) : null,
        )),
      ],
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
}
