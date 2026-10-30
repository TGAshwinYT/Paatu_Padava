import 'package:hive_flutter/hive_flutter.dart';

/// Remembers which local playlist a Spotify playlist/album was imported into, and
/// which Spotify tracks were already handled, so re-importing only adds NEW songs.
///
/// Stored in its own local Hive box (no Supabase schema change needed). If the
/// local playlist is later deleted, the link is simply ignored.
class SpotifyImportLink {
  final String spotifyKey; // "playlist:<id>" or "album:<id>"
  final String playlistId; // local UserPlaylist.id
  final Set<String> importedKeys; // SpotifyTrackKey.keyFor(...) of handled tracks
  final int updatedAt;

  const SpotifyImportLink({
    required this.spotifyKey,
    required this.playlistId,
    required this.importedKeys,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'spotify_key': spotifyKey,
        'playlist_id': playlistId,
        'imported_keys': importedKeys.toList(),
        'updated_at': updatedAt,
      };

  factory SpotifyImportLink.fromMap(Map<dynamic, dynamic> m) => SpotifyImportLink(
        spotifyKey: m['spotify_key']?.toString() ?? '',
        playlistId: m['playlist_id']?.toString() ?? '',
        importedKeys: ((m['imported_keys'] as List?) ?? const []).map((e) => e.toString()).toSet(),
        updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
      );
}

class SpotifyImportLinks {
  SpotifyImportLinks._();
  static const String boxName = 'spotify_import_links';

  static Future<Box> _box() async =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : await Hive.openBox(boxName);

  static Future<SpotifyImportLink?> get(String spotifyKey) async {
    try {
      final data = (await _box()).get(spotifyKey);
      if (data is Map) return SpotifyImportLink.fromMap(data);
    } catch (_) {}
    return null;
  }

  static Future<void> save(SpotifyImportLink link) async {
    try {
      await (await _box()).put(link.spotifyKey, link.toMap());
    } catch (_) {}
  }

  static Future<void> remove(String spotifyKey) async {
    try {
      await (await _box()).delete(spotifyKey);
    } catch (_) {}
  }
}
