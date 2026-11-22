import '../../models/song.dart';
import '../../core/dsa/lru_cache.dart';
import '../../domain/models/clustered_track_result.dart';
import '../../logic/search_query_planner.dart';
import '../../logic/track_quality_filter.dart';
import '../../data/repositories/song_repository.dart';
import '../app_logger.dart';
import 'search_models.dart';

/// Helper for collection summaries, playlist synthesis, clustering, and classification.
class SearchCollectionHelper {
  static final LruCache<String, ClassifiedSearchPayload> classifiedLruCache =
      LruCache<String, ClassifiedSearchPayload>(capacity: 25);

  static final LruCache<String, List<Song>> hydratedCollectionCache =
      LruCache<String, List<Song>>(capacity: 30);

  /// Synthesizes dynamic 'Movie Soundtrack' auto-playlists directly from album metadata
  static List<Map<String, dynamic>> generateAutoPlaylistsFromAlbums(
    List<Map<String, dynamic>> albums, {
    int maxCount = 4,
  }) {
    final List<Map<String, dynamic>> autoPlaylists = [];
    for (final album in albums.take(maxCount)) {
      final title = (album['title'] ?? album['name'] ?? '').toString().trim();
      final id = album['id']?.toString() ?? '';
      final img = album['image']?.toString() ?? album['cover_url']?.toString() ?? '';
      final artist = album['artist']?.toString() ?? album['composer']?.toString() ?? '';
      final songCount = album['song_count'] ?? 0;
      if (title.isNotEmpty) {
        autoPlaylists.add({
          'id': id.isNotEmpty ? id : 'pl_${title.toLowerCase().replaceAll(' ', '_')}',
          'title': '$title (All Songs)',
          'subtitle': songCount > 0 ? '$songCount Tracks • Movie Playlist' : 'Movie Playlist',
          'image': img,
          'artist': artist,
          'song_count': songCount,
          'source': id.startsWith('mov_') || id.startsWith('jailer') || id.startsWith('leo') ? 'catalog' : 'auto_album',
          'type': 'playlist',
        });
      }
    }
    return autoPlaylists;
  }

  /// Deduplicates and merges playlist collections across providers
  static List<Map<String, dynamic>> mergePlaylists(
    List<Map<String, dynamic>> primary,
    List<Map<String, dynamic>> secondary,
  ) {
    final List<Map<String, dynamic>> merged = [];
    final Set<String> seen = {};

    for (final p in primary) {
      final key = (p['title'] ?? '').toString().toLowerCase().trim();
      if (key.isNotEmpty && seen.add(key)) {
        merged.add(p);
      }
    }

    for (final p in secondary) {
      final key = (p['title'] ?? '').toString().toLowerCase().trim();
      if (key.isNotEmpty && seen.add(key)) {
        merged.add(p);
      }
    }

    return merged;
  }

  /// Ensures playlists section is never empty when valid songs or albums exist
  static List<Map<String, dynamic>> ensurePopulatedPlaylists(
    List<Map<String, dynamic>> providerPlaylists,
    List<Song> songs,
    List<Map<String, dynamic>> albums,
    String query, {
    List<String>? preferredLanguages,
  }) {
    final List<Map<String, dynamic>> result = List.from(providerPlaylists);
    final Set<String> seenIds = {
      for (final p in result) (p['id'] ?? p['title'] ?? '').toString().toLowerCase().trim()
    };
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return result;

    for (final alb in albums.take(3)) {
      final title = (alb['title'] ?? alb['name'] ?? '').toString().trim();
      final id = 'pl_${title.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_ost';
      if (title.isNotEmpty && seenIds.add(id)) {
        result.add({
          'id': id,
          'title': '$title Soundtracks',
          'artist': alb['artist'] ?? alb['composer'] ?? 'Various Artists',
          'image': alb['image'] ?? alb['cover_url'] ?? (songs.isNotEmpty ? songs.first.coverUrl : ''),
          'type': 'Playlist',
          'source': 'auto_album',
          'song_count': alb['song_count'] ?? 10,
        });
      }
    }

    if (result.length < 3 && songs.isNotEmpty) {
      final bestOfTitle = '${SearchQueryPlanner.cleanTitle(cleanQ)} Hits';
      final bestOfId = 'pl_${cleanQ.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_hits';
      if (seenIds.add(bestOfId)) {
        result.insert(0, {
          'id': bestOfId,
          'title': bestOfTitle,
          'artist': songs.first.artist,
          'image': songs.first.coverUrl,
          'type': 'Playlist',
          'source': 'auto_hits',
          'song_count': songs.length,
        });
      }
    }

    return result;
  }

  /// Converts raw album maps into lightweight CollectionSummary objects
  static List<CollectionSummary> parseAlbumSummaries(List<Map<String, dynamic>> rawAlbums) {
    final List<CollectionSummary> list = [];
    final Set<String> seen = {};
    for (final alb in rawAlbums) {
      final title = alb['title']?.toString() ?? alb['name']?.toString() ?? '';
      if (title.isEmpty) continue;
      final key = title.toLowerCase().trim();
      if (seen.contains(key)) continue;
      seen.add(key);

      list.add(CollectionSummary(
        id: alb['id']?.toString() ?? '',
        title: title,
        subtitle: alb['artist']?.toString() ?? alb['subtitle']?.toString() ?? 'Album',
        artworkUrl: alb['image']?.toString() ?? alb['cover_url']?.toString() ?? '',
        type: CollectionType.album,
        trackCount: (alb['song_count'] as num?)?.toInt(),
      ));
    }
    return list;
  }

  /// Converts raw playlist maps into lightweight CollectionSummary objects
  static List<CollectionSummary> parsePlaylistSummaries(List<Map<String, dynamic>> rawPlaylists) {
    final List<CollectionSummary> list = [];
    final Set<String> seen = {};
    for (final pl in rawPlaylists) {
      final title = pl['title']?.toString() ?? pl['name']?.toString() ?? '';
      if (title.isEmpty) continue;
      final key = title.toLowerCase().trim();
      if (seen.contains(key)) continue;
      seen.add(key);

      list.add(CollectionSummary(
        id: pl['id']?.toString() ?? '',
        title: title,
        subtitle: pl['subtitle']?.toString() ?? 'Playlist',
        artworkUrl: pl['image']?.toString() ?? pl['cover_url']?.toString() ?? '',
        type: CollectionType.playlist,
        trackCount: (pl['song_count'] as num?)?.toInt(),
      ));
    }
    return list;
  }

  /// Lazily hydrates the full tracklist for an album or playlist on demand
  static Future<List<Song>> hydrateCollectionTracks(CollectionSummary summary) async {
    final cached = hydratedCollectionCache.get(summary.id);
    if (cached != null) return cached;

    List<Song> songs = [];
    try {
      if (summary.type == CollectionType.album) {
        final details = await SongRepository.getAlbumDetails(
          albumId: summary.id,
          albumTitle: summary.title,
        );
        if (details != null && details['songs'] is List<Song>) {
          songs = details['songs'] as List<Song>;
        }
      } else {
        final src = (summary.id.startsWith('VL') || summary.id.startsWith('RD')) ? 'youtube' : 'saavn';
        final details = await SongRepository.getRemotePlaylistTracks(
          playlistId: summary.id,
          playlistTitle: summary.title,
          source: src,
        );
        if (details['tracks'] is List<Song>) {
          songs = details['tracks'] as List<Song>;
        }
      }
    } catch (e) {
      AppLogger.log('SearchCollectionHelper', 'Error hydrating collection ${summary.title}: $e');
    }

    if (songs.isNotEmpty) {
      hydratedCollectionCache.put(summary.id, songs);
    }
    return songs;
  }

  /// Clusters raw candidate songs into ClusteredTrackResults
  static List<ClusteredTrackResult> clusterAndClassifySongs(
    List<Song> songs, {
    required String query,
    bool isExplicitMixRequest = false,
  }) {
    if (songs.isEmpty) return const [];

    final Map<String, List<Song>> groups = {};
    final Map<String, ContentClassification> classifications = {};

    for (final song in songs) {
      final classification = TrackQualityFilter.classifyTrack(
        title: song.title,
        durationSec: song.duration,
        source: song.source,
        artist: song.artist,
        query: query,
      );

      if (classification == ContentClassification.rejectedJunk) {
        continue;
      }

      classifications[song.id] = classification;

      final coreTitle = SearchQueryPlanner.extractNormalizedCoreTitle(song.title);
      final primaryArtist = song.primaryArtist.toLowerCase().trim();
      final groupKey = '$coreTitle|$primaryArtist';

      groups.putIfAbsent(groupKey, () => []).add(song);
    }

    final List<ClusteredTrackResult> clusters = [];

    for (final entry in groups.entries) {
      final candidates = entry.value;
      if (candidates.isEmpty) continue;

      candidates.sort((a, b) {
        final classA = classifications[a.id] ?? ContentClassification.officialTrack;
        final classB = classifications[b.id] ?? ContentClassification.officialTrack;

        if (classA == ContentClassification.officialTrack && classB != ContentClassification.officialTrack) {
          return -1;
        }
        if (classB == ContentClassification.officialTrack && classA != ContentClassification.officialTrack) {
          return 1;
        }

        final scoreA = SearchQueryPlanner.calculateRelevanceScore(
          query: query,
          song: a,
          classification: classA,
          isExplicitMixRequest: isExplicitMixRequest,
        );
        final scoreB = SearchQueryPlanner.calculateRelevanceScore(
          query: query,
          song: b,
          classification: classB,
          isExplicitMixRequest: isExplicitMixRequest,
        );
        return scoreB.compareTo(scoreA);
      });

      final primary = candidates.first;
      final alternates = candidates.skip(1).toList();
      final primaryClass = classifications[primary.id] ?? ContentClassification.officialTrack;

      final confidence = SearchQueryPlanner.calculateRelevanceScore(
        query: query,
        song: primary,
        classification: primaryClass,
        isExplicitMixRequest: isExplicitMixRequest,
      );

      final combinedVersions = <Song>[
        ...primary.versions,
        ...alternates.where((alt) => !primary.versions.any((v) => v.id == alt.id && v.source == alt.source)),
      ];

      final hydratedPrimary = primary.copyWith(
        versions: combinedVersions,
      );

      clusters.add(ClusteredTrackResult(
        primaryTrack: hydratedPrimary,
        category: primaryClass,
        confidenceScore: confidence,
        alternateVersions: combinedVersions,
      ));
    }

    clusters.sort((a, b) {
      final cmp = b.confidenceScore.compareTo(a.confidenceScore);
      if (cmp != 0) return cmp;
      return a.primaryTrack.id.compareTo(b.primaryTrack.id);
    });
    return clusters;
  }

  /// Evaluates whether the top clustered result meets the threshold (>= 0.85) to be crowned Top Result
  static ClusteredTrackResult? evaluateTopResult(
    List<ClusteredTrackResult> clusters, {
    required String query,
    bool isExplicitMixRequest = false,
  }) {
    if (clusters.isEmpty) return null;
    final top = clusters.first;

    if (top.confidenceScore < 0.85) {
      return null;
    }

    if (top.category != ContentClassification.officialTrack && !isExplicitMixRequest) {
      return null;
    }

    return top;
  }

  /// High-performance classified search returning grouped studio tracks + fan mixes
  static Future<ClassifiedSearchPayload> searchClassifiedUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
    int? generationId,
    required int currentGenerationId,
    required Future<SearchResults> Function(String query, {String? language, int limit}) searchUnifiedFn,
  }) async {
    final clean = rawQuery.trim();
    if (clean.isEmpty) {
      return const ClassifiedSearchPayload(query: '');
    }

    final cacheKey = '${clean.toLowerCase()}__${language?.toLowerCase() ?? ""}';
    final cached = classifiedLruCache.get(cacheKey);
    if (cached != null) {
      return cached;
    }

    final intent = SearchQueryPlanner.analyzeQuery(clean, explicitLanguage: language);
    final rawResults = await searchUnifiedFn(clean, language: language, limit: limit);

    if (generationId != null && generationId != currentGenerationId) {
      return const ClassifiedSearchPayload(query: '');
    }

    final allRawSongs = [
      ...rawResults.songs,
      ...rawResults.saavnSongs,
      ...rawResults.ytSongs,
    ];

    final clusters = clusterAndClassifySongs(
      allRawSongs,
      query: clean,
      isExplicitMixRequest: intent.isExplicitMixRequest,
    );

    final topResult = evaluateTopResult(
      clusters,
      query: clean,
      isExplicitMixRequest: intent.isExplicitMixRequest,
    );

    final albums = parseAlbumSummaries(rawResults.albums);
    final playlists = parsePlaylistSummaries(rawResults.playlists);

    final payload = ClassifiedSearchPayload(
      query: clean,
      clusteredSongs: clusters,
      albums: albums,
      playlists: playlists,
      artists: rawResults.artists,
      topResult: topResult,
      didYouMean: rawResults.didYouMean,
    );

    if (!payload.isEmpty) {
      classifiedLruCache.put(cacheKey, payload);
    }

    return payload;
  }
}
