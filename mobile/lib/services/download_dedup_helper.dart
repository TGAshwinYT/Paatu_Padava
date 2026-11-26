import '../models/song.dart';
import '../models/user_playlist.dart';
import 'spotify_track_key.dart';

/// Pure-Dart canonical matching & deduplication helpers for offline downloads.
/// Prevents storing duplicate audio files when playlists are deleted and
/// re-imported with different provider IDs or title formatting variants.
class DownloadDedupHelper {
  DownloadDedupHelper._();

  static final RegExp _fromMovieRegex = RegExp(
    r'\s*[\(\[][Ff]rom\s+["\u201c\u201d\u2018\u2019]?[^)\u201d\]]+["\u201c\u201d\u2018\u2019]?[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _noiseParenRegex = RegExp(
    r'\s*[\(\[][^)\u201d\]]*(?:remaster(?:ed)?|official|audio|lyric|video|lyrical|motion picture|soundtrack|ost|feat\.?|ft\.?)[^)\u201d\]]*[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _pipeSuffixRegex = RegExp(r'\|.*$');
  static final RegExp _featSuffixRegex = RegExp(r'\s*[-–—]\s*(?:feat\.?|ft\.?).*$', caseSensitive: false);
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');

  /// Strips movie tags, remaster/official markers, and feat suffixes for canonical comparison.
  static String cleanTitleForDedup(String rawTitle) {
    var t = rawTitle.trim();
    t = t.replaceAll(_fromMovieRegex, '');
    t = t.replaceAll(_noiseParenRegex, '');
    t = t.replaceAll(_pipeSuffixRegex, '');
    t = t.replaceAll(_featSuffixRegex, '');
    t = t.replaceAll(_multiSpaceRegex, ' ').trim();
    return t;
  }

  /// Canonical key "<normalizedCleanTitle>|<firstNormalizedArtist>".
  static String canonicalKey(String title, String artist) =>
      SpotifyTrackKey.keyFor(cleanTitleForDedup(title), artist);

  /// True when two tracks represent the same song across different IDs/providers.
  static bool isSameSong(Song a, Song b) {
    if (a.id.isNotEmpty && a.id == b.id) return true;
    final cleanA = cleanTitleForDedup(a.title);
    final cleanB = cleanTitleForDedup(b.title);
    if (!SpotifyTrackKey.sameTrack(
      titleA: cleanA,
      artistsA: a.artist,
      titleB: cleanB,
      artistsB: b.artist,
    )) {
      return false;
    }
    if (a.duration > 0 && b.duration > 0 && (a.duration - b.duration).abs() > 15) {
      return false;
    }
    return true;
  }

  /// Finds an already-downloaded song matching [title], [artist], and optional [durationSeconds].
  static Song? findMatch({
    required Iterable<Song> downloadedSongs,
    required String title,
    required String artist,
    int durationSeconds = 0,
  }) {
    final cleanTarget = cleanTitleForDedup(title);
    if (cleanTarget.isEmpty) return null;

    for (final existing in downloadedSongs) {
      final cleanExisting = cleanTitleForDedup(existing.title);
      if (!SpotifyTrackKey.sameTrack(
        titleA: cleanTarget,
        artistsA: artist,
        titleB: cleanExisting,
        artistsB: existing.artist,
      )) {
        continue;
      }
      if (durationSeconds > 0 &&
          existing.duration > 0 &&
          (durationSeconds - existing.duration).abs() > 15) {
        continue;
      }
      return existing;
    }
    return null;
  }

  /// Groups duplicate downloaded songs (same canonical title, shared artist, duration <= 15s).
  /// Each returned list has >= 2 items, ordered so index 0 is the primary copy to keep.
  static List<List<Song>> findDuplicateGroups(List<Song> downloadedSongs) {
    final groups = <List<Song>>[];
    final assigned = <String>{};

    for (int i = 0; i < downloadedSongs.length; i++) {
      final primary = downloadedSongs[i];
      if (!assigned.add(primary.id)) continue;

      final cluster = <Song>[primary];
      for (int j = i + 1; j < downloadedSongs.length; j++) {
        final candidate = downloadedSongs[j];
        if (assigned.contains(candidate.id)) continue;
        if (isSameSong(primary, candidate)) {
          assigned.add(candidate.id);
          cluster.add(candidate);
        }
      }
      if (cluster.length > 1) {
        groups.add(cluster);
      }
    }
    return groups;
  }

  /// Returns downloaded songs from [playlist] that are NOT used in any other playlist or [favoriteSongs].
  static List<Song> findOrphanedPlaylistDownloads({
    required UserPlaylist playlist,
    required List<UserPlaylist> allPlaylists,
    required List<Song> favoriteSongs,
    required List<Song> downloadedSongs,
  }) {
    if (playlist.tracks.isEmpty || downloadedSongs.isEmpty) return const [];

    final protectedSongs = <Song>[
      ...favoriteSongs,
      for (final pl in allPlaylists)
        if (pl.id != playlist.id) ...pl.tracks,
    ];

    final orphaned = <Song>[];
    final seenDownloadedIds = <String>{};

    for (final track in playlist.tracks) {
      final downloaded = downloadedSongs.where((d) => d.id == track.id).firstOrNull ??
          findMatch(
            downloadedSongs: downloadedSongs,
            title: track.title,
            artist: track.artist,
            durationSeconds: track.duration,
          );
      if (downloaded == null || !seenDownloadedIds.add(downloaded.id)) continue;

      final stillUsedElsewhere = protectedSongs.any((p) => isSameSong(p, downloaded));
      if (!stillUsedElsewhere) {
        orphaned.add(downloaded);
      }
    }
    return orphaned;
  }
}
