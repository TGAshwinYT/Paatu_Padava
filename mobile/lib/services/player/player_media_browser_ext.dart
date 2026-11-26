part of '../player_handler.dart';

extension PlayerMediaBrowserExt on PaatuAudioHandler {
  Future<List<MediaItem>> _getChildrenImpl(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.MEDIA_ROOT_ID) {
      return [
        const MediaItem(
          id: 'root_liked',
          title: 'Liked Songs',
          playable: false,
        ),
        const MediaItem(
          id: 'root_history',
          title: 'Recently Played',
          playable: false,
        ),
        const MediaItem(
          id: 'root_downloads',
          title: 'Downloaded Songs',
          playable: false,
        ),
        const MediaItem(
          id: 'root_playlists',
          title: 'Playlists',
          playable: false,
        ),
      ];
    }

    if (parentMediaId == 'root_liked') {
      final songs = FavoritesManager.getFavorites();
      return songs.map((s) => s.toMediaItem().copyWith(playable: true)).toList();
    }

    if (parentMediaId == 'root_downloads') {
      final songs = DownloadManager.getDownloadedSongs();
      return songs.map((s) => s.toMediaItem().copyWith(playable: true)).toList();
    }

    if (parentMediaId == 'root_history') {
      final songs = HistoryManager.getHistory();
      return songs.take(30).map((s) => s.toMediaItem().copyWith(playable: true)).toList();
    }

    if (parentMediaId == 'root_playlists') {
      final playlists = PlaylistManager.getPlaylists();
      return playlists.map<MediaItem>((pl) => MediaItem(
        id: 'pl_${pl.id}',
        title: pl.title,
        playable: false,
        artUri: pl.coverUrl.isNotEmpty ? Uri.tryParse(pl.coverUrl) : null,
      )).toList();
    }

    if (parentMediaId.startsWith('pl_')) {
      final plId = parentMediaId.substring(3);
      final playlist = PlaylistManager.getPlaylist(plId);
      if (playlist != null) {
        return playlist.tracks.map((s) => s.toMediaItem().copyWith(playable: true)).toList();
      }
    }

    return [];
  }

  Future<MediaItem?> _getMediaItemImpl(String mediaId) async {
    for (final song in playlist) {
      if (song.id == mediaId) return song.toMediaItem();
    }
    final liked = FavoritesManager.getFavorites();
    for (final song in liked) {
      if (song.id == mediaId) return song.toMediaItem();
    }
    final history = HistoryManager.getHistory();
    for (final song in history) {
      if (song.id == mediaId) return song.toMediaItem();
    }
    return null;
  }

  Future<void> _playFromMediaIdImpl(String mediaId, [Map<String, dynamic>? extras]) async {
    for (int i = 0; i < playlist.length; i++) {
      if (playlist[i].id == mediaId) {
        await skipToQueueItem(i);
        return;
      }
    }

    final liked = FavoritesManager.getFavorites();
    final likedIdx = liked.indexWhere((s) => s.id == mediaId);
    if (likedIdx != -1) {
      await playSong(liked[likedIdx], queue: liked);
      return;
    }

    final history = HistoryManager.getHistory();
    final histIdx = history.indexWhere((s) => s.id == mediaId);
    if (histIdx != -1) {
      await playSong(history[histIdx]);
      return;
    }

    final playlists = PlaylistManager.getPlaylists();
    for (final pl in playlists) {
      final idx = pl.tracks.indexWhere((s) => s.id == mediaId);
      if (idx != -1) {
        await playSong(pl.tracks[idx], queue: pl.tracks);
        return;
      }
    }

    final downloaded = DownloadManager.getDownloadedSongs();
    final dlIdx = downloaded.indexWhere((s) => s.id == mediaId);
    if (dlIdx != -1) {
      await playSong(downloaded[dlIdx], queue: downloaded);
      return;
    }
  }
}
