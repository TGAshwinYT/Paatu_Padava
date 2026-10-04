import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import '../services/radio_engine.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';

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

/// Spotify-style: Cohesive seed-based collaborative filtering, audio cluster similarity,
/// strict artist diversity caps, and gentle transition curves.
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
      final primaryLang = prefLangs.firstOrNull ?? 'tamil';

      // 1. Fetch from collaborative filtering backend + JioSaavn related tracks
      final List<Future<List<Song>>> futures = [
        ApiClient.fetchRecommendations(
          seedSong.id,
          artist: seedSong.artist,
          language: primaryLang,
        ),
        SaavnClient.getRelatedSongs(seedSong.id, language: primaryLang),
        SaavnClient.search('${seedSong.artist} hits', limit: count, language: primaryLang),
      ];

      final results = await Future.wait(futures);
      final List<Song> allCandidates = results.expand((x) => x).toList();

      // Build exclusion set
      final Set<String> exclusions = {};
      for (final s in queue) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
      }
      for (final s in history) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
      }
      exclusions.add(seedSong.id);
      exclusions.add(seedSong.canonicalBaseKey);

      final Set<String> seenKeys = {};
      final List<Song> filtered = [];

      for (final c in allCandidates) {
        if (c.title.trim().isEmpty) continue;
        final baseKey = c.canonicalBaseKey;
        if (exclusions.contains(c.id) || exclusions.contains(baseKey) || seenKeys.contains(baseKey)) {
          continue;
        }

        // Check artist diversity in current selection (at most 1 per 3 tracks)
        final cArtist = c.primaryArtist;
        final recentWindow = filtered.length >= 3 ? filtered.sublist(filtered.length - 3) : filtered;
        if (recentWindow.any((s) => s.primaryArtist == cArtist)) {
          continue;
        }

        seenKeys.add(baseKey);
        filtered.add(c.copyWith(isSmartRecommended: true));
        if (filtered.length >= count) break;
      }

      return filtered;
    } catch (e) {
      debugPrint('[SpotifyStyleStrategy] Error: $e');
      return [];
    }
  }
}

/// YouTube Music-style: Radio-mix exploration, related video autoplay seeds,
/// genre-adjacent discovery, and energetic variety.
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
      final primaryLang = prefLangs.firstOrNull ?? 'tamil';

      // 1. First attempt native YouTube Music contextual radio mix
      final radioTracks = await RadioEngine.buildSongRadio(seedSong);

      // 2. Build exclusions
      final Set<String> exclusions = {};
      for (final s in queue) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
      }
      for (final s in history) {
        exclusions.add(s.id);
        exclusions.add(s.canonicalBaseKey);
      }
      exclusions.add(seedSong.id);
      exclusions.add(seedSong.canonicalBaseKey);

      final Set<String> seenKeys = {};
      final List<Song> upcoming = [];

      for (final s in radioTracks) {
        if (s.title.trim().isEmpty) continue;
        final baseKey = s.canonicalBaseKey;
        if (exclusions.contains(s.id) || exclusions.contains(baseKey) || seenKeys.contains(baseKey)) {
          continue;
        }
        seenKeys.add(baseKey);
        upcoming.add(s.copyWith(isSmartRecommended: true));
        if (upcoming.length >= count) break;
      }

      // If YouTube radio yielded fewer tracks, supplement with trending in user language
      if (upcoming.length < count) {
        final trending = await SaavnClient.getTrending(language: primaryLang);
        for (final s in trending) {
          final baseKey = s.canonicalBaseKey;
          if (exclusions.contains(s.id) || exclusions.contains(baseKey) || seenKeys.contains(baseKey)) {
            continue;
          }
          seenKeys.add(baseKey);
          upcoming.add(s.copyWith(isSmartRecommended: true));
          if (upcoming.length >= count) break;
        }
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
