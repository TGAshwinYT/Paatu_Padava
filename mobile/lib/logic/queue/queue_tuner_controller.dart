import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../services/app_logger.dart';
import '../../services/favorites_manager.dart';
import '../../services/history_manager.dart';
import '../../services/queue_cooldown_manager.dart';
import '../../services/radio_engine.dart';
import '../../services/saavn_client.dart';
import '../../services/settings_manager.dart';
import '../audio_queue_handler.dart';
import '../markov_cosine_radio_strategy.dart';
import '../next_track_strategy.dart';
import '../track_quality_filter.dart';
import 'queue_tuner_mode.dart';

/// Controller managing real-time queue mood/vibe lenses (Mix, Familiar, Discover, Composer).
/// Acts as the presentation layer above NextTrackStrategy (Option A over Option C).
class QueueTunerController {
  final AudioQueueHandler? queueHandler;
  final ValueNotifier<QueueTunerMode> modeNotifier = ValueNotifier(QueueTunerMode.mix);

  QueueTunerMode get mode => modeNotifier.value;
  bool _isTuning = false;

  QueueTunerController({this.queueHandler});

  /// Changes active tuner mode and instantly recalculates upcoming auto-suggestions.
  Future<void> setTunerMode(QueueTunerMode newMode) async {
    if (modeNotifier.value == newMode && !_isTuning) return;
    modeNotifier.value = newMode;

    if (queueHandler == null) return;
    final currentSong = queueHandler!.currentSong;
    if (currentSong == null) return;

    _isTuning = true;
    try {
      AppLogger.log('QueueTunerController', 'Switching tuner mode to "${newMode.name}" for "${currentSong.title}"');

      // 1. Fetch fresh candidate pool from the user's active backend strategy
      final strategy = NextTrackStrategyFactory.getStrategy(SettingsManager.nextTrackStrategy);
      List<Song> baseCandidates = await strategy.getUpcomingTracks(
        seedSong: currentSong,
        queue: queueHandler!.queue,
        history: HistoryManager.getHistory(),
        count: 24,
      );

      // Safe fallback if active strategy yielded empty list
      if (baseCandidates.isEmpty) {
        baseCandidates = await RadioEngine.buildSongRadio(currentSong, limit: 20);
      }

      // 2. Apply active Tuner lens
      final tunedCandidates = await filterAndRankCandidates(
        seedSong: currentSong,
        candidates: baseCandidates,
        mode: newMode,
      );

      // 3. Update AudioQueueHandler upcoming auto-suggestions
      if (tunedCandidates.isNotEmpty) {
        final capped = tunedCandidates.take(15).toList();
        await queueHandler!.replaceAutoSuggestions(capped);
      }
    } catch (e, stack) {
      AppLogger.recordError(e, stack, context: 'QueueTunerController.setTunerMode');
    } finally {
      _isTuning = false;
    }
  }

  /// Filters and ranks a candidate pool according to the specified [QueueTunerMode].
  static Future<List<Song>> filterAndRankCandidates({
    required Song seedSong,
    required List<Song> candidates,
    required QueueTunerMode mode,
  }) async {
    final List<Song> pool = List<Song>.from(candidates);

    switch (mode) {
      case QueueTunerMode.mix:
        return _rankForMix(seedSong, pool);

      case QueueTunerMode.familiar:
        return _rankForFamiliar(seedSong, pool);

      case QueueTunerMode.discover:
        return _rankForDiscover(seedSong, pool);

      case QueueTunerMode.composer:
        return await _rankForComposer(seedSong, pool);
    }
  }

  // ================= 1. Balanced Mix (Default) ================= //
  static List<Song> _rankForMix(Song seedSong, List<Song> pool) {
    final seedIsDevotional = TrackQualityFilter.isDevotionalSong(seedSong);
    final scored = <MapEntry<double, Song>>[];
    for (final c in pool) {
      if (c.isSameSongOrDub(seedSong)) continue;
      if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(c)) continue;
      final vector = SongFeatureVector.extractRelative(seedSong, c);
      double score = vector.compositeVectorScore;

      if (RadioEngine.isSharedMusicDirectorOrComposer(seedSong, c)) {
        score += 0.30;
      }
      final seedYear = RadioEngine.extractReleaseYear(seedSong);
      final cYear = RadioEngine.extractReleaseYear(c);
      if (seedYear != null && cYear != null && (seedYear - cYear).abs() <= 4) {
        score += 0.25;
      }

      scored.add(MapEntry(score, c));
    }
    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.map((e) => e.value).toList();
  }

  // ================= 2. Familiar (Songs & Artists User Loves) ================= //
  static List<Song> _rankForFamiliar(Song seedSong, List<Song> pool) {
    final history = HistoryManager.getHistory();
    final favorites = FavoritesManager.getFavorites();
    final seedIsDevotional = TrackQualityFilter.isDevotionalSong(seedSong);

    final knownIds = <String>{};
    final knownKeys = <String>{};
    final artistPlayCount = <String, int>{};

    for (final s in history) {
      if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(s)) continue;
      knownIds.add(s.id);
      knownKeys.add(s.canonicalBaseKey);
      if (s.cleanTitleKey.isNotEmpty) knownKeys.add(s.cleanTitleKey);
      final a = QueueCooldownManager.normalizeArtistKey(s.primaryArtist);
      if (a.isNotEmpty) {
        artistPlayCount[a] = (artistPlayCount[a] ?? 0) + 1;
      }
    }
    for (final s in favorites) {
      if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(s)) continue;
      knownIds.add(s.id);
      knownKeys.add(s.canonicalBaseKey);
      if (s.cleanTitleKey.isNotEmpty) knownKeys.add(s.cleanTitleKey);
      final a = QueueCooldownManager.normalizeArtistKey(s.primaryArtist);
      if (a.isNotEmpty) {
        artistPlayCount[a] = (artistPlayCount[a] ?? 0) + 2;
      }
    }

    final scored = <MapEntry<double, Song>>[];
    for (final c in pool) {
      if (c.isSameSongOrDub(seedSong)) continue;
      if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(c)) continue;
      double score = 1.0;
      final isExactKnown = knownIds.contains(c.id) ||
          knownKeys.contains(c.canonicalBaseKey) ||
          knownKeys.contains(c.cleanTitleKey);

      if (isExactKnown) {
        score += 8.0;
      }

      final cArtist = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);
      final plays = artistPlayCount[cArtist] ?? 0;
      score += min(5.0, plays * 0.5);

      scored.add(MapEntry(score, c));
    }

    scored.sort((a, b) => b.key.compareTo(a.key));
    final ranked = scored.map((e) => e.value).toList();

    // If candidate pool didn't have enough familiar tracks, supplement from favorites/history
    if (ranked.where((s) => knownIds.contains(s.id)).length < 3) {
      final targetLang = (seedSong.language ?? 'tamil').toLowerCase();
      final familiarGems = [...favorites, ...history].where((s) {
        if (s.isSameSongOrDub(seedSong)) return false;
        if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(s)) return false;
        final sLang = s.language?.toLowerCase();
        return sLang == null || sLang == targetLang;
      }).take(5);

      for (final g in familiarGems) {
        if (!ranked.any((r) => r.isSameSongOrDub(g))) {
          ranked.insert(0, g);
        }
      }
    }

    return ranked;
  }

  // ================= 3. Discover (Strict Fresh Music) ================= //
  static List<Song> _rankForDiscover(Song seedSong, List<Song> pool) {
    final history = HistoryManager.getHistory();
    final favorites = FavoritesManager.getFavorites();
    final seedIsDevotional = TrackQualityFilter.isDevotionalSong(seedSong);

    final knownIds = <String>{};
    final knownKeys = <String>{};
    final heavyArtists = <String>{};

    for (final s in history) {
      if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(s)) continue;
      knownIds.add(s.id);
      knownKeys.add(s.canonicalBaseKey);
      if (s.cleanTitleKey.isNotEmpty) knownKeys.add(s.cleanTitleKey);
      final a = QueueCooldownManager.normalizeArtistKey(s.primaryArtist);
      if (a.isNotEmpty) heavyArtists.add(a);
    }
    for (final s in favorites) {
      if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(s)) continue;
      knownIds.add(s.id);
      knownKeys.add(s.canonicalBaseKey);
      if (s.cleanTitleKey.isNotEmpty) knownKeys.add(s.cleanTitleKey);
      final a = QueueCooldownManager.normalizeArtistKey(s.primaryArtist);
      if (a.isNotEmpty) heavyArtists.add(a);
    }

    // Filter out known songs and devotional tracks
    final freshPool = pool.where((c) {
      if (c.isSameSongOrDub(seedSong)) return false;
      if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(c)) return false;
      if (knownIds.contains(c.id)) return false;
      if (knownKeys.contains(c.canonicalBaseKey)) return false;
      if (c.cleanTitleKey.isNotEmpty && knownKeys.contains(c.cleanTitleKey)) return false;
      return true;
    }).toList();

    final scored = <MapEntry<double, Song>>[];
    for (final c in freshPool) {
      double score = 5.0;
      final cArtist = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);

      // Reward artists the user hasn't played often
      if (!heavyArtists.contains(cArtist)) {
        score += 4.0;
      }
      final vector = SongFeatureVector.extractRelative(seedSong, c);
      score += vector.compositeVectorScore;

      scored.add(MapEntry(score, c));
    }

    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.map((e) => e.value).toList();
  }

  // ================= 4. Composer Flow (Music Director Focus) ================= //
  static Future<List<Song>> _rankForComposer(Song seedSong, List<Song> pool) async {
    final seedIsDevotional = TrackQualityFilter.isDevotionalSong(seedSong);
    final scored = <MapEntry<double, Song>>[];
    final matchingComposer = <Song>[];
    final nonMatching = <Song>[];

    for (final c in pool) {
      if (c.isSameSongOrDub(seedSong)) continue;
      if (!seedIsDevotional && TrackQualityFilter.isDevotionalSong(c)) continue;
      if (RadioEngine.isSharedMusicDirectorOrComposer(seedSong, c)) {
        matchingComposer.add(c);
      } else {
        nonMatching.add(c);
      }
    }

    // If candidate pool has fewer than 4 composer tracks, fetch directly from Saavn
    if (matchingComposer.length < 5) {
      try {
        final director = _resolveMusicDirectorName(seedSong);
        if (director.isNotEmpty) {
          final lang = seedSong.language ?? 'tamil';
          final searchRes = await SaavnClient.search('$director $lang hits', limit: 10, language: lang);
          for (final s in searchRes) {
            if (!s.isSameSongOrDub(seedSong) &&
                (seedIsDevotional || !TrackQualityFilter.isDevotionalSong(s)) &&
                !matchingComposer.any((m) => m.isSameSongOrDub(s))) {
              matchingComposer.add(s);
            }
          }
        }
      } catch (_) {}
    }

    for (final c in matchingComposer) {
      final vector = SongFeatureVector.extractRelative(seedSong, c);
      scored.add(MapEntry(10.0 + vector.compositeVectorScore, c));
    }
    for (final c in nonMatching) {
      final vector = SongFeatureVector.extractRelative(seedSong, c);
      scored.add(MapEntry(vector.compositeVectorScore, c));
    }

    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.map((e) => e.value).toList();
  }

  static String _resolveMusicDirectorName(Song s) {
    final raw = '${s.artist}, ${s.primaryArtist}'.toLowerCase();
    for (final md in [
      'anirudh', 'ar rahman', 'a r rahman', 'yuvan', 'harris jayaraj',
      'ilaiyaraaja', 'ilayaraja', 'santhosh narayanan', 'gv prakash',
      'd imman', 'deva', 'vidyasagar', 'keeravaani', 'pritam', 'thaman',
      'devi sri prasad', 'sushin shyam', 'shaan rahman', 'jakes bejoy'
    ]) {
      if (raw.contains(md)) return md;
    }
    return s.primaryArtist;
  }
}
