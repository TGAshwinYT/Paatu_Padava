import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../core/dsa/lru_cache.dart';
import '../../core/dsa/prefix_trie.dart';
import '../../domain/models/clustered_track_result.dart';
import '../../logic/search_query_planner.dart';
import '../../data/repositories/song_repository.dart';
import '../saavn_client.dart';
import '../youtube_client.dart';
import '../catalog_database.dart';
import '../settings_manager.dart';
import '../artist_sanitizer.dart';
import '../app_logger.dart';
import '../api_client.dart';
import '../lyrics_search_service.dart';
import '../semantic_search_service.dart';
import 'search_models.dart';
import 'search_cache.dart';
import 'query_normalizer.dart';
import 'local_catalog_search.dart';
import 'search_result_ranker.dart';
import 'search_collection_helper.dart';

/// Handles remote search provider calls (JioSaavn, YouTube, Audius),
/// typeahead debouncing and caching, collection hydration, and clustering.
class RemoteProviderSearch {
  static final LruCache<String, List<String>> _typeaheadLruCache =
      LruCache<String, List<String>>(capacity: 100, defaultTtl: const Duration(minutes: 15));

  static final LruCache<String, SearchTypeaheadBundle> typeaheadBundleCache =
      LruCache<String, SearchTypeaheadBundle>(capacity: 60, defaultTtl: const Duration(minutes: 5));

  static final LruCache<String, List<Song>> _pagedYouTubeCache =
      LruCache<String, List<Song>>(capacity: 30, defaultTtl: const Duration(minutes: 10));

  static int _searchGenerationId = 0;
  static int get currentGenerationId => _searchGenerationId;
  static int nextGenerationId() => ++_searchGenerationId;

  /// Clears typeahead and autocomplete caches on library updates
  static void clearTypeaheadCache() {
    _typeaheadLruCache.clear();
    typeaheadBundleCache.clear();
  }

  /// Queries local PrefixTrie then merges suggestions from YouTube and JioSaavn
  static Future<List<String>> getTypeaheadSuggestions(
    String query, {
    PrefixTrie<String>? localTrie,
    int limit = 10,
    bool skipRemote = false,
    void Function(List<String> partial)? onPartialResults,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    final cacheKey = '${clean.toLowerCase()}|lim=$limit|sr=$skipRemote';
    final cached = _typeaheadLruCache.get(cacheKey);
    if (cached != null) {
      onPartialResults?.call(cached);
      return cached;
    }

    final List<String> suggestions = [];
    final Set<String> seenLower = {};

    void addSuggestion(String s) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) return;
      final lower = trimmed.toLowerCase();
      if (seenLower.add(lower)) {
        suggestions.add(trimmed);
      }
    }

    final List<String> deferredLocal = [];

    if (localTrie != null) {
      final localMatches = localTrie.findByPrefix(clean, limit: limit + 2);
      final maxLocalInitial = skipRemote ? limit : (limit <= 5 ? 2 : (limit * 0.4).ceil());
      for (final m in localMatches) {
        if (suggestions.length < maxLocalInitial) {
          addSuggestion(m.term);
        } else {
          deferredLocal.add(m.term);
        }
      }
      if (suggestions.isNotEmpty) {
        onPartialResults?.call(List<String>.from(suggestions));
      }
    }

    if (skipRemote) {
      return suggestions.take(limit).toList();
    }

    int remoteAddedCount = 0;
    final ytFuture = YouTubeClient.getSearchSuggestions(clean)
        .timeout(const Duration(milliseconds: 600), onTimeout: () => <String>[])
        .catchError((_) => <String>[]);
    final saavnFuture = SaavnClient.getSearchSuggestions(clean)
        .timeout(const Duration(milliseconds: 600), onTimeout: () => <String>[])
        .catchError((_) => <String>[]);

    final f1 = ytFuture.then((ytList) {
      if (ytList.isNotEmpty) {
        bool addedAny = false;
        for (final s in ytList) {
          if (suggestions.length >= limit) break;
          final lenBefore = suggestions.length;
          addSuggestion(s);
          if (suggestions.length > lenBefore) {
            addedAny = true;
            remoteAddedCount++;
          }
        }
        if (addedAny) onPartialResults?.call(List<String>.from(suggestions));
      }
    });

    final f2 = saavnFuture.then((saavnList) {
      if (saavnList.isNotEmpty) {
        bool addedAny = false;
        for (final s in saavnList) {
          if (suggestions.length >= limit) break;
          final lenBefore = suggestions.length;
          addSuggestion(s);
          if (suggestions.length > lenBefore) {
            addedAny = true;
            remoteAddedCount++;
          }
        }
        if (addedAny) onPartialResults?.call(List<String>.from(suggestions));
      }
    });

    try {
      await Future.wait([f1, f2]);
    } catch (e) {
      debugPrint('[RemoteProviderSearch] getTypeaheadSuggestions notice: $e');
    }

    if (suggestions.length < limit && deferredLocal.isNotEmpty) {
      for (final def in deferredLocal) {
        if (suggestions.length >= limit) break;
        addSuggestion(def);
      }
    }

    final result = suggestions.take(limit).toList();
    if (remoteAddedCount > 0 || skipRemote) {
      _typeaheadLruCache.put(cacheKey, result);
    }

    return result;
  }

  /// Fetches rich autocomplete bundle: text completions, top songs, and top albums
  static Future<SearchTypeaheadBundle> getTypeaheadBundle(
    String query, {
    PrefixTrie<String>? localTrie,
    int limit = 6,
    void Function(SearchTypeaheadBundle partial)? onPartial,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const SearchTypeaheadBundle();

    final cacheKey = clean.toLowerCase();
    final cached = typeaheadBundleCache.get(cacheKey);
    if (cached != null) return cached;

    final ytFuture = YouTubeClient.getSearchSuggestions(clean)
        .timeout(const Duration(milliseconds: 350), onTimeout: () => <String>[])
        .catchError((_) => <String>[]);
    final saavnFuture = SaavnClient.getAutocompleteData(clean)
        .timeout(const Duration(milliseconds: 2500), onTimeout: () => <String, dynamic>{})
        .catchError((_) => <String, dynamic>{});

    if (onPartial != null) {
      saavnFuture.then((saavnData) {
        final partialComps = <String>[];
        final seen = <String>{};
        if (localTrie != null) {
          for (final m in localTrie.findByPrefix(clean, limit: 3)) {
            final t = m.term.trim();
            if (t.isNotEmpty && !YouTubeClient.isJunkSuggestion(t) && seen.add(t.toLowerCase())) {
              partialComps.add(t);
            }
          }
        }
        final saavnComps = (saavnData['completions'] as List<dynamic>?)?.cast<String>() ?? <String>[];
        for (final s in saavnComps) {
          final t = s.trim();
          if (partialComps.length < limit && t.isNotEmpty && !YouTubeClient.isJunkSuggestion(t) && seen.add(t.toLowerCase())) {
            partialComps.add(t);
          }
        }
        var sSongs = (saavnData['songs'] as List<dynamic>?)?.cast<Song>() ?? <Song>[];
        var sAlbums = (saavnData['albums'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
        if (sSongs.isEmpty) {
          final cachedSearch = SearchCache.get(clean);
          if (cachedSearch != null && cachedSearch.songs.isNotEmpty) sSongs = cachedSearch.songs;
        }
        if (sAlbums.isEmpty) {
          final cachedSearch = SearchCache.get(clean);
          if (cachedSearch != null && cachedSearch.albums.isNotEmpty) sAlbums = cachedSearch.albums;
        }
        final List<Song> partialDeduped = [];
        for (final s in sSongs) {
          if (partialDeduped.length >= 3) break;
          final isDup = partialDeduped.any((existing) =>
              existing.id == s.id ||
              (s.canonicalBaseKey.isNotEmpty && existing.canonicalBaseKey == s.canonicalBaseKey) ||
              SearchQueryPlanner.isSameSong(
                titleA: existing.title,
                artistsA: existing.artist,
                titleB: s.title,
                artistsB: s.artist,
              ) ||
              (s.cleanTitleKey.isNotEmpty && existing.cleanTitleKey == s.cleanTitleKey));
          if (!isDup) {
            partialDeduped.add(s);
          }
        }
        onPartial(SearchTypeaheadBundle(
          completions: partialComps,
          songs: partialDeduped,
          albums: sAlbums.take(2).toList(),
        ));
      }).catchError((_) {});
    }

    final res = await Future.wait([ytFuture, saavnFuture]);
    final ytCompletions = res[0] as List<String>;
    final saavnData = res[1] as Map<String, dynamic>;

    final completions = <String>[];
    final seen = <String>{};

    void addComp(String s) {
      final t = s.trim();
      if (t.isNotEmpty && !YouTubeClient.isJunkSuggestion(t) && seen.add(t.toLowerCase())) {
        completions.add(t);
      }
    }

    if (localTrie != null) {
      for (final m in localTrie.findByPrefix(clean, limit: 3)) {
        addComp(m.term);
      }
    }

    final saavnComps = (saavnData['completions'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    for (final s in saavnComps) {
      if (completions.length >= limit) break;
      addComp(s);
    }

    for (final s in ytCompletions) {
      if (completions.length >= limit) break;
      addComp(s);
    }

    var songs = (saavnData['songs'] as List<dynamic>?)?.cast<Song>() ?? <Song>[];
    var albums = (saavnData['albums'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];

    if (songs.isEmpty) {
      final cachedSearch = SearchCache.get(clean);
      if (cachedSearch != null && cachedSearch.songs.isNotEmpty) {
        songs = cachedSearch.songs;
      }
    }
    if (albums.isEmpty) {
      final cachedSearch = SearchCache.get(clean);
      if (cachedSearch != null && cachedSearch.albums.isNotEmpty) {
        albums = cachedSearch.albums;
      }
    }

    final List<Song> dedupedSongs = [];
    for (final s in songs) {
      if (dedupedSongs.length >= 3) break;
      final isDup = dedupedSongs.any((existing) =>
          existing.id == s.id ||
          (s.canonicalBaseKey.isNotEmpty && existing.canonicalBaseKey == s.canonicalBaseKey) ||
          SearchQueryPlanner.isSameSong(
            titleA: existing.title,
            artistsA: existing.artist,
            titleB: s.title,
            artistsB: s.artist,
          ) ||
          (s.cleanTitleKey.isNotEmpty && existing.cleanTitleKey == s.cleanTitleKey));
      if (!isDup) {
        dedupedSongs.add(s);
      }
    }

    final bundle = SearchTypeaheadBundle(
      completions: completions,
      songs: dedupedSongs,
      albums: albums.take(2).toList(),
    );

    typeaheadBundleCache.put(cacheKey, bundle);
    return bundle;
  }

  /// Pre-warms the primary search query in the background on debounced typing pauses
  static void prewarmQuery(
    String query, {
    String? language,
    void Function(List<Song> songs, List<Map<String, dynamic>> albums)? onPrewarmed,
  }) {
    final clean = query.trim();
    if (clean.length < 2) return;
    final cached = SearchCache.get(clean, language: language);
    if (cached != null) {
      if (cached.songs.isNotEmpty || cached.albums.isNotEmpty) {
        onPrewarmed?.call(cached.songs.take(3).toList(), cached.albums.take(2).toList());
      }
      return;
    }

    SaavnClient.search(clean, limit: 25, language: language).then((songs) {
      if (songs.isNotEmpty) {
        final existing = SearchCache.get(clean, language: language);
        final extractedAlbums = <Map<String, dynamic>>[];
        final seen = <String>{};
        final qLower = clean.toLowerCase();
        for (final s in songs.take(6)) {
          final alb = s.album.trim();
          final albLower = alb.toLowerCase();
          if (alb.isNotEmpty &&
              albLower != 'single' &&
              albLower != 'unknown' &&
              albLower != 'various artists' &&
              albLower != 'studio album' &&
              (qLower.length > 3 || QueryNormalizer.isAlbumOrMovieEntityMatch(alb, qLower) || albLower == qLower || albLower.startsWith('$qLower ')) &&
              seen.add(albLower)) {
            extractedAlbums.add({
              'id': alb.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase(),
              'title': alb,
              'artist': s.artist,
              'image': s.coverUrl,
              'type': 'Album',
              'is_movie': true,
              'source': s.source,
            });
          }
        }
        if (existing == null) {
          SearchCache.put(
            clean,
            SearchResults(
              songs: songs,
              saavnSongs: songs,
              albums: extractedAlbums,
              playlists: ensurePopulatedPlaylists(
                const [],
                songs,
                extractedAlbums,
                clean,
                preferredLanguages: language != null ? [language] : SettingsManager.preferredLanguages,
              ),
              isFinal: false,
            ),
            language: language,
          );
        }
        onPrewarmed?.call(songs.take(3).toList(), extractedAlbums.take(2).toList());

        final matchedAlb = extractedAlbums.firstWhere(
          (a) => QueryNormalizer.isAlbumOrMovieEntityMatch((a['title'] ?? a['name'] ?? '').toString(), clean),
          orElse: () => typeaheadBundleCache.get(clean)?.albums.firstWhere(
                (a) => QueryNormalizer.isAlbumOrMovieEntityMatch((a['title'] ?? a['name'] ?? '').toString(), clean),
                orElse: () => <String, dynamic>{},
              ) ?? <String, dynamic>{},
        );
        if (matchedAlb.isNotEmpty) {
          final albId = matchedAlb['id']?.toString() ?? '';
          final albTitle = (matchedAlb['title'] ?? matchedAlb['name'] ?? '').toString();
          SongRepository.getAlbumDetails(albumId: albId, albumTitle: albTitle).then((details) {
            final soundtrack = details?['songs'] as List<Song>? ?? <Song>[];
            if (soundtrack.isNotEmpty) {
              final currentCached = SearchCache.get(clean, language: language);
              if (currentCached != null) {
                final merged = <Song>[];
                for (final s in currentCached.songs) {
                  if (s.title.toLowerCase().trim() == clean.toLowerCase().trim() && !merged.any((x) => x.id == s.id)) {
                    merged.add(s);
                  }
                }
                for (final s in soundtrack) {
                  if (!merged.any((x) => x.id == s.id)) merged.add(s);
                }
                for (final s in currentCached.songs) {
                  if (!merged.any((x) => x.id == s.id)) merged.add(s);
                }
                SearchCache.put(
                  clean,
                  SearchResults(
                    songs: merged,
                    saavnSongs: merged,
                    albums: currentCached.albums.isNotEmpty ? currentCached.albums : extractedAlbums,
                    playlists: currentCached.playlists,
                    isFinal: false,
                  ),
                  language: language,
                );
              }
            }
          }).catchError((_) {});
        }
      }
    }).catchError((_) {});
  }

  /// Instant resolution for pasted YouTube URLs or Playlist links
  static Future<Map<String, dynamic>?> resolveDirectUrlOrEntity(String clean) async {
    final ytVideoId = YouTubeClient.extractVideoId(clean);
    final ytPlaylistId = YouTubeClient.extractPlaylistId(clean);

    final isExplicitPlaylist = ytPlaylistId != null &&
        (clean.contains('list=') || RegExp(r'^(?:PL|UU|LL|FL|RD)[a-zA-Z0-9_-]{16,}$').hasMatch(clean) || clean.startsWith('OLAK5uy_'));

    if ((ytVideoId != null && (clean.contains('youtu') || clean.contains('http'))) || isExplicitPlaylist) {
      if (isExplicitPlaylist) {
        final playlistTracks = await YouTubeClient.getPlaylistTracks(ytPlaylistId, limit: 40);
        if (playlistTracks.isNotEmpty) {
          return {
            'type': 'playlist',
            'id': ytPlaylistId,
            'title': 'YouTube Playlist',
            'subtitle': '${playlistTracks.length} tracks (Client Resolved)',
            'image': playlistTracks.first.coverUrl,
            'tracks': playlistTracks,
          };
        }
      } else if (ytVideoId != null) {
        final track = await YouTubeClient.resolveTrackFromUrl(clean);
        if (track != null) {
          return {
            'type': 'song',
            'id': track.id,
            'title': track.title,
            'subtitle': track.artist,
            'image': track.coverUrl,
            'tracks': [track],
          };
        }
      }
    }
    return null;
  }

  /// Synthesizes dynamic 'Movie Soundtrack' auto-playlists directly from album metadata
  static List<Map<String, dynamic>> generateAutoPlaylistsFromAlbums(List<Map<String, dynamic>> albums, {int maxCount = 4}) =>
      SearchCollectionHelper.generateAutoPlaylistsFromAlbums(albums, maxCount: maxCount);

  /// Deduplicates and merges playlist collections across providers
  static List<Map<String, dynamic>> mergePlaylists(List<Map<String, dynamic>> primary, List<Map<String, dynamic>> secondary) =>
      SearchCollectionHelper.mergePlaylists(primary, secondary);

  /// Ensures playlists section is never empty when valid songs or albums exist
  static List<Map<String, dynamic>> ensurePopulatedPlaylists(
    List<Map<String, dynamic>> providerPlaylists,
    List<Song> songs,
    List<Map<String, dynamic>> albums,
    String query, {
    List<String>? preferredLanguages,
  }) => SearchCollectionHelper.ensurePopulatedPlaylists(providerPlaylists, songs, albums, query, preferredLanguages: preferredLanguages);

  /// Searches playlists across JioSaavn, YouTube, and dynamic album-based playlists
  static Future<List<Map<String, dynamic>>> searchPlaylists(
    String query, {
    String? language,
    int limit = 20,
  }) async {
    final intent = QueryNormalizer.understandQuery(query);
    final effectiveLang = intent.explicitLanguage ??
        (language != null && language.isNotEmpty && language.toLowerCase() != 'all' ? language : null);
    final saavnQuery = SearchQueryPlanner.formatProviderQuery(intent.cleanQuery, explicitLanguage: effectiveLang);

    final saavnFuture = SaavnClient.searchPlaylists(saavnQuery, limit: limit, language: effectiveLang)
        .timeout(const Duration(seconds: 4), onTimeout: () => <Map<String, dynamic>>[]);
    final ytFuture = YouTubeClient.searchPlaylists(intent.cleanQuery, limit: limit)
        .timeout(const Duration(seconds: 5), onTimeout: () => <Map<String, dynamic>>[]);
    final albumsFuture = SaavnClient.searchAlbums(saavnQuery, limit: 4)
        .timeout(const Duration(seconds: 3), onTimeout: () => <Map<String, dynamic>>[]);

    final results = await Future.wait([saavnFuture, ytFuture, albumsFuture]);
    final saavnPlaylists = results[0];
    final ytPlaylists = results[1];
    final albums = results[2];

    final autoPlaylists = generateAutoPlaylistsFromAlbums(albums);

    final List<Map<String, dynamic>> merged = [];
    final Set<String> seenTitles = {};

    for (final p in autoPlaylists) {
      final key = (p['title'] ?? '').toString().toLowerCase();
      if (seenTitles.add(key)) merged.add(p);
    }

    final rawMerged = <Map<String, dynamic>>[];
    int sIdx = 0;
    int yIdx = 0;
    while (sIdx < saavnPlaylists.length || yIdx < ytPlaylists.length) {
      if (sIdx < saavnPlaylists.length) {
        final p = saavnPlaylists[sIdx++];
        final key = (p['title'] ?? '').toString().toLowerCase();
        if (key.isNotEmpty && seenTitles.add(key)) rawMerged.add(p);
      }
      if (yIdx < ytPlaylists.length) {
        final p = ytPlaylists[yIdx++];
        final key = (p['title'] ?? '').toString().toLowerCase();
        if (key.isNotEmpty && seenTitles.add(key)) rawMerged.add(p);
      }
    }

    final filteredPlaylists = QueryNormalizer.filterPlaylistsByRelevanceAndLanguage(
      rawMerged,
      query: query,
      language: effectiveLang,
    );
    merged.addAll(filteredPlaylists);
    return merged;
  }

  /// Multi-source paginated song search (JioSaavn + YouTube Music + Canonical Deduplication)
  static Future<List<Song>> searchSongsPaged(
    String query, {
    int page = 1,
    int limit = 20,
    String? language,
  }) async {
    try {
      final intent = QueryNormalizer.understandQuery(query);
      final effectiveLang = intent.explicitLanguage ?? language;

      final saavnFuture = SaavnClient.search(query, limit: limit, page: page, language: effectiveLang)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);

      final ytQuery = SearchQueryPlanner.formatProviderQuery(query, explicitLanguage: effectiveLang);
      final ytOffset = (page - 1) * limit;
      final Future<List<Song>> ytFuture = () async {
        final cached = _pagedYouTubeCache.get(ytQuery);
        if (cached != null) {
          if (ytOffset >= cached.length) return <Song>[];
          return cached.skip(ytOffset).take(limit).toList();
        }
        final pool = await YouTubeClient.search(ytQuery, limit: 25)
            .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
        if (pool.isNotEmpty) {
          _pagedYouTubeCache.put(ytQuery, pool);
        }
        if (ytOffset >= pool.length) return <Song>[];
        return pool.skip(ytOffset).take(limit).toList();
      }();

      final results = await Future.wait([saavnFuture, ytFuture]);
      final saavnSongs = results[0];
      final ytSongs = results[1];

      return SearchResultRanker.deduplicateAndRankUnified(
        saavnSongs: saavnSongs,
        ytSongs: ytSongs,
        intent: intent,
        preferredLanguages: effectiveLang != null ? [effectiveLang] : null,
      );
    } catch (e, stack) {
      AppLogger.log('RemoteProviderSearch', 'searchSongsPaged error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchSongsPaged query="$query", page=$page');
      return <Song>[];
    }
  }

  /// Tab search: Songs only with progressive pagination and semantic ranking
  static Future<List<Song>> searchSongsTab(String query, {String? language, int limit = 25, int page = 1}) async {
    try {
      final songs = await SaavnClient.search(query, limit: limit, page: page, language: language)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
      for (final s in songs) {
        if (s.lyrics != null && s.lyrics!.isNotEmpty) {
          LyricsSearchService.instance.indexLyrics(s, s.lyrics!);
        }
      }

      final lyricHits = LyricsSearchService.instance.searchLyrics(query);
      final List<Song> enrichedSongs = [];
      for (final s in songs) {
        final hit = lyricHits.cast<LyricSearchResult?>().firstWhere(
          (h) => h?.songId == s.id,
          orElse: () => null,
        );
        if (hit != null) {
          enrichedSongs.add(s.copyWith(matchedLyricSnippet: hit.matchingSnippet));
        } else {
          enrichedSongs.add(s);
        }
      }

      for (final hit in lyricHits) {
        if (!enrichedSongs.any((s) => s.id == hit.songId)) {
          final matched = LyricsSearchService.instance.getSong(hit.songId);
          if (matched != null) {
            enrichedSongs.insert(0, matched.copyWith(matchedLyricSnippet: hit.matchingSnippet));
          }
        }
      }

      final grouped = SongRepository.groupCanonicalSongs(enrichedSongs, preferredLanguage: language);
      final deduped = SongRepository.deduplicateSongs(grouped);
      return SemanticSearchService.instance.rankBySemanticIntent(deduped, query);
    } catch (e, stack) {
      AppLogger.log('RemoteProviderSearch', 'searchSongsTab error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchSongsTab query="$query"');
      final offlineMatches = LocalCatalogSearch.searchDownloadedSongs(query);
      if (offlineMatches.isNotEmpty) return offlineMatches;
      return <Song>[];
    }
  }

  /// Tab search: Albums only
  static Future<List<Map<String, dynamic>>> searchAlbumsTab(String query, {int limit = 25}) async {
    try {
      final albumsFuture = SaavnClient.searchAlbums(query, limit: limit)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Map<String, dynamic>>[]);
      final songsFuture = SaavnClient.search(query, limit: 15)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
      final catMoviesFuture = CatalogDatabase.searchMovies(query, limit: limit);
      final res = await Future.wait([albumsFuture, songsFuture, catMoviesFuture]);
      final directAlbums = res[0] as List<Map<String, dynamic>>;
      final songs = res[1] as List<Song>;
      final catMovies = res[2] as List<Map<String, dynamic>>;

      final List<Map<String, dynamic>> correlatedAlbums = [];
      final qClean = query.toLowerCase().trim();
      final qCore = qClean;
      final initialAlbums = correlatedAlbums;
      final Set<String> seenAlbumNames = {};
      final typeaheadBundle = typeaheadBundleCache.get(qClean) ?? typeaheadBundleCache.get(qCore);
      if (typeaheadBundle != null && typeaheadBundle.albums.isNotEmpty) {
        for (final alb in typeaheadBundle.albums) {
          final t = (alb['title'] ?? alb['name'] ?? '').toString().toLowerCase().trim();
          if (t.isNotEmpty && seenAlbumNames.add(t)) {
            initialAlbums.add({...alb, 'type': 'Album', 'is_movie': true});
          }
        }
      }

      for (final m in catMovies) {
        final title = (m['title'] ?? '').toString().trim();
        if (title.isNotEmpty && seenAlbumNames.add(title.toLowerCase())) {
          correlatedAlbums.add(m);
        }
      }

      for (final song in songs) {
        final albName = song.album.trim();
        final albId = song.albumId?.trim() ?? '';
        if (albName.isNotEmpty && albName.toLowerCase() != 'unknown album') {
          final key = albName.toLowerCase();
          if (seenAlbumNames.add(key)) {
            correlatedAlbums.add({
              'id': albId.isNotEmpty ? albId : 'alb_${song.id}',
              'title': albName,
              'image': song.coverUrl,
              'year': '',
              'artist': song.artist,
            });
          }
        }
      }

      for (final alb in directAlbums) {
        final title = (alb['title'] ?? alb['name'] ?? '').toString().trim();
        if (title.isNotEmpty && seenAlbumNames.add(title.toLowerCase())) {
          correlatedAlbums.add(alb);
        }
      }

      return QueryNormalizer.filterGenuineAlbums(correlatedAlbums, query: query);
    } catch (e, stack) {
      AppLogger.log('RemoteProviderSearch', 'searchAlbumsTab error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchAlbumsTab query="$query"');
      return <Map<String, dynamic>>[];
    }
  }

  /// Tab search: Artists only
  static Future<List<Map<String, dynamic>>> searchArtistsTab(String query, {String? language, int limit = 25}) async {
    try {
      final artistsFuture = SaavnClient.searchArtists(query, limit: limit, language: language)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Map<String, dynamic>>[]);
      final songsFuture = SaavnClient.search(query, limit: 15, language: language)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Song>[]);
      final catArtistsFuture = CatalogDatabase.searchArtists(query, limit: limit);
      final res = await Future.wait([artistsFuture, songsFuture, catArtistsFuture]);
      final directArtists = res[0] as List<Map<String, dynamic>>;
      final songs = res[1] as List<Song>;
      final catArtists = res[2] as List<Map<String, dynamic>>;

      final List<Map<String, dynamic>> correlatedArtists = [];
      final Set<String> seenArtistNames = {};

      for (final ca in catArtists) {
        final name = (ca['name'] ?? '').toString().trim();
        if (name.isNotEmpty && seenArtistNames.add(name.toLowerCase())) {
          correlatedArtists.add(ca);
        }
      }

      for (final song in songs) {
        final genuine = ArtistSanitizer.extractAllGenuineArtists(song.artist);
        for (final artName in genuine) {
          if (artName.isNotEmpty && artName.toLowerCase() != 'various artists') {
            final key = artName.toLowerCase();
            if (seenArtistNames.add(key)) {
              correlatedArtists.add({
                'id': 'art_${song.id}_${key.replaceAll(' ', '_')}',
                'name': artName,
                'title': artName,
                'image': song.coverUrl,
                'role': 'Singer / Music Director',
              });
            }
          }
        }
      }

      for (final art in directArtists) {
        final name = (art['name'] ?? art['title'] ?? '').toString().trim();
        if (name.isNotEmpty && seenArtistNames.add(name.toLowerCase())) {
          correlatedArtists.add(art);
        }
      }

      return QueryNormalizer.filterArtistsByLanguage(
        correlatedArtists,
        language: language,
        query: query,
      );
    } catch (e, stack) {
      AppLogger.log('RemoteProviderSearch', 'searchArtistsTab error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchArtistsTab query="$query"');
      return <Map<String, dynamic>>[];
    }
  }

  /// Tab search: YouTube Music tracks
  static Future<List<Song>> searchYtMusicTab(String query, {String? language, int limit = 25}) async {
    try {
      final intent = QueryNormalizer.understandQuery(query);
      final targetLang = intent.explicitLanguage ?? language;
      final ytQuery = (targetLang != null && !query.toLowerCase().contains(targetLang.toLowerCase()))
          ? '$targetLang $query'
          : query;
      var yt = await YouTubeClient.search(ytQuery, limit: limit)
          .timeout(const Duration(seconds: 6), onTimeout: () => <Song>[]);
      if (yt.isEmpty) {
        final saavn = await SaavnClient.search(query, limit: limit, language: language);
        yt = saavn.map((s) => s.copyWith(source: 'youtube')).toList();
      }
      final filteredYt = targetLang != null
          ? SongRepository.filterByLanguage(yt, targetLang)
          : yt;
      final groupedYt = SongRepository.groupCanonicalSongs(filteredYt, preferredLanguage: targetLang);
      return SongRepository.deduplicateSongs(groupedYt);
    } catch (e, stack) {
      AppLogger.log('RemoteProviderSearch', 'searchYtMusicTab error: $e', level: LogLevel.error);
      AppLogger.recordError(e, stack, context: 'searchYtMusicTab query="$query"');
      return <Song>[];
    }
  }

  /// Tab search: Audius tracks (deprecated/removed)
  static Future<List<Song>> searchAudiusTab(String query, {int limit = 25}) async {
    return const <Song>[];
  }

  /// Records a search click event for telemetry
  static Future<void> recordSearchClick(Song song) async {
    try {
      await ApiClient.recordSearchClick(song);
    } catch (e) {
      AppLogger.log('RemoteProviderSearch', 'recordSearchClick error: $e', level: LogLevel.warn);
    }
  }

  /// Converts raw album maps into lightweight CollectionSummary objects
  static List<CollectionSummary> parseAlbumSummaries(List<Map<String, dynamic>> rawAlbums) =>
      SearchCollectionHelper.parseAlbumSummaries(rawAlbums);

  /// Converts raw playlist maps into lightweight CollectionSummary objects
  static List<CollectionSummary> parsePlaylistSummaries(List<Map<String, dynamic>> rawPlaylists) =>
      SearchCollectionHelper.parsePlaylistSummaries(rawPlaylists);

  /// Lazily hydrates the full tracklist for an album or playlist on demand
  static Future<List<Song>> hydrateCollectionTracks(CollectionSummary summary) =>
      SearchCollectionHelper.hydrateCollectionTracks(summary);

  /// Clusters raw candidate songs into ClusteredTrackResults
  static List<ClusteredTrackResult> clusterAndClassifySongs(
    List<Song> songs, {
    required String query,
    bool isExplicitMixRequest = false,
  }) => SearchCollectionHelper.clusterAndClassifySongs(songs, query: query, isExplicitMixRequest: isExplicitMixRequest);

  /// Evaluates whether the top clustered result meets the threshold (>= 0.85) to be crowned Top Result
  static ClusteredTrackResult? evaluateTopResult(
    List<ClusteredTrackResult> clusters, {
    required String query,
    bool isExplicitMixRequest = false,
  }) => SearchCollectionHelper.evaluateTopResult(clusters, query: query, isExplicitMixRequest: isExplicitMixRequest);

  /// High-performance classified search returning grouped studio tracks + fan mixes
  static Future<ClassifiedSearchPayload> searchClassifiedUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
    int? generationId,
    required Future<SearchResults> Function(String query, {String? language, int limit}) searchUnifiedFn,
  }) => SearchCollectionHelper.searchClassifiedUnified(
    rawQuery,
    language: language,
    limit: limit,
    generationId: generationId,
    currentGenerationId: _searchGenerationId,
    searchUnifiedFn: searchUnifiedFn,
  );
}
