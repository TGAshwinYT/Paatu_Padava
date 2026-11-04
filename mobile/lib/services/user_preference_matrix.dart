import 'package:paatu_padava_mobile/services/search_service.dart';
import '../models/song.dart';
import 'favorites_manager.dart';
import 'history_manager.dart';
import 'artist_sanitizer.dart';
import 'settings_manager.dart';

/// Dynamic On-Device User Preference Matrix for Paatu Padava.
/// Re-ranks search results and recommended queues by learning the user's personal
/// affinity vectors from Liked Songs (`FavoritesManager`) and Play History (`HistoryManager`).
class UserPreferenceIndex {
  final Set<String> likedSongIds;
  final Set<String> likedDedupKeys;
  final Map<String, int> likedArtistCounts;
  final Map<String, int> histSongCounts;
  final Map<String, int> histArtistCounts;

  const UserPreferenceIndex({
    required this.likedSongIds,
    required this.likedDedupKeys,
    required this.likedArtistCounts,
    required this.histSongCounts,
    required this.histArtistCounts,
  });

  factory UserPreferenceIndex.fromSongs(List<Song> favs, List<Song> hist) {
    final likedSongIds = <String>{};
    final likedDedupKeys = <String>{};
    final likedArtistCounts = <String, int>{};

    for (final fav in favs) {
      if (fav.id.isNotEmpty) likedSongIds.add(fav.id);
      if (fav.deduplicationKey.isNotEmpty) likedDedupKeys.add(fav.deduplicationKey);
      final primary = fav.primaryArtist.toLowerCase().trim();
      if (primary.isNotEmpty) {
        likedArtistCounts[primary] = (likedArtistCounts[primary] ?? 0) + 1;
      }
    }

    final histSongCounts = <String, int>{};
    final histArtistCounts = <String, int>{};

    for (final h in hist) {
      if (h.id.isNotEmpty) {
        histSongCounts[h.id] = (histSongCounts[h.id] ?? 0) + 1;
      }
      final primary = h.primaryArtist.toLowerCase().trim();
      if (primary.isNotEmpty) {
        histArtistCounts[primary] = (histArtistCounts[primary] ?? 0) + 1;
      }
    }

    return UserPreferenceIndex(
      likedSongIds: likedSongIds,
      likedDedupKeys: likedDedupKeys,
      likedArtistCounts: likedArtistCounts,
      histSongCounts: histSongCounts,
      histArtistCounts: histArtistCounts,
    );
  }
}

class UserPreferenceMatrix {
  /// Computes personalized user affinity using pre-indexed preference sets/maps for O(1) lookups.
  static double computeAffinityWithIndex(Song song, UserPreferenceIndex index) {
    double affinity = 0.0;

    // 1. Liked Song Direct Match (+0.40) - O(1)
    final isLiked = index.likedSongIds.contains(song.id) ||
        (song.deduplicationKey.isNotEmpty && index.likedDedupKeys.contains(song.deduplicationKey));
    if (isLiked) {
      affinity += 0.40;
    }

    // 2. Favorite Artist Affinity (+0.30) - O(k) where k <= 4
    final songArtists = ArtistSanitizer.extractAllGenuineArtists(song.artist);
    final songArtistsLower = songArtists.map((a) => a.toLowerCase().trim()).toSet();
    songArtistsLower.add(song.primaryArtist.toLowerCase().trim());
    songArtistsLower.remove('');

    int likedArtistMatches = 0;
    for (final artist in songArtistsLower) {
      likedArtistMatches += index.likedArtistCounts[artist] ?? 0;
    }
    if (likedArtistMatches >= 3) {
      affinity += 0.30;
    } else if (likedArtistMatches >= 1) {
      affinity += 0.20;
    }

    // 3. Listening History Frequency (+0.30) - O(k)
    final songIdPlays = index.histSongCounts[song.id] ?? 0;
    int totalArtistPlays = 0;
    for (final artist in songArtistsLower) {
      totalArtistPlays += index.histArtistCounts[artist] ?? 0;
    }
    final otherArtistPlays = totalArtistPlays - songIdPlays;
    final historyPlayCount = (songIdPlays * 2) + (otherArtistPlays > 0 ? otherArtistPlays : 0);

    if (historyPlayCount >= 4) {
      affinity += 0.30;
    } else if (historyPlayCount >= 2) {
      affinity += 0.20;
    } else if (historyPlayCount >= 1) {
      affinity += 0.10;
    }

    return affinity.clamp(0.0, 1.0);
  }

  /// Computes a personalized user affinity score between 0.0 and 1.0 for a song.
  static double computeAffinity(
    Song song, {
    List<Song>? likedSongs,
    List<Song>? historySongs,
  }) {
    final favs = likedSongs ?? (FavoritesManager.favoritesNotifier.value);
    final hist = historySongs ?? (HistoryManager.historyNotifier.value);
    final index = UserPreferenceIndex.fromSongs(favs, hist);
    return computeAffinityWithIndex(song, index);
  }

  static double _scoreVariant(String q, String titleLower, String albumLower, String artistLower) {
    if (q.isEmpty) return 0.0;
    if (SearchService.isAlbumOrMovieEntityMatch(albumLower, q)) {
      return 1.0;
    }
    // Check if title contains '(From "Movie")' matching the query (crucial for YouTube tracks with empty album)
    final fromMovieRegex = RegExp(r'[\(\[\-]\s*(?:from|ost|soundtrack\s+from)\s*["\x27\u201c\u201d\u2018\u2019]?([^"\x27\u201c\u201d\u2018\u2019\)\]]+)', caseSensitive: false);
    final match = fromMovieRegex.firstMatch(titleLower);
    final extractedMovie = match?.group(1)?.trim() ?? '';
    if (extractedMovie.isNotEmpty && SearchService.isAlbumOrMovieEntityMatch(extractedMovie, q)) {
      return 1.0;
    }
    if (titleLower == q) {
      return 0.98;
    } else if (titleLower.startsWith('$q ') || titleLower.startsWith('$q-') || (q.length > 3 && titleLower.startsWith(q))) {
      return 0.88;
    } else if (albumLower.startsWith('$q ') || (q.length > 3 && albumLower.startsWith(q))) {
      return 0.85;
    } else if (q.length <= 3) {
      final tokenRegex = RegExp(r'\b' + RegExp.escape(q) + r'\b');
      if (tokenRegex.hasMatch(titleLower)) return 0.75;
      if (tokenRegex.hasMatch(albumLower)) return 0.72;
      if (artistLower == q) return 0.65;
      return 0.10;
    } else {
      if (titleLower.contains(q)) return 0.70;
      if (albumLower.contains(q)) return 0.68;
      if (artistLower.contains(q)) return 0.65;
      return 0.30;
    }
  }

  /// Re-ranks a list of candidate songs by combining query relevance with the user preference affinity.
  static List<Song> reRankWithPreferences(
    List<Song> candidates,
    String query, {
    QueryIntent? intent,
    List<Song>? likedSongs,
    List<Song>? historySongs,
    List<String>? preferredLanguages,
  }) {
    if (candidates.isEmpty) return candidates;
    final qLower = query.trim().toLowerCase();

    final favs = likedSongs ?? (FavoritesManager.favoritesNotifier.value);
    final hist = historySongs ?? (HistoryManager.historyNotifier.value);
    final prefIndex = UserPreferenceIndex.fromSongs(favs, hist);

    final scored = candidates.map((song) {
      final titleLower = song.title.toLowerCase();
      final artistLower = song.artist.toLowerCase();
      final albumLower = song.album.toLowerCase();

      double relevance = _scoreVariant(qLower, titleLower, albumLower, artistLower);
      if (intent != null) {
        final coreQ = intent.effectiveCoreQuery.toLowerCase().trim();
        if (coreQ.isNotEmpty && coreQ != qLower) {
          final s = _scoreVariant(coreQ, titleLower, albumLower, artistLower);
          if (s > relevance) relevance = s;
        }
        final transQ = intent.transliteratedQuery.toLowerCase().trim();
        if (transQ.isNotEmpty && transQ != qLower) {
          final s = _scoreVariant(transQ, titleLower, albumLower, artistLower);
          if (s > relevance) relevance = s;
        }
        final dym = intent.didYouMeanSuggestion?.toLowerCase().trim();
        if (dym != null && dym.isNotEmpty && dym != qLower) {
          final s = _scoreVariant(dym, titleLower, albumLower, artistLower);
          if (s > relevance) relevance = s;
        }
      }

      // User Personal Preference (0.0 to 1.0)
      final userAffinity = computeAffinityWithIndex(song, prefIndex);

      // Weighted Multi-Factor Score: 85% Query Relevance + 15% User Personal Affinity
      final effectiveAffinity = relevance >= 0.45 ? userAffinity : (userAffinity * 0.30);
      double compositeScore = (0.85 * relevance) + (0.15 * effectiveAffinity);

      // Multi-Language Parity: Prioritize songs in user's preferred languages
      final targetLangs = (preferredLanguages ?? SettingsManager.preferredLanguages)
          .map((l) => l.toLowerCase().trim())
          .where((l) => l.isNotEmpty)
          .toSet();

      if (targetLangs.isNotEmpty) {
        final sLang = song.language?.toLowerCase().trim() ?? '';
        final titleHasPref = targetLangs.any((l) => titleLower.contains(l));
        final albumHasPref = targetLangs.any((l) => albumLower.contains(l));
        final isPreferred = targetLangs.contains(sLang) || titleHasPref || albumHasPref;

        if (isPreferred) {
          compositeScore *= 1.25; // First-class preferred language boost (+25%)
        } else if (sLang.isNotEmpty && !targetLangs.contains(sLang) && sLang != 'english') {
          compositeScore *= 0.80; // Secondary regional language demotion when preferred languages specified
        }
      }

      return MapEntry(compositeScore, song);
    }).toList();

    final Map<String, int> arrivalOrder = {
      for (int i = 0; i < candidates.length; i++) candidates[i].id: i
    };

    // Deterministic tie-breaking: Score -> Exact Title -> Album Track Order -> Studio Source -> Art -> Arrival Order / ID
    scored.sort((a, b) {
      final scoreCmp = b.key.compareTo(a.key);
      if (scoreCmp != 0) return scoreCmp;

      final sA = a.value;
      final sB = b.value;

      final albA = sA.album.toLowerCase().trim();
      final albB = sB.album.toLowerCase().trim();
      final aAlbumMatch = SearchService.isAlbumOrMovieEntityMatch(albA, qLower) ? 1 : 0;
      final bAlbumMatch = SearchService.isAlbumOrMovieEntityMatch(albB, qLower) ? 1 : 0;
      if (aAlbumMatch != bAlbumMatch) return bAlbumMatch.compareTo(aAlbumMatch);

      final targetLangs = (preferredLanguages ?? SettingsManager.preferredLanguages)
          .map((l) => l.toLowerCase().trim())
          .where((l) => l.isNotEmpty)
          .toSet();
      if (targetLangs.isNotEmpty) {
        final aLang = sA.language?.toLowerCase().trim() ?? '';
        final bLang = sB.language?.toLowerCase().trim() ?? '';
        final aMatch = targetLangs.contains(aLang) || targetLangs.any((l) => sA.title.toLowerCase().contains(l));
        final bMatch = targetLangs.contains(bLang) || targetLangs.any((l) => sB.title.toLowerCase().contains(l));
        if (aMatch != bMatch) return aMatch ? -1 : 1;
      }

      // If both tracks belong to the SAME matched movie/soundtrack entity, preserve official tracklist order!
      if (aAlbumMatch == 1 && bAlbumMatch == 1 && albA == albB) {
        final aExact = (sA.title.toLowerCase().trim() == qLower) ? 1 : 0;
        final bExact = (sB.title.toLowerCase().trim() == qLower) ? 1 : 0;
        if (aExact != bExact) return bExact.compareTo(aExact);

        final idxA = arrivalOrder[sA.id] ?? 0;
        final idxB = arrivalOrder[sB.id] ?? 0;
        if (idxA != idxB) return idxA.compareTo(idxB);
      }

      final aExact = (sA.title.toLowerCase().trim() == qLower) ? 1 : 0;
      final bExact = (sB.title.toLowerCase().trim() == qLower) ? 1 : 0;
      if (aExact != bExact) return bExact.compareTo(aExact);

      final aStudio = (sA.source.toLowerCase() == 'saavn') ? 1 : 0;
      final bStudio = (sB.source.toLowerCase() == 'saavn') ? 1 : 0;
      if (aStudio != bStudio) return bStudio.compareTo(aStudio);

      final aArt = sA.hasOfficialAlbumArt ? 1 : 0;
      final bArt = sB.hasOfficialAlbumArt ? 1 : 0;
      if (aArt != bArt) return bArt.compareTo(aArt);

      final idxA = arrivalOrder[sA.id] ?? 0;
      final idxB = arrivalOrder[sB.id] ?? 0;
      if (idxA != idxB) return idxA.compareTo(idxB);

      return sA.id.compareTo(sB.id);
    });
    return scored.map((e) => e.value).toList();
  }
}
