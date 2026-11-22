import 'dart:async';
import '../models/song.dart';
import '../domain/models/clustered_track_result.dart';
import '../core/dsa/prefix_trie.dart';

import 'search/search_models.dart';
import 'search/query_normalizer.dart';
import 'search/search_filter_engine.dart';
import 'search/local_catalog_search.dart';
import 'search/search_result_ranker.dart';
import 'search/remote_provider_search.dart';
import 'search/search_collection_helper.dart';
import 'search/search_progressive_orchestrator.dart';

export 'search/search_models.dart';
export 'search/search_cache.dart';
export 'search/query_normalizer.dart';
export 'search/search_filter_engine.dart';
export 'search/local_catalog_search.dart';
export 'search/search_result_ranker.dart';
export 'search/remote_provider_search.dart';
export 'search/search_collection_helper.dart';
export 'search/search_progressive_orchestrator.dart';

/// Facade for the Paatu Padava Search Engine.
/// Coordinates multi-phase progressive search, query normalization,
/// multi-factor relevance ranking, and local catalog indexing.
class SearchService {
  // Regex and constant delegations
  static RegExp get dialogueRegex => QueryNormalizer.dialogueRegex;
  static RegExp get arabicScriptRegex => QueryNormalizer.arabicScriptRegex;
  static RegExp get knownIndianArtistsRegex => QueryNormalizer.knownIndianArtistsRegex;
  static List<String> get knownLanguages => QueryNormalizer.knownLanguages;
  static Map<String, String> get tanglishIndex => QueryNormalizer.tanglishIndex;

  // Generation ID delegations
  static int get currentGenerationId => RemoteProviderSearch.currentGenerationId;
  static int nextGenerationId() => RemoteProviderSearch.nextGenerationId();

  // Query normalization & filtering delegations
  static String expandPhoneticQuery(String query) => QueryNormalizer.expandPhoneticQuery(query);
  static List<String> generateUniversalPhoneticVariants(String query) => QueryNormalizer.generateUniversalPhoneticVariants(query);
  static bool isAlbumOrMovieEntityMatch(String title, String query) => QueryNormalizer.isAlbumOrMovieEntityMatch(title, query);
  static List<Map<String, dynamic>> filterArtistsByLanguage(
    List<Map<String, dynamic>> artists, {
    String? language,
    required String query,
  }) => SearchFilterEngine.filterArtistsByLanguage(artists, language: language, query: query);
  static List<Map<String, dynamic>> filterGenuineAlbums(
    List<Map<String, dynamic>> rawAlbums, {
    String? query,
    String? preferredLanguage,
    List<String>? preferredLanguages,
  }) => SearchFilterEngine.filterGenuineAlbums(rawAlbums, query: query, preferredLanguage: preferredLanguage, preferredLanguages: preferredLanguages);
  static List<Map<String, dynamic>> filterPlaylistsByRelevanceAndLanguage(
    List<Map<String, dynamic>> rawPlaylists, {
    required String query,
    String? language,
  }) => SearchFilterEngine.filterPlaylistsByRelevanceAndLanguage(rawPlaylists, query: query, language: language);
  static List<Map<String, dynamic>> extractAlbumsFromSongList(
    List<Song> songs, {
    String? query,
    List<Map<String, dynamic>>? existingAlbums,
    List<String>? preferredLanguages,
  }) => SearchFilterEngine.extractAlbumsFromSongList(songs, query: query, existingAlbums: existingAlbums, preferredLanguages: preferredLanguages);
  static QueryIntent understandQuery(String raw) => QueryNormalizer.understandQuery(raw);

  // Local catalog search delegations
  static List<Song> searchDownloadedSongs(String query) => LocalCatalogSearch.searchDownloadedSongs(query);

  // Ranking & deduplication delegations
  static double calculateStringSimilarity(Song song, QueryIntent intent) => SearchResultRanker.calculateStringSimilarity(song, intent);
  static double calculateSourcePopularity(Song song) => SearchResultRanker.calculateSourcePopularity(song);
  static double calculateUserAffinity(Song song, {List<Song>? history, List<Song>? favorites}) =>
      SearchResultRanker.calculateUserAffinity(song, history: history, favorites: favorites);
  static double calculateCompositeRelevance(
    Song song,
    QueryIntent intent, {
    List<Song>? history,
    List<Song>? favorites,
    List<String>? preferredLanguages,
    UserAffinityContext? affinityContext,
  }) => SearchResultRanker.calculateCompositeRelevance(song, intent, history: history, favorites: favorites, preferredLanguages: preferredLanguages, affinityContext: affinityContext);
  static double scoreSong(
    Song song,
    QueryIntent intent, {
    required List<String> preferredLanguages,
    List<Song>? history,
    List<Song>? favorites,
  }) => SearchResultRanker.scoreSong(song, intent, preferredLanguages: preferredLanguages, history: history, favorites: favorites);
  static int compareRankedEntries(
    MapEntry<double, Song> a,
    MapEntry<double, Song> b,
    String queryLower, {
    Map<String, int>? arrivalOrder,
    List<String>? preferredLanguages,
  }) => SearchResultRanker.compareRankedEntries(a, b, queryLower, arrivalOrder: arrivalOrder, preferredLanguages: preferredLanguages);
  static List<Song> deduplicateAndRankUnified({
    required List<Song> saavnSongs,
    required List<Song> ytSongs,
    List<Song> audiusSongs = const [],
    required QueryIntent intent,
    List<String>? preferredLanguages,
    List<Song>? history,
    List<Song>? favorites,
    UserAffinityContext? affinityContext,
  }) => SearchResultRanker.deduplicateAndRankUnified(
    saavnSongs: saavnSongs,
    ytSongs: ytSongs,
    audiusSongs: audiusSongs,
    intent: intent,
    preferredLanguages: preferredLanguages,
    history: history,
    favorites: favorites,
    affinityContext: affinityContext,
  );
  static List<Song> interleaveRankedResults(List<Song> primarySongs, List<Song> secondarySongs) =>
      SearchResultRanker.interleaveRankedResults(primarySongs, secondarySongs);

  // Remote provider search delegations
  static void clearTypeaheadCache() => RemoteProviderSearch.clearTypeaheadCache();
  static Future<List<String>> getTypeaheadSuggestions(
    String query, {
    PrefixTrie<String>? localTrie,
    int limit = 10,
    bool skipRemote = false,
    void Function(List<String> partial)? onPartialResults,
  }) => RemoteProviderSearch.getTypeaheadSuggestions(query, localTrie: localTrie, limit: limit, skipRemote: skipRemote, onPartialResults: onPartialResults);
  static Future<SearchTypeaheadBundle> getTypeaheadBundle(
    String query, {
    PrefixTrie<String>? localTrie,
    int limit = 6,
    void Function(SearchTypeaheadBundle partial)? onPartial,
  }) => RemoteProviderSearch.getTypeaheadBundle(query, localTrie: localTrie, limit: limit, onPartial: onPartial);
  static void prewarmQuery(
    String query, {
    String? language,
    void Function(List<Song> songs, List<Map<String, dynamic>> albums)? onPrewarmed,
  }) => RemoteProviderSearch.prewarmQuery(query, language: language, onPrewarmed: onPrewarmed);
  static Future<Map<String, dynamic>?> resolveDirectUrlOrEntity(String clean) => RemoteProviderSearch.resolveDirectUrlOrEntity(clean);
  static List<Map<String, dynamic>> generateAutoPlaylistsFromAlbums(List<Map<String, dynamic>> albums, {int maxCount = 4}) =>
      SearchCollectionHelper.generateAutoPlaylistsFromAlbums(albums, maxCount: maxCount);
  static List<Map<String, dynamic>> mergePlaylists(List<Map<String, dynamic>> primary, List<Map<String, dynamic>> secondary) =>
      SearchCollectionHelper.mergePlaylists(primary, secondary);
  static List<Map<String, dynamic>> ensurePopulatedPlaylists(
    List<Map<String, dynamic>> providerPlaylists,
    List<Song> songs,
    List<Map<String, dynamic>> albums,
    String query, {
    List<String>? preferredLanguages,
  }) => SearchCollectionHelper.ensurePopulatedPlaylists(providerPlaylists, songs, albums, query, preferredLanguages: preferredLanguages);
  static Future<List<Map<String, dynamic>>> searchPlaylists(String query, {String? language, int limit = 20}) =>
      RemoteProviderSearch.searchPlaylists(query, language: language, limit: limit);
  static Future<List<Song>> searchSongsPaged(String query, {int page = 1, int limit = 20, String? language}) =>
      RemoteProviderSearch.searchSongsPaged(query, page: page, limit: limit, language: language);
  static Future<List<Song>> searchSongsTab(String query, {String? language, int limit = 25, int page = 1}) =>
      RemoteProviderSearch.searchSongsTab(query, language: language, limit: limit, page: page);
  static Future<List<Map<String, dynamic>>> searchAlbumsTab(String query, {int limit = 25}) =>
      RemoteProviderSearch.searchAlbumsTab(query, limit: limit);
  static Future<List<Map<String, dynamic>>> searchArtistsTab(String query, {String? language, int limit = 25}) =>
      RemoteProviderSearch.searchArtistsTab(query, language: language, limit: limit);
  static Future<List<Song>> searchYtMusicTab(String query, {String? language, int limit = 25}) =>
      RemoteProviderSearch.searchYtMusicTab(query, language: language, limit: limit);
  static Future<List<Song>> searchAudiusTab(String query, {int limit = 25}) => RemoteProviderSearch.searchAudiusTab(query, limit: limit);
  static Future<void> recordSearchClick(Song song) => RemoteProviderSearch.recordSearchClick(song);
  static List<CollectionSummary> parseAlbumSummaries(List<Map<String, dynamic>> rawAlbums) => SearchCollectionHelper.parseAlbumSummaries(rawAlbums);
  static List<CollectionSummary> parsePlaylistSummaries(List<Map<String, dynamic>> rawPlaylists) => SearchCollectionHelper.parsePlaylistSummaries(rawPlaylists);
  static Future<List<Song>> hydrateCollectionTracks(CollectionSummary summary) => SearchCollectionHelper.hydrateCollectionTracks(summary);
  static List<ClusteredTrackResult> clusterAndClassifySongs(
    List<Song> songs, {
    required String query,
    bool isExplicitMixRequest = false,
  }) => SearchCollectionHelper.clusterAndClassifySongs(songs, query: query, isExplicitMixRequest: isExplicitMixRequest);
  static ClusteredTrackResult? evaluateTopResult(
    List<ClusteredTrackResult> clusters, {
    required String query,
    bool isExplicitMixRequest = false,
  }) => SearchCollectionHelper.evaluateTopResult(clusters, query: query, isExplicitMixRequest: isExplicitMixRequest);
  static Future<ClassifiedSearchPayload> searchClassifiedUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
    int? generationId,
  }) => RemoteProviderSearch.searchClassifiedUnified(
    rawQuery,
    language: language,
    limit: limit,
    generationId: generationId,
    searchUnifiedFn: searchUnified,
  );

  /// Progressive search yielding JioSaavn results immediately (~300ms),
  /// followed by progressively merged YouTube and Audius results.
  static Stream<SearchResults> searchProgressive(
    String rawQuery, {
    String? language,
    QueryIntent? precomputedIntent,
    int limit = 25,
  }) => SearchProgressiveOrchestrator.searchProgressive(
    rawQuery,
    language: language,
    precomputedIntent: precomputedIntent,
    limit: limit,
  );

  /// High-precision unified search across JioSaavn & YouTube Music
  static Future<SearchResults> searchUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
  }) => SearchProgressiveOrchestrator.searchUnified(
    rawQuery,
    language: language,
    limit: limit,
  );
}
