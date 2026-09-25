import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/models/track_entity.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/youtube_client.dart';
import '../../services/settings_manager.dart';
import '../../services/auth_manager.dart';

/// Clean Architecture Data Repository: Multi-Source Catalog Aggregator
/// Combines high-bitrate JioSaavn CDN audio with YouTube Music catalog data.
/// Enforces strict language query appending, deduplication via [TrackEntity.deduplicationKey],
/// and smart fallback for duplicate compilation album artwork.
class CatalogRepository {
  static final Map<String, String> _verifiedArtistAvatars = {
    'anirudh ravichander': 'https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg',
    'a.r. rahman': 'https://c.saavncdn.com/artists/A_R_Rahman_500x500.jpg',
    'yuvan shankar raja': 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg',
    'harris jayaraj': 'https://c.saavncdn.com/artists/Harris_Jayaraj_500x500.jpg',
    'hiphop tamizha': 'https://c.saavncdn.com/artists/Hiphop_Tamizha_500x500.jpg',
    'santhosh narayanan': 'https://c.saavncdn.com/artists/Santhosh_Narayanan_500x500.jpg',
    'sid sriram': 'https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg',
    'g. v. prakash kumar': 'https://c.saavncdn.com/artists/G_V_Prakash_Kumar_500x500.jpg',
    'shreya ghoshal': 'https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg',
    'ilaiyaraaja': 'https://c.saavncdn.com/artists/Ilaiyaraaja_500x500.jpg',
    'd. imman': 'https://c.saavncdn.com/artists/D_Imman_500x500.jpg',
    'vijay antony': 'https://c.saavncdn.com/artists/Vijay_Antony_500x500.jpg',
    'pradeep kumar': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg',
    'jonita gandhi': 'https://c.saavncdn.com/artists/Jonita_Gandhi_500x500.jpg',
    'dhee': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg',
    'kaushik krish': 'https://c.saavncdn.com/artists/Kaushik_Krish_500x500.jpg',
    'haricharan': 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg',
    'karthik': 'https://c.saavncdn.com/artists/Karthik_500x500.jpg',
    'chinmayi': 'https://c.saavncdn.com/artists/Chinmayi_Sripada_500x500.jpg',
    'swetha mohan': 'https://c.saavncdn.com/artists/Swetha_Mohan_500x500.jpg',
    's. p. balasubrahmanyam': 'https://c.saavncdn.com/artists/S_P_Balasubrahmanyam_500x500.jpg',
    'k. s. chithra': 'https://c.saavncdn.com/artists/K_S_Chithra_500x500.jpg',
  };

  /// Enforce strict language parameter appending on queries ("$query $language").
  /// Guarantees regional queries prioritize matching language versions over original language releases.
  static String appendLanguageParameter(String query, [String? language]) {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return cleanQ;

    final lang = (language != null && language.isNotEmpty)
        ? language.trim().toLowerCase()
        : (SettingsManager.preferredLanguages.isNotEmpty
            ? SettingsManager.preferredLanguages.first.trim().toLowerCase()
            : (AuthManager.currentUser?.preferredLanguages.isNotEmpty == true
                ? AuthManager.currentUser!.preferredLanguages.first.trim().toLowerCase()
                : 'tamil'));

    if (lang.isEmpty || lang == 'all') return cleanQ;

    final lower = cleanQ.toLowerCase();
    const knownLanguages = [
      'tamil', 'telugu', 'hindi', 'malayalam', 'kannada',
      'english', 'punjabi', 'marathi', 'bengali'
    ];

    if (knownLanguages.any((l) => lower.contains(l))) {
      return cleanQ;
    }

    final capitalized = lang[0].toUpperCase() + lang.substring(1);
    return '$cleanQ $capitalized';
  }

  /// Multi-source aggregated search querying JioSaavn CDN and YouTube Music in parallel.
  /// Deduplicates across both sources using [TrackEntity.deduplicationKey] and applies distinct artwork.
  static Future<List<TrackEntity>> searchAggregated(
    String query, {
    String? language,
    int limit = 25,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final biasedQuery = appendLanguageParameter(cleanQuery, language);
    debugPrint('[CatalogRepository] Aggregated search for: "$biasedQuery" (raw: "$cleanQuery", limit: $limit)');

    try {
      final results = await Future.wait([
        // 1. Direct JioSaavn CDN query (320kbps high fidelity)
        SaavnClient.search(biasedQuery, limit: limit, language: language).catchError((_) => <Song>[]),
        // 2. Direct YouTube Music search (Innertube client)
        YouTubeClient.search(biasedQuery, limit: limit).catchError((_) => <Song>[]),
      ]);

      final saavnTracks = results[0].map((s) => TrackEntity.fromSong(s)).toList();
      final ytTracks = results[1].map((s) => TrackEntity.fromSong(s)).toList();

      // Interleave results, prioritizing high-fidelity JioSaavn
      final List<TrackEntity> merged = [];
      final int maxLen = saavnTracks.length > ytTracks.length ? saavnTracks.length : ytTracks.length;
      for (int i = 0; i < maxLen; i++) {
        if (i < saavnTracks.length) merged.add(saavnTracks[i]);
        if (i < ytTracks.length) merged.add(ytTracks[i]);
      }

      // Deduplicate using deduplicationKey
      final deduplicated = deduplicateTracks(merged);

      // Re-rank by language relevance match
      final targetLang = (language ?? 'tamil').toLowerCase();
      deduplicated.sort((a, b) {
        final aMatch = a.title.toLowerCase().contains(targetLang) ||
            a.language?.toLowerCase() == targetLang;
        final bMatch = b.title.toLowerCase().contains(targetLang) ||
            b.language?.toLowerCase() == targetLang;
        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;
        return 0;
      });

      // Ensure distinct artwork across consecutive items
      return ensureDistinctArtwork(deduplicated);
    } catch (e) {
      debugPrint('[CatalogRepository] Search error: $e');
      return [];
    }
  }

  /// Deduplicates a list of TrackEntity objects across all catalogs.
  /// Deduplication is strictly evaluated on [TrackEntity.deduplicationKey] and track ID.
  static List<TrackEntity> deduplicateTracks(List<TrackEntity> tracks) {
    final List<TrackEntity> unique = [];
    final Set<String> seenKeys = {};
    final Set<String> seenIds = {};

    for (final track in tracks) {
      final key = track.deduplicationKey;
      final id = track.id.trim();

      if (id.isNotEmpty && seenIds.contains(id)) continue;
      if (key.isNotEmpty && seenKeys.contains(key)) continue;

      if (id.isNotEmpty) seenIds.add(id);
      if (key.isNotEmpty) seenKeys.add(key);
      unique.add(track);
    }

    return unique;
  }

  /// Deduplicates legacy Song models via deduplicationKey
  static List<Song> deduplicateSongs(List<Song> songs) {
    final tracks = songs.map((s) => TrackEntity.fromSong(s)).toList();
    return deduplicateTracks(tracks).map((t) => t.toSong()).toList();
  }

  /// Ensures compilation album covers with identical URLs (e.g. repeated "100% Melodies")
  /// fall back to track-specific verified artist avatars or YouTube thumbnails.
  static List<TrackEntity> ensureDistinctArtwork(List<TrackEntity> tracks) {
    if (tracks.isEmpty) return [];

    final List<TrackEntity> result = [];
    final Map<String, int> coverFrequency = {};

    // 1. Calculate occurrence frequency of each cover URL
    for (final track in tracks) {
      final c = track.coverUrl.trim();
      if (c.isNotEmpty) {
        coverFrequency[c] = (coverFrequency[c] ?? 0) + 1;
      }
    }

    final Set<String> assignedCovers = {};

    // 2. Iterate and replace duplicate compilation covers
    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final currentCover = track.coverUrl.trim();
      final isDuplicate = (coverFrequency[currentCover] ?? 0) > 1;

      if (!isDuplicate || !assignedCovers.contains(currentCover)) {
        if (currentCover.isNotEmpty) assignedCovers.add(currentCover);
        result.add(track);
      } else {
        // Fallback Strategy 1: Match primary artist avatar from verified map
        String fallbackCover = '';
        final artistParts = track.artist.toLowerCase().split(RegExp(r'[,&/]'));
        for (final part in artistParts) {
          final trimmed = part.trim();
          if (_verifiedArtistAvatars.containsKey(trimmed)) {
            fallbackCover = _verifiedArtistAvatars[trimmed]!;
            break;
          }
        }

        // Fallback Strategy 2: If track is from YouTube or has YouTube ID format, use high-res video thumbnail
        if (fallbackCover.isEmpty && (track.source == 'youtube' || track.id.length == 11)) {
          fallbackCover = 'https://img.youtube.com/vi/${track.id}/hqdefault.jpg';
        }

        // Fallback Strategy 3: Dynamic high-res artist avatar from CDN
        if (fallbackCover.isEmpty && track.artist.isNotEmpty) {
          final cleanArtist = track.artist.split(',').first.trim().replaceAll(' ', '_');
          fallbackCover = 'https://c.saavncdn.com/artists/${cleanArtist}_500x500.jpg';
        }

        final distinctCover = fallbackCover.isNotEmpty ? fallbackCover : currentCover;
        assignedCovers.add(distinctCover);
        result.add(track.copyWith(coverUrl: distinctCover));
      }
    }

    return result;
  }
}
