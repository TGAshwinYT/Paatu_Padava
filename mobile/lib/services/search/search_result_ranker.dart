import 'dart:math' as math;
import '../../models/song.dart';
import '../../domain/models/track_entity.dart';
import '../../core/dsa/bk_tree.dart';
import '../../core/dsa/trigram_index.dart';
import '../../logic/search_query_planner.dart';
import '../artist_sanitizer.dart';
import '../catalog_database.dart';
import '../favorites_manager.dart';
import '../history_manager.dart';
import '../settings_manager.dart';
import '../../data/repositories/song_repository.dart';
import 'search_models.dart';
import 'query_normalizer.dart';

/// Stage 3 & 4: Multi-factor relevance scoring, deduplication, and deterministic ranking.
class SearchResultRanker {
  /// Evaluates exact match, token containment, and Levenshtein metric distance via BkTree
  static double calculateStringSimilarity(Song song, QueryIntent intent) {
    final qLower = intent.cleanQuery.toLowerCase();
    final transLower = intent.transliteratedQuery.toLowerCase();
    final titleNorm = song.normalizedTitle;
    final cleanTitle = SearchQueryPlanner.cleanTitle(song.title).toLowerCase();

    if (qLower.isEmpty) return 0.0;
    if (cleanTitle == qLower || titleNorm == qLower || transLower == cleanTitle || transLower == titleNorm) {
      return 1.0;
    }

    bool isWordPrefix(String text, String prefix) {
      if (prefix.length > 3) return text.startsWith(prefix);
      if (!text.startsWith(prefix)) return false;
      if (text.length == prefix.length) return true;
      final nextChar = text.codeUnitAt(prefix.length);
      final isAlnum = (nextChar >= 48 && nextChar <= 57) ||
          (nextChar >= 65 && nextChar <= 90) ||
          (nextChar >= 97 && nextChar <= 122);
      return !isAlnum;
    }

    if (isWordPrefix(cleanTitle, qLower) || isWordPrefix(titleNorm, qLower) || isWordPrefix(cleanTitle, transLower)) {
      return 0.95;
    }

    double similarity = 0.0;

    // Levenshtein typo-tolerance using BkTree: strictly Distance = 0 for <= 3 chars
    if (qLower.length > 3) {
      final int distClean = BkTree.levenshteinDistance(qLower, cleanTitle);
      final int maxLenClean = math.max(qLower.length, cleanTitle.length);
      final double levClean = maxLenClean == 0 ? 1.0 : (1.0 - (distClean / maxLenClean)).clamp(0.0, 1.0);

      final int distNorm = BkTree.levenshteinDistance(qLower, titleNorm);
      final int maxLenNorm = math.max(qLower.length, titleNorm.length);
      final double levNorm = maxLenNorm == 0 ? 1.0 : (1.0 - (distNorm / maxLenNorm)).clamp(0.0, 1.0);

      final int distTrans = BkTree.levenshteinDistance(transLower, titleNorm);
      final int maxLenTrans = math.max(transLower.length, titleNorm.length);
      final double levTrans = maxLenTrans == 0 ? 1.0 : (1.0 - (distTrans / maxLenTrans)).clamp(0.0, 1.0);

      similarity = math.max(levClean, math.max(levNorm, levTrans));

      // Tri-Gram Jaccard similarity for Tanglish phonetic transliteration
      final double jaccardScore = TrigramIndex.jaccard(qLower, cleanTitle);
      if (jaccardScore > 0.50) {
        similarity = math.max(similarity, jaccardScore * 0.95);
      }
    }

    bool matchesToken(String text, String token) {
      if (token.isEmpty || text.isEmpty) return false;
      if (token.length <= 3) {
        int idx = text.indexOf(token);
        while (idx != -1) {
          final isStartWord = idx == 0 ||
              !((text.codeUnitAt(idx - 1) >= 48 && text.codeUnitAt(idx - 1) <= 57) ||
                  (text.codeUnitAt(idx - 1) >= 65 && text.codeUnitAt(idx - 1) <= 90) ||
                  (text.codeUnitAt(idx - 1) >= 97 && text.codeUnitAt(idx - 1) <= 122));
          final end = idx + token.length;
          final isEndWord = end == text.length ||
              !((text.codeUnitAt(end) >= 48 && text.codeUnitAt(end) <= 57) ||
                  (text.codeUnitAt(end) >= 65 && text.codeUnitAt(end) <= 90) ||
                  (text.codeUnitAt(end) >= 97 && text.codeUnitAt(end) <= 122));
          if (isStartWord && isEndWord) return true;
          idx = text.indexOf(token, idx + 1);
        }
        return false;
      }
      return text.contains(token);
    }

    if (matchesToken(cleanTitle, qLower) || matchesToken(titleNorm, qLower) || matchesToken(titleNorm, transLower)) {
      final tokenBoost = 0.80 + (0.15 * (qLower.length / math.max(1, titleNorm.length)));
      similarity = math.max(similarity, tokenBoost);
    }

    final artistLower = song.primaryArtist.toLowerCase();
    final coreLower = intent.effectiveCoreQuery.toLowerCase();
    if (qLower.length > 3) {
      if (artistLower.isNotEmpty &&
          (artistLower == qLower || matchesToken(artistLower, qLower) || matchesToken(artistLower, coreLower))) {
        similarity = math.max(similarity, 0.85);
      }
    } else {
      if (artistLower.isNotEmpty && (artistLower == qLower || artistLower == coreLower)) {
        similarity = math.max(similarity, 0.85);
      }
    }

    final albumLower = song.album.toLowerCase();
    if (albumLower.isNotEmpty) {
      final exactAlbum = albumLower == qLower ||
          albumLower == transLower ||
          albumLower == coreLower ||
          (albumLower.contains(' - ') && albumLower.split(' - ').first.trim() == qLower);
      if (exactAlbum) {
        similarity = math.max(similarity, 0.98);
      } else if (qLower.length > 3) {
        if (matchesToken(albumLower, qLower) ||
            matchesToken(albumLower, transLower) ||
            (qLower.length >= 4 && qLower.contains(albumLower)) ||
            (qLower.length >= 4 && BkTree.levenshteinDistance(albumLower, qLower, maxDistance: 1) <= 1)) {
          similarity = math.max(similarity, 0.90);
        }
      } else if (matchesToken(albumLower, qLower)) {
        similarity = math.max(similarity, 0.90);
      }
    }
    return similarity.clamp(0.0, 1.0);
  }

  /// Weights 320kbps JioSaavn studio catalog, YouTube Music Official Topic/VEVO badges, etc.
  static double calculateSourcePopularity(Song song) {
    double score = 0.0;

    if (song.source == 'saavn') {
      score += 0.25;
    } else if (song.artist.toLowerCase().contains('topic') ||
        song.artist.toLowerCase().contains('vevo') ||
        song.hasOfficialAlbumArt) {
      score += 0.22;
    } else {
      score += 0.18;
    }

    if (song.hasOfficialAlbumArt) {
      score += 0.30;
    } else if (song.coverUrl.isNotEmpty &&
        !song.coverUrl.contains('default.jpg') &&
        !song.coverUrl.contains('mqdefault.jpg')) {
      score += 0.20;
    } else {
      score += 0.05;
    }

    if (song.duration >= 90 && song.duration <= 360) {
      score += 0.25;
    } else if (song.duration >= 45 && song.duration <= 600) {
      score += 0.15;
    }

    if (song.versionTag == 'Original') {
      score += 0.20;
    } else {
      score += 0.10;
    }

    return score.clamp(0.0, 1.0);
  }

  /// Checks whether the song artist is in history or favorites
  static double calculateUserAffinity(
    Song song, {
    List<Song>? history,
    List<Song>? favorites,
  }) {
    final hist = history ?? (HistoryManager.historyNotifier.value);
    final favs = favorites ?? (FavoritesManager.favoritesNotifier.value);

    final candArtist = song.primaryArtist.toLowerCase();
    final candAlbum = song.album.toLowerCase();
    if (candArtist.isEmpty && candAlbum.isEmpty) return 0.0;

    for (final fav in favs) {
      if (fav.id == song.id) return 1.0;
      if (candArtist.isNotEmpty &&
          (fav.primaryArtist.toLowerCase() == candArtist ||
              SongRepository.normalizeArtist(fav.artist).toLowerCase() == candArtist)) {
        return 1.0;
      }
      if (candAlbum.isNotEmpty &&
          candAlbum != 'studio album' &&
          candAlbum != 'single' &&
          candAlbum != 'unknown' &&
          fav.album.toLowerCase() == candAlbum) {
        return 0.95;
      }
    }

    int playCount = 0;
    for (final h in hist) {
      if (h.id == song.id) return 0.90;
      if (candArtist.isNotEmpty &&
          (h.primaryArtist.toLowerCase() == candArtist ||
              SongRepository.normalizeArtist(h.artist).toLowerCase() == candArtist)) {
        playCount++;
      } else if (candAlbum.isNotEmpty &&
          candAlbum != 'studio album' &&
          candAlbum != 'single' &&
          candAlbum != 'unknown' &&
          h.album.toLowerCase() == candAlbum) {
        playCount += 2;
      }
    }

    if (playCount >= 5) return 1.0;
    if (playCount >= 3) return 0.75;
    if (playCount == 2) return 0.50;
    if (playCount == 1) return 0.25;

    return 0.0;
  }

  /// Computes composite multi-factor relevance score:
  /// Score = (0.50 * StringSimilarity) + (0.30 * SourcePopularity) + (0.20 * UserAffinity)
  static double calculateCompositeRelevance(
    Song song,
    QueryIntent intent, {
    List<Song>? history,
    List<Song>? favorites,
    List<String>? preferredLanguages,
    UserAffinityContext? affinityContext,
  }) {
    if (intent.explicitLanguage != null &&
        SongRepository.isLanguageMismatch(song, intent.explicitLanguage!)) {
      return 0.0;
    }

    final stringSim = calculateStringSimilarity(song, intent);
    final qLower = intent.cleanQuery.toLowerCase();
    final songLang = song.language?.toLowerCase().trim() ?? '';
    final cleanTitle = SearchQueryPlanner.cleanTitle(song.title).toLowerCase();
    final isExactTitleMatch = cleanTitle == qLower || song.normalizedTitle == qLower;
    final isArtistTarget = song.primaryArtist.isNotEmpty &&
        (qLower == song.primaryArtist.toLowerCase() || song.primaryArtist.toLowerCase().contains(qLower));

    const nonRegionalLanguages = {
      'arabic', 'spanish', 'french', 'turkish', 'russian', 'korean', 'chinese', 'german', 'italian', 'persian', 'japanese'
    };
    final isExplicitForeign = intent.explicitLanguage != null && nonRegionalLanguages.contains(intent.explicitLanguage!.toLowerCase());
    final isForeignInQuery = nonRegionalLanguages.any((l) => qLower.contains(l));

    if (!isExplicitForeign && !isForeignInQuery) {
      if (songLang == 'arabic' || songLang == 'turkish' || songLang == 'persian') {
        return 0.0;
      }
      if (songLang != 'urdu') {
        if (ArtistSanitizer.isMiddleEasternOrForeignArtist(song.artist) ||
            ArtistSanitizer.isMiddleEasternOrForeignArtist(song.title) ||
            QueryNormalizer.arabicScriptRegex.hasMatch('${song.title} ${song.artist}')) {
          return 0.0;
        }
      }
      if (songLang.isNotEmpty && nonRegionalLanguages.contains(songLang)) {
        if (!isExactTitleMatch && !isArtistTarget) {
          return 0.0;
        }
      }
    }

    final titleLower = song.title.toLowerCase();
    if (QueryNormalizer.dialogueRegex.hasMatch(titleLower)) {
      final queryAsksDialogue = qLower.contains('dialogue') || qLower.contains('scene') || qLower.contains('ringtone');
      if (!queryAsksDialogue && !isExactTitleMatch && !isArtistTarget) {
        return 0.0;
      }
    }

    if (qLower.length <= 3) {
      final userPrefLangs = (preferredLanguages != null && preferredLanguages.isNotEmpty)
          ? preferredLanguages.map((l) => l.toLowerCase().trim()).toSet()
          : SettingsManager.preferredLanguages.map((l) => l.toLowerCase().trim()).toSet();

      final hasRegionalMatch = song.source == 'saavn' ||
          userPrefLangs.contains(song.language?.toLowerCase().trim()) ||
          userPrefLangs.any((l) => song.title.toLowerCase().contains(l) || song.album.toLowerCase().contains(l));
      if (song.source == 'youtube' && !hasRegionalMatch) {
        final titleAndArtist = '${song.title} ${song.artist} ${song.album}'.toLowerCase();
        if (!QueryNormalizer.knownIndianArtistsRegex.hasMatch(titleAndArtist) && !userPrefLangs.any((l) => titleAndArtist.contains(l))) {
          return 0.0;
        }
      }
    }
    final popularity = calculateSourcePopularity(song);
    final affinity = affinityContext?.computeAffinity(song) ??
        calculateUserAffinity(song, history: history, favorites: favorites);

    final double effectiveAffinity;
    if (stringSim >= 0.60) {
      effectiveAffinity = affinity;
    } else if (stringSim >= 0.25) {
      effectiveAffinity = affinity * ((stringSim - 0.25) / 0.35);
    } else {
      effectiveAffinity = 0.0;
    }

    double score = (0.50 * stringSim) + (0.30 * popularity) + (0.20 * effectiveAffinity);

    if (stringSim >= 0.98) {
      score = math.max(score, 0.75);
    }

    if (song.matchedLyricSnippet != null && song.matchedLyricSnippet!.isNotEmpty) {
      score = math.max(score, 0.90);
    }

    String albLower = song.album.toLowerCase().trim();
    if (albLower.isEmpty || albLower == 'single' || albLower == 'unknown' || albLower == 'unknown album') {
      final fromMovieRegex = RegExp(r'[\(\[\-]\s*(?:from|ost|soundtrack\s+from)\s*["\x27\u201c\u201d\u2018\u2019]?([^"\x27\u201c\u201d\u2018\u2019\)\]]+)', caseSensitive: false);
      final match = fromMovieRegex.firstMatch(song.title);
      if (match != null) {
        albLower = match.group(1)?.toLowerCase().trim() ?? '';
      }
    }
    if (qLower.isNotEmpty && albLower.isNotEmpty) {
      final isAlbMatch = QueryNormalizer.isAlbumOrMovieEntityMatch(albLower, qLower) ||
          (intent.effectiveCoreQuery.isNotEmpty && QueryNormalizer.isAlbumOrMovieEntityMatch(albLower, intent.effectiveCoreQuery));
      if (isAlbMatch) {
        if (preferredLanguages != null && preferredLanguages.isNotEmpty) {
          final targetLangs = preferredLanguages.map((l) => l.toLowerCase().trim()).toSet();
          final songLang = song.language?.toLowerCase().trim() ?? '';
          final matchesLang = targetLangs.contains(songLang) ||
              targetLangs.any((l) => song.title.toLowerCase().contains(l) || song.album.toLowerCase().contains(l));
          score = matchesLang ? 1.0 : 0.85;
        } else {
          score = 1.0;
        }
      } else if (albLower.startsWith('$qLower ') || albLower.startsWith('$qLower-') || albLower.startsWith('$qLower (')) {
        score = (score + 0.35).clamp(0.0, 1.0);
      }
    }

    if (qLower.length <= 3 && stringSim < 0.80) {
      score = score * 0.30;
    }

    if (preferredLanguages != null && preferredLanguages.isNotEmpty) {
      final userLangs = preferredLanguages.map((l) => l.toLowerCase().trim()).toSet();
      final songLang = song.language?.toLowerCase().trim() ?? '';
      if (userLangs.contains(songLang) || userLangs.any((l) => song.title.toLowerCase().contains(l))) {
        score = (score + 0.05).clamp(0.0, 1.0);
      }
    }

    return score.clamp(0.0, 1.0);
  }

  /// Backward-compatible adapter for scoreSong.
  static double scoreSong(
    Song song,
    QueryIntent intent, {
    required List<String> preferredLanguages,
    List<Song>? history,
    List<Song>? favorites,
  }) {
    return calculateCompositeRelevance(
      song,
      intent,
      history: history,
      favorites: favorites,
      preferredLanguages: preferredLanguages,
    );
  }

  /// Deterministic 5-tier ranking comparison.
  static int compareRankedEntries(
    MapEntry<double, Song> a,
    MapEntry<double, Song> b,
    String queryLower, {
    Map<String, int>? arrivalOrder,
    List<String>? preferredLanguages,
  }) {
    final scoreCmp = b.key.compareTo(a.key);
    if (scoreCmp != 0) return scoreCmp;

    final songA = a.value;
    final songB = b.value;

    if (preferredLanguages != null && preferredLanguages.isNotEmpty) {
      final targetLangs = preferredLanguages.map((l) => l.toLowerCase().trim()).toSet();
      final aLang = songA.language?.toLowerCase().trim() ?? '';
      final bLang = songB.language?.toLowerCase().trim() ?? '';
      final aMatch = targetLangs.contains(aLang) || targetLangs.any((l) => songA.title.toLowerCase().contains(l));
      final bMatch = targetLangs.contains(bLang) || targetLangs.any((l) => songB.title.toLowerCase().contains(l));
      if (aMatch != bMatch) return aMatch ? -1 : 1;
    }

    final albA = songA.album.toLowerCase().trim();
    final albB = songB.album.toLowerCase().trim();
    final aAlbumMatch = QueryNormalizer.isAlbumOrMovieEntityMatch(albA, queryLower) ? 1 : 0;
    final bAlbumMatch = QueryNormalizer.isAlbumOrMovieEntityMatch(albB, queryLower) ? 1 : 0;
    if (aAlbumMatch != bAlbumMatch) return bAlbumMatch.compareTo(aAlbumMatch);

    if (aAlbumMatch == 1 && bAlbumMatch == 1 && albA == albB && arrivalOrder != null) {
      final aExact = (songA.title.toLowerCase().trim() == queryLower) ? 1 : 0;
      final bExact = (songB.title.toLowerCase().trim() == queryLower) ? 1 : 0;
      if (aExact != bExact) return bExact.compareTo(aExact);

      final idxA = arrivalOrder[songA.id] ?? 0;
      final idxB = arrivalOrder[songB.id] ?? 0;
      if (idxA != idxB) return idxA.compareTo(idxB);
    }

    final aExact = (songA.title.toLowerCase().trim() == queryLower) ? 1 : 0;
    final bExact = (songB.title.toLowerCase().trim() == queryLower) ? 1 : 0;
    if (aExact != bExact) return bExact.compareTo(aExact);

    bool titleMatches(String title) {
      final t = title.toLowerCase().trim();
      if (t == queryLower || t.contains(queryLower) || queryLower.contains(t)) return true;
      if (t.length >= 3 && queryLower.length >= 3 && (t.length - queryLower.length).abs() <= 2) {
        return BkTree.levenshteinDistance(t, queryLower, maxDistance: 2) <= 2;
      }
      return false;
    }

    final aTitleMatch = titleMatches(songA.title) ? 1 : 0;
    final bTitleMatch = titleMatches(songB.title) ? 1 : 0;
    if (aTitleMatch != bTitleMatch) return bTitleMatch.compareTo(aTitleMatch);

    final aStudio = (songA.source.toLowerCase() == 'saavn') ? 1 : 0;
    final bStudio = (songB.source.toLowerCase() == 'saavn') ? 1 : 0;
    if (aStudio != bStudio) return bStudio.compareTo(aStudio);

    final aArt = songA.hasOfficialAlbumArt ? 1 : 0;
    final bArt = songB.hasOfficialAlbumArt ? 1 : 0;
    if (aArt != bArt) return bArt.compareTo(aArt);

    if (arrivalOrder != null) {
      final idxA = arrivalOrder[songA.id] ?? 0;
      final idxB = arrivalOrder[songB.id] ?? 0;
      if (idxA != idxB) return idxA.compareTo(idxB);
    }

    return songA.id.compareTo(songB.id);
  }

  /// Deduplicates across JioSaavn, YouTube, and Audius, and ranks deterministically.
  static List<Song> deduplicateAndRankUnified({
    required List<Song> saavnSongs,
    required List<Song> ytSongs,
    List<Song> audiusSongs = const [],
    required QueryIntent intent,
    List<String>? preferredLanguages,
    List<Song>? history,
    List<Song>? favorites,
    UserAffinityContext? affinityContext,
  }) {
    final Map<String, Song> canonicalMap = {};
    final Map<String, List<Song>> bucketByCleanKey = {};
    final Set<String> seenIds = {};
    final List<Song> deduplicatedPool = [];

    for (final song in saavnSongs) {
      if (!seenIds.add(song.id)) continue;
      final fp = SearchQueryPlanner.generateCanonicalFingerprint(song.title, song.artist);
      if (fp.isNotEmpty && canonicalMap.containsKey(fp)) continue;

      bool isDup = false;
      if (song.cleanTitleKey.isNotEmpty) {
        final bucket = bucketByCleanKey[song.cleanTitleKey];
        if (bucket != null) {
          for (final existing in bucket) {
            if (song.duration == 0 || existing.duration == 0 || (existing.duration - song.duration).abs() <= 12) {
              isDup = true;
              break;
            }
            if (SearchQueryPlanner.isSameSong(
              titleA: existing.title,
              artistsA: existing.artist,
              titleB: song.title,
              artistsB: song.artist,
            )) {
              isDup = true;
              break;
            }
          }
        }
      }

      if (isDup) continue;

      if (fp.isNotEmpty) canonicalMap[fp] = song;
      if (song.cleanTitleKey.isNotEmpty) {
        (bucketByCleanKey[song.cleanTitleKey] ??= []).add(song);
      }
      deduplicatedPool.add(song);
    }

    for (final ytSong in [...ytSongs, ...audiusSongs]) {
      if (!seenIds.add(ytSong.id)) continue;

      Song? matchedPrimary;
      final fp = SearchQueryPlanner.generateCanonicalFingerprint(ytSong.title, ytSong.artist);
      if (fp.isNotEmpty && canonicalMap.containsKey(fp)) {
        matchedPrimary = canonicalMap[fp];
      }

      if (matchedPrimary == null && ytSong.cleanTitleKey.isNotEmpty) {
        final bucket = bucketByCleanKey[ytSong.cleanTitleKey];
        if (bucket != null) {
          for (final existing in bucket) {
            if (SearchQueryPlanner.isSameSong(
              titleA: existing.title,
              artistsA: existing.artist,
              titleB: ytSong.title,
              artistsB: ytSong.artist,
            )) {
              matchedPrimary = existing;
              break;
            }
          }
        }
      }

      if (matchedPrimary == null && deduplicatedPool.length < 50) {
        for (final existing in deduplicatedPool) {
          if (SearchQueryPlanner.isSameSong(
            titleA: existing.title,
            artistsA: existing.artist,
            titleB: ytSong.title,
            artistsB: ytSong.artist,
          )) {
            matchedPrimary = existing;
            break;
          }
        }
      }

      if (matchedPrimary != null) {
        final existingVersions = List<TrackEntity>.from(matchedPrimary.versions);
        if (!existingVersions.any((v) => v.id == ytSong.id)) {
          existingVersions.add(ytSong);
          final updated = matchedPrimary.copyWith(versions: existingVersions);
          final idx = deduplicatedPool.indexOf(matchedPrimary);
          if (idx != -1) {
            deduplicatedPool[idx] = updated;
          }
          if (fp.isNotEmpty) canonicalMap[fp] = updated;
          if (matchedPrimary.cleanTitleKey.isNotEmpty) {
            final b = bucketByCleanKey[matchedPrimary.cleanTitleKey];
            if (b != null) {
              final bIdx = b.indexOf(matchedPrimary);
              if (bIdx != -1) b[bIdx] = updated;
            }
          }
        }
      } else {
        var processedYt = ytSong;
        if (!processedYt.hasOfficialAlbumArt) {
          final studioCover = CatalogDatabase.getSongCoverArt(
            processedYt.title,
            artist: processedYt.artist,
            album: processedYt.album,
          );
          if (studioCover != null && studioCover.isNotEmpty) {
            processedYt = processedYt.copyWith(coverUrl: studioCover);
          }
        }
        if (fp.isNotEmpty) canonicalMap[fp] = processedYt;
        if (processedYt.cleanTitleKey.isNotEmpty) {
          (bucketByCleanKey[processedYt.cleanTitleKey] ??= []).add(processedYt);
        }
        deduplicatedPool.add(processedYt);
      }
    }

    final effAffinityContext = affinityContext ?? UserAffinityContext.fromSongs(
      favorites: favorites,
      history: history,
    );

    final cleanQuery = intent.cleanQuery.toLowerCase();
    final targetLangs = (preferredLanguages != null && preferredLanguages.isNotEmpty)
        ? preferredLanguages.map((l) => l.toLowerCase().trim()).toSet()
        : null;

    final sortKeys = <RankSortKey>[];
    for (int i = 0; i < deduplicatedPool.length; i++) {
      final song = deduplicatedPool[i];
      final score = calculateCompositeRelevance(
        song,
        intent,
        history: history,
        favorites: favorites,
        preferredLanguages: preferredLanguages,
        affinityContext: effAffinityContext,
      );
      if (score <= 0.0) continue;

      int langMatch = 0;
      if (targetLangs != null) {
        final aLang = song.language?.toLowerCase().trim() ?? '';
        if (targetLangs.contains(aLang) || targetLangs.any((l) => song.title.toLowerCase().contains(l))) {
          langMatch = 1;
        }
      }

      final albLower = song.album.toLowerCase().trim();
      final albumMatch = QueryNormalizer.isAlbumOrMovieEntityMatch(albLower, cleanQuery) ? 1 : 0;
      final exactMatch = (song.title.toLowerCase().trim() == cleanQuery) ? 1 : 0;

      final t = song.title.toLowerCase().trim();
      int titleMatch = 0;
      if (t == cleanQuery || t.contains(cleanQuery) || cleanQuery.contains(t)) {
        titleMatch = 1;
      } else if (t.length >= 3 && cleanQuery.length >= 3 && (t.length - cleanQuery.length).abs() <= 2) {
        if (BkTree.levenshteinDistance(t, cleanQuery, maxDistance: 2) <= 2) {
          titleMatch = 1;
        }
      }

      sortKeys.add(RankSortKey(
        score: score,
        langMatch: langMatch,
        albumMatch: albumMatch,
        exactMatch: exactMatch,
        titleMatch: titleMatch,
        isStudio: (song.source.toLowerCase() == 'saavn') ? 1 : 0,
        hasArt: song.hasOfficialAlbumArt ? 1 : 0,
        arrivalIdx: i,
        albLower: albLower,
        song: song,
      ));
    }

    sortKeys.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;

      if (a.langMatch != b.langMatch) return b.langMatch.compareTo(a.langMatch);
      if (a.albumMatch != b.albumMatch) return b.albumMatch.compareTo(a.albumMatch);

      if (a.albumMatch == 1 && b.albumMatch == 1 && a.albLower == b.albLower) {
        if (a.exactMatch != b.exactMatch) return b.exactMatch.compareTo(a.exactMatch);
        if (a.arrivalIdx != b.arrivalIdx) return a.arrivalIdx.compareTo(b.arrivalIdx);
      }

      if (a.exactMatch != b.exactMatch) return b.exactMatch.compareTo(a.exactMatch);
      if (a.titleMatch != b.titleMatch) return b.titleMatch.compareTo(a.titleMatch);
      if (a.isStudio != b.isStudio) return b.isStudio.compareTo(a.isStudio);
      if (a.hasArt != b.hasArt) return b.hasArt.compareTo(a.hasArt);
      return a.arrivalIdx.compareTo(b.arrivalIdx);
    });

    return sortKeys.map((k) => k.song).toList();
  }

  /// Interleaves primary (JioSaavn) and secondary (YouTube) search candidates.
  static List<Song> interleaveRankedResults(
    List<Song> primarySongs,
    List<Song> secondarySongs,
  ) {
    if (primarySongs.isEmpty) return secondarySongs;
    if (secondarySongs.isEmpty) return primarySongs;

    final List<Song> merged = [];
    final Set<String> seenKeys = {};

    for (final song in primarySongs) {
      final key = song.cleanTitleKey;
      if (key.isNotEmpty) seenKeys.add(key);
    }

    final List<Song> distinctSecondary = [];
    for (final song in secondarySongs) {
      final key = song.cleanTitleKey;
      if (key.isEmpty || !seenKeys.contains(key)) {
        if (key.isNotEmpty) seenKeys.add(key);
        distinctSecondary.add(song);
      }
    }

    int primIdx = 0;
    int secIdx = 0;

    while (primIdx < primarySongs.length || secIdx < distinctSecondary.length) {
      for (int i = 0; i < 2 && primIdx < primarySongs.length; i++) {
        merged.add(primarySongs[primIdx++]);
      }
      if (secIdx < distinctSecondary.length) {
        merged.add(distinctSecondary[secIdx++]);
      }
    }

    return merged;
  }
}
