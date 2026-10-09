import 'dart:math';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import 'api_client.dart';
import 'saavn_client.dart';
import 'settings_manager.dart';
import 'app_logger.dart';
import 'queue_cooldown_manager.dart';

class RadioEngine {
  /// Builds a curated 50-track discovery radio mix based on a seed song.
  /// Combines related recommendations, artist top hits, contextual recommendations,
  /// and regional trending tracks while enforcing artist diversity, strict language lockdown,
  /// and anti-cross-language dub deduplication.
  static Future<List<Song>> buildSongRadio(Song seedSong, {int limit = 50}) async {
    final prefLangs = SettingsManager.preferredLanguages;
    final targetLang = (seedSong.language != null && seedSong.language!.isNotEmpty)
        ? seedSong.language!.toLowerCase()
        : (prefLangs.firstOrNull ?? 'tamil').toLowerCase();

    // 1. Fetch Primary Recommendations from Saavn
    List<Song> relatedSongs = [];
    try {
      relatedSongs = await SaavnClient.getRelatedSongs(seedSong.id, language: targetLang);
    } catch (e) {
      AppLogger.log('RadioEngine', 'Primary recommendations fallback: $e');
    }

    // 2. Fetch Seed Artist Top Hits in Target Language
    List<Song> artistHits = [];
    final primaryArtist = seedSong.primaryArtist;
    if (primaryArtist.isNotEmpty && primaryArtist.toLowerCase() != 'various artists') {
      try {
        final query = '$primaryArtist $targetLang hits';
        artistHits = await SaavnClient.search(query, limit: 15, language: targetLang);
      } catch (e) {
        AppLogger.log('RadioEngine', 'Artist hits fallback: $e');
      }
    }

    // 3. Fetch Contextual Recommendations from Backend ML
    List<Song> backendRecs = [];
    try {
      backendRecs = await ApiClient.fetchRecommendations(
        seedSong.id,
        artist: primaryArtist,
        language: targetLang,
      );
    } catch (e) {
      AppLogger.log('RadioEngine', 'Backend recommendations fallback: $e');
    }

    // 4. Fetch Regional Trending in Target Language as Discovery Filler
    List<Song> trending = [];
    try {
      trending = await SongRepository.getTrendingMerged(language: targetLang);
    } catch (e) {
      AppLogger.log('RadioEngine', 'Trending fallback: $e');
    }

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
      targetLanguage: targetLang,
      limit: limit,
    );
  }

  /// Pure filtering and diversity shaping logic:
  /// - Enforces anti-repetition and anti-cross-language dubs against seed song.
  /// - Enforces strict target language isolation.
  /// - Enforces sliding window artist diversity (max 2 songs per artist in any 6-song window).
  /// - Fills up to the specified limit without duplicates.
  static List<Song> shapeRadioQueue({
    required Song seedSong,
    required List<Song> candidatePool,
    String? targetLanguage,
    int limit = 50,
  }) {
    final targetLang = (targetLanguage != null && targetLanguage.isNotEmpty)
        ? targetLanguage.toLowerCase()
        : (seedSong.language?.toLowerCase() ?? 'tamil');

    final List<Song> radioTracks = [seedSong];
    final Set<String> seenKeys = {
      seedSong.id,
      seedSong.canonicalBaseKey,
      seedSong.canonicalSongKey,
      if (seedSong.cleanTitleKey.isNotEmpty) seedSong.cleanTitleKey,
    };

    // Filter candidate pool with anti-repetition & artist diversity
    // Enforce max 2 tracks per artist in any consecutive 6-track window
    for (final candidate in candidatePool) {
      if (radioTracks.length >= limit) break;

      final key = candidate.canonicalBaseKey;
      final titleKey = candidate.cleanTitleKey;
      if (seenKeys.contains(candidate.id) ||
          seenKeys.contains(key) ||
          (titleKey.isNotEmpty && seenKeys.contains(titleKey)) ||
          QueueCooldownManager.isCoolingDown(candidate)) {
        continue;
      }

      // Language check
      if (candidate.language != null && candidate.language!.isNotEmpty) {
        final cLang = candidate.language!.toLowerCase().trim();
        if (cLang != targetLang) {
          continue;
        }
      }

      // Anti-cross-language dub check
      if (candidate.isSameSongOrDub(seedSong) || radioTracks.any((r) => candidate.isSameSongOrDub(r))) {
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
      radioTracks.add(candidate.copyWith(language: targetLang));
    }

    return radioTracks;
  }
}
