import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';

class SearchActiveTypingSuggestions extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final List<Song> localSongMatches;
  final List<String> queryCompletions;
  final void Function(Song song) onPlaySong;
  final void Function(String query) onSelectQuery;
  final void Function(String query) onAppendQuery;

  const SearchActiveTypingSuggestions({
    super.key,
    required this.localSongMatches,
    required this.queryCompletions,
    required this.onPlaySong,
    required this.onSelectQuery,
    required this.onAppendQuery,
  });

  @override
  Widget build(BuildContext context) {
    if (localSongMatches.isEmpty && queryCompletions.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        // 1. Search Suggestions (Autocomplete) - Always displayed FIRST right under search bar (Spotify & YouTube Music benchmark)
        if (queryCompletions.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Text(
              'SEARCH SUGGESTIONS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...queryCompletions.take(5).map((query) {
            final clean = _unescape.convert(Song.sanitize(query));
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: AppColors.surfaceElevated.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  leading: const Icon(Icons.search_rounded, color: AppColors.neonViolet, size: 20),
                  title: Text(
                    clean,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  trailing: SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(Icons.north_west_rounded, color: Colors.white38, size: 18),
                      tooltip: 'Insert to search',
                      onPressed: () => onAppendQuery(query),
                    ),
                  ),
                  onTap: () => onSelectQuery(query),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        // 2. Direct Song Matches - Shown below suggestions only when song title genuinely matches
        if (localSongMatches.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Row(
              children: [
                Icon(Icons.flash_on_rounded, size: 14, color: AppColors.electricCyan),
                SizedBox(width: 6),
                Text(
                  'INSTANT MATCHES',
                  style: TextStyle(
                    color: AppColors.electricCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          ...localSongMatches.take(3).map((song) {
            final cleanTitle = _unescape.convert(Song.sanitize(song.title));
            final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  onTap: () => onPlaySong(song),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: song.coverUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: song.coverUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 100,
                              memCacheHeight: 100,
                              errorWidget: (_, __, ___) => Container(
                                color: AppColors.surfaceDark,
                                child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 20),
                              ),
                            )
                          : Container(
                              color: AppColors.surfaceDark,
                              child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 20),
                            ),
                    ),
                  ),
                  title: Text(
                    cleanTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    cleanArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                  trailing: SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.neonViolet, size: 28),
                      tooltip: 'Play Now',
                      onPressed: () => onPlaySong(song),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
