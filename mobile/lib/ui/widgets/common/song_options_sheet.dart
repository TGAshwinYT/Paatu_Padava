import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../../services/download_manager.dart';
import '../../../services/favorites_manager.dart';
import '../../../services/blacklist_manager.dart';
import '../../theme/app_theme.dart';
import '../add_to_playlist_dialog.dart';
import '../cover_art_image.dart';

/// Universal, production-grade song options modal sheet for Paatu Padava.
/// Replaces all disparate _showSongOptions implementations with a unified,
/// Spotify/Apple Music-grade context menu with haptic feedback.
class SongOptionsSheet {
  static final HtmlUnescape _unescape = HtmlUnescape();

  static void show(
    BuildContext context,
    Song song, {
    VoidCallback? onRemove,
    String? removeLabel,
  }) {
    HapticFeedback.lightImpact();
    final cleanTitle = _unescape.convert(Song.sanitize(song.title));
    final cleanArtist = _unescape.convert(Song.sanitize(song.artist));

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header: Song artwork + Title + Artist
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    CoverArtImage(
                      song: song,
                      width: 50,
                      height: 50,
                      borderRadius: BorderRadius.circular(10),
                      memCacheWidth: 150,
                      memCacheHeight: 150,
                      errorWidget: Container(
                        width: 50,
                        height: 50,
                        color: AppColors.surfaceDark,
                        child: const Icon(Icons.music_note_rounded, color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cleanTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            cleanArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.surfaceBorder, height: 1),

              // Action Options List
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    // 1. Play Next
                    ListTile(
                      leading: const Icon(Icons.playlist_play_rounded, color: AppColors.electricCyan, size: 24),
                      title: const Text('Play Next', style: TextStyle(color: Colors.white, fontSize: 14)),
                      onTap: () {
                        Navigator.pop(bottomCtx);
                        HapticFeedback.mediumImpact();
                        audioHandler.insertNext(song);
                        _showFloatingToast(context, 'Playing "$cleanTitle" next');
                      },
                    ),

                    // 2. Add to Queue
                    ListTile(
                      leading: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 22),
                      title: const Text('Add to Queue', style: TextStyle(color: Colors.white, fontSize: 14)),
                      onTap: () {
                        Navigator.pop(bottomCtx);
                        HapticFeedback.lightImpact();
                        audioHandler.addToQueue(song);
                        _showFloatingToast(context, 'Added "$cleanTitle" to queue');
                      },
                    ),

                    // 3. Start Song Radio
                    ListTile(
                      leading: const Icon(Icons.radio_rounded, color: AppColors.neonViolet, size: 22),
                      title: const Text('Start Song Radio', style: TextStyle(color: Colors.white, fontSize: 14)),
                      onTap: () {
                        Navigator.pop(bottomCtx);
                        HapticFeedback.mediumImpact();
                        audioHandler.startSongRadio(song);
                        _showFloatingToast(context, 'Starting radio for "$cleanTitle"...');
                      },
                    ),

                    // 4. Add to Playlist
                    ListTile(
                      leading: const Icon(Icons.playlist_add_rounded, color: AppColors.neonViolet, size: 24),
                      title: const Text('Add to Playlist', style: TextStyle(color: Colors.white, fontSize: 14)),
                      onTap: () {
                        Navigator.pop(bottomCtx);
                        AddToPlaylistDialog.show(context, song);
                      },
                    ),

                    // 5. Download / Remove Download
                    ValueListenableBuilder<List<Song>>(
                      valueListenable: DownloadManager.downloadedSongsNotifier,
                      builder: (context, _, __) {
                        final isDownloaded = DownloadManager.isDownloaded(song.id);
                        return ListTile(
                          leading: Icon(
                            isDownloaded ? Icons.delete_outline_rounded : Icons.download_rounded,
                            color: isDownloaded ? Colors.redAccent : AppColors.electricCyan,
                            size: 22,
                          ),
                          title: Text(
                            isDownloaded ? 'Remove from Downloads' : 'Download Offline',
                            style: TextStyle(
                              color: isDownloaded ? Colors.redAccent : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(bottomCtx);
                            if (isDownloaded) {
                              DownloadManager.deleteSong(song.id);
                              _showFloatingToast(context, 'Removed from downloads');
                            } else {
                              DownloadManager.downloadSong(song);
                              _showFloatingToast(context, 'Downloading "$cleanTitle"...');
                            }
                          },
                        );
                      },
                    ),

                    // 6. Like / Favorite Toggle
                    ValueListenableBuilder<List<Song>>(
                      valueListenable: FavoritesManager.favoritesNotifier,
                      builder: (context, _, __) {
                        final isFav = FavoritesManager.isFavorite(song.id);
                        return ListTile(
                          leading: Icon(
                            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isFav ? const Color(0xFFEC4899) : Colors.white70,
                            size: 22,
                          ),
                          title: Text(
                            isFav ? 'Remove from Liked Songs' : 'Like Song',
                            style: TextStyle(
                              color: isFav ? const Color(0xFFEC4899) : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          onTap: () async {
                            Navigator.pop(bottomCtx);
                            HapticFeedback.lightImpact();
                            final wasLiked = await FavoritesManager.toggleFavorite(song);
                            if (context.mounted) {
                              _showFloatingToast(
                                context,
                                wasLiked ? 'Added to Liked Songs' : 'Removed from Liked Songs',
                              );
                            }
                          },
                        );
                      },
                    ),

                    // 7. Optional Custom Removal Action (e.g. from Playlist / History)
                    if (onRemove != null)
                      ListTile(
                        leading: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 22),
                        title: Text(
                          removeLabel ?? 'Remove',
                          style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                        ),
                        onTap: () {
                          Navigator.pop(bottomCtx);
                          onRemove();
                        },
                      ),

                    // 8. Don't play this song (Blacklist)
                    ListTile(
                      leading: const Icon(Icons.block_rounded, color: Colors.redAccent, size: 20),
                      title: const Text("Don't play this song", style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Never recommend or autoplay this track', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      onTap: () {
                        Navigator.pop(bottomCtx);
                        BlacklistManager.blacklistSong(song);
                        _showFloatingToast(context, 'Blocked "$cleanTitle"');
                      },
                    ),

                    // 9. Don't play this artist (Blacklist)
                    if (song.primaryArtist.isNotEmpty && song.primaryArtist.toLowerCase() != 'various artists')
                      ListTile(
                        leading: const Icon(Icons.person_off_rounded, color: Colors.redAccent, size: 20),
                        title: Text('Don\'t play "${song.primaryArtist}"', style: const TextStyle(color: Colors.white, fontSize: 14)),
                        subtitle: const Text('Hide all tracks by this artist', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        onTap: () {
                          Navigator.pop(bottomCtx);
                          BlacklistManager.blacklistArtist(song.primaryArtist);
                          _showFloatingToast(context, 'Blocked artist "${song.primaryArtist}"');
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _showFloatingToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }
}
