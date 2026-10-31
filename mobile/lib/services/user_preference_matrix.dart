import '../models/song.dart';
import 'favorites_manager.dart';
import 'history_manager.dart';
import 'artist_sanitizer.dart';

/// Dynamic On-Device User Preference Matrix for Paatu Padava.
/// Re-ranks search results and recommended queues by learning the user's personal
/// affinity vectors from Liked Songs (`FavoritesManager`) and Play History (`HistoryManager`).
class UserPreferenceMatrix {
  /// Computes a personalized user affinity score between 0.0 and 1.0 for a song.
  static double computeAffinity(
    Song song, {
    List<Song>? likedSongs,
    List<Song>? historySongs,
  }) {
    final favs = likedSongs ?? (FavoritesManager.favoritesNotifier.value);
    final hist = historySongs ?? (HistoryManager.historyNotifier.value);

    double affinity = 0.0;

    // 1. Liked Song Direct Match (+0.40)
    final isLiked = favs.any((f) => f.id == song.id || f.deduplicationKey == song.deduplicationKey);
    if (isLiked) {
      affinity += 0.40;
    }

    // 2. Favorite Artist Affinity (+0.30)
    final songArtists = ArtistSanitizer.extractAllGenuineArtists(song.artist);
    final songArtistsLower = songArtists.map((a) => a.toLowerCase()).toSet();
    songArtistsLower.add(song.primaryArtist.toLowerCase());

    int likedArtistMatches = 0;
    for (final fav in favs) {
      final favPrimary = fav.primaryArtist.toLowerCase();
      if (songArtistsLower.contains(favPrimary)) {
        likedArtistMatches++;
      }
    }
    if (likedArtistMatches >= 3) {
      affinity += 0.30;
    } else if (likedArtistMatches >= 1) {
      affinity += 0.20;
    }

    // 3. Listening History Frequency (+0.30)
    int historyPlayCount = 0;
    for (final h in hist) {
      if (h.id == song.id) {
        historyPlayCount += 2;
      } else if (songArtistsLower.contains(h.primaryArtist.toLowerCase())) {
        historyPlayCount += 1;
      }
    }

    if (historyPlayCount >= 4) {
      affinity += 0.30;
    } else if (historyPlayCount >= 2) {
      affinity += 0.20;
    } else if (historyPlayCount >= 1) {
      affinity += 0.10;
    }

    return affinity.clamp(0.0, 1.0);
  }

  /// Re-ranks a list of candidate songs by combining query relevance with the user preference affinity.
  static List<Song> reRankWithPreferences(
    List<Song> candidates,
    String query, {
    List<Song>? likedSongs,
    List<Song>? historySongs,
  }) {
    if (candidates.isEmpty) return candidates;
    final qLower = query.trim().toLowerCase();

    final favs = likedSongs ?? (FavoritesManager.favoritesNotifier.value);
    final hist = historySongs ?? (HistoryManager.historyNotifier.value);

    final scored = candidates.map((song) {
      final titleLower = song.title.toLowerCase();
      final artistLower = song.artist.toLowerCase();

      // Base Query Relevance (0.0 to 1.0)
      double relevance = 0.0;
      if (titleLower == qLower) {
        relevance = 1.0;
      } else if (titleLower.startsWith(qLower)) {
        relevance = 0.85;
      } else if (titleLower.contains(qLower)) {
        relevance = 0.70;
      } else if (artistLower.contains(qLower)) {
        relevance = 0.65;
      } else {
        relevance = 0.40;
      }

      // User Personal Preference (0.0 to 1.0)
      final userAffinity = computeAffinity(song, likedSongs: favs, historySongs: hist);

      // Weighted Multi-Factor Score: 60% Query Relevance + 40% User Personal Affinity
      final compositeScore = (0.60 * relevance) + (0.40 * userAffinity);

      return MapEntry(compositeScore, song);
    }).toList();

    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.map((e) => e.value).toList();
  }
}
