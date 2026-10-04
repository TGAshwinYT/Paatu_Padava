import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import '../services/history_manager.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';
import 'audio_queue_handler.dart';
import 'next_track_strategy.dart';

enum SmartShuffleMode {
  off,        // Sequential playback
  standard,   // Intelligent nearest-neighbor reordering of user queue
  smart,      // User queue + persistent AI recommendation interleaving
}

/// Spotify-grade Smart Shuffle & Intelligent Queue Reordering Controller.
/// Features:
/// 1. Persistent anti-repetition memory (backed by HistoryManager Hive store across sessions).
/// 2. Multi-tier recommendation sourcing (Backend ML Recommender + Contextual Related + Artist hits).
/// 3. Soft language matching with scoring weights instead of shallow hard exclusions.
/// 4. Nearest-neighbor queue reordering via /api/music/shuffle-order & Markov transition chains.
class SmartShuffleController {
  final AudioQueueHandler? queueHandler;
  final ValueNotifier<SmartShuffleMode> modeNotifier = ValueNotifier(SmartShuffleMode.off);

  SmartShuffleMode get mode => modeNotifier.value;
  bool get isSmartActive => mode == SmartShuffleMode.smart;
  bool get isStandardActive => mode == SmartShuffleMode.standard;

  bool _isIngesting = false;
  final List<String> _sessionPlayedIds = [];
  final List<String> _sessionPlayedKeys = [];
  final Map<String, int> _negativeFeedback = {};
  final Map<String, int> _positiveFeedback = {};

  SmartShuffleController({this.queueHandler}) {
    // Listen to queue changes & index updates to trigger Smart recommendation ingestion
    queueHandler?.currentIndexNotifier.addListener(_onQueueProgress);
    queueHandler?.queueNotifier.addListener(_onQueueProgress);
  }

  void recordRecentlyPlayed(Song song) {
    _sessionPlayedIds.remove(song.id);
    _sessionPlayedIds.insert(0, song.id);
    _sessionPlayedKeys.remove(song.canonicalBaseKey);
    _sessionPlayedKeys.insert(0, song.canonicalBaseKey);
    if (_sessionPlayedIds.length > 50) {
      _sessionPlayedIds.removeLast();
    }
    if (_sessionPlayedKeys.length > 50) {
      _sessionPlayedKeys.removeLast();
    }
  }

  void recordFeedback({required Song song, required bool isPositive}) {
    final key = song.canonicalBaseKey;
    final artistKey = song.primaryArtist;
    if (isPositive) {
      _positiveFeedback[key] = (_positiveFeedback[key] ?? 0) + 1;
      _positiveFeedback[artistKey] = (_positiveFeedback[artistKey] ?? 0) + 1;
    } else {
      _negativeFeedback[key] = (_negativeFeedback[key] ?? 0) + 1;
      _negativeFeedback[artistKey] = (_negativeFeedback[artistKey] ?? 0) + 1;
    }
  }

  /// Records listen/skip feedback: skip (< 30s) is negative; completed listen (>= 30s) is positive
  void recordPlaybackFeedback(Song song, {required int listenedSeconds, required int totalSeconds}) {
    final isPositive = listenedSeconds >= 30;
    recordFeedback(song: song, isPositive: isPositive);
  }

  /// Calculates user affinity score for a song based on positive and negative feedback
  double getSongAffinityScore(Song song) {
    final key = song.canonicalBaseKey;
    final pos = _positiveFeedback[key] ?? 0;
    final neg = _negativeFeedback[key] ?? 0;
    return (pos - neg).toDouble();
  }

  /// Helper to check artist diversity in sliding window of size 5 (at most 1 per 5 tracks)
  bool isArtistAllowed(Song candidate, List<Song> existing) {
    final candArtist = candidate.primaryArtist;
    final window = existing.length >= 4 ? existing.sublist(existing.length - 4) : existing;
    return !window.any((s) => s.primaryArtist == candArtist);
  }

  /// Comprehensive anti-repeat exclusion set combining canonical keys across:
  /// - Current playing and upcoming queue tracks
  /// - Current session play history
  /// - Persistent Hive history across app restarts (up to 100 items)
  Set<String> _getExclusionKeys() {
    final exclusions = <String>{};
    if (queueHandler != null) {
      for (final s in queueHandler!.queue) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        exclusions.add(s.canonicalSongKey);
      }
    }
    exclusions.addAll(_sessionPlayedIds);
    exclusions.addAll(_sessionPlayedKeys);
    for (final s in HistoryManager.getHistory()) {
      exclusions.add(s.id);
      exclusions.add(s.canonicalBaseKey);
      exclusions.add(s.canonicalSongKey);
    }
    return exclusions;
  }

  void _onQueueProgress() {
    if (queueHandler == null || _isIngesting) return;
    if (isSmartActive && queueHandler!.upcomingCount < 3) {
      ingestSmartRecommendations();
    } else if (queueHandler!.upcomingCount < 2 && queueHandler!.queue.isNotEmpty) {
      autoRefillUpcoming();
    }
  }

  /// Cycles mode: Off -> Standard -> Smart -> Off
  void cycleMode() {
    switch (mode) {
      case SmartShuffleMode.off:
        setMode(SmartShuffleMode.standard);
        break;
      case SmartShuffleMode.standard:
        setMode(SmartShuffleMode.smart);
        break;
      case SmartShuffleMode.smart:
        setMode(SmartShuffleMode.off);
        break;
    }
  }

  /// Explicitly set the shuffle mode
  Future<void> setMode(SmartShuffleMode newMode) async {
    if (modeNotifier.value == newMode) return;
    modeNotifier.value = newMode;

    if (queueHandler == null) return;
    final currentIndex = queueHandler!.currentIndex;
    if (currentIndex < 0 || currentIndex >= queueHandler!.queue.length) return;
    final currentSong = queueHandler!.currentSong;

    if (newMode == SmartShuffleMode.standard) {
      // 1. Standard Shuffle: Intelligent nearest-neighbor reordering of user songs
      final upcoming = queueHandler!.queue
          .sublist(currentIndex + 1)
          .where((s) => !s.isSmartRecommended)
          .toList();

      if (upcoming.isNotEmpty) {
        final orderedIds = await ApiClient.fetchSmartShuffle(upcoming, currentSong);
        final orderedUpcoming = _reorderQueueByIds(upcoming, orderedIds);
        queueHandler!.replaceUpcomingQueue(orderedUpcoming);
      }
    } else if (newMode == SmartShuffleMode.smart) {
      // 2. Smart Shuffle: Immediately check and interleave recommendations
      if (queueHandler!.upcomingCount < 3) {
        await ingestSmartRecommendations();
      }
    } else {
      // 3. Off: Restore sequential order and purge smart injected songs
      final originalList = queueHandler!.originalQueue;
      final originalIdx = originalList.indexWhere((s) => s.id == currentSong?.id);

      List<Song> restoredUpcoming;
      if (originalIdx != -1 && originalIdx + 1 < originalList.length) {
        restoredUpcoming = originalList.sublist(originalIdx + 1);
      } else {
        restoredUpcoming = queueHandler!.queue
            .sublist(currentIndex + 1)
            .where((s) => !s.isSmartRecommended)
            .toList();
      }
      queueHandler!.replaceUpcomingQueue(restoredUpcoming);
    }
  }

  /// Multi-tier Smart Ingestion Engine:
  /// Concurrently fetches recommendations across multiple sources (backend ML, related songs,
  /// artist hits, regional trending), deduplicates at the canonical-song level, applies
  /// artist diversity caps (at most 1 per 5 tracks), and interleaves suggestions.
  Future<void> ingestSmartRecommendations() async {
    if (queueHandler == null || _isIngesting || !isSmartActive) return;
    if (queueHandler!.upcomingCount >= 4) return;

    final currentSong = queueHandler!.currentSong;
    if (currentSong == null) return;

    _isIngesting = true;
    final prefLangs = SettingsManager.preferredLanguages;
    final primaryLang = prefLangs.firstOrNull ?? 'tamil';

    // 1. Resolve authentic user seed without cascading: suggestions do not seed suggestions!
    Song userSeed = currentSong;
    final currentIndex = queueHandler!.currentIndex;
    for (int i = currentIndex; i >= 0; i--) {
      final s = queueHandler!.queue[i];
      if (!s.isSmartRecommended) {
        userSeed = s;
        break;
      }
    }

    try {
      // 2. Multi-Source Concurrent Recommendation Retrieval
      final List<Future<List<Song>>> candidateFutures = [
        // Source 1: Backend Machine Learning Taste Recommender
        ApiClient.fetchRecommendations(
          userSeed.id,
          artist: userSeed.artist,
          language: primaryLang,
        ),
        // Source 2: Contextual Related Songs for user seed (hard language filter removed)
        SaavnClient.getRelatedSongs(userSeed.id, language: primaryLang),
        // Source 3: Artist Hits (capped)
        SaavnClient.search('${userSeed.artist} hits', limit: 8, language: primaryLang),
        // Source 4: Regional Trending in user's primary language
        SaavnClient.getTrending(language: primaryLang),
      ];

      final results = await Future.wait(candidateFutures);
      final List<Song> allCandidates = results.expand((x) => x).toList();

      // 3. Canonical-Level Deduplication & Feedback Scoring
      final exclusionKeys = _getExclusionKeys();
      final Set<String> seenKeys = <String>{};
      final List<MapEntry<double, Song>> scored = [];

      for (final c in allCandidates) {
        if (c.title.trim().isEmpty) continue;
        final baseKey = c.canonicalBaseKey;
        final songKey = c.canonicalSongKey;

        if (exclusionKeys.contains(c.id) ||
            exclusionKeys.contains(baseKey) ||
            exclusionKeys.contains(songKey) ||
            seenKeys.contains(baseKey)) {
          continue;
        }
        seenKeys.add(baseKey);

        double score = 10.0;

        // Language affinity scoring bonus (soft prior, never hard filter)
        if (c.language != null && c.language!.isNotEmpty) {
          final cLang = c.language!.toLowerCase();
          if (prefLangs.any((l) => l.toLowerCase() == cLang)) {
            score += 8.0;
          }
        } else {
          score += 4.0;
        }

        // Artist affinity bonus (capped)
        if (c.primaryArtist == userSeed.primaryArtist) {
          score += 4.0;
        }

        // Feedback weighting (penalize early skips, boost full listens/likes)
        final neg = _negativeFeedback[baseKey] ?? _negativeFeedback[c.primaryArtist] ?? 0;
        final pos = _positiveFeedback[baseKey] ?? _positiveFeedback[c.primaryArtist] ?? 0;
        score -= (neg * 8.0);
        score += (pos * 5.0);

        // Duration sanity bonus (2 - 7 minutes)
        if (c.duration >= 120 && c.duration <= 420) {
          score += 1.0;
        }

        scored.add(MapEntry(score, c));
      }

      scored.sort((a, b) => b.key.compareTo(a.key));
      final candidates = scored.map((e) => e.value).toList();

      if (candidates.isEmpty) {
        _isIngesting = false;
        return;
      }

      // 4. Interleave recommendations with Artist Diversity Caps (at most 1 per 5 tracks)
      final currentUpcoming = queueHandler!.queue.sublist(queueHandler!.currentIndex + 1).toList();
      final List<Song> interleaved = [];
      int recoIdx = 0;

      for (int i = 0; i < currentUpcoming.length; i++) {
        interleaved.add(currentUpcoming[i]);
        if ((i + 1) % 2 == 0 && recoIdx < candidates.length) {
          // Find next candidate that clears artist cap
          int lookahead = recoIdx;
          while (lookahead < candidates.length && !isArtistAllowed(candidates[lookahead], interleaved)) {
            lookahead++;
          }
          if (lookahead < candidates.length) {
            final picked = candidates.removeAt(lookahead);
            interleaved.add(picked.copyWith(isSmartRecommended: true));
          }
        }
      }

      // If upcoming queue was small, append up to 3 recommended tracks respecting diversity
      while (interleaved.length < 4 && candidates.isNotEmpty) {
        int lookahead = 0;
        while (lookahead < candidates.length && !isArtistAllowed(candidates[lookahead], interleaved)) {
          lookahead++;
        }
        if (lookahead < candidates.length) {
          final picked = candidates.removeAt(lookahead);
          interleaved.add(picked.copyWith(isSmartRecommended: true));
        } else {
          break;
        }
      }

      // 5. Apply Intelligent Shuffle Reordering to preserve acoustic flow
      if (interleaved.length > 2) {
        final orderedIds = await ApiClient.fetchSmartShuffle(interleaved, userSeed);
        final orderedInterleaved = _reorderQueueByIds(interleaved, orderedIds);
        queueHandler!.replaceUpcomingQueue(orderedInterleaved);
      } else {
        queueHandler!.replaceUpcomingQueue(interleaved);
      }
    } catch (e) {
      debugPrint('[SmartShuffleController] Ingestion error: $e');
    } finally {
      _isIngesting = false;
    }
  }

  /// Reorders queue according to ordered ID list while preserving any unmatched songs
  List<Song> _reorderQueueByIds(List<Song> queue, List<String> orderedIds) {
    final map = {for (final s in queue) s.id: s};
    final List<Song> result = [];
    for (final id in orderedIds) {
      final song = map.remove(id);
      if (song != null) result.add(song);
    }
    result.addAll(map.values);
    return result;
  }

  /// Auto-populates Up Next when the user starts a fresh queue with a single song
  Future<void> populateUpNextForNewQueue(Song seedSong) async {
    if (queueHandler == null) return;
    try {
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      final tracks = await strategy.getUpcomingTracks(
        seedSong: seedSong,
        queue: queueHandler!.queue,
        history: HistoryManager.getHistory(),
        count: 8,
      );

      if (tracks.isNotEmpty && queueHandler != null && queueHandler!.queue.isNotEmpty) {
        for (final track in tracks) {
          await queueHandler!.addToQueue(track);
        }
      }
    } catch (e) {
      debugPrint('[SmartShuffleController] populateUpNextForNewQueue error: $e');
    }
  }

  /// Auto-refill upcoming queue when 1 or fewer upcoming tracks remain
  Future<void> autoRefillUpcoming({int count = 5}) async {
    if (queueHandler == null || _isIngesting) return;
    final current = queueHandler!.currentSong;
    if (current == null) return;

    _isIngesting = true;
    try {
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      final tracks = await strategy.getUpcomingTracks(
        seedSong: current,
        queue: queueHandler!.queue,
        history: HistoryManager.getHistory(),
        count: count,
      );

      if (tracks.isNotEmpty && queueHandler != null && queueHandler!.queue.isNotEmpty) {
        for (final track in tracks) {
          await queueHandler!.addToQueue(track);
        }
      }
    } catch (e) {
      debugPrint('[SmartShuffleController] autoRefillUpcoming error: $e');
    } finally {
      _isIngesting = false;
    }
  }

  void dispose() {
    queueHandler?.currentIndexNotifier.removeListener(_onQueueProgress);
    queueHandler?.queueNotifier.removeListener(_onQueueProgress);
  }
}
