import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';
import 'audio_queue_handler.dart';

enum SmartShuffleMode {
  off,        // Sequential playback
  standard,   // Shuffles only user's added songs
  smart,      // User queue + automatic recommendation interleaving
}

class SmartShuffleController {
  final AudioQueueHandler queueHandler;
  final ValueNotifier<SmartShuffleMode> modeNotifier = ValueNotifier(SmartShuffleMode.off);

  SmartShuffleMode get mode => modeNotifier.value;
  bool get isSmartActive => mode == SmartShuffleMode.smart;
  bool get isStandardActive => mode == SmartShuffleMode.standard;

  bool _isIngesting = false;
  final List<String> _recentHistoryIds = [];

  SmartShuffleController({required this.queueHandler}) {
    // Listen to queue changes & index updates to trigger Smart recommendation ingestion
    queueHandler.currentIndexNotifier.addListener(_onQueueProgress);
    queueHandler.queueNotifier.addListener(_onQueueProgress);
  }

  void recordRecentlyPlayed(String songId) {
    _recentHistoryIds.remove(songId);
    _recentHistoryIds.insert(0, songId);
    if (_recentHistoryIds.length > 25) {
      _recentHistoryIds.removeLast();
    }
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
  void setMode(SmartShuffleMode newMode) {
    if (modeNotifier.value == newMode) return;
    modeNotifier.value = newMode;

    final currentIndex = queueHandler.currentIndex;
    if (currentIndex < 0 || currentIndex >= queueHandler.queue.length) return;

    if (newMode == SmartShuffleMode.standard) {
      // 1. Standard Shuffle: Shuffles only the user's added songs (purging smart tracks)
      final upcoming = queueHandler.queue
          .sublist(currentIndex + 1)
          .where((s) => !s.isSmartRecommended)
          .toList()
        ..shuffle();
      queueHandler.replaceUpcomingQueue(upcoming);
    } else if (newMode == SmartShuffleMode.smart) {
      // 2. Smart Shuffle: Immediately check and interleave recommendations
      if (queueHandler.upcomingCount < 3) {
        ingestSmartRecommendations();
      }
    } else {
      // 3. Off: Restore sequential order and purge smart injected songs
      final originalList = queueHandler.originalQueue;
      final currentSong = queueHandler.currentSong;
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

  /// Smart Ingestion Engine: Fetches related tracks and interleaves 1 track every 2-3 tracks
  Future<void> ingestSmartRecommendations() async {
    if (_isIngesting || !isSmartActive) return;
    if (queueHandler.upcomingCount >= 4) return;

    final currentSong = queueHandler.currentSong;
    if (currentSong == null) return;

    _isIngesting = true;
    final prefLang = SettingsManager.preferredLanguages.firstOrNull ?? 'tamil';

    try {
      // 1. Fetch recommendations from JioSaavn or Backend recommendation graph
      List<Song> candidates = await SaavnClient.getRelatedSongs(currentSong.id, language: prefLang);
      if (candidates.isEmpty) {
        candidates = await ApiClient.fetchRecommendations(
          currentSong.id,
          artist: currentSong.artist,
          language: prefLang,
        );
      }
      if (candidates.isEmpty) {
        candidates = await SaavnClient.search('${currentSong.artist} hits', limit: 10, language: prefLang);
      }

      // 2. Strict language filter & deduplication against queue and recent history
      final currentQueueIds = queueHandler.queue.map((s) => s.id).toSet();
      final filtered = candidates.where((candidate) {
        if (currentQueueIds.contains(candidate.id)) return false;
        if (_recentHistoryIds.contains(candidate.id)) return false;

        // Strict language adherence
        if (candidate.language != null && candidate.language!.isNotEmpty) {
          if (candidate.language!.toLowerCase() != prefLang.toLowerCase()) return false;
        }
        return true;
      }).toList();

      if (filtered.isEmpty) {
        _isIngesting = false;
        return;
      }

      // 3. Interleave 1 recommended track every 2-3 tracks into upcoming queue
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

      queueHandler.replaceUpcomingQueue(interleaved);
    } catch (e) {
      debugPrint('[SmartShuffleController] Ingestion error: $e');
    } finally {
      _isIngesting = false;
    }
  }

  void dispose() {
    queueHandler.currentIndexNotifier.removeListener(_onQueueProgress);
    queueHandler.queueNotifier.removeListener(_onQueueProgress);
  }
}
