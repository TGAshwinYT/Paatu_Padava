import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../../services/download_manager.dart';
import '../../../services/favorites_manager.dart';
import '../../theme/app_theme.dart';
import '../add_to_playlist_dialog.dart';

class SearchSongOptionsSheet {
  static final HtmlUnescape _unescape = HtmlUnescape();

  static void show(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.radio_rounded, color: AppColors.neonViolet),
              title: const Text('Start Song Radio', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                audioHandler.startSongRadio(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Starting radio for "${_unescape.convert(Song.sanitize(song.title))}"...')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded, color: AppColors.neonViolet),
              title: const Text('Play Next', style: TextStyle(color: Colors.white)),
              onTap: () {
                audioHandler.insertNext(song);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Playing "${_unescape.convert(Song.sanitize(song.title))}" next')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded, color: Colors.white70),
              title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
              onTap: () {
                audioHandler.addToQueue(song);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added "${_unescape.convert(Song.sanitize(song.title))}" to queue')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded, color: AppColors.electricCyan),
              title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                AddToPlaylistDialog.show(context, song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppColors.electricCyan),
              title: const Text('Download Offline', style: TextStyle(color: Colors.white)),
              onTap: () {
                DownloadManager.downloadSong(song);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border_rounded, color: AppColors.neonViolet),
              title: const Text('Like / Favorite', style: TextStyle(color: Colors.white)),
              onTap: () {
                FavoritesManager.toggleFavorite(song);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
