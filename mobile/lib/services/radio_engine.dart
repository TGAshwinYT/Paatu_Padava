import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import 'api_client.dart';
import 'history_manager.dart';
import 'player_handler.dart';
import 'saavn_client.dart';
import 'settings_manager.dart';

class RadioEngine {
  /// Builds a curated 50-track discovery radio mix based on a seed song.
  /// Combines related recommendations, artist top hits, contextual recommendations,
  /// and regional trending tracks while enforcing artist diversity and anti-repetition.
  static Future<List<Song>> buildSongRadio(Song seedSong, {int limit = 50}) async {
    final List<Song> radioTracks = [seedSong];
    final Set<String> seenKeys = {
      seedSong.id,
      seedSong.canonicalBaseKey,
      seedSong.canonicalSongKey,
    };

    final prefLangs = SettingsManager.preferredLanguages;
    final primaryLang = prefLangs.isNotEmpty ? prefLangs.first : 'tamil';

    // 1. Fetch Primary Recommendations from Saavn
    List<Song> relatedSongs = [];
    try {
      relatedSongs = await SaavnClient.getRelatedSongs(seedSong.id, language: primaryLang);
    } catch (_) {}

    // 2. Fetch Seed Artist Top Hits
    List<Song> artistHits = [];
    final primaryArtist = seedSong.primaryArtist;
    if (primaryArtist.isNotEmpty && primaryArtist.toLowerCase() != 'various artists') {
      try {
        final query = '$primaryArtist songs';
        artistHits = await SaavnClient.search(query, limit: 15);
      } catch (_) {}
    }

    // 3. Fetch Contextual Recommendations from Backend ML
    List<Song> backendRecs = [];
    try {
      backendRecs = await ApiClient.fetchForYou(language: primaryLang);
    } catch (_) {}

    // 4. Fetch Regional Trending as Discovery Filler
    List<Song> trending = [];
    try {
      trending = await SongRepository.getTrendingMerged(language: primaryLang);
    } catch (_) {}

    // Interleave candidates: Related -> Artist -> Backend ML -> Trending
    final candidatePool = <Song>[];
    final maxLen = [relatedSongs.length, artistHits.length, backendRecs.length, trending.length].reduce(max);

    for (int i = 0; i < maxLen; i++) {
      if (i < relatedSongs.length) candidatePool.add(relatedSongs[i]);
      if (i < backendRecs.length) candidatePool.add(backendRecs[i]);
      if (i < artistHits.length) candidatePool.add(artistHits[i]);
      if (i < trending.length) candidatePool.add(trending[i]);
    }

    return shapeRadioQueue(
      seedSong: seedSong,
      candidatePool: candidatePool,
      limit: limit,
    );
  }

  /// Pure filtering and diversity shaping logic:
  /// - Enforces anti-repetition against seed song.
  /// - Enforces sliding window artist diversity (max 2 songs per artist in any 6-song window).
  /// - Fills up to the specified limit without duplicates.
  static List<Song> shapeRadioQueue({
    required Song seedSong,
    required List<Song> candidatePool,
    int limit = 50,
  }) {
    final List<Song> radioTracks = [seedSong];
    final Set<String> seenKeys = {
      seedSong.id,
      seedSong.canonicalBaseKey,
      seedSong.canonicalSongKey,
    };

    // Filter candidate pool with anti-repetition & artist diversity
    // Enforce max 2 tracks per artist in any consecutive 6-track window
    for (final candidate in candidatePool) {
      if (radioTracks.length >= limit) break;

      final key = candidate.canonicalBaseKey;
      if (seenKeys.contains(candidate.id) || seenKeys.contains(key)) {
        continue;
      }

      // Check sliding window artist diversity
      final candArtist = candidate.primaryArtist;
      final window = radioTracks.length >= 6
          ? radioTracks.sublist(radioTracks.length - 6)
          : radioTracks;

      final countInWindow = window.where((s) => s.primaryArtist == candArtist).length;
      if (countInWindow >= 2) {
        continue;
      }

      seenKeys.add(candidate.id);
      seenKeys.add(key);
      radioTracks.add(candidate);
    }

    // If still under limit, fill with remaining deduplicated songs
    if (radioTracks.length < limit) {
      for (final candidate in candidatePool) {
        if (radioTracks.length >= limit) break;
        final key = candidate.canonicalBaseKey;
        if (!seenKeys.contains(candidate.id) && !seenKeys.contains(key)) {
          seenKeys.add(candidate.id);
          seenKeys.add(key);
          radioTracks.add(candidate);
        }
      }
    }

    return radioTracks;
  }

  /// Starts song radio immediately on the global player
  static Future<int> playSongRadio(Song seedSong) async {
    final radioQueue = await buildSongRadio(seedSong);
    if (radioQueue.isNotEmpty) {
      await audioHandler.playSong(seedSong, queue: radioQueue);
      return radioQueue.length;
    }
    return 0;
  }
}
