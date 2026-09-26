import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import '../services/history_manager.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';
import 'audio_queue_handler.dart';

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
  final AudioQueueHandler queueHandler;
  final ValueNotifier<SmartShuffleMode> modeNotifier = ValueNotifier(SmartShuffleMode.off);

  SmartShuffleMode get mode => modeNotifier.value;
  bool get isSmartActive => mode == SmartShuffleMode.smart;
  bool get isStandardActive => mode == SmartShuffleMode.standard;

  bool _isIngesting = false;
  final List<String> _sessionPlayedIds = [];

  SmartShuffleController({required this.queueHandler}) {
    // Listen to queue changes & index updates to trigger Smart recommendation ingestion
    queueHandler.currentIndexNotifier.addListener(_onQueueProgress);
    queueHandler.queueNotifier.addListener(_onQueueProgress);
  }

  void recordRecentlyPlayed(String songId) {
    _sessionPlayedIds.remove(songId);
    _sessionPlayedIds.insert(0, songId);
    if (_sessionPlayedIds.length > 50) {
      _sessionPlayedIds.removeLast();
    }
  }

  /// Comprehensive anti-repeat exclusion set combining:
  /// - Current playing and upcoming queue tracks
  /// - Current session play history
  /// - Persistent Hive history across app restarts (up to 100 items)
  Set<String> _getExclusionIds() {
    final exclusions = <String>{};
    exclusions.addAll(queueHandler.queue.map((s) => s.id));
    exclusions.addAll(_sessionPlayedIds);
    exclusions.addAll(HistoryManager.getHistory().map((s) => s.id));
    return exclusions;
  }

  void _onQueueProgress() {
    if (isSmartActive && queueHandler.upcomingCount < 3 && !_isIngesting) {
      ingestSmartRecommendations();
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

    final currentIndex = queueHandler.currentIndex;
    if (currentIndex < 0 || currentIndex >= queueHandler.queue.length) return;
    final currentSong = queueHandler.currentSong;

    if (newMode == SmartShuffleMode.standard) {
      // 1. Standard Shuffle: Intelligent nearest-neighbor reordering of user songs
      final upcoming = queueHandler.queue
          .sublist(currentIndex + 1)
          .where((s) => !s.isSmartRecommended)
          .toList();

      if (upcoming.isNotEmpty) {
        final orderedIds = await ApiClient.fetchSmartShuffle(upcoming, currentSong);
        final orderedUpcoming = _reorderQueueByIds(upcoming, orderedIds);
        queueHandler.replaceUpcomingQueue(orderedUpcoming);
      }
    } else if (newMode == SmartShuffleMode.smart) {
      // 2. Smart Shuffle: Immediately check and interleave recommendations
      if (queueHandler.upcomingCount < 3) {
        await ingestSmartRecommendations();
      }
    } else {
      // 3. Off: Restore sequential order and purge smart injected songs
      final originalList = queueHandler.originalQueue;
      final originalIdx = originalList.indexWhere((s) => s.id == currentSong?.id);

      List<Song> restoredUpcoming;
      if (originalIdx != -1 && originalIdx + 1 < originalList.length) {
        restoredUpcoming = originalList.sublist(originalIdx + 1);
      } else {
        restoredUpcoming = queueHandler.queue
            .sublist(currentIndex + 1)
            .where((s) => !s.isSmartRecommended)
            .toList();
      }
      queueHandler.replaceUpcomingQueue(restoredUpcoming);
    }
  }

  /// Multi-tier Smart Ingestion Engine:
  /// Concurrently fetches recommendations across multiple sources, ranks them with scoring weights,
  /// deduplicates against persistent history, and interleaves them using nearest-neighbor similarity.
  Future<void> ingestSmartRecommendations() async {
    if (_isIngesting || !isSmartActive) return;
    if (queueHandler.upcomingCount >= 4) return;

    final currentSong = queueHandler.currentSong;
    if (currentSong == null) return;

    _isIngesting = true;
    final prefLangs = SettingsManager.preferredLanguages;
    final primaryLang = prefLangs.firstOrNull ?? 'tamil';

    try {
      // 1. Multi-Tier Concurrent Recommendation Retrieval
      final List<Future<List<Song>>> candidateFutures = [
        // Tier 1: Machine Learning Personal Recommender from Backend
        ApiClient.fetchRecommendations(
          currentSong.id,
          artist: currentSong.artist,
          language: primaryLang,
        ),
        // Tier 2: Contextual Related Songs from JioSaavn
        SaavnClient.getRelatedSongs(currentSong.id, language: primaryLang),
        // Tier 3: Contextual Artist Hits
        SaavnClient.search('${currentSong.artist} hits', limit: 12, language: primaryLang),
      ];

      final results = await Future.wait(candidateFutures);
      final List<Song> allCandidates = results.expand((x) => x).toList();

      // 2. Soft Language Scoring & Anti-Repeat Filtering
      final exclusionIds = _getExclusionIds();
      final Set<String> seenIds = <String>{};
      final List<MapEntry<double, Song>> scored = [];

      for (final c in allCandidates) {
        if (exclusionIds.contains(c.id) || seenIds.contains(c.id)) continue;
        seenIds.add(c.id);

        double score = 10.0;

        // Language affinity scoring bonus (soft filter, not hard exclusion)
        if (c.language != null && c.language!.isNotEmpty) {
          final cLang = c.language!.toLowerCase();
          if (prefLangs.any((l) => l.toLowerCase() == cLang)) {
            score += 8.0;
          }
        } else {
          score += 4.0; // Unlabeled tracks get neutral boost
        }

        // Artist affinity bonus
        if (c.artist.toLowerCase() == currentSong.artist.toLowerCase()) {
          score += 5.0;
        } else if (c.artist.toLowerCase().contains(currentSong.artist.toLowerCase()) ||
            currentSong.artist.toLowerCase().contains(c.artist.toLowerCase())) {
          score += 2.5;
        }

        // Duration sanity bonus (2 - 7 minutes)
        if (c.duration >= 120 && c.duration <= 420) {
          score += 1.0;
        }

        scored.add(MapEntry(score, c));
      }

      scored.sort((a, b) => b.key.compareTo(a.key));
      final filtered = scored.map((e) => e.value).toList();

      if (filtered.isEmpty) {
        _isIngesting = false;
        return;
      }

      // 3. Interleave recommendations into upcoming queue
      final currentUpcoming = queueHandler.queue.sublist(queueHandler.currentIndex + 1).toList();
      final List<Song> interleaved = [];
      int recoIdx = 0;

      for (int i = 0; i < currentUpcoming.length; i++) {
        interleaved.add(currentUpcoming[i]);
        if ((i + 1) % 2 == 0 && recoIdx < filtered.length) {
          interleaved.add(filtered[recoIdx].copyWith(isSmartRecommended: true));
          recoIdx++;
        }
      }

      // If upcoming queue was small, append up to 3 recommended tracks
      while (recoIdx < filtered.length && (interleaved.length < 4 || recoIdx < 3)) {
        interleaved.add(filtered[recoIdx].copyWith(isSmartRecommended: true));
        recoIdx++;
      }

      // 4. Apply Intelligent Shuffle Reordering to preserve acoustic flow
      if (interleaved.length > 2) {
        final orderedIds = await ApiClient.fetchSmartShuffle(interleaved, currentSong);
        final orderedInterleaved = _reorderQueueByIds(interleaved, orderedIds);
        queueHandler.replaceUpcomingQueue(orderedInterleaved);
      } else {
        queueHandler.replaceUpcomingQueue(interleaved);
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

  void dispose() {
    queueHandler.currentIndexNotifier.removeListener(_onQueueProgress);
    queueHandler.queueNotifier.removeListener(_onQueueProgress);
  }
}
