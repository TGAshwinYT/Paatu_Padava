import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import '../services/radio_engine.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';
import '../services/youtube_client.dart';
import '../services/queue_cooldown_manager.dart';

abstract class NextTrackStrategy {
  String get id;
  String get displayName;
  String get description;

  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 5,
  });
}

/// Spotify-style: Cohesive seed-based collaborative filtering, same-soundtrack OST tracks,
/// composer hit clusters, strict language lockdown, and anti-cross-language dub deduplication.
class SpotifyStyleStrategy implements NextTrackStrategy {
  @override
  String get id => 'spotify_style';

  @override
  String get displayName => 'Spotify Style (Cohesive Clusters)';

  @override
  String get description => 'Curates closely related acoustic clusters, similar tempo, and collaborative seeds';

  @override
  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 5,
  }) async {
    try {
      final prefLangs = SettingsManager.preferredLanguages;
      final targetLang = (seedSong.language != null && seedSong.language!.isNotEmpty)
          ? seedSong.language!.toLowerCase()
          : (prefLangs.firstOrNull ?? 'tamil').toLowerCase();

      // 1. Fetch from multi-tier Spotify-style cohesive sources concurrently
      final List<Future<List<Song>>> futures = [
        // Source A: Backend Machine Learning Collaborative Recommender (Language Locked)
        ApiClient.fetchRecommendations(
          seedSong.id,
          artist: seedSong.primaryArtist,
          language: targetLang,
        ),
        // Source B: Same Composer / Primary Artist Top Hits in Target Language
        if (seedSong.primaryArtist.isNotEmpty && seedSong.primaryArtist.toLowerCase() != 'various artists')
          SaavnClient.search('${seedSong.primaryArtist} $targetLang hits', limit: 12, language: targetLang),
        // Source C: Same Movie Soundtrack / Album hit tracks
        if (seedSong.album.isNotEmpty && seedSong.album.toLowerCase() != 'unknown album')
          SaavnClient.search('${seedSong.album} $targetLang songs', limit: 8, language: targetLang),
        // Source D: JioSaavn related tracks
        SaavnClient.getRelatedSongs(seedSong.id, language: targetLang),
      ];

      final results = await Future.wait(futures);
      final List<Song> allCandidates = results.expand((x) => x).toList();

      // 2. Build strict exclusion set to eliminate repeat plays
      final Set<String> exclusions = {};
      for (final s in queue) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      for (final s in history) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      exclusions.add(seedSong.id);
      exclusions.add(seedSong.canonicalBaseKey);
      if (seedSong.cleanTitleKey.isNotEmpty) exclusions.add(seedSong.cleanTitleKey);

      final Set<String> seenKeys = {};
      final List<Song> filtered = [];
      final Map<String, int> artistCounts = {};

      for (final c in allCandidates) {
        if (c.title.trim().isEmpty) continue;
        final baseKey = c.canonicalBaseKey;
        final titleKey = c.cleanTitleKey;

        // 1. Basic ID, Canonical Title & 75-song cooldown exclusion
        if (exclusions.contains(c.id) ||
            exclusions.contains(baseKey) ||
            (titleKey.isNotEmpty && (exclusions.contains(titleKey) || seenKeys.contains(titleKey))) ||
            seenKeys.contains(baseKey) ||
            QueueCooldownManager.isCoolingDown(c)) {
          continue;
        }

        // 2. STRICT Language Isolation Gate:
        // Never allow foreign/dubbed language tracks into a single-language radio stream
        if (c.language != null && c.language!.isNotEmpty) {
          final cLang = c.language!.toLowerCase().trim();
          if (cLang != targetLang) {
            continue;
          }
        }

        // 3. STRICT Anti-Cross-Language Dub Check:
        // Drop any candidate that is a dubbed release or identical musical recording of seedSong
        if (c.isSameSongOrDub(seedSong)) {
          continue;
        }

        // Check against active upcoming queue to prevent duplicate dubbed variants
        if (queue.any((q) => c.isSameSongOrDub(q)) || filtered.any((f) => c.isSameSongOrDub(f))) {
          continue;
        }

        // 4. Sliding Window Artist Diversity (max 2 songs per artist in suggestion pool)
        final cArtist = c.primaryArtist;
        final currentArtistCount = artistCounts[cArtist] ?? 0;
        if (currentArtistCount >= 2) {
          continue;
        }

        seenKeys.add(baseKey);
        if (titleKey.isNotEmpty) seenKeys.add(titleKey);
        artistCounts[cArtist] = currentArtistCount + 1;
        filtered.add(c.copyWith(isSmartRecommended: true, language: targetLang));
        if (filtered.length >= count) break;
      }

      // If pool is still small, fill with Regional Trending in target language
      if (filtered.length < count) {
        final trending = await SaavnClient.getTrending(language: targetLang);
        for (final s in trending) {
          final baseKey = s.canonicalBaseKey;
          if (exclusions.contains(s.id) ||
              exclusions.contains(baseKey) ||
              seenKeys.contains(baseKey) ||
              s.isSameSongOrDub(seedSong) ||
              filtered.any((f) => s.isSameSongOrDub(f))) {
            continue;
          }
          if (s.language != null && s.language!.isNotEmpty && s.language!.toLowerCase() != targetLang) {
            continue;
          }
          seenKeys.add(baseKey);
          filtered.add(s.copyWith(isSmartRecommended: true, language: targetLang));
          if (filtered.length >= count) break;
        }
      }

      return filtered;
    } catch (e) {
      debugPrint('[SpotifyStyleStrategy] Error: $e');
      return [];
    }
  }
}

/// YouTube Music-style: Algorithmic related video autoplay queue from YouTubeExplode,
/// genre-adjacent discovery, and strict anti-dub language consistency.
class YtMusicStyleStrategy implements NextTrackStrategy {
  @override
  String get id => 'ytmusic_style';

  @override
  String get displayName => 'YouTube Music Style (Eclectic Radio)';

  @override
  String get description => 'Deeper discovery, algorithmic radio seeds, and genre-adjacent track exploration';

  @override
  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 5,
  }) async {
    try {
      final prefLangs = SettingsManager.preferredLanguages;
      final targetLang = (seedSong.language != null && seedSong.language!.isNotEmpty)
          ? seedSong.language!.toLowerCase()
          : (prefLangs.firstOrNull ?? 'tamil').toLowerCase();

      // 1. Fetch native YouTube Music related autoplay tracks
      final List<Song> candidatePool = [];
      try {
        final ytRelated = await YouTubeClient.getRelatedSongs(seedSong, limit: count * 2);
        candidatePool.addAll(ytRelated);
      } catch (e) {
        debugPrint('[YtMusicStyleStrategy] YouTube related fetch notice: $e');
      }

      // 2. Supplement with RadioEngine curated candidate pool if YouTube yielded few tracks
      if (candidatePool.length < count) {
        final radioTracks = await RadioEngine.buildSongRadio(seedSong, limit: count * 2);
        candidatePool.addAll(radioTracks);
      }

      // 3. Build exclusions
      final Set<String> exclusions = {};
      for (final s in queue) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      for (final s in history) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
        if (s.cleanTitleKey.isNotEmpty) exclusions.add(s.cleanTitleKey);
      }
      exclusions.add(seedSong.id);
      exclusions.add(seedSong.canonicalBaseKey);
      if (seedSong.cleanTitleKey.isNotEmpty) exclusions.add(seedSong.cleanTitleKey);

      final Set<String> seenKeys = {};
      final List<Song> upcoming = [];
      final Map<String, int> artistCounts = {};

      for (final s in candidatePool) {
        if (s.title.trim().isEmpty) continue;
        final baseKey = s.canonicalBaseKey;
        final titleKey = s.cleanTitleKey;
        if (exclusions.contains(s.id) ||
            exclusions.contains(baseKey) ||
            (titleKey.isNotEmpty && (exclusions.contains(titleKey) || seenKeys.contains(titleKey))) ||
            seenKeys.contains(baseKey) ||
            QueueCooldownManager.isCoolingDown(s)) {
          continue;
        }

        // Language check
        if (s.language != null && s.language!.isNotEmpty) {
          final sLang = s.language!.toLowerCase().trim();
          if (sLang != targetLang) {
            continue;
          }
        }

        // Anti-cross-language dub check
        if (s.isSameSongOrDub(seedSong)) {
          continue;
        }
        if (queue.any((q) => s.isSameSongOrDub(q)) || upcoming.any((u) => s.isSameSongOrDub(u))) {
          continue;
        }

        // Artist diversity
        final artist = s.primaryArtist;
        final countForArtist = artistCounts[artist] ?? 0;
        if (countForArtist >= 2) {
          continue;
        }

        seenKeys.add(baseKey);
        if (titleKey.isNotEmpty) seenKeys.add(titleKey);
        artistCounts[artist] = countForArtist + 1;
        upcoming.add(s.copyWith(isSmartRecommended: true, language: targetLang));
        if (upcoming.length >= count) break;
      }

      // Fallback if still under target count: use SpotifyStyleStrategy
      if (upcoming.isEmpty) {
        final fallback = SpotifyStyleStrategy();
        return await fallback.getUpcomingTracks(
          seedSong: seedSong,
          queue: queue,
          history: history,
          count: count,
        );
      }

      return upcoming;
    } catch (e) {
      debugPrint('[YtMusicStyleStrategy] Error: $e');
      return [];
    }
  }
}

class NextTrackStrategyFactory {
  static NextTrackStrategy getStrategy(NextTrackStrategyMode mode) {
    switch (mode) {
      case NextTrackStrategyMode.spotifyStyle:
        return SpotifyStyleStrategy();
      case NextTrackStrategyMode.ytMusicStyle:
        return YtMusicStyleStrategy();
    }
  }
}
