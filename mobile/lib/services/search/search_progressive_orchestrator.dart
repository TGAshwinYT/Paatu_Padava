import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../domain/models/app_error.dart';
import '../saavn_client.dart';
import '../youtube_client.dart';
import '../settings_manager.dart';
import '../fuzzy_search_service.dart';
import '../error_handler.dart';
import '../app_logger.dart';
import '../artist_sanitizer.dart';
import '../catalog_database.dart';
import '../user_preference_matrix.dart';
import '../../logic/search_query_planner.dart';
import '../../logic/lyrics/indic_romanizer.dart';
import '../../data/repositories/song_repository.dart';

import 'search_models.dart';
import 'search_cache.dart';
import 'query_normalizer.dart';
import 'search_filter_engine.dart';
import 'local_catalog_search.dart';
import 'search_result_ranker.dart';
import 'remote_provider_search.dart';
import 'search_collection_helper.dart';

/// Orchestrates the 3-phase progressive search pipeline:
/// Phase 0: Instant Master Catalog Yield (0-15ms)
/// Phase 1: JioSaavn Online Yield (~300ms)
/// Phase 2: YouTube / Federated Fallback & Progressive Merge
class SearchProgressiveOrchestrator {
  /// Progressive search yielding JioSaavn results immediately (~300ms),
  /// followed by progressively merged YouTube and Audius results.
  static Stream<SearchResults> searchProgressive(
    String rawQuery, {
    String? language,
    QueryIntent? precomputedIntent,
    int limit = 25,
  }) async* {
    final normalizedRaw = rawQuery.trim().toLowerCase();
    final intent = precomputedIntent ?? QueryNormalizer.understandQuery(normalizedRaw);
    if (intent.cleanQuery.isEmpty) {
      yield SearchResults();
      return;
    }

    final prefLangs = SettingsManager.preferredLanguages;
    final effectiveLang = intent.explicitLanguage ??
        (language != null && language.isNotEmpty && language.toLowerCase() != 'all' && language.toLowerCase() != 'any' ? language : null);

    // SWR: Yield fast LRU cache immediately
    final cached = SearchCache.get(rawQuery, language: effectiveLang) ?? SearchCache.get(rawQuery);
    if (cached != null) {
      yield SearchResults(
        songs: cached.songs,
        ytSongs: cached.ytSongs,
        saavnSongs: cached.saavnSongs,
        audiusSongs: cached.audiusSongs,
        albums: cached.albums,
        artists: cached.artists,
        playlists: cached.playlists,
        topResult: cached.topResult,
        didYouMean: cached.didYouMean,
        error: cached.error,
        isFinal: false,
        isCached: true,
      );
    }

    final saavnSearchQuery = SearchQueryPlanner.formatProviderQuery(intent.cleanQuery, explicitLanguage: effectiveLang);

    bool saavnFailed = false;
    bool ytFailed = false;
    SearchResults? lastEmittedBundle;
    List<Song> catalogSongs = [];
    List<Map<String, dynamic>> initialAlbums = [];
    List<Map<String, dynamic>> initialArtists = [];
    List<Map<String, dynamic>> initialPlaylists = [];

    try {
      final Future<List<Song>> saavnFuture = () async {
        try {
          final results = await SaavnClient.search(
            saavnSearchQuery,
            limit: limit,
            language: effectiveLang,
          ).timeout(const Duration(seconds: 4), onTimeout: () {
            saavnFailed = true;
            return <Song>[];
          });
          if (results.isNotEmpty) saavnFailed = false;
          return results;
        } catch (e) {
          saavnFailed = true;
          debugPrint('[SearchProgressiveOrchestrator] Upstream Saavn primary search fault isolated: $e');
          return <Song>[];
        }
      }();

      final Future<List<Song>> transliteratedSaavnFuture = () async {
        if (intent.transliteratedQuery == intent.cleanQuery) {
          if (effectiveLang != null && effectiveLang != 'english' && !intent.cleanQuery.toLowerCase().contains(effectiveLang.toLowerCase())) {
            try {
              return await SaavnClient.search('${intent.cleanQuery} $effectiveLang', limit: limit, language: effectiveLang).timeout(const Duration(seconds: 2), onTimeout: () => <Song>[]);
            } catch (_) { return <Song>[]; }
          }
          return <Song>[];
        }
        try {
          final transQuery = SearchQueryPlanner.formatProviderQuery(intent.transliteratedQuery, explicitLanguage: effectiveLang);
          return await SaavnClient.search(
            transQuery,
            limit: limit,
            language: effectiveLang,
          ).timeout(const Duration(seconds: 2), onTimeout: () => <Song>[]);
        } catch (e) {
          debugPrint('[SearchProgressiveOrchestrator] Upstream Saavn transliterated search fault isolated: $e');
          return <Song>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> albumsFuture = () async {
        try {
          final cachedBundle = RemoteProviderSearch.typeaheadBundleCache.get(intent.cleanQuery.toLowerCase()) ??
              RemoteProviderSearch.typeaheadBundleCache.get(intent.effectiveCoreQuery.toLowerCase());
          final cachedAlbums = cachedBundle?.albums ?? const <Map<String, dynamic>>[];
          var alb = await SaavnClient.searchAlbums(intent.cleanQuery, limit: 16)
              .timeout(const Duration(milliseconds: 2000), onTimeout: () => <Map<String, dynamic>>[]);
          if (alb.isEmpty && intent.effectiveCoreQuery != intent.cleanQuery && intent.effectiveCoreQuery != saavnSearchQuery) {
            alb = await SaavnClient.searchAlbums(intent.effectiveCoreQuery, limit: 16)
                .timeout(const Duration(milliseconds: 2000), onTimeout: () => <Map<String, dynamic>>[]);
          }
          if (alb.isEmpty && saavnSearchQuery.toLowerCase() != intent.cleanQuery.toLowerCase()) {
            final cleanAlbs = await SaavnClient.searchAlbums(saavnSearchQuery, limit: 16)
                .timeout(const Duration(milliseconds: 2000), onTimeout: () => <Map<String, dynamic>>[]);
            alb.addAll(cleanAlbs);
          }
          return cachedAlbums.isNotEmpty ? [...cachedAlbums, ...alb] : alb;
        } catch (e) {
          debugPrint('[SearchProgressiveOrchestrator] Upstream Saavn albums search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> artistsFuture = () async {
        try {
          final isGeneric = intent.cleanQuery.toLowerCase() == 'top hits' ||
              intent.cleanQuery.toLowerCase() == 'hits' ||
              intent.cleanQuery.toLowerCase() == 'top songs' ||
              intent.cleanQuery.toLowerCase() == 'songs';
          final artistSearchQuery = SearchQueryPlanner.formatArtistQuery(intent.effectiveCoreQuery, explicitLanguage: effectiveLang, isGeneric: isGeneric);
          final rawArtists = await SaavnClient.searchArtists(artistSearchQuery, limit: 12, language: effectiveLang)
              .timeout(const Duration(seconds: 2), onTimeout: () => <Map<String, dynamic>>[]);
          return SearchFilterEngine.filterArtistsByLanguage(rawArtists, language: effectiveLang, query: intent.effectiveCoreQuery);
        } catch (e) {
          debugPrint('[SearchProgressiveOrchestrator] Upstream Saavn artists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> playlistsFuture = () async {
        try {
          final pList = await SaavnClient.searchPlaylists(intent.cleanQuery, limit: 10, language: effectiveLang).timeout(const Duration(seconds: 2), onTimeout: () => <Map<String, dynamic>>[]);
          if (pList.isNotEmpty || saavnSearchQuery.toLowerCase() == intent.cleanQuery.toLowerCase()) return pList;
          return await SaavnClient.searchPlaylists(saavnSearchQuery, limit: 10, language: effectiveLang)
              .timeout(const Duration(seconds: 2), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          debugPrint('[SearchProgressiveOrchestrator] Upstream Saavn playlists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      final ytSearchQuery = SearchQueryPlanner.formatProviderQuery(intent.cleanQuery, explicitLanguage: effectiveLang);

      final Future<List<Song>> ytFuture = () async {
        try {
          final res = await YouTubeClient.search(ytSearchQuery, limit: limit)
              .timeout(const Duration(milliseconds: 3500), onTimeout: () {
            ytFailed = true;
            return <Song>[];
          });
          if (res.isNotEmpty) ytFailed = false;
          return res;
        } catch (e, stack) {
          ytFailed = true;
          AppLogger.recordError(e, stack, context: 'SearchProgressiveOrchestrator: YouTube search failed for query "$ytSearchQuery"');
          AppLogger.log('SearchProgressiveOrchestrator', 'Upstream YouTube search fault isolated: $e');
          debugPrint('[SearchProgressiveOrchestrator] Upstream YouTube search fault isolated: $e');
          return <Song>[];
        }
      }();

      final Future<List<Map<String, dynamic>>> ytPlaylistsFuture = () async {
        try {
          final ytPls = await YouTubeClient.searchPlaylists('${intent.cleanQuery} songs', limit: 8).timeout(const Duration(milliseconds: 1400), onTimeout: () => <Map<String, dynamic>>[]);
          if (ytPls.isNotEmpty) return ytPls;
          return await YouTubeClient.searchPlaylists(intent.cleanQuery, limit: 8)
              .timeout(const Duration(milliseconds: 1200), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          debugPrint('[SearchProgressiveOrchestrator] Upstream YouTube playlists search fault isolated: $e');
          return <Map<String, dynamic>>[];
        }
      }();

      // ── PHASE 0: Instant Local Master Catalog Yield (0-15ms) ──
      catalogSongs = [];
      List<Map<String, dynamic>> catMovies = [];
      List<Map<String, dynamic>> catArtists = [];
      try {
        catalogSongs = await LocalCatalogSearch.searchCatalogSongs(intent, language: effectiveLang, limit: limit);
        catMovies = await LocalCatalogSearch.searchCatalogMovies(intent, limit: 8);
        catArtists = await LocalCatalogSearch.searchCatalogArtists(intent, limit: 6);
      } catch (e, stack) {
        AppLogger.log('SearchProgressiveOrchestrator', 'Phase 0 local catalog search error: $e', level: LogLevel.warn);
        AppLogger.recordError(e, stack, context: 'Phase 0 local catalog search failed for query "${intent.cleanQuery}"');
      }

      final phase0Albums = catMovies.map((m) => {
        ...m,
        'image': m['image'] ?? m['cover_url'] ?? '',
      }).toList();
      final phase0Playlists = SearchCollectionHelper.generateAutoPlaylistsFromAlbums(phase0Albums);

      if (catalogSongs.isNotEmpty || phase0Albums.isNotEmpty) {
        final phase0Bundle = SearchResults(
          songs: catalogSongs,
          saavnSongs: catalogSongs,
          albums: phase0Albums,
          artists: catArtists,
          playlists: phase0Playlists,
          isFinal: false,
        );
        lastEmittedBundle = phase0Bundle;
        yield phase0Bundle;
      }

      // ── PHASE 1: JioSaavn Online Yield (~300ms) ──
      final saavnResults = await Future.wait([
        saavnFuture,
        transliteratedSaavnFuture,
        albumsFuture,
        artistsFuture,
        playlistsFuture,
      ]);

      final rawSaavn = saavnResults[0] as List<Song>;
      final rawTransSaavn = saavnResults[1] as List<Song>;
      final rawAlbums = saavnResults[2] as List<Map<String, dynamic>>;
      final artists = saavnResults[3] as List<Map<String, dynamic>>;
      final rawPlaylists = saavnResults[4] as List<Map<String, dynamic>>;

      final List<Song> combinedSaavn = [...catalogSongs, ...rawSaavn, ...rawTransSaavn];
      final groupedSaavn = SongRepository.groupCanonicalSongs(combinedSaavn, preferredLanguage: effectiveLang, preferredLanguages: prefLangs);
      final deduplicatedSaavn = SongRepository.deduplicateSongs(groupedSaavn);

      List<Song> candidateSaavn = intent.explicitLanguage != null
          ? SongRepository.filterByLanguage(deduplicatedSaavn, intent.explicitLanguage!)
          : deduplicatedSaavn;

      bool bypassedExplicitLang = false;
      if (candidateSaavn.isEmpty && deduplicatedSaavn.isNotEmpty && intent.explicitLanguage != null) {
        candidateSaavn = deduplicatedSaavn;
        bypassedExplicitLang = true;
      }

      final queryAffinityCtx = UserAffinityContext.fromSongs();
      final scoredSaavn = candidateSaavn.map((s) {
        final score = SearchResultRanker.calculateCompositeRelevance(
          s,
          bypassedExplicitLang ? intent.copyWith(explicitLanguage: null) : intent,
          preferredLanguages: prefLangs,
          affinityContext: queryAffinityCtx,
        );
        return MapEntry(score, s);
      }).where((e) => e.key > 0.0).toList();

      final qClean = intent.cleanQuery.toLowerCase();
      final qCore = intent.effectiveCoreQuery.toLowerCase();
      final Map<String, int> saavnArrival = {
        for (int i = 0; i < candidateSaavn.length; i++) candidateSaavn[i].id: i
      };
      scoredSaavn.sort((a, b) => SearchResultRanker.compareRankedEntries(a, b, qClean, arrivalOrder: saavnArrival, preferredLanguages: prefLangs));
      final rankedSaavn = scoredSaavn.map((e) => e.value).toList();

      final matchingAlbums = rawAlbums.where(
        (a) => QueryNormalizer.isAlbumOrMovieEntityMatch((a['title'] ?? a['name'] ?? '').toString(), qClean) ||
            (qCore.isNotEmpty && QueryNormalizer.isAlbumOrMovieEntityMatch((a['title'] ?? a['name'] ?? '').toString(), qCore)),
      ).toList();

      final Future<List<Song>> soundtrackFuture = () async {
        if (matchingAlbums.isEmpty) return <Song>[];
        final albId = matchingAlbums.first['id']?.toString() ?? '';
        final albTitle = (matchingAlbums.first['title'] ?? matchingAlbums.first['name'] ?? '').toString();
        try {
          final details = await SongRepository.getAlbumDetails(albumId: albId, albumTitle: albTitle)
              .timeout(const Duration(milliseconds: 1200), onTimeout: () => null);
          return (details?['songs'] as List<Song>?) ?? <Song>[];
        } catch (_) {
          return <Song>[];
        }
      }();

      final matchingArtist = artists.where((a) {
        final name = (a['name'] ?? a['title'] ?? '').toString().toLowerCase().trim();
        return name == qClean || name == qCore;
      }).firstOrNull;

      final Future<List<Map<String, dynamic>>> artistOfficialAlbumsFuture = () async {
        if (matchingArtist == null) return <Map<String, dynamic>>[];
        final artId = matchingArtist['id']?.toString() ?? '';
        if (artId.isEmpty) return <Map<String, dynamic>>[];
        try {
          return await SaavnClient.getArtistAlbums(artId, limit: 40)
              .timeout(const Duration(milliseconds: 1800), onTimeout: () => <Map<String, dynamic>>[]);
        } catch (e) {
          AppLogger.log('SearchProgressiveOrchestrator', 'Phase 2 artist albums fetch fault: $e', level: LogLevel.debug);
          return <Map<String, dynamic>>[];
        }
      }();

      initialAlbums = [];
      final Set<String> seenAlbumNames = {};
      final typeaheadBundle = RemoteProviderSearch.typeaheadBundleCache.get(qClean) ??
          RemoteProviderSearch.typeaheadBundleCache.get(qCore);
      if (typeaheadBundle != null && typeaheadBundle.albums.isNotEmpty) {
        for (final alb in typeaheadBundle.albums) {
          final t = (alb['title'] ?? alb['name'] ?? '').toString().toLowerCase().trim();
          if (t.isNotEmpty && seenAlbumNames.add(t)) {
            initialAlbums.add({...alb, 'type': 'Album', 'is_movie': true});
          }
        }
      }

      for (final s in rankedSaavn.take(6)) {
        final isAlbRel = qClean.length > 3 || QueryNormalizer.isAlbumOrMovieEntityMatch(s.album, qClean) ||
            (qCore.isNotEmpty && QueryNormalizer.isAlbumOrMovieEntityMatch(s.album, qCore)) ||
            s.album.toLowerCase().trim() == qClean ||
            s.album.toLowerCase().trim().startsWith('$qClean ');
        final alb = s.album.trim();
        final albLower = alb.toLowerCase();
        if (alb.isNotEmpty &&
            albLower != 'single' &&
            albLower != 'unknown' &&
            albLower != 'various artists' &&
            albLower != 'studio album' &&
            isAlbRel && seenAlbumNames.add(albLower)) {
          initialAlbums.add({
            'id': s.album.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase(),
            'title': alb,
            'artist': s.artist,
            'image': s.coverUrl,
            'type': 'Album',
            'is_movie': true,
            'source': s.source,
          });
        }
      }

      for (final cm in catMovies) {
        final t = (cm['title'] ?? '').toString().toLowerCase().trim();
        if (t.isNotEmpty && seenAlbumNames.add(t)) {
          var img = cm['image'] ?? cm['cover_url'] ?? '';
          if (img.toString().isEmpty || img.toString().contains('default')) {
            img = CatalogDatabase.getMoviePoster(cm['title']?.toString() ?? '') ?? '';
          }
          initialAlbums.add({
            ...cm,
            'image': img,
            'artist': cm['artist'] ?? cm['composer'] ?? '',
          });
        }
      }

      for (final alb in SearchFilterEngine.filterGenuineAlbums(rawAlbums, query: intent.cleanQuery, preferredLanguages: prefLangs)) {
        final t = (alb['title'] ?? alb['name'] ?? '').toString().toLowerCase().trim();
        if (t.isNotEmpty && seenAlbumNames.add(t)) {
          initialAlbums.add(alb);
        }
      }

      initialAlbums = SearchFilterEngine.extractAlbumsFromSongList(
        rankedSaavn,
        query: intent.cleanQuery,
        existingAlbums: initialAlbums,
        preferredLanguages: prefLangs,
      );

      final autoPlaylists = SearchCollectionHelper.generateAutoPlaylistsFromAlbums(initialAlbums);
      final filteredRawPlaylists = SearchFilterEngine.filterPlaylistsByRelevanceAndLanguage(
        rawPlaylists,
        query: intent.cleanQuery,
        language: effectiveLang,
      );
      initialPlaylists = SearchCollectionHelper.ensurePopulatedPlaylists(
        SearchCollectionHelper.mergePlaylists(autoPlaylists, filteredRawPlaylists),
        rankedSaavn,
        initialAlbums,
        intent.cleanQuery,
        preferredLanguages: prefLangs,
      );

      initialArtists = [];
      final Set<String> seenArtistNames = {};

      void addCleanArtist(Map<String, dynamic> artMap) {
        final raw = Song.sanitize(artMap['name'] ?? artMap['title'] ?? '').trim();
        if (raw.isEmpty || raw.toLowerCase() == 'unknown artist') return;
        if (ArtistSanitizer.isCompositeOrMultiArtist(raw)) return;
        final canon = ArtistSanitizer.canonicalArtistName(raw);
        final canonLower = canon.toLowerCase();
        if (seenArtistNames.add(canonLower)) {
          final existingImg = artMap['image']?.toString() ?? '';
          final verifiedImg = existingImg.isNotEmpty && !existingImg.contains('default')
              ? existingImg
              : (SongRepository.verifiedArtistAvatars[canonLower] ?? CatalogDatabase.getArtistProfileImage(canon) ?? '');
          final isVerified = verifiedImg.isNotEmpty || SongRepository.isArtistVerified(canon);

          initialArtists.add({
            ...artMap,
            'name': canon,
            'image': verifiedImg,
            'is_verified': isVerified,
          });
        }
      }

      for (final ca in catArtists) {
        addCleanArtist(ca);
      }
      for (final a in artists) {
        addCleanArtist(a);
      }

      if (initialArtists.isEmpty) {
        final songArtists = CatalogDatabase.extractArtistsFromSongs(combinedSaavn, limit: 6);
        for (final sa in songArtists) {
          addCleanArtist(sa);
        }
      }

      Map<String, dynamic>? initialTopResult;
      String? didYouMean;

      final exactMovieMatch = initialAlbums.where(
        (a) => (a['title'] ?? '').toString().toLowerCase().trim() == intent.cleanQuery.toLowerCase().trim(),
      ).firstOrNull;

      if (exactMovieMatch != null) {
        initialTopResult = {
          'type': 'album',
          'id': exactMovieMatch['id']?.toString() ?? '',
          'title': exactMovieMatch['title']?.toString() ?? '',
          'artist': exactMovieMatch['artist']?.toString() ?? exactMovieMatch['composer']?.toString() ?? 'Soundtrack',
          'cover_url': exactMovieMatch['image']?.toString() ?? exactMovieMatch['cover_url']?.toString() ?? '',
          'score': 1.0,
        };
      } else if (scoredSaavn.isNotEmpty && scoredSaavn.first.key >= 0.70) {
        final top = scoredSaavn.first.value;
        initialTopResult = {
          'type': 'song',
          'id': top.id,
          'title': top.title,
          'artist': top.artist,
          'cover_url': top.coverUrl,
          'duration': top.duration,
          'source': top.source,
          'score': scoredSaavn.first.key,
          'versions': top.versions.map((v) => v.toMap()).toList(),
        };
      }

      final hasStrongMatch = (initialTopResult != null && (initialTopResult['score'] as num? ?? 0.0) >= 0.80) ||
          exactMovieMatch != null ||
          initialAlbums.any((a) => QueryNormalizer.isAlbumOrMovieEntityMatch((a['title'] ?? '').toString(), intent.cleanQuery));

      if (hasStrongMatch) {
        didYouMean = null;
      } else if (intent.transliteratedQuery.toLowerCase() != intent.cleanQuery.toLowerCase() &&
          !IndicRomanizer.hasIndicScript(intent.cleanQuery)) {
        didYouMean = intent.transliteratedQuery;
      } else {
        final correction = FuzzySearchService.findCorrection(intent.cleanQuery);
        if (correction != null && correction.corrected.toLowerCase() != intent.cleanQuery.toLowerCase()) {
          didYouMean = correction.corrected;
        }
      }

      List<Song> albumSoundtrackSongs = [];
      if (matchingAlbums.isNotEmpty) {
        try {
          albumSoundtrackSongs = await soundtrackFuture.timeout(
            const Duration(milliseconds: 650),
            onTimeout: () => <Song>[],
          );
        } catch (_) {}
      }

      final List<Song> initialPhaseSongs = [];
      for (final s in rankedSaavn) {
        final sim = SearchResultRanker.calculateStringSimilarity(s, intent);
        if (sim >= 0.95 && !initialPhaseSongs.any((x) => x.id == s.id)) {
          initialPhaseSongs.add(s);
        }
      }
      for (final s in albumSoundtrackSongs) {
        if (!initialPhaseSongs.any((x) => x.id == s.id)) {
          initialPhaseSongs.add(s);
        }
      }
      for (final s in rankedSaavn) {
        if (!initialPhaseSongs.any((x) => x.id == s.id)) {
          initialPhaseSongs.add(s);
        }
      }

      final phase1Bundle = SearchResults(
        songs: initialPhaseSongs,
        saavnSongs: rankedSaavn,
        albums: initialAlbums,
        artists: initialArtists,
        playlists: initialPlaylists,
        topResult: initialTopResult,
        didYouMean: didYouMean,
        isFinal: false,
      );
      lastEmittedBundle = phase1Bundle;
      yield phase1Bundle;

      // ── PHASE 2: YouTube / Federated Fallback & Progressive Merge ──
      final rawYt = await ytFuture;
      final extraMeta = await Future.wait([
        ytPlaylistsFuture,
        artistOfficialAlbumsFuture.timeout(const Duration(milliseconds: 1000), onTimeout: () => <Map<String, dynamic>>[]),
      ]);

      final rawYtPlaylists = extraMeta[0];
      final artistOfficialAlbums = extraMeta[1];

      for (final alb in artistOfficialAlbums) {
        final t = (alb['title'] ?? alb['name'] ?? '').toString().toLowerCase().trim();
        if (t.isNotEmpty && seenAlbumNames.add(t)) {
          initialAlbums.insert(0, alb);
        }
      }

      final filteredYtPlaylists = SearchFilterEngine.filterPlaylistsByRelevanceAndLanguage(
        rawYtPlaylists,
        query: intent.cleanQuery,
        language: effectiveLang,
      );
      final finalPlaylists = SearchCollectionHelper.mergePlaylists(initialPlaylists, filteredYtPlaylists);

      final groupedYt = SongRepository.groupCanonicalSongs(rawYt, preferredLanguage: effectiveLang, preferredLanguages: prefLangs);
      final deduplicatedYt = SongRepository.deduplicateSongs(groupedYt);
      List<Song> candidateYt = intent.explicitLanguage != null
          ? SongRepository.filterByLanguage(deduplicatedYt, intent.explicitLanguage!)
          : deduplicatedYt;
      bool bypassedExplicitLangYt = false;
      if (candidateYt.isEmpty && deduplicatedYt.isNotEmpty && intent.explicitLanguage != null) {
        candidateYt = deduplicatedYt;
        bypassedExplicitLangYt = true;
      }
      if (ytFailed && candidateYt.isEmpty && cached != null && cached.ytSongs.isNotEmpty) {
        candidateYt = cached.ytSongs;
      }
      final ytSongs = candidateYt;

      final scoredYt = candidateYt.map((s) {
        final score = SearchResultRanker.calculateCompositeRelevance(
          s,
          bypassedExplicitLangYt ? intent.copyWith(explicitLanguage: null) : intent,
          preferredLanguages: prefLangs,
          affinityContext: queryAffinityCtx,
        );
        return MapEntry(score, s);
      }).where((e) => e.key > 0.0).toList();
      final Map<String, int> ytArrival = {
        for (int i = 0; i < candidateYt.length; i++) candidateYt[i].id: i
      };
      scoredYt.sort((a, b) => SearchResultRanker.compareRankedEntries(a, b, qClean, arrivalOrder: ytArrival, preferredLanguages: prefLangs));
      final rankedYt = scoredYt.map((e) => e.value).toList();

      final List<Song> enrichedSaavn = [];
      for (final s in rankedSaavn) {
        final sim = SearchResultRanker.calculateStringSimilarity(s, intent);
        if (sim >= 0.95 && !enrichedSaavn.any((x) => x.id == s.id)) {
          enrichedSaavn.add(s);
        }
      }
      for (final s in albumSoundtrackSongs) {
        if (!enrichedSaavn.any((x) => x.id == s.id)) {
          enrichedSaavn.add(s);
        }
      }
      for (final s in rankedSaavn) {
        if (!enrichedSaavn.any((x) => x.id == s.id)) {
          enrichedSaavn.add(s);
        }
      }

      final List<Song> mergedSongs = SearchResultRanker.deduplicateAndRankUnified(
        saavnSongs: enrichedSaavn,
        ytSongs: candidateYt,
        audiusSongs: const [],
        intent: intent,
        preferredLanguages: prefLangs,
        affinityContext: queryAffinityCtx,
      );

      for (final s in mergedSongs.take(5)) {
        CatalogDatabase.insertDynamicSong(s);
      }

      final userRankedSongs = UserPreferenceMatrix.reRankWithPreferences(
        mergedSongs,
        intent.cleanQuery,
        intent: intent,
        preferredLanguages: prefLangs,
      );

      Map<String, dynamic>? finalTopResult = initialTopResult;
      if (exactMovieMatch != null) {
        finalTopResult = initialTopResult;
      } else if (userRankedSongs.isNotEmpty) {
        final top = userRankedSongs.first;
        final topScore = SearchResultRanker.calculateCompositeRelevance(top, intent, preferredLanguages: prefLangs);
        if (topScore >= 0.70) {
          finalTopResult = {
            'type': 'song',
            'id': top.id,
            'title': top.title,
            'artist': top.artist,
            'cover_url': top.coverUrl,
            'duration': top.duration,
            'source': top.source,
            'score': topScore,
            'versions': top.versions.map((v) => v.toMap()).toList(),
          };
        }
      }

      final List<Map<String, dynamic>> finalArtists = List<Map<String, dynamic>>.from(initialArtists);
      if (finalArtists.length < 5) {
        for (final sa in CatalogDatabase.extractArtistsFromSongs(userRankedSongs, limit: 8)) {
          final raw = Song.sanitize(sa['name'] ?? sa['title'] ?? '').trim();
          if (raw.isEmpty || raw.toLowerCase() == 'unknown artist') continue;
          if (ArtistSanitizer.isCompositeOrMultiArtist(raw)) continue;
          final canon = ArtistSanitizer.canonicalArtistName(raw);
          final canonLower = canon.toLowerCase();
          if (seenArtistNames.add(canonLower)) {
            final existingImg = sa['image']?.toString() ?? '';
            final verifiedImg = existingImg.isNotEmpty && !existingImg.contains('default')
                ? existingImg
                : (SongRepository.verifiedArtistAvatars[canonLower] ?? CatalogDatabase.getArtistProfileImage(canon) ?? '');
            final isVerified = verifiedImg.isNotEmpty || SongRepository.isArtistVerified(canon);

            finalArtists.add({
              ...sa,
              'name': canon,
              'image': verifiedImg,
              'is_verified': isVerified,
            });
          }
        }
      }

      FuzzySearchService.registerSongs(userRankedSongs.where((s) => s.source == 'saavn' && s.title.length <= 40).toList());

      if (didYouMean != null) {
        final hasStrongMatchPhase2 = (finalTopResult != null && (finalTopResult['score'] as num? ?? 0.0) >= 0.80) ||
            (userRankedSongs.isNotEmpty && SearchResultRanker.calculateStringSimilarity(userRankedSongs.first, intent) >= 0.85);
        if (hasStrongMatchPhase2) {
          didYouMean = null;
        }
      }

      AppError? searchError;
      if (userRankedSongs.isEmpty && ytSongs.isEmpty && initialAlbums.isEmpty && finalArtists.isEmpty && finalPlaylists.isEmpty && (saavnFailed && ytFailed)) {
        final offlineMatches = LocalCatalogSearch.searchDownloadedSongs(intent.cleanQuery);
        if (offlineMatches.isNotEmpty) {
          final offlineBundle = SearchResults(
            songs: offlineMatches,
            isOfflineResult: true,
            isFinal: true,
          );
          SearchCache.put(rawQuery, offlineBundle, language: effectiveLang);
          yield offlineBundle;
          return;
        }
        searchError = AppError.offline(debugDetails: 'All upstream providers failed for "${intent.cleanQuery}"');
      }

      final finalAlbums = SearchFilterEngine.extractAlbumsFromSongList(
        userRankedSongs,
        query: intent.cleanQuery,
        existingAlbums: initialAlbums,
        preferredLanguages: prefLangs,
      );
      final populatedFinalPlaylists = SearchCollectionHelper.ensurePopulatedPlaylists(
        finalPlaylists,
        userRankedSongs,
        finalAlbums,
        intent.cleanQuery,
        preferredLanguages: prefLangs,
      );

      final finalBundle = SearchResults(
        songs: userRankedSongs,
        ytSongs: rankedYt.isNotEmpty ? rankedYt : ytSongs,
        saavnSongs: rankedSaavn,
        audiusSongs: const [],
        albums: finalAlbums,
        artists: finalArtists,
        playlists: populatedFinalPlaylists,
        topResult: finalTopResult,
        didYouMean: didYouMean,
        error: searchError,
        isFinal: true,
      );

      SearchCache.put(rawQuery, finalBundle, language: effectiveLang);
      yield finalBundle;
    } catch (e, stack) {
      debugPrint('[SearchProgressiveOrchestrator] Search error: $e');
      final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'SearchProgressiveOrchestrator.searchProgressive');
      if (cached != null && cached.songs.isNotEmpty) {
        yield SearchResults(
          songs: cached.songs,
          ytSongs: cached.ytSongs,
          saavnSongs: cached.saavnSongs,
          audiusSongs: cached.audiusSongs,
          albums: cached.albums,
          artists: cached.artists,
          playlists: cached.playlists,
          topResult: cached.topResult,
          didYouMean: cached.didYouMean,
          error: appErr,
          isFinal: true,
        );
      } else if (lastEmittedBundle != null && !lastEmittedBundle.isEmpty) {
        yield SearchResults(
          songs: lastEmittedBundle.songs,
          ytSongs: lastEmittedBundle.ytSongs,
          saavnSongs: lastEmittedBundle.saavnSongs,
          audiusSongs: lastEmittedBundle.audiusSongs,
          albums: lastEmittedBundle.albums,
          artists: lastEmittedBundle.artists,
          playlists: lastEmittedBundle.playlists,
          topResult: lastEmittedBundle.topResult,
          didYouMean: lastEmittedBundle.didYouMean,
          error: lastEmittedBundle.error ?? appErr,
          isFinal: true,
        );
      } else if (catalogSongs.isNotEmpty) {
        yield SearchResults(
          songs: catalogSongs,
          saavnSongs: catalogSongs,
          albums: initialAlbums,
          artists: initialArtists,
          playlists: initialPlaylists,
          error: appErr,
          isFinal: true,
        );
      } else {
        final offlineMatches = LocalCatalogSearch.searchDownloadedSongs(intent.cleanQuery);
        if (offlineMatches.isNotEmpty) {
          yield SearchResults(
            songs: offlineMatches,
            isOfflineResult: true,
            isFinal: true,
          );
        } else {
          yield SearchResults(error: appErr, isFinal: true);
        }
      }
    }
  }

  /// High-precision unified search across JioSaavn & YouTube Music
  static Future<SearchResults> searchUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
  }) async {
    SearchResults lastResult = SearchResults();
    await for (final res in searchProgressive(rawQuery, language: language, limit: limit)) {
      lastResult = res;
    }
    return lastResult;
  }
}
