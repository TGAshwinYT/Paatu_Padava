import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';
import '../../screens/artist_screen.dart';
import '../../screens/album_screen.dart';
import '../../screens/remote_playlist_screen.dart';
import '../../../services/catalog_database.dart';

/// Clean Spotify-style vertical list tile for an Artist
class SearchArtistTile extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final Map<String, dynamic> artist;
  final VoidCallback? onRecordClick;

  const SearchArtistTile({
    super.key,
    required this.artist,
    this.onRecordClick,
  });

  @override
  Widget build(BuildContext context) {
    final id = artist['id']?.toString() ?? '';
    final rawName = artist['name']?.toString() ?? artist['title']?.toString() ?? '';
    final name = _unescape.convert(Song.sanitize(rawName));
    final img = artist['image']?.toString() ?? artist['cover_url']?.toString() ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: () {
        onRecordClick?.call();
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
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipOval(
          child: img.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: img,
                  fit: BoxFit.cover,
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                  errorWidget: (_, __, ___) => _buildAvatarFallback(),
                )
              : _buildAvatarFallback(),
        ),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text(
        'Artist',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Colors.white30,
        size: 20,
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      color: AppColors.surfaceElevated,
      child: const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 26),
    );
  }
}

/// Clean Spotify-style vertical list tile for an Album
class SearchAlbumTile extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final Map<String, dynamic> album;
  final VoidCallback? onRecordClick;

  const SearchAlbumTile({
    super.key,
    required this.album,
    this.onRecordClick,
  });

  @override
  Widget build(BuildContext context) {
    final id = album['id']?.toString() ?? '';
    final rawTitle = album['title']?.toString() ?? album['name']?.toString() ?? '';
    final title = _unescape.convert(Song.sanitize(rawTitle));
    final rawArtist = album['artist']?.toString() ?? album['subtitle']?.toString() ?? album['composer']?.toString() ?? '';
    final artist = _unescape.convert(Song.sanitize(rawArtist));
    final songCount = int.tryParse(album['song_count']?.toString() ?? '0') ?? 0;
    final year = album['year']?.toString() ?? '';
    var img = album['image']?.toString() ?? album['cover_url']?.toString() ?? '';
    if (img.isEmpty || img.contains('default')) {
      img = CatalogDatabase.getMoviePoster(title) ?? CatalogDatabase.getSongCoverArt(title, album: title) ?? '';
    }

    // Build subtitle metadata
    String subtitle = 'Album';
    if (artist.isNotEmpty && artist.toLowerCase() != 'unknown artist') {
      subtitle = 'Album • $artist';
    } else if (songCount > 0) {
      subtitle = 'Album • $songCount tracks';
    } else if (year.isNotEmpty) {
      subtitle = 'Album • $year';
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: () {
        onRecordClick?.call();
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
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: img.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: img,
                  fit: BoxFit.cover,
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                  errorWidget: (_, __, ___) => _buildAlbumFallback(),
                )
              : _buildAlbumFallback(),
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
        ),
      ),
      trailing: const Icon(
        Icons.album_rounded,
        color: Colors.white24,
        size: 18,
      ),
    );
  }

  Widget _buildAlbumFallback() {
    return Container(
      color: AppColors.surfaceElevated,
      child: const Icon(Icons.album_rounded, color: AppColors.textSecondary, size: 26),
    );
  }
}

/// Clean Spotify-style vertical list tile for a Playlist
class SearchPlaylistTile extends StatelessWidget {
  static final HtmlUnescape _unescape = HtmlUnescape();

  final Map<String, dynamic> playlist;
  final VoidCallback? onRecordClick;

  const SearchPlaylistTile({
    super.key,
    required this.playlist,
    this.onRecordClick,
  });

  @override
  Widget build(BuildContext context) {
    final id = playlist['id']?.toString() ?? '';
    final rawTitle = playlist['title']?.toString() ?? playlist['name']?.toString() ?? '';
    final cleanTitle = _unescape
        .convert(Song.sanitize(rawTitle))
        .replaceAll(RegExp(r'\s*\((All Songs|Full Album)\)', caseSensitive: false), '')
        .trim();
    final rawSubtitle = playlist['subtitle']?.toString() ?? '';
    final subtitleText = rawSubtitle.isNotEmpty
        ? 'Playlist • ${_unescape.convert(rawSubtitle)}'
        : 'Playlist';
    final img = playlist['image']?.toString() ?? playlist['cover_url']?.toString() ?? '';
    final source = playlist['source']?.toString() ?? 'saavn';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: () {
        onRecordClick?.call();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RemotePlaylistScreen(
              playlistId: id,
              playlistTitle: cleanTitle,
              imageUrl: img,
              subtitle: rawSubtitle,
              source: source,
            ),
          ),
        );
      },
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: img.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: img,
                  fit: BoxFit.cover,
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                  errorWidget: (_, __, ___) => _buildPlaylistFallback(),
                )
              : _buildPlaylistFallback(),
        ),
      ),
      title: Text(
        cleanTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
        ),
      ),
      trailing: const Icon(
        Icons.queue_music_rounded,
        color: Colors.white24,
        size: 18,
      ),
    );
  }

  Widget _buildPlaylistFallback() {
    return Container(
      color: AppColors.surfaceElevated,
      child: const Icon(Icons.queue_music_rounded, color: AppColors.textSecondary, size: 26),
    );
  }
}
