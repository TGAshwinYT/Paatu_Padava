part of '../spotify_import_service.dart';

Future<Song?> _matchSingleTrackImpl(
  SpotifyTrackItem track, {
  String? preferredLanguage,
}) async {
  final cleanTitle = SpotifyImportService.cleanTrackTitle(track.title);
  final primaryArtist = SpotifyImportService.cleanArtistName(track.artist);
  final movieHint = SpotifyImportService.extractMovieFromTitle(track.title);
  final targetAlbum = track.album ?? movieHint;

  String? effectiveCover = track.coverUrl;
  if (effectiveCover != null && CoverArtResolver.isSpotifyCover(effectiveCover)) {
    effectiveCover = CoverArtResolver.upgradeSpotifyCover(effectiveCover);
  }
  if ((effectiveCover == null || effectiveCover.isEmpty || CoverArtResolver.isPlaylistCover(effectiveCover)) &&
      (track.spotifyId != null || track.spotifyUri != null)) {
    final idToResolve = track.spotifyId ?? track.spotifyUri!;
    effectiveCover = await SpotifyImportService.resolveSpotifyTrackThumbnail(idToResolve);
  }

  try {
    final localCandidates = await CatalogDatabase.searchCatalog(cleanTitle, limit: 5);
    for (final candidate in localCandidates) {
      if (SpotifyImportService._isUnwantedType(candidate.title, cleanTitle)) continue;
      final cCleanTitle = SpotifyImportService.cleanTrackTitle(candidate.title);
      final titleSim = SpotifyImportService.computeTitleSimilarity(cleanTitle, cCleanTitle);
      if (titleSim >= 85) {
        var matched = candidate;
        if (effectiveCover != null &&
            effectiveCover.isNotEmpty &&
            !CoverArtResolver.isPlaylistCover(effectiveCover)) {
          matched = matched.copyWith(coverUrl: effectiveCover);
        }
        return matched;
      }
    }
  } catch (e) {
    AppLogger.debug('SpotifyImportService', 'Handled exception: $e');
  }

  try {
    final List<Song> candidates = [];
    final Set<String> seenIds = {};

    void addCandidates(List<Song> songs) {
      for (final s in songs) {
        if (s.id.isNotEmpty && seenIds.add(s.id)) candidates.add(s);
      }
    }

    addCandidates(await SaavnClient.search('$cleanTitle $primaryArtist', limit: 6));

    final altTitle = SpotifyImportService.getPhoneticVariant(cleanTitle);
    if (altTitle != null && altTitle.toLowerCase() != cleanTitle.toLowerCase()) {
      addCandidates(await SaavnClient.search('$altTitle $primaryArtist', limit: 6));
    }

    bool hasConfidentMatch = candidates.any((c) =>
        !SpotifyImportService._isUnwantedType(c.title, cleanTitle) &&
        SpotifyImportService.scoreCandidate(target: track, candidate: c, movieHint: movieHint) >= 85);

    if (!hasConfidentMatch && targetAlbum != null && targetAlbum.trim().isNotEmpty) {
      final cleanAlb = SpotifyImportService.cleanTrackTitle(targetAlbum);
      if (cleanAlb.isNotEmpty && !cleanAlb.toLowerCase().contains(cleanTitle.toLowerCase())) {
        addCandidates(await SaavnClient.search('$cleanAlb $cleanTitle', limit: 6));
      }
    }

    hasConfidentMatch = candidates.any((c) =>
        !SpotifyImportService._isUnwantedType(c.title, cleanTitle) &&
        SpotifyImportService.scoreCandidate(target: track, candidate: c, movieHint: movieHint) >= 85);

    if (!hasConfidentMatch) {
      addCandidates(await SaavnClient.search(cleanTitle, limit: 6));
    }

    final List<MapEntry<Song, int>> scored = [];
    for (final candidate in candidates) {
      if (SpotifyImportService._isUnwantedType(candidate.title, cleanTitle)) continue;
      final score = SpotifyImportService.scoreCandidate(target: track, candidate: candidate, movieHint: movieHint);
      if (score >= 70) scored.add(MapEntry(candidate, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));

    for (final entry in scored) {
      var cand = entry.key;
      if (cand.streamUrl != null && cand.streamUrl!.isNotEmpty) {
        final isHealthy = await SpotifyImportService.isStreamPlayable(cand.streamUrl);
        if (!isHealthy) continue;
      }

      if (effectiveCover != null &&
          effectiveCover.isNotEmpty &&
          !CoverArtResolver.isPlaylistCover(effectiveCover)) {
        cand = cand.copyWith(coverUrl: effectiveCover);
      } else if (cand.coverUrl.isEmpty || CoverArtResolver.isPlaylistCover(cand.coverUrl)) {
        try {
          final resolved = await CoverArtResolver.resolveCover(cand).timeout(
            const Duration(milliseconds: 1200),
            onTimeout: () => cand.coverUrl,
          );
          if (resolved.isNotEmpty && !CoverArtResolver.isPlaylistCover(resolved)) {
            cand = cand.copyWith(coverUrl: resolved);
          }
        } catch (e) {
          AppLogger.debug('SpotifyImportService', 'Handled exception: $e');
        }
      }
      return cand;
    }
  } catch (e) {
    AppLogger.log('SpotifyImportService', 'Saavn match search notice: $e');
  }

  try {
    final ytResults = await YouTubeClient.search('$cleanTitle $primaryArtist audio', limit: 6);
    final List<MapEntry<Song, int>> scoredYt = [];
    for (final candidate in ytResults) {
      if (SpotifyImportService._isUnwantedType(candidate.title, cleanTitle)) continue;
      final score = SpotifyImportService.scoreCandidate(target: track, candidate: candidate, movieHint: movieHint);
      if (score >= 65) scoredYt.add(MapEntry(candidate, score));
    }
    scoredYt.sort((a, b) => b.value.compareTo(a.value));

    if (scoredYt.isNotEmpty) {
      var bestYt = scoredYt.first.key;
      if (effectiveCover != null &&
          effectiveCover.isNotEmpty &&
          !CoverArtResolver.isPlaylistCover(effectiveCover)) {
        bestYt = bestYt.copyWith(coverUrl: effectiveCover);
      } else {
        try {
          final resolved = await CoverArtResolver.resolveCover(bestYt).timeout(
            const Duration(milliseconds: 1200),
            onTimeout: () => bestYt.coverUrl,
          );
          if (resolved.isNotEmpty && !CoverArtResolver.isPlaylistCover(resolved)) {
            bestYt = bestYt.copyWith(coverUrl: resolved);
          }
        } catch (e) {
          AppLogger.debug('SpotifyImportService', 'Handled exception: $e');
        }
      }
      return bestYt;
    }

    if (ytResults.isNotEmpty) {
      return SpotifyImportService._synthesizeTrack(
        track,
        effectiveCover: effectiveCover,
        fallbackCandidate: ytResults.first,
      );
    }
  } catch (e) {
    AppLogger.log('SpotifyImportService', 'YouTube match search notice: $e');
  }

  return SpotifyImportService._synthesizeTrack(track, effectiveCover: effectiveCover);
}
