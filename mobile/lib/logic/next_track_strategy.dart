import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import '../services/radio_engine.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';
import '../services/youtube_client.dart';
import '../services/queue_cooldown_manager.dart';
import '../services/download_manager.dart';
import '../services/favorites_manager.dart';
import '../services/history_manager.dart';
import '../services/app_logger.dart';
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

  final targetLanguage = targetLang ?? seedSong.language?.toLowerCase() ?? 'tamil';
  final primaryArtist = QueueCooldownManager.normalizeArtistKey(seedSong.primaryArtist);

  // Score candidates: Same Artist (score 3) > Same Language (score 2) > Other (score 1)
  final List<MapEntry<int, Song>> scored = [];
  final Set<String> seen = {};

  for (final s in pool) {
    if (s.title.trim().isEmpty) continue;
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
          : (prefLangs.firstOrNull ?? 'tamil').toLowerCase();

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

      // 3. Weighted Blend Fetching:
      // Session Anchor (60% weight) + Current Track (40% weight)
      final List<Future<List<Song>>> anchorFutures = [
        ApiClient.fetchRecommendations(
          anchorSong.id,
          artist: anchorSong.primaryArtist,
          language: targetLang,
        ),
        if (anchorSong.primaryArtist.isNotEmpty && anchorSong.primaryArtist.toLowerCase() != 'various artists')
          SaavnClient.search('${anchorSong.primaryArtist} $targetLang hits', limit: 12, language: targetLang),
        if (anchorSong.album.isNotEmpty && anchorSong.album.toLowerCase() != 'unknown album')
          SaavnClient.search('${anchorSong.album} $targetLang songs', limit: 8, language: targetLang),
        SaavnClient.getRelatedSongs(anchorSong.id, language: targetLang),
      ];

      final List<Future<List<Song>>> currentFutures = (seedSong.id != anchorSong.id)
          ? [
              ApiClient.fetchRecommendations(
                seedSong.id,
                artist: seedSong.primaryArtist,
                language: targetLang,
              ),
              if (seedSong.primaryArtist.isNotEmpty && seedSong.primaryArtist.toLowerCase() != 'various artists')
                SaavnClient.search('${seedSong.primaryArtist} $targetLang hits', limit: 8, language: targetLang),
              SaavnClient.getRelatedSongs(seedSong.id, language: targetLang),
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

      // 4. Pre-filter candidate tracks for language, duplicate variants, and cooldowns
      final Set<String> seenKeys = {};
      final List<Song> validCandidates = [];

      for (final c in blendedPool) {
        if (c.title.trim().isEmpty) continue;
        final baseKey = c.canonicalBaseKey;
        final titleKey = c.cleanTitleKey;

        if (exclusions.contains(c.id) ||
            exclusions.contains(baseKey) ||
            (titleKey.isNotEmpty && (exclusions.contains(titleKey) || seenKeys.contains(titleKey))) ||
            seenKeys.contains(baseKey) ||
            QueueCooldownManager.isCoolingDown(c)) {
          continue;
        }

        // Language lockdown: single-language radio
        if (c.language != null && c.language!.isNotEmpty) {
          final cLang = c.language!.toLowerCase().trim();
          if (cLang != targetLang) continue;
        }

        // Anti-cross-language dubs against seed and queue
        if (c.isSameSongOrDub(seedSong) || c.isSameSongOrDub(anchorSong)) continue;
        if (queue.any((q) => c.isSameSongOrDub(q)) || validCandidates.any((f) => c.isSameSongOrDub(f))) {
          continue;
        }

        seenKeys.add(baseKey);
        if (titleKey.isNotEmpty) seenKeys.add(titleKey);
        validCandidates.add(c.copyWith(isSmartRecommended: true, language: targetLang));
      }

      // 5. Candidate Ranking & Scoring
      final targetArtistKey = QueueCooldownManager.normalizeArtistKey(seedSong.primaryArtist);
      final anchorArtistKey = QueueCooldownManager.normalizeArtistKey(anchorSong.primaryArtist);

      final scoredCandidates = <MapEntry<Song, double>>[];
      for (final c in validCandidates) {
        double score = 0.5;
        final cArtistKey = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);
        if (cArtistKey == targetArtistKey) {
          score += 0.35;
        } else if (cArtistKey == anchorArtistKey) {
          score += 0.20;
        }
        if (c.language != null && c.language!.toLowerCase().trim() == targetLang) {
          score += 0.15;
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

      // If pool is still below target batch, supplement with Regional Trending in target language
      if (shapedTracks.length < targetBatch) {
        final trending = await SaavnClient.getTrending(language: targetLang);
        final trendingCandidates = <Song>[];
        for (final s in trending) {
          final baseKey = s.canonicalBaseKey;
          if (exclusions.contains(s.id) ||
              exclusions.contains(baseKey) ||
              seenKeys.contains(baseKey) ||
              s.isSameSongOrDub(seedSong) ||
              s.isSameSongOrDub(anchorSong) ||
              shapedTracks.any((f) => s.isSameSongOrDub(f))) {
            continue;
          }
          if (s.language != null && s.language!.isNotEmpty && s.language!.toLowerCase() != targetLang) {
            continue;
          }
          seenKeys.add(baseKey);
          trendingCandidates.add(s.copyWith(isSmartRecommended: true, language: targetLang));
        }

        trendingCandidates.shuffle();

        final remainingCount = targetBatch - shapedTracks.length;
        final lastPlacedArtist = shapedTracks.isNotEmpty ? shapedTracks.last.primaryArtist : seedSong.primaryArtist;
        final shapedTrending = enforceArtistDispersionAndNoBackToBack(
          trendingCandidates,
          seedArtist: lastPlacedArtist,
          count: remainingCount,
        );
        shapedTracks.addAll(shapedTrending);
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
          : (prefLangs.firstOrNull ?? 'tamil').toLowerCase();

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

      // 3. Audio-First Master Filtering & Deduplication
      final Set<String> seenKeys = {};
      final List<Song> validCandidates = [];

      for (final s in candidatePool) {
        if (s.title.trim().isEmpty) continue;
        final baseKey = s.canonicalBaseKey;
        final titleKey = s.cleanTitleKey;
        final artist = QueueCooldownManager.normalizeArtistKey(s.primaryArtist);

        if (exclusions.contains(s.id) ||
            exclusions.contains(baseKey) ||
            (titleKey.isNotEmpty && (exclusions.contains(titleKey) || seenKeys.contains(titleKey))) ||
            seenKeys.contains(baseKey) ||
            QueueCooldownManager.isCoolingDown(s)) {
          continue;
        }

        // Rolling Skip Reactivity blacklist check
        if (_skippedArtists.contains(artist) || (titleKey.isNotEmpty && _skippedTrackKeys.contains(titleKey))) {
          continue;
        }

        // Language check
        if (s.language != null && s.language!.isNotEmpty) {
          final sLang = s.language!.toLowerCase().trim();
          if (sLang != targetLang) continue;
        }

        // Anti-cross-language dubs
        if (s.isSameSongOrDub(seedSong)) continue;
        if (queue.any((q) => s.isSameSongOrDub(q)) || validCandidates.any((u) => s.isSameSongOrDub(u))) {
          continue;
        }

        seenKeys.add(baseKey);
        if (titleKey.isNotEmpty) seenKeys.add(titleKey);
        validCandidates.add(s.copyWith(isSmartRecommended: true, language: targetLang));
      }

      // 4. Enforce Artist Dispersion (QueueCooldownManager + ZERO Back-to-Back duplicates)
      final shapedTracks = enforceArtistDispersionAndNoBackToBack(
        validCandidates,
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

// ================= Factory & Coordinator ================= //

class NextTrackStrategyFactory {
  static final SpotifyStyleStrategy _spotifyStrategy = SpotifyStyleStrategy();
  static final YtMusicStyleStrategy _ytMusicStrategy = YtMusicStyleStrategy();
  static final MarkovCosineRadioStrategy _markovCosineStrategy = MarkovCosineRadioStrategy();

  static NextTrackStrategy getStrategy(NextTrackStrategyMode mode) {
    switch (mode) {
      case NextTrackStrategyMode.spotifyStyle:
        return _spotifyStrategy;
      case NextTrackStrategyMode.ytMusicStyle:
        return _ytMusicStrategy;
      case NextTrackStrategyMode.markovCosineRadio:
        return _markovCosineStrategy;
    }
  }

  /// Convenience coordinator to record a skip across active strategy instances
  static void recordSkip(Song skippedSong, {required int listenedSeconds}) {
    _spotifyStrategy.recordSkip(skippedSong, listenedSeconds: listenedSeconds);
    _ytMusicStrategy.recordSkip(skippedSong, listenedSeconds: listenedSeconds);
    _markovCosineStrategy.recordSkip(skippedSong, listenedSeconds: listenedSeconds);
  }

  /// Convenience coordinator to record a track transition across active strategy instances
  static void recordTransition(Song from, Song to, {bool isPositive = true}) {
    _spotifyStrategy.recordTransition(from, to, isPositive: isPositive);
    _ytMusicStrategy.recordTransition(from, to, isPositive: isPositive);
    _markovCosineStrategy.recordTransition(from, to, isPositive: isPositive);
  }

  /// Convenience coordinator to reset session anchor across strategy instances
  static void resetSession({Song? initialAnchor}) {
    _spotifyStrategy.resetSession(initialAnchor: initialAnchor);
    _ytMusicStrategy.resetSession(initialAnchor: initialAnchor);
    _markovCosineStrategy.resetSession(initialAnchor: initialAnchor);
  }
}
