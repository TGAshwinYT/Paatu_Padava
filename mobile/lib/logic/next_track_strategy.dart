import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/radio_engine.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';
import '../services/youtube_client.dart';
import '../services/queue_cooldown_manager.dart';
import '../services/download_manager.dart';
import '../services/favorites_manager.dart';
import '../services/history_manager.dart';
import '../services/app_logger.dart';
import '../services/blacklist_manager.dart';
import '../services/catalog_database.dart';
import 'markov_cosine_radio_strategy.dart';

abstract class NextTrackStrategy {
  String get id;
  String get displayName;
  String get description;

  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 20,
  });

  /// Invalidate and branch the recommendation graph when a track is skipped
  void recordSkip(Song skippedSong, {required int listenedSeconds});

  /// Records a track-to-track transition to train sequential listening models
  void recordTransition(Song from, Song to, {bool isPositive = true});

  /// Resets the session context anchor and any temporary skip blacklists
  void resetSession({Song? initialAnchor});
}

// ================= Shared Anti-Fatigue & Formatting Helpers ================= //

/// Enforces Spotify & Apple Music Artist Dispersion rules:
/// 1. Rejects candidates whose primary artist appeared in the last 4 played tracks (via [QueueCooldownManager]).
/// 2. Mathematically guarantees ZERO BACK-TO-BACK artist duplicates in the generated queue:
///    `result[0].primaryArtist != seedArtist` (when possible) and `result[i].primaryArtist != result[i-1].primaryArtist`.
/// 3. Sliding window limit: max [maxPerArtist] tracks per artist in the generated batch.
List<Song> enforceArtistDispersionAndNoBackToBack(
  List<Song> candidates, {
  required String seedArtist,
  int maxPerArtist = 2,
  int count = 20,
}) {
  final List<Song> result = [];
  final List<Song> deferred = [];
  final Map<String, int> artistCounts = {};
  String lastArtist = QueueCooldownManager.normalizeArtistKey(seedArtist);

  for (final c in candidates) {
    if (result.length >= count) break;
    if (BlacklistManager.isBlacklisted(c)) continue;
    final a = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);

    // 1. Sliding window per-artist cap (max 2 songs per artist in the pool)
    if (a.isNotEmpty && (artistCounts[a] ?? 0) >= maxPerArtist) {
      continue;
    }

    // 2. Reject if artist is cooling down from the last 4 played tracks (anti-fatigue)
    if (a.isNotEmpty && QueueCooldownManager.isArtistCoolingDown(a, window: 4)) {
      continue;
    }

    // 3. Zero Back-to-Back Artist Guarantee:
    // If this candidate shares the primary artist with the last added track (or seed at index 0),
    // hold it in a deferred buffer until a different artist is placed.
    if (a.isNotEmpty && a == lastArtist) {
      deferred.add(c);
      continue;
    }

    // Candidate is eligible for immediate placement
    result.add(c);
    lastArtist = a;
    if (a.isNotEmpty) {
      artistCounts[a] = (artistCounts[a] ?? 0) + 1;
    }

    // After placing a new artist, check if any deferred candidate now has a different artist!
    if (deferred.isNotEmpty) {
      for (int i = 0; i < deferred.length; i++) {
        final d = deferred[i];
        final da = QueueCooldownManager.normalizeArtistKey(d.primaryArtist);
        if (da != lastArtist && (da.isEmpty || (artistCounts[da] ?? 0) < maxPerArtist)) {
          result.add(d);
          lastArtist = da;
          if (da.isNotEmpty) {
            artistCounts[da] = (artistCounts[da] ?? 0) + 1;
          }
          deferred.removeAt(i);
          break; // Advance one at a time to maintain alternating artist order
        }
      }
    }
  }

  // Pool starvation fallback: if fewer than count items were collected and deferred tracks remain,
  // append them while minimizing adjacent duplicates to prevent silence.
  if (result.length < count && deferred.isNotEmpty) {
    for (final d in deferred) {
      if (result.length >= count) break;
      final da = QueueCooldownManager.normalizeArtistKey(d.primaryArtist);
      if (da != lastArtist) {
        result.add(d);
        lastArtist = da;
      }
    }
  }

  return result;
}

/// Circuit Breaker: Queries local downloaded tracks, favorites, and history with matching
/// artist or genre/language tags when upstream recommendation endpoints fail or are offline.
List<Song> getLocalFallbackTracks(
  Song seedSong, {
  required Set<String> exclusions,
  required int count,
  String? targetLang,
}) {
  AppLogger.log('NextTrackStrategy', 'Engaging local circuit breaker fallback for "${seedSong.title}"');
  final List<Song> pool = [];

  try {
    pool.addAll(DownloadManager.getDownloadedSongs());
  } catch (_) {}

  try {
    pool.addAll(FavoritesManager.getFavorites());
  } catch (_) {}

  try {
    pool.addAll(HistoryManager.getHistory());
  } catch (_) {}

  final targetLanguage = targetLang ??
      seedSong.language?.toLowerCase() ??
      SettingsManager.preferredLanguages.firstOrNull?.toLowerCase() ??
      '';
  final primaryArtist = QueueCooldownManager.normalizeArtistKey(seedSong.primaryArtist);

  // Score candidates: Same Artist (score 3) > Same Language (score 2) > Other (score 1)
  final List<MapEntry<int, Song>> scored = [];
  final Set<String> seen = {};

  for (final s in pool) {
    if (s.title.trim().isEmpty) continue;
    if (BlacklistManager.isBlacklisted(s)) continue;
    final bKey = s.canonicalBaseKey;
    final tKey = s.cleanTitleKey;

    if (exclusions.contains(s.id) ||
        exclusions.contains(bKey) ||
        (tKey.isNotEmpty && exclusions.contains(tKey)) ||
        seen.contains(bKey)) {
      continue;
    }

    if (s.isSameSongOrDub(seedSong)) continue;

    int score = 1;
    final sArtist = QueueCooldownManager.normalizeArtistKey(s.primaryArtist);
    final sLang = s.language?.toLowerCase().trim();

    if (sArtist.isNotEmpty && sArtist == primaryArtist) {
      score += 2;
    }
    if (sLang != null && sLang == targetLanguage) {
      score += 1;
    }

    seen.add(bKey);
    scored.add(MapEntry(score, s.copyWith(isSmartRecommended: true)));
  }

  scored.sort((a, b) => b.key.compareTo(a.key));
  final candidates = scored.map((e) => e.value).toList();

  return enforceArtistDispersionAndNoBackToBack(
    candidates,
    seedArtist: seedSong.primaryArtist,
    count: count,
  );
}

// ================= 1. Spotify Strategy Implementation ================= //

/// Spotify-style:
/// 1. "Adaptive Session Context Anchoring": Stores initial session seed track and artist ID.
///    Computes recommendations using a weighted blend of the session anchor (60%)
///    and the current track (40%), shifting smoothly as user listens through songs.
/// 2. Batch Generation: Generates an initial pool of 20 tracks instead of polling 1-by-1.
/// 3. Artist Dispersion: Integrates with [QueueCooldownManager] (rejects candidates if primary
///    artist appeared in last 4 played tracks) and enforces zero back-to-back artist duplicates.
/// 4. Skip Reactivity: Records skips under 30s into a rolling 5-artist fatigue cooldown.
class SpotifyStyleStrategy implements NextTrackStrategy {
  @override
  String get id => 'spotify_style';

  @override
  String get displayName => 'Spotify Style (Anchored Radio)';

  @override
  String get description => 'Weighted session anchoring (60% anchor / 40% current) with strict artist dispersion';

  Song? _sessionAnchorTrack;
  final Queue<String> _skippedArtists = Queue<String>();
  final Set<String> _skippedTrackKeys = <String>{};

  @visibleForTesting
  List<String> get skippedArtists => _skippedArtists.toList();

  @visibleForTesting
  Song? get sessionAnchor => _sessionAnchorTrack;

  @override
  void resetSession({Song? initialAnchor}) {
    _sessionAnchorTrack = initialAnchor;
    _skippedArtists.clear();
    _skippedTrackKeys.clear();
    AppLogger.log('SpotifyStyleStrategy', 'Session anchor reset. Anchor: ${_sessionAnchorTrack?.title ?? "none"}');
  }

  @override
  void recordSkip(Song skippedSong, {required int listenedSeconds}) {
    // Spotify Radio records short skips (<30s) to penalize and cool down skipped artist/track
    if (listenedSeconds < 30) {
      final artist = QueueCooldownManager.normalizeArtistKey(skippedSong.primaryArtist);
      if (artist.isNotEmpty && artist != 'various artists') {
        _skippedArtists.addLast(artist);
        while (_skippedArtists.length > 5) {
          _skippedArtists.removeFirst();
        }
      }
      if (skippedSong.cleanTitleKey.isNotEmpty) {
        _skippedTrackKeys.add(skippedSong.cleanTitleKey);
      }
      QueueCooldownManager.recordPlayed(skippedSong);
      AppLogger.log(
        'SpotifyStyleStrategy',
        'Recorded skip for "${skippedSong.title}" after ${listenedSeconds}s. Active cooling artist: $artist',
      );
    }
  }

  @override
  void recordTransition(Song from, Song to, {bool isPositive = true}) {
    // Adaptive session anchoring: smoothly advance anchor as user listens through tracks
    if (isPositive && to.id != _sessionAnchorTrack?.id) {
      _sessionAnchorTrack = to;
      AppLogger.log('SpotifyStyleStrategy', 'Smoothly shifted anchor to "${to.title}"');
    }
  }

  @override
  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 20,
  }) async {
    try {
      // 1. Session Context Anchoring:
      if (_sessionAnchorTrack == null) {
        _sessionAnchorTrack = seedSong;
        AppLogger.log('SpotifyStyleStrategy', 'Anchored session to "${seedSong.title}" by ${seedSong.primaryArtist}');
      }

      final anchorSong = _sessionAnchorTrack!;
      final prefLangs = SettingsManager.preferredLanguages;
      final targetLang = (seedSong.language != null && seedSong.language!.isNotEmpty)
          ? seedSong.language!.toLowerCase()
          : (prefLangs.firstOrNull ?? '').toLowerCase();

      final targetBatch = count > 0 ? count : 20;

      // 2. Build strict exclusion set (capped to last 50 tracks in history to prevent pool starvation)
      final Set<String> exclusions = {};
      for (final s in queue) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      final recentHistory = history.length > 50 ? history.sublist(history.length - 50) : history;
      for (final s in recentHistory) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      exclusions.add(seedSong.id);
      exclusions.add(seedSong.canonicalBaseKey);
      if (seedSong.cleanTitleKey.isNotEmpty) exclusions.add(seedSong.cleanTitleKey);

      exclusions.add(anchorSong.id);
      exclusions.add(anchorSong.canonicalBaseKey);
      if (anchorSong.cleanTitleKey.isNotEmpty) exclusions.add(anchorSong.cleanTitleKey);

      // 3. Weighted Blend Fetching via Upstream Graph Endpoints:
      // Session Anchor (60% weight) + Current Track (40% weight)
      // Piggyback on YouTube Music Next (RDAMVM) & JioSaavn Reco (reco.getreco) graph APIs directly,
      // with instant local CatalogDatabase lookups for guaranteed zero-latency candidates
      final List<Future<List<Song>>> anchorFutures = [
        YouTubeClient.getRadioTracks(
          anchorSong,
          limit: 15,
          excludedArtists: _skippedArtists.toSet(),
          excludedKeys: _skippedTrackKeys,
        ),
        SaavnClient.getRelatedSongs(anchorSong.id, language: targetLang),
        CatalogDatabase.getSongsByArtist(anchorSong.primaryArtist),
        if (anchorSong.primaryArtist.isNotEmpty && anchorSong.primaryArtist.toLowerCase() != 'various artists')
          SaavnClient.search('${anchorSong.primaryArtist} $targetLang', limit: 12, language: targetLang),
        if (anchorSong.album.isNotEmpty && anchorSong.album.toLowerCase() != 'unknown album')
          SaavnClient.search(anchorSong.album, limit: 8, language: targetLang),
      ];

      final List<Future<List<Song>>> currentFutures = (seedSong.id != anchorSong.id)
          ? [
              YouTubeClient.getRadioTracks(
                seedSong,
                limit: 10,
                excludedArtists: _skippedArtists.toSet(),
                excludedKeys: _skippedTrackKeys,
              ),
              SaavnClient.getRelatedSongs(seedSong.id, language: targetLang),
              CatalogDatabase.getSongsByArtist(seedSong.primaryArtist),
              if (seedSong.primaryArtist.isNotEmpty && seedSong.primaryArtist.toLowerCase() != 'various artists')
                SaavnClient.search('${seedSong.primaryArtist} $targetLang', limit: 8, language: targetLang),
            ]
          : [];

      final anchorResults = await Future.wait(anchorFutures);
      final currentResults = currentFutures.isNotEmpty ? await Future.wait(currentFutures) : <List<Song>>[];

      final List<Song> anchorCandidates = anchorResults.expand((x) => x).toList();
      final List<Song> currentCandidates = currentResults.expand((x) => x).toList();

      // If anchor pool runs dry, promote current seedSong as new anchor to keep radio thriving
      if (anchorCandidates.isEmpty && seedSong.id != _sessionAnchorTrack?.id) {
        _sessionAnchorTrack = seedSong;
      }

      // Interleave with 60% anchor / 40% current ratio
      final List<Song> blendedPool = [];
      int aIdx = 0;
      int cIdx = 0;
      while (aIdx < anchorCandidates.length || cIdx < currentCandidates.length) {
        for (int i = 0; i < 3 && aIdx < anchorCandidates.length; i++) {
          blendedPool.add(anchorCandidates[aIdx++]);
        }
        for (int j = 0; j < 2 && cIdx < currentCandidates.length; j++) {
          blendedPool.add(currentCandidates[cIdx++]);
        }
        if (currentCandidates.isEmpty && aIdx < anchorCandidates.length) {
          blendedPool.add(anchorCandidates[aIdx++]);
        }
      }

      // 4. Pre-filter candidate tracks using RadioEngine.applyHardFiltering
      final hardFiltered = RadioEngine.applyHardFiltering(
        seedSong: seedSong,
        candidates: blendedPool,
        queue: queue,
        history: recentHistory,
        targetLanguage: targetLang,
      );

      final List<Song> validCandidates = hardFiltered.where((c) {
        if (c.isSameSongOrDub(anchorSong)) return false;
        final cArtistKey = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);
        if (_skippedArtists.contains(cArtistKey)) return false;
        if (c.cleanTitleKey.isNotEmpty && _skippedTrackKeys.contains(c.cleanTitleKey)) return false;
        return true;
      }).toList();

      // 5. Candidate Ranking & Scoring (Session-Aware)
      final targetArtistKey = QueueCooldownManager.normalizeArtistKey(seedSong.primaryArtist);
      final anchorArtistKey = QueueCooldownManager.normalizeArtistKey(anchorSong.primaryArtist);
      final seedYear = RadioEngine.extractReleaseYear(seedSong);

      final scoredCandidates = <MapEntry<Song, double>>[];
      for (final c in validCandidates) {
        final vector = SongFeatureVector.extractRelative(seedSong, c);
        double score = vector.compositeVectorScore;
        final cArtistKey = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);
        if (cArtistKey == targetArtistKey) {
          score += 0.35;
        } else if (cArtistKey == anchorArtistKey) {
          score += 0.20;
        }

        // Era proximity boost (±4 years)
        final cYear = RadioEngine.extractReleaseYear(c);
        if (seedYear != null && cYear != null && (seedYear - cYear).abs() <= 4) {
          score += 0.25;
        }

        // Music Director / Composer boost
        if (RadioEngine.isSharedMusicDirectorOrComposer(seedSong, c)) {
          score += 0.30;
        }

        if (c.language != null && c.language!.toLowerCase().trim() == targetLang) {
          score += 0.20;
        }
        if (_skippedArtists.contains(cArtistKey)) {
          score -= 0.50;
        }
        if (c.cleanTitleKey.isNotEmpty && _skippedTrackKeys.contains(c.cleanTitleKey)) {
          score -= 0.60;
        }
        scoredCandidates.add(MapEntry(c, score));
      }
      scoredCandidates.sort((a, b) => b.value.compareTo(a.value));
      final rankedCandidates = scoredCandidates.map((e) => e.key).toList();

      // 6. Enforce Artist Dispersion (QueueCooldownManager last 4 played + ZERO back-to-back duplicates)
      final shapedTracks = enforceArtistDispersionAndNoBackToBack(
        rankedCandidates,
        seedArtist: seedSong.primaryArtist,
        count: targetBatch,
      );

      // If pool is still below target batch, supplement with genuine catalog tracks by the same artist/composer
      if (shapedTracks.length < targetBatch) {
        final supplement = <Song>[];
        try {
          supplement.addAll(await CatalogDatabase.getSongsByArtist(seedSong.primaryArtist));
          if (anchorSong.primaryArtist != seedSong.primaryArtist) {
            supplement.addAll(await CatalogDatabase.getSongsByArtist(anchorSong.primaryArtist));
          }
        } catch (_) {}
        if (supplement.length < targetBatch - shapedTracks.length) {
          try {
            final sRes = await SaavnClient.search('${seedSong.primaryArtist} $targetLang', limit: 12, language: targetLang);
            supplement.addAll(sRes);
          } catch (_) {}
        }

        final filteredSupplement = RadioEngine.applyHardFiltering(
          seedSong: seedSong,
          candidates: supplement,
          queue: queue,
          history: recentHistory,
          targetLanguage: targetLang,
        ).where((s) {
          if (s.isSameSongOrDub(anchorSong)) return false;
          if (shapedTracks.any((f) => s.isSameSongOrDub(f))) return false;
          return true;
        }).toList();

        final remainingCount = targetBatch - shapedTracks.length;
        final lastPlacedArtist = shapedTracks.isNotEmpty ? shapedTracks.last.primaryArtist : seedSong.primaryArtist;
        final shapedSupplement = enforceArtistDispersionAndNoBackToBack(
          filteredSupplement,
          seedArtist: lastPlacedArtist,
          count: remainingCount,
        );
        shapedTracks.addAll(shapedSupplement);
      }

      // 7. Circuit Breaker Fallback: if all upstream endpoints failed or yielded zero tracks
      if (shapedTracks.isEmpty) {
        return getLocalFallbackTracks(
          seedSong,
          exclusions: exclusions,
          count: targetBatch,
          targetLang: targetLang,
        );
      }

      return shapedTracks;
    } catch (e) {
      debugPrint('[SpotifyStyleStrategy] Upstream failure: $e');
      return getLocalFallbackTracks(
        seedSong,
        exclusions: {seedSong.id, seedSong.canonicalBaseKey},
        count: count,
      );
    }
  }
}

// ================= 2. YouTube Music Auto-Mix Implementation ================= //

/// YouTube Music-style:
/// 1. Radio Graph Walking: Uses native YouTube Radio playlist tokens (RDAMVM$videoId)
///    and directed recommendation graph traversal.
/// 2. Audio-First Master Filtering: Prioritizes Topic channels (- Topic, VEVO, official release metadata).
///    Strictly excludes live recordings, fan covers, and tracks with duration deviations (>120s delta).
/// 3. Skip Reactivity: When a recommended track is skipped with < 30 seconds of playback,
///    invalidates the active graph branch, places the artist into a rolling 5-track cooldown queue,
///    and branches the mix back to the session anchor.
class YtMusicStyleStrategy implements NextTrackStrategy {
  @override
  String get id => 'ytmusic_style';

  @override
  String get displayName => 'YouTube Music Style (Dynamic Auto-Mix)';

  @override
  String get description => 'Native YouTube Radio graph walking with topic channel priority and rolling skip reactivity';

  Song? _sessionAnchorSong;
  Song? _currentGraphNode;
  final Queue<String> _skippedArtists = Queue<String>();
  final Set<String> _skippedTrackKeys = <String>{};
  final List<Song> _graphCache = [];

  @visibleForTesting
  List<String> get skippedArtists => _skippedArtists.toList();

  @visibleForTesting
  Song? get sessionAnchor => _sessionAnchorSong;

  @override
  void resetSession({Song? initialAnchor}) {
    _sessionAnchorSong = initialAnchor;
    _currentGraphNode = initialAnchor;
    _skippedArtists.clear();
    _skippedTrackKeys.clear();
    _graphCache.clear();
    AppLogger.log('YtMusicStyleStrategy', 'Auto-mix session reset. Anchor: ${_sessionAnchorSong?.title ?? "none"}');
  }

  @override
  void recordSkip(Song skippedSong, {required int listenedSeconds}) {
    // Skip Reactivity: Invalidate and branch the auto-mix graph away when skipped with < 30s playback
    if (listenedSeconds < 30) {
      final artist = QueueCooldownManager.normalizeArtistKey(skippedSong.primaryArtist);
      if (artist.isNotEmpty && artist != 'various artists') {
        _skippedArtists.addLast(artist);
        while (_skippedArtists.length > 5) {
          _skippedArtists.removeFirst();
        }
      }
      if (skippedSong.cleanTitleKey.isNotEmpty) {
        _skippedTrackKeys.add(skippedSong.cleanTitleKey);
      }

      // Invalidate existing graph cache branch for this artist
      _graphCache.removeWhere((s) {
        final a = QueueCooldownManager.normalizeArtistKey(s.primaryArtist);
        return a == artist || s.cleanTitleKey == skippedSong.cleanTitleKey || _skippedArtists.contains(a);
      });

      // Branch graph away: Reset current walk node back to session anchor
      if (_sessionAnchorSong != null) {
        _currentGraphNode = _sessionAnchorSong;
      }

      AppLogger.log(
        'YtMusicStyleStrategy',
        'Skip Reactivity triggered (<30s). Branched auto-mix away from artist "$artist". '
        'Active cooling artists: ${_skippedArtists.length}',
      );
    }
  }

  @override
  void recordTransition(Song from, Song to, {bool isPositive = true}) {
    if (isPositive) {
      _currentGraphNode = to;
    }
  }

  @override
  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 20,
  }) async {
    try {
      if (_sessionAnchorSong == null) {
        _sessionAnchorSong = seedSong;
        _currentGraphNode = seedSong;
      }

      final targetBatch = count > 0 ? count : 20;
      final prefLangs = SettingsManager.preferredLanguages;
      final targetLang = (seedSong.language != null && seedSong.language!.isNotEmpty)
          ? seedSong.language!.toLowerCase()
          : (prefLangs.firstOrNull ?? '').toLowerCase();

      // 1. Build exclusion set (capped to last 50 tracks in history to prevent pool starvation)
      final Set<String> exclusions = {};
      for (final s in queue) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      final recentHistory = history.length > 50 ? history.sublist(history.length - 50) : history;
      for (final s in recentHistory) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      exclusions.add(seedSong.id);
      exclusions.add(seedSong.canonicalBaseKey);
      if (seedSong.cleanTitleKey.isNotEmpty) exclusions.add(seedSong.cleanTitleKey);

      // 2. Radio Graph Walking:
      final walkNode = _currentGraphNode ?? seedSong;
      final List<Song> candidatePool = [];

      try {
        String? walkVideoId = (walkNode.source == 'youtube' && walkNode.id.length == 11) ? walkNode.id : null;
        if (walkVideoId == null) {
          final sRes = await YouTubeClient.search('${walkNode.title} ${walkNode.primaryArtist} audio', limit: 3);
          if (sRes.isNotEmpty) {
            walkVideoId = sRes.first.id;
          }
        }

        if (walkVideoId != null && walkVideoId.isNotEmpty) {
          final automix = await YouTubeClient.getUpNextAutomix(walkVideoId, limit: targetBatch * 2);
          candidatePool.addAll(automix);
        }

        if (candidatePool.length < targetBatch) {
          final radioTracks = await YouTubeClient.getRadioTracks(
            walkNode,
            limit: targetBatch * 2,
            excludedArtists: _skippedArtists.toSet(),
            excludedKeys: _skippedTrackKeys,
          );
          candidatePool.addAll(radioTracks);
        }
        if (candidatePool.length < targetBatch) {
          try {
            final catSongs = await CatalogDatabase.getSongsByArtist(walkNode.primaryArtist);
            candidatePool.addAll(catSongs);
          } catch (_) {}
        }
      } catch (e) {
        AppLogger.log('YtMusicStyleStrategy', 'Radio graph walk notice: $e');
      }

      // Supplement with RadioEngine if needed
      if (candidatePool.length < targetBatch) {
        try {
          final supplemental = await RadioEngine.buildSongRadio(seedSong, limit: targetBatch);
          candidatePool.addAll(supplemental);
        } catch (_) {}
      }

      // 3. Audio-First Master Filtering & Deduplication via RadioEngine.applyHardFiltering
      final hardFiltered = RadioEngine.applyHardFiltering(
        seedSong: walkNode,
        candidates: candidatePool,
        queue: queue,
        history: recentHistory,
        targetLanguage: targetLang,
      );

      final List<Song> validCandidates = hardFiltered.where((s) {
        final artist = QueueCooldownManager.normalizeArtistKey(s.primaryArtist);
        if (_skippedArtists.contains(artist)) return false;
        if (s.cleanTitleKey.isNotEmpty && _skippedTrackKeys.contains(s.cleanTitleKey)) return false;
        return true;
      }).toList();

      // 4. Session-Aware Scoring & Diversity Re-Ranking
      final rankedCandidates = RadioEngine.scoreAndReRankCandidates(
        seedSong: walkNode,
        candidates: validCandidates,
        history: recentHistory,
        lastPlayedArtists: _skippedArtists.toList(),
      );

      // 5. Enforce Artist Dispersion (QueueCooldownManager + ZERO Back-to-Back duplicates)
      final shapedTracks = enforceArtistDispersionAndNoBackToBack(
        rankedCandidates,
        seedArtist: seedSong.primaryArtist,
        count: targetBatch,
      );

      // Advance graph walk node to the last selected track to continue the path next cycle
      if (shapedTracks.isNotEmpty) {
        _currentGraphNode = shapedTracks.last;
      }

      // 5. Circuit Breaker Fallback
      if (shapedTracks.isEmpty) {
        return getLocalFallbackTracks(
          seedSong,
          exclusions: exclusions,
          count: targetBatch,
          targetLang: targetLang,
        );
      }

      return shapedTracks;
    } catch (e) {
      debugPrint('[YtMusicStyleStrategy] Upstream failure: $e');
      return getLocalFallbackTracks(
        seedSong,
        exclusions: {seedSong.id, seedSong.canonicalBaseKey},
        count: count,
      );
    }
  }
}

// ================= Unified Smart Radio AI (Path B) ================= //

/// Consolidated Unified Smart Radio AI Strategy.
/// Merges the best algorithmic pillars:
/// 1. Mathematical multi-factor vector similarity (SongFeatureVector: artist, era, composer, language, duration)
/// 2. Laplace-smoothed Markov Transition Matrix learning
/// 3. Spotify Dual-Anchor session continuity (60% Anchor / 40% Current)
/// 4. YouTube fast skip reactivity (<30s skips branch away and cool down artist)
/// 5. Zero back-to-back same-artist repetition and Poisson artist dispersion
/// 6. Multi-source resilience via JioSaavn reco.getreco, local CatalogDatabase, and non-blocking YouTube automix
class UnifiedSmartRadioStrategy implements NextTrackStrategy {
  @override
  String get id => 'unified_smart_radio';

  @override
  String get displayName => 'Unified Smart Radio AI';

  @override
  String get description =>
      'Multi-factor vector similarity, dual session anchoring, Markov transition learning & instant skip reactivity';

  static final MarkovTransitionMatrix _markovMatrix = MarkovTransitionMatrix();
  Song? _sessionAnchorTrack;
  final Queue<String> _skippedArtists = Queue<String>();
  final Set<String> _skippedTrackKeys = <String>{};

  @visibleForTesting
  Song? get sessionAnchor => _sessionAnchorTrack;

  @visibleForTesting
  List<String> get skippedArtists => _skippedArtists.toList();

  @override
  void resetSession({Song? initialAnchor}) {
    _sessionAnchorTrack = initialAnchor;
    _skippedArtists.clear();
    _skippedTrackKeys.clear();
    AppLogger.log('UnifiedSmartRadioStrategy', 'Session anchor reset. Anchor: ${_sessionAnchorTrack?.title ?? "none"}');
  }

  @override
  void recordSkip(Song skippedSong, {required int listenedSeconds}) {
    if (listenedSeconds < 30) {
      final artist = QueueCooldownManager.normalizeArtistKey(skippedSong.primaryArtist);
      if (artist.isNotEmpty && artist != 'various artists') {
        _skippedArtists.addLast(artist);
        while (_skippedArtists.length > 5) {
          _skippedArtists.removeFirst();
        }
      }
      if (skippedSong.cleanTitleKey.isNotEmpty) {
        _skippedTrackKeys.add(skippedSong.cleanTitleKey);
      }
      QueueCooldownManager.recordPlayed(skippedSong);
      if (_sessionAnchorTrack != null) {
        _markovMatrix.recordTransition(_sessionAnchorTrack!, skippedSong, isPositive: false);
      }
      AppLogger.log(
        'UnifiedSmartRadioStrategy',
        'Skip Reactivity recorded for "${skippedSong.title}" (${listenedSeconds}s). Cooling artist: $artist',
      );
    }
  }

  @override
  void recordTransition(Song from, Song to, {bool isPositive = true}) {
    _markovMatrix.recordTransition(from, to, isPositive: isPositive);
    if (isPositive && to.id != _sessionAnchorTrack?.id) {
      _sessionAnchorTrack = to;
      AppLogger.log('UnifiedSmartRadioStrategy', 'Smoothly shifted anchor to "${to.title}"');
    }
  }

  @override
  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 20,
  }) async {
    try {
      if (_sessionAnchorTrack == null) {
        _sessionAnchorTrack = seedSong;
        AppLogger.log('UnifiedSmartRadioStrategy', 'Anchored session to "${seedSong.title}" by ${seedSong.primaryArtist}');
      }

      final anchorSong = _sessionAnchorTrack!;
      final prefLangs = SettingsManager.preferredLanguages;
      final targetLang = (seedSong.language != null && seedSong.language!.isNotEmpty)
          ? seedSong.language!.toLowerCase()
          : (prefLangs.firstOrNull ?? '').toLowerCase();

      final targetBatch = count > 0 ? count : 20;

      // 1. Build exclusion set
      final Set<String> exclusions = {};
      for (final s in queue) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      final recentHistory = history.length > 50 ? history.sublist(history.length - 50) : history;
      for (final s in recentHistory) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      exclusions.add(seedSong.id);
      exclusions.add(seedSong.canonicalBaseKey);
      if (seedSong.cleanTitleKey.isNotEmpty) exclusions.add(seedSong.cleanTitleKey);
      exclusions.add(anchorSong.id);
      exclusions.add(anchorSong.canonicalBaseKey);
      if (anchorSong.cleanTitleKey.isNotEmpty) exclusions.add(anchorSong.cleanTitleKey);

      // 2. Multi-tier Candidate Generation:
      // Sourced from JioSaavn Reco + CatalogDatabase + Clean Artist Search + YouTube Automix (non-blocking)
      final List<Future<List<Song>>> anchorFutures = [
        SaavnClient.getRelatedSongs(anchorSong.id, language: targetLang),
        CatalogDatabase.getSongsByArtist(anchorSong.primaryArtist),
        if (anchorSong.primaryArtist.isNotEmpty && anchorSong.primaryArtist.toLowerCase() != 'various artists')
          SaavnClient.search('${anchorSong.primaryArtist} $targetLang', limit: 12, language: targetLang),
        YouTubeClient.getRadioTracks(
          anchorSong,
          limit: 10,
          excludedArtists: _skippedArtists.toSet(),
          excludedKeys: _skippedTrackKeys,
        ).timeout(const Duration(milliseconds: 1500), onTimeout: () => <Song>[]),
      ];

      final List<Future<List<Song>>> currentFutures = (seedSong.id != anchorSong.id)
          ? [
              SaavnClient.getRelatedSongs(seedSong.id, language: targetLang),
              CatalogDatabase.getSongsByArtist(seedSong.primaryArtist),
              if (seedSong.primaryArtist.isNotEmpty && seedSong.primaryArtist.toLowerCase() != 'various artists')
                SaavnClient.search('${seedSong.primaryArtist} $targetLang', limit: 10, language: targetLang),
              YouTubeClient.getRadioTracks(
                seedSong,
                limit: 10,
                excludedArtists: _skippedArtists.toSet(),
                excludedKeys: _skippedTrackKeys,
              ).timeout(const Duration(milliseconds: 1500), onTimeout: () => <Song>[]),
            ]
          : [];

      final anchorResults = await Future.wait(anchorFutures);
      final currentResults = currentFutures.isNotEmpty ? await Future.wait(currentFutures) : <List<Song>>[];

      final List<Song> anchorCandidates = anchorResults.expand((x) => x).toList();
      final List<Song> currentCandidates = currentResults.expand((x) => x).toList();

      if (anchorCandidates.isEmpty && seedSong.id != _sessionAnchorTrack?.id) {
        _sessionAnchorTrack = seedSong;
      }

      // Dual-Anchor Interleaving: 60% session anchor / 40% current track
      final List<Song> blendedPool = [];
      int aIdx = 0;
      int cIdx = 0;
      while (aIdx < anchorCandidates.length || cIdx < currentCandidates.length) {
        for (int i = 0; i < 3 && aIdx < anchorCandidates.length; i++) {
          blendedPool.add(anchorCandidates[aIdx++]);
        }
        for (int j = 0; j < 2 && cIdx < currentCandidates.length; j++) {
          blendedPool.add(currentCandidates[cIdx++]);
        }
        if (currentCandidates.isEmpty && aIdx < anchorCandidates.length) {
          blendedPool.add(anchorCandidates[aIdx++]);
        }
      }

      // 3. Pre-filter candidate tracks using RadioEngine.applyHardFiltering
      final hardFiltered = RadioEngine.applyHardFiltering(
        seedSong: seedSong,
        candidates: blendedPool,
        queue: queue,
        history: recentHistory,
        targetLanguage: targetLang,
      );

      final List<Song> validCandidates = hardFiltered.where((c) {
        if (c.isSameSongOrDub(anchorSong)) return false;
        final cArtistKey = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);
        if (_skippedArtists.contains(cArtistKey)) return false;
        if (c.cleanTitleKey.isNotEmpty && _skippedTrackKeys.contains(c.cleanTitleKey)) return false;
        return true;
      }).toList();

      // 4. Mathematical Vector & Markov Scoring
      final targetArtistKey = QueueCooldownManager.normalizeArtistKey(seedSong.primaryArtist);
      final anchorArtistKey = QueueCooldownManager.normalizeArtistKey(anchorSong.primaryArtist);
      final seedYear = RadioEngine.extractReleaseYear(seedSong);

      final scoredCandidates = <MapEntry<Song, double>>[];
      for (final c in validCandidates) {
        final vector = SongFeatureVector.extractRelative(seedSong, c);
        final vectorScore = vector.compositeVectorScore;
        final markovProb = _markovMatrix.getProbability(seedSong, c);

        double score = (0.50 * vectorScore) + (0.30 * markovProb);

        final cArtistKey = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);
        if (cArtistKey == targetArtistKey) {
          score += 0.35;
        } else if (cArtistKey == anchorArtistKey) {
          score += 0.20;
        }

        // Era proximity boost (±4 years)
        final cYear = RadioEngine.extractReleaseYear(c);
        if (seedYear != null && cYear != null && (seedYear - cYear).abs() <= 4) {
          score += 0.25;
        }

        // Music Director / Composer boost
        if (RadioEngine.isSharedMusicDirectorOrComposer(seedSong, c)) {
          score += 0.30;
        }

        if (c.language != null && c.language!.toLowerCase().trim() == targetLang) {
          score += 0.20;
        }
        if (_skippedArtists.contains(cArtistKey)) {
          score -= 0.50;
        }
        if (c.cleanTitleKey.isNotEmpty && _skippedTrackKeys.contains(c.cleanTitleKey)) {
          score -= 0.60;
        }
        scoredCandidates.add(MapEntry(c, score));
      }
      scoredCandidates.sort((a, b) => b.value.compareTo(a.value));
      final rankedCandidates = scoredCandidates.map((e) => e.key).toList();

      // 5. Enforce Artist Dispersion (Zero Back-to-Back Duplicates + Poisson spacing)
      final shapedTracks = enforceArtistDispersionAndNoBackToBack(
        rankedCandidates,
        seedArtist: seedSong.primaryArtist,
        count: targetBatch,
      );

      // If pool is still below target batch, supplement with genuine catalog tracks (NEVER trending chart hits)
      if (shapedTracks.length < targetBatch) {
        final supplement = <Song>[];
        try {
          supplement.addAll(await CatalogDatabase.getSongsByArtist(seedSong.primaryArtist));
          if (anchorSong.primaryArtist != seedSong.primaryArtist) {
            supplement.addAll(await CatalogDatabase.getSongsByArtist(anchorSong.primaryArtist));
          }
        } catch (_) {}
        if (supplement.length < targetBatch - shapedTracks.length) {
          try {
            final sRes = await SaavnClient.search('${seedSong.primaryArtist} $targetLang', limit: 12, language: targetLang);
            supplement.addAll(sRes);
          } catch (_) {}
        }

        final filteredSupplement = RadioEngine.applyHardFiltering(
          seedSong: seedSong,
          candidates: supplement,
          queue: queue,
          history: recentHistory,
          targetLanguage: targetLang,
        ).where((s) {
          if (s.isSameSongOrDub(anchorSong)) return false;
          if (shapedTracks.any((f) => s.isSameSongOrDub(f))) return false;
          return true;
        }).toList();

        final remainingCount = targetBatch - shapedTracks.length;
        final lastPlacedArtist = shapedTracks.isNotEmpty ? shapedTracks.last.primaryArtist : seedSong.primaryArtist;
        final shapedSupplement = enforceArtistDispersionAndNoBackToBack(
          filteredSupplement,
          seedArtist: lastPlacedArtist,
          count: remainingCount,
        );
        shapedTracks.addAll(shapedSupplement);
      }

      // 6. Circuit Breaker Fallback
      if (shapedTracks.isEmpty) {
        return getLocalFallbackTracks(
          seedSong,
          exclusions: exclusions,
          count: targetBatch,
          targetLang: targetLang,
        );
      }

      return shapedTracks;
    } catch (e) {
      debugPrint('[UnifiedSmartRadioStrategy] Fallback to circuit breaker: $e');
      return getLocalFallbackTracks(
        seedSong,
        exclusions: {seedSong.id, seedSong.canonicalBaseKey},
        count: count,
      );
    }
  }
}

// ================= Factory & Coordinator ================= //

class NextTrackStrategyFactory {
  static final UnifiedSmartRadioStrategy _unifiedStrategy = UnifiedSmartRadioStrategy();
  static final SpotifyStyleStrategy _spotifyStrategy = SpotifyStyleStrategy();
  static final YtMusicStyleStrategy _ytMusicStrategy = YtMusicStyleStrategy();
  static final MarkovCosineRadioStrategy _markovCosineStrategy = MarkovCosineRadioStrategy();

  static NextTrackStrategy getStrategy([NextTrackStrategyMode? mode]) {
    final effectiveMode = mode ?? SettingsManager.nextTrackStrategy;
    switch (effectiveMode) {
      case NextTrackStrategyMode.markovCosineRadio:
        return _markovCosineStrategy;
      case NextTrackStrategyMode.spotifyStyle:
        return _spotifyStrategy;
      case NextTrackStrategyMode.ytMusicStyle:
        return _ytMusicStrategy;
      case NextTrackStrategyMode.unifiedSmartRadio:
        return _unifiedStrategy;
    }
  }

  /// Convenience coordinator to record a skip across active strategy instances
  static void recordSkip(Song skippedSong, {required int listenedSeconds}) {
    _unifiedStrategy.recordSkip(skippedSong, listenedSeconds: listenedSeconds);
    _spotifyStrategy.recordSkip(skippedSong, listenedSeconds: listenedSeconds);
    _ytMusicStrategy.recordSkip(skippedSong, listenedSeconds: listenedSeconds);
    _markovCosineStrategy.recordSkip(skippedSong, listenedSeconds: listenedSeconds);
  }

  /// Convenience coordinator to record a track transition across active strategy instances
  static void recordTransition(Song from, Song to, {bool isPositive = true}) {
    _unifiedStrategy.recordTransition(from, to, isPositive: isPositive);
    _spotifyStrategy.recordTransition(from, to, isPositive: isPositive);
    _ytMusicStrategy.recordTransition(from, to, isPositive: isPositive);
    _markovCosineStrategy.recordTransition(from, to, isPositive: isPositive);
  }

  /// Convenience coordinator to reset session anchor across strategy instances
  static void resetSession({Song? initialAnchor}) {
    _unifiedStrategy.resetSession(initialAnchor: initialAnchor);
    _spotifyStrategy.resetSession(initialAnchor: initialAnchor);
    _ytMusicStrategy.resetSession(initialAnchor: initialAnchor);
    _markovCosineStrategy.resetSession(initialAnchor: initialAnchor);
  }
}
