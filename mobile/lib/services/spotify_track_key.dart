/// Pure-Dart helpers that decide "is this Spotify track already in my playlist?".
///
/// A Spotify track (title + artists) and the Song we matched it to (JioSaavn /
/// YouTube title + artists) never look identical, and the matcher can pick a
/// DIFFERENT source/id on a later import. So we never compare ids; we compare a
/// normalised title plus at least one shared artist.
class SpotifyTrackKey {
  SpotifyTrackKey._();

  static final RegExp _nonWord = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);
  static final RegExp _artistSplit =
      RegExp(r'[,&;/]|\bfeat\.?\b|\bft\.?\b|\band\b', caseSensitive: false);

  /// Lower-case letters/marks/digits only (works for Tamil/Hindi scripts too).
  static String norm(String s) => s.toLowerCase().replaceAll(_nonWord, '');

  /// Set of normalised artist names from "A, B & C feat. D".
  static Set<String> artistSet(String artists) => artists
      .split(_artistSplit)
      .map(norm)
      .where((a) => a.isNotEmpty)
      .toSet();

  /// Stable identity of a SPOTIFY track: "<title>|<first artist>".
  /// [cleanTitle] must already have "(From ...)" / "[Remastered]" noise removed.
  static String keyFor(String cleanTitle, String artists) {
    final first = artists.split(_artistSplit).map(norm).firstWhere((a) => a.isNotEmpty, orElse: () => '');
    return '${norm(cleanTitle)}|$first';
  }

  /// True when two tracks are the same song: equal normalised title and, when both
  /// sides list artists, at least one artist in common.
  static bool sameTrack({
    required String titleA,
    required String artistsA,
    required String titleB,
    required String artistsB,
  }) {
    final ta = norm(titleA);
    if (ta.isEmpty || ta != norm(titleB)) return false;
    final aa = artistSet(artistsA);
    final ab = artistSet(artistsB);
    if (aa.isEmpty || ab.isEmpty) return true;
    return aa.any(ab.contains);
  }
}
