part of 'download_manager.dart';

Song? _findDownloadedMatchImpl(Song song) {
  if (DownloadManager.isDownloaded(song.id)) {
    final p = DownloadManager.getLocalFilePath(song.id);
    if (p != null) {
      return song.copyWith(
        localFilePath: p,
        localCoverPath: DownloadManager.getLocalCoverPath(song.id) ?? song.localCoverPath,
        isDownloaded: true,
      );
    }
  }
  return _findDownloadedMatchByMetaImpl(
    title: song.title,
    artist: song.artist,
    durationSeconds: song.duration,
  );
}

Song? _findDownloadedMatchByMetaImpl({
  required String title,
  required String artist,
  int durationSeconds = 0,
}) {
  final downloaded = DownloadManager.getDownloadedSongs();
  if (downloaded.isEmpty) return null;
  return DownloadDedupHelper.findMatch(
    downloadedSongs: downloaded,
    title: title,
    artist: artist,
    durationSeconds: durationSeconds,
  );
}

Future<int> _deduplicateExistingDownloadsImpl() async {
  if (!Hive.isBoxOpen(DownloadManager.boxName)) return 0;
  final downloaded = DownloadManager.getDownloadedSongs();
  if (downloaded.length < 2) return 0;

  final groups = DownloadDedupHelper.findDuplicateGroups(downloaded);
  int removedCount = 0;

  for (final group in groups) {
    // Keep index 0 (newest downloadedAt from getDownloadedSongs() sort order)
    for (int i = 1; i < group.length; i++) {
      final dup = group[i];
      await DownloadManager.deleteSong(dup.id);
      removedCount++;
    }
  }

  if (removedCount > 0) {
    AppLogger.log('DownloadManager', 'Deduplicated $removedCount redundant offline song(s) to free storage');
  }
  return removedCount;
}

List<Song> _getOrphanedDownloadsForPlaylistImpl(UserPlaylist playlist) {
  final downloaded = DownloadManager.getDownloadedSongs();
  if (downloaded.isEmpty || playlist.tracks.isEmpty) return const [];
  return DownloadDedupHelper.findOrphanedPlaylistDownloads(
    playlist: playlist,
    allPlaylists: PlaylistManager.getPlaylists(),
    favoriteSongs: FavoritesManager.getFavorites(),
    downloadedSongs: downloaded,
  );
}

Future<void> _deleteSongsByIdsImpl(List<String> songIds) async {
  for (final id in songIds) {
    await DownloadManager.deleteSong(id);
  }
}

Future<void> _backfillMissingCoversImpl() async {
  if (!Hive.isBoxOpen(DownloadManager.boxName) || DownloadManager._documentsDirPath == null) return;
  try {
    final coversDir = Directory('${DownloadManager._documentsDirPath}/offline_covers');
    if (!coversDir.existsSync()) coversDir.createSync(recursive: true);

    for (final key in DownloadManager._box.keys) {
      final data = DownloadManager._box.get(key);
      if (data != null && data is Map) {
        final song = Song.fromMap(data);
        final existing = DownloadManager.getLocalCoverPath(song.id);
        if (existing == null) {
          String artUrl = song.coverUrl;
          if (artUrl.isEmpty || CoverArtResolver.isPlaylistCover(artUrl) || artUrl.startsWith('file://') || artUrl.startsWith('/') || artUrl.contains(':\\')) {
            try {
              artUrl = await CoverArtResolver.resolveCover(song);
            } catch (e) {
              AppLogger.debug('DownloadManager', 'Handled exception: $e');
            }
          }
          if (artUrl.isEmpty || artUrl.startsWith('file://') || artUrl.startsWith('/') || artUrl.contains(':\\')) {
            artUrl = CatalogDatabase.getSongCoverArt(song.title, artist: song.artist, album: song.album) ??
                CatalogDatabase.getMoviePoster(song.album) ?? '';
          }
          if (artUrl.isNotEmpty && (artUrl.startsWith('http://') || artUrl.startsWith('https://'))) {
            final safeName = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            final targetPath = '${coversDir.path}/$safeName.jpg';
            final tmp = '$targetPath.tmp';
            try {
              await DownloadManager._downloadFile(artUrl, tmp);
              final tmpF = File(tmp);
              if (tmpF.existsSync() && tmpF.lengthSync() > 100) {
                final targetF = File(targetPath);
                if (targetF.existsSync()) targetF.deleteSync();
                tmpF.renameSync(targetPath);
                final updated = song.copyWith(localCoverPath: targetPath, coverUrl: artUrl);
                await DownloadManager._box.put(key, updated.toMap());
              }
            } catch (e) {
              AppLogger.debug('DownloadManager', 'Handled exception: $e');
            }
          }
        }
      }
    }
  } catch (e) {
    AppLogger.debug('DownloadManager', 'Handled exception: $e');
  }
}
