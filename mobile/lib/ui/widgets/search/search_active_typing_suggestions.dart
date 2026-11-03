import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../services/favorites_manager.dart';
import '../../../services/search_history_manager.dart';
import '../../theme/app_theme.dart';

class SearchActiveTypingSuggestions extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final List<Song> localSongMatches;
  final List<String> queryCompletions;
  final void Function(Song song) onPlaySong;
  final void Function(String query) onSelectQuery;
  final void Function(String query) onAppendQuery;
  final String? query;
  final void Function(Song song)? onShowOptions;

  const SearchActiveTypingSuggestions({
    super.key,
    required this.localSongMatches,
    required this.queryCompletions,
    required this.onPlaySong,
    required this.onSelectQuery,
    required this.onAppendQuery,
    this.query,
    this.onShowOptions,
  });

  @override
  Widget build(BuildContext context) {
    final cleanQ = query?.trim() ?? '';
    final effectiveCompletions = queryCompletions.isNotEmpty
        ? queryCompletions
        : (cleanQ.isNotEmpty
            ? [cleanQ, if (!cleanQ.toLowerCase().contains(' song')) '$cleanQ songs', if (!cleanQ.toLowerCase().contains(' hit')) '$cleanQ hits']
            : const <String>[]);

    if (localSongMatches.isEmpty && effectiveCompletions.isEmpty) {
      return const SizedBox.shrink();
    }

    final historyQueries = SearchHistoryManager.historyNotifier.value.map((h) => h.toLowerCase().trim()).toSet();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 120),
      children: [
        // 1. Autocomplete Search Suggestions (Flat, borderless Spotify standard)
        if (effectiveCompletions.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Text(
              'SEARCH SUGGESTIONS',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
          ),
          ...effectiveCompletions.take(5).map((q) {
            final clean = _unescape.convert(Song.sanitize(q));
            final isHistory = historyQueries.contains(clean.toLowerCase().trim());
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              leading: Icon(
                isHistory ? Icons.history_rounded : Icons.search_rounded,
                color: Colors.white70,
                size: 22,
              ),
              title: Text(
                clean,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w400),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.north_west_rounded, color: Colors.white54, size: 18),
                tooltip: 'Insert to search',
                onPressed: () => onAppendQuery(q),
              ),
              onTap: () => onSelectQuery(q),
            );
          }),
          const SizedBox(height: 8),
        ],

        // 2. Direct Matching Entities (Songs)
        if (localSongMatches.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Row(
              children: [
                Icon(Icons.flash_on_rounded, size: 13, color: AppColors.electricCyan),
                SizedBox(width: 4),
                Text(
                  'INSTANT MATCHES',
                  style: TextStyle(color: AppColors.electricCyan, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ],
            ),
          ),
          ...localSongMatches.take(4).map((song) {
            final cleanTitle = _unescape.convert(Song.sanitize(song.title));
            final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

            return ValueListenableBuilder<List<Song>>(
              valueListenable: FavoritesManager.favoritesNotifier,
              builder: (context, favorites, _) {
                final isFav = favorites.any((f) => f.id == song.id);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  onTap: () => onPlaySong(song),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: song.coverUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: song.coverUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 120,
                              memCacheHeight: 120,
                              errorWidget: (_, __, ___) => Container(
                                color: AppColors.surfaceDark,
                                child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 22),
                              ),
                            )
                          : Container(
                              color: AppColors.surfaceDark,
                              child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 22),
                            ),
                    ),
                  ),
                  title: Text(
                    cleanTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Song • $cleanArtist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onShowOptions != null)
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                          tooltip: 'Options',
                          onPressed: () => onShowOptions!(song),
                        ),
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                          color: isFav ? AppColors.electricCyan : Colors.white70,
                          size: 22,
                        ),
                        tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                        onPressed: () => FavoritesManager.toggleFavorite(song),
                      ),
                    ],
                  ),
                );
              },
            );
          }),
        ],
      ],
    );
  }
}
