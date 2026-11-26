import 'package:flutter/material.dart';
import '../../../models/user_playlist.dart';
import '../../../services/download_manager.dart';
import '../../../services/playlist_manager.dart';

/// Shows a confirmation dialog for deleting or leaving [playlist].
/// If the playlist contains downloaded songs not used in any other playlist or
/// Liked Songs, offers an optional checkbox to delete those downloads as well.
/// Returns `true` if the playlist was deleted/left, `false` if cancelled.
Future<bool> showDeletePlaylistDialog(
  BuildContext context,
  UserPlaylist playlist,
) async {
  final isOwner = playlist.isOwner;
  final orphanedDownloads = DownloadManager.getOrphanedDownloadsForPlaylist(playlist);
  bool deleteOrphanedDownloads = false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        title: Text(
          isOwner ? 'Delete Playlist?' : 'Leave Playlist?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isOwner
                  ? 'Are you sure you want to delete "${playlist.title}"? This cannot be undone.'
                  : 'Are you sure you want to leave "${playlist.title}"? It will be removed from your library but remain active for other collaborators.',
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
            if (orphanedDownloads.isNotEmpty) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteOrphanedDownloads,
                onChanged: (val) {
                  setDialogState(() {
                    deleteOrphanedDownloads = val ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.redAccent,
                checkColor: Colors.white,
                title: Text(
                  'Also delete ${orphanedDownloads.length} downloaded ${orphanedDownloads.length == 1 ? 'song' : 'songs'} not in other playlists or Liked Songs',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              isOwner ? 'Delete' : 'Leave',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return false;

  if (isOwner) {
    await PlaylistManager.deletePlaylist(playlist.id);
  } else {
    await PlaylistManager.deletePlaylistDirectly(playlist.id);
  }

  if (deleteOrphanedDownloads && orphanedDownloads.isNotEmpty) {
    await DownloadManager.deleteSongsByIds(
      orphanedDownloads.map((s) => s.id).toList(),
    );
  }

  return true;
}
