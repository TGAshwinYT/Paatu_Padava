import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/auth_manager.dart';
import '../services/settings_manager.dart';
import '../services/history_manager.dart';
import '../services/saavn_client.dart';
import '../services/api_client.dart';
import '../data/repositories/song_repository.dart';

import '../domain/models/app_error.dart';
import '../services/error_handler.dart';
import '../services/youtube_client.dart';
import '../services/spotify_import_service.dart';
import '../services/cache_manager.dart';
import 'stream_resolver.dart';
import '../domain/models/track_entity.dart';
import '../domain/models/home_feed_models.dart';

class HomeFeedState {
  final List<Song> madeForYou;
  final List<Song> trendingMerged;
  final List<Song> youtubeTrending;
  final List<Song> spotifyTop10;
  final List<Song> newReleases;
  final List<Map<String, dynamic>> popularArtists;
  final List<Map<String, dynamic>> featuredAlbums;
  final List<Song> recentHistory;
  final HeroShowcase? heroShowcase;
  final List<RankedChartSong> top10Charts;
  final List<FeelingMix> feelingMixes;
  final List<Song> quickPicks;
  final String activeFeeling;
  final bool isLoading;
  final String? error;
  final AppError? appError;

  const HomeFeedState({
    this.madeForYou = const [],
    this.trendingMerged = const [],
    this.youtubeTrending = const [],
    this.spotifyTop10 = const [],
    this.newReleases = const [],
    this.popularArtists = const [],
    this.featuredAlbums = const [],
    this.recentHistory = const [],
    this.heroShowcase,
    this.top10Charts = const [],
    this.feelingMixes = const [],
    this.quickPicks = const [],
    this.activeFeeling = 'all',
    this.isLoading = false,
    this.error,
    this.appError,
  });

  bool get isEmpty =>
      madeForYou.isEmpty &&
      trendingMerged.isEmpty &&
      youtubeTrending.isEmpty &&
      spotifyTop10.isEmpty &&
      newReleases.isEmpty &&
      popularArtists.isEmpty &&
      featuredAlbums.isEmpty &&
      (heroShowcase == null || heroShowcase!.tracks.isEmpty);

  HomeFeedState copyWith({
    List<Song>? madeForYou,
    List<Song>? trendingMerged,
    List<Song>? youtubeTrending,
    List<Song>? spotifyTop10,
    List<Song>? newReleases,
    List<Map<String, dynamic>>? popularArtists,
    List<Map<String, dynamic>>? featuredAlbums,
    List<Song>? recentHistory,
    HeroShowcase? heroShowcase,
    List<RankedChartSong>? top10Charts,
    List<FeelingMix>? feelingMixes,
    List<Song>? quickPicks,
    String? activeFeeling,
    bool? isLoading,
    String? error,
    AppError? appError,
  }) {
    return HomeFeedState(
      madeForYou: madeForYou ?? this.madeForYou,
      trendingMerged: trendingMerged ?? this.trendingMerged,
      youtubeTrending: youtubeTrending ?? this.youtubeTrending,
      spotifyTop10: spotifyTop10 ?? this.spotifyTop10,
      newReleases: newReleases ?? this.newReleases,
      popularArtists: popularArtists ?? this.popularArtists,
      featuredAlbums: featuredAlbums ?? this.featuredAlbums,
      recentHistory: recentHistory ?? this.recentHistory,
      heroShowcase: heroShowcase ?? this.heroShowcase,
      top10Charts: top10Charts ?? this.top10Charts,
      feelingMixes: feelingMixes ?? this.feelingMixes,
      quickPicks: quickPicks ?? this.quickPicks,
      activeFeeling: activeFeeling ?? this.activeFeeling,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      appError: appError,
    );
  }
}

/// Unified Home Feed provider orchestrating JioSaavn, YouTube Music, and User Taste recommendations.
/// Implements Stale-While-Revalidate (SWR) with Hive and consolidated single-payload API resolution.
class HomeFeedProvider extends ChangeNotifier {
  static final HomeFeedProvider instance = HomeFeedProvider._internal();
  factory HomeFeedProvider() => instance;
  HomeFeedProvider._internal();

  HomeFeedState _state = const HomeFeedState(isLoading: true);
  HomeFeedState get state => _state;

  String _currentLanguage = 'Tamil';
  String get currentLanguage => _currentLanguage;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    _resolveCurrentLanguage();
    // Dynamically react whenever user finishes onboarding or changes preferences
    AuthManager.authNotifier.addListener(_onPreferencesChanged);
    SettingsManager.languagesNotifier.addListener(_onPreferencesChanged);

    // Stale-While-Revalidate:
    // 1. Immediately emit cached Home Feed so Home Screen renders instantly with zero loading spinner
    await _loadCachedFeed(_currentLanguage);

    // 2. Fetch fresh sections in parallel in background, update cache, and notify listeners
    unawaited(_revalidateFeed(_currentLanguage));
  }

  @override
  void dispose() {
    if (_isInitialized) {
      AuthManager.authNotifier.removeListener(_onPreferencesChanged);
      SettingsManager.languagesNotifier.removeListener(_onPreferencesChanged);
      _isInitialized = false;
    }
    super.dispose();
  }

  void _resolveCurrentLanguage() {
    final userLangs = AuthManager.currentUser?.preferredLanguages;
    if (userLangs != null && userLangs.isNotEmpty) {
      _currentLanguage = userLangs.first;
      return;
    }
    final prefLangs = SettingsManager.preferredLanguages;
    if (prefLangs.isNotEmpty) {
      _currentLanguage = prefLangs.first;
    }
  }

  void _onPreferencesChanged() {
    final userLangs = AuthManager.currentUser?.preferredLanguages;
    final topLang = (userLangs != null && userLangs.isNotEmpty)
        ? userLangs.first
        : (SettingsManager.preferredLanguages.isNotEmpty ? SettingsManager.preferredLanguages.first : null);
    if (topLang != null && topLang.isNotEmpty && topLang != _currentLanguage) {
      _currentLanguage = topLang;
      loadFeed(forceRefresh: true);
    } else if (AuthManager.isLoggedIn) {
      loadFeed(forceRefresh: true);
    }
  }

  void setLanguage(String lang) {
    if (_currentLanguage == lang) return;
    _currentLanguage = lang;
    loadFeed();
  }

  void setActiveFeeling(String feelingId) {
    if (_state.activeFeeling == feelingId) return;
    _state = _state.copyWith(activeFeeling: feelingId);
    notifyListeners();
  }

  Future<void> _loadCachedFeed(String lang) async {
    try {
      final raw = CacheManager.getCachedHomeFeedSync(lang) ?? await CacheManager.getCachedHomeFeed(lang);
      if (raw != null) {
        final madeForYou = _decodeSongList(raw['madeForYou']);
        final trendingMerged = _decodeSongList(raw['trendingMerged'] ?? raw['trending']);
        final youtubeTrending = _decodeSongList(raw['youtubeTrending']);
        final spotifyTop10 = _decodeSongList(raw['spotifyTop10']);
        final newReleases = _decodeSongList(raw['newReleases']);
        final popularArtists = (raw['popularArtists'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final rawFeaturedAlbums = (raw['featuredAlbums'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final featuredAlbums = rawFeaturedAlbums.where((a) {
          final count = int.tryParse(a['song_count']?.toString() ?? '0') ?? 2;
          final title = (a['title'] ?? '').toString().toLowerCase();
          return count > 1 && !title.contains('single');
        }).toList();
        final recentHistory = HistoryManager.getRecentSongs();

        HeroShowcase? heroShowcase;
        if (raw['heroShowcase'] is Map) {
          try {
            heroShowcase = HeroShowcase.fromMap(Map<String, dynamic>.from(raw['heroShowcase'] as Map));
          } catch (_) {}
        }

        final top10Charts = (raw['top10Charts'] as List<dynamic>?)
                ?.map((e) {
                  try {
                    return RankedChartSong.fromMap(Map<String, dynamic>.from(e as Map));
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<RankedChartSong>()
                .toList() ??
            [];

        final feelingMixes = (raw['feelingMixes'] as List<dynamic>?)
                ?.map((e) {
                  try {
                    return FeelingMix.fromMap(Map<String, dynamic>.from(e as Map));
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<FeelingMix>()
                .toList() ??
            [];

        final quickPicks = _decodeSongList(raw['quickPicks']);
        final rememberFeeling = SettingsManager.isHomeRememberFeelingEnabled;
        final savedFeeling = rememberFeeling ? (raw['activeFeeling']?.toString() ?? 'all') : 'all';

        if (madeForYou.isNotEmpty ||
            trendingMerged.isNotEmpty ||
            youtubeTrending.isNotEmpty ||
            spotifyTop10.isNotEmpty ||
            heroShowcase != null) {
          _state = HomeFeedState(
            madeForYou: madeForYou,
            trendingMerged: trendingMerged,
            youtubeTrending: youtubeTrending,
            spotifyTop10: spotifyTop10,
            newReleases: newReleases,
            popularArtists: popularArtists,
            featuredAlbums: featuredAlbums,
            recentHistory: recentHistory,
            heroShowcase: heroShowcase,
            top10Charts: top10Charts,
            feelingMixes: feelingMixes,
            quickPicks: quickPicks,
            activeFeeling: savedFeeling,
            isLoading: false, // Instant cache-first render: no loading spinner
          );
          notifyListeners();

          // Silently prewarm top 3 tracks in background for instant sub-second playback
          final topSongs = madeForYou.isNotEmpty ? madeForYou : trendingMerged;
          DefaultStreamResolver.prewarmSongs(topSongs, limit: 3);
        }
      }
    } catch (e) {
      debugPrint('[HomeFeedProvider] SWR cache read error: $e');
    }
  }

  Future<void> _persistFeedToCache(String lang, HomeFeedState feed) async {
    try {
      final cacheData = {
        'madeForYou': feed.madeForYou.map((s) => s.toMap()).toList(),
        'trendingMerged': feed.trendingMerged.map((s) => s.toMap()).toList(),
        'youtubeTrending': feed.youtubeTrending.map((s) => s.toMap()).toList(),
        'spotifyTop10': feed.spotifyTop10.map((s) => s.toMap()).toList(),
        'newReleases': feed.newReleases.map((s) => s.toMap()).toList(),
        'popularArtists': feed.popularArtists,
        'featuredAlbums': feed.featuredAlbums,
        'heroShowcase': feed.heroShowcase?.toMap(),
        'top10Charts': feed.top10Charts.map((r) => r.toMap()).toList(),
        'feelingMixes': feed.feelingMixes.map((f) => f.toMap()).toList(),
        'quickPicks': feed.quickPicks.map((s) => s.toMap()).toList(),
        'activeFeeling': feed.activeFeeling,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await CacheManager.saveCachedHomeFeed(lang, cacheData);
    } catch (e) {
      debugPrint('[HomeFeedProvider] SWR cache write error: $e');
    }
  }

  static List<Song> _decodeSongList(dynamic rawList) {
    if (rawList is! List) return [];
    final List<Song> songs = [];
    for (final item in rawList) {
      if (item is Map) {
        try {
          songs.add(Song.fromMap(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
    }
    return songs;
  }

  /// Strictly purges cross-language leaks (e.g. Hindi tracks in Tamil playlists)
  /// when the user's preferred language list does not explicitly include Hindi.
  List<Song> _filterCrossLanguageLeaks(List<Song> songs, String primaryLang) {
    final userLangs = SettingsManager.preferredLanguages.map((l) => l.toLowerCase().trim()).toSet();
    final allowsHindi = userLangs.contains('hindi');

    return songs.where((song) {
      final sLang = song.language?.toLowerCase().trim() ?? '';
      if (!allowsHindi && sLang == 'hindi') {
        return false;
      }
      if (!allowsHindi) {
        if (RegExp(r'[\u0900-\u097F]').hasMatch(song.title) ||
            RegExp(r'[\u0900-\u097F]').hasMatch(song.artist)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Enforces authentic artist profile avatars, prioritizes verified portraits,
  /// queries Spotify API when needed, and strictly rejects song/album cover art.
  static Future<List<Map<String, dynamic>>> _enrichPopularArtists(
    List<Map<String, dynamic>> rawList,
    String language,
  ) async {
    final isTamil = language.toLowerCase().trim() == 'tamil';
    var filtered = List<Map<String, dynamic>>.from(rawList);

    if (isTamil) {
      final userLangs = SettingsManager.preferredLanguages.map((l) => l.toLowerCase().trim()).toSet();
      final allowsHindi = userLangs.contains('hindi');
      if (!allowsHindi) {
        const hindiSingers = {
          'arijit singh', 'neha kakkar', 'badshah', 'jubin nautiyal', 'atif aslam',
          'vishal mishra', 'darshan raval', 'armaan malik', 'yo yo honey singh',
          'b praak', 'guru randhawa', 'tony kakkar', 'sonu nigam', 'kumar sanu',
          'alka yagnik', 'udith narayan',
        };
        filtered = filtered.where((a) {
          final name = SongRepository.normalizeArtist(a['name']?.toString() ?? '');
          if (RegExp(r'[\u0900-\u097F]').hasMatch(a['name']?.toString() ?? '')) return false;
          return !hindiSingers.contains(name);
        }).toList();
      }

      for (final seed in SongRepository.tamilArtistSeeds.reversed) {
        final norm = SongRepository.normalizeArtist(seed);
        final idx = filtered.indexWhere((a) => SongRepository.normalizeArtist(a['name']?.toString() ?? '') == norm);
        final avatar = SongRepository.verifiedArtistAvatars[norm] ?? '';
        if (idx >= 0) {
          final existing = filtered.removeAt(idx);
          filtered.insert(0, existing);
        } else {
          filtered.insert(0, {
            'id': 'seed_$norm',
            'name': seed,
            'image': avatar,
          });
        }
      }
    }

    // Ensure Artist cards use the fetched artist profile image, never the song's cover image.
    final enriched = await Future.wait(filtered.map((art) async {
      final name = Song.sanitize(art['name']?.toString() ?? 'Artist');
      final norm = SongRepository.normalizeArtist(name);
      var img = art['image']?.toString() ?? art['cover_url']?.toString() ?? '';

      // Check if image is a song/album cover (contains /albums/ or /songs/ or saavn numeric path without /artists/)
      final isSongCover = img.contains('/albums/') ||
          img.contains('/songs/') ||
          (img.contains('c.saavncdn.com') && !img.contains('/artists/'));

      if (SongRepository.verifiedArtistAvatars.containsKey(norm)) {
        img = SongRepository.verifiedArtistAvatars[norm]!;
      } else if (isSongCover || img.isEmpty) {
        try {
          final liveImg = await SaavnClient.getArtistImage(name)
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
          if (liveImg != null && liveImg.isNotEmpty) {
            img = liveImg;
          } else {
            final fetched = await SpotifyImportService.getArtistProfileImage(name)
                .timeout(const Duration(seconds: 3), onTimeout: () => null);
            if (fetched != null && fetched.isNotEmpty) {
              img = fetched;
            } else if (isSongCover) {
              img = '';
            }
          }
        } catch (_) {
          if (isSongCover) img = '';
        }
      }

      return {
        ...art,
        'name': name,
        'image': img,
      };
    }));

    return enriched;
  }

  /// Loads feed applying Stale-While-Revalidate (SWR):
  /// 1. Instantly renders local cached feed on cold launch
  /// 2. Fetches fresh Home sections in parallel in the background
  /// 3. Updates cache, notifies listeners, and silently prewarms top audio streams
  Future<void> loadFeed({bool forceRefresh = false}) async {
    final lang = _currentLanguage;

    // SWR Step 1: Render cached state instantly if available
    if (!forceRefresh && _state.isEmpty) {
      await _loadCachedFeed(lang);
    } else if (forceRefresh) {
      _state = _state.copyWith(isLoading: true, error: null);
      notifyListeners();
    }

    await _revalidateFeed(lang);
  }

  /// Background revalidation of fresh Home Feed sections
  Future<void> _revalidateFeed(String lang) async {
    try {
      // Parallel fetch for flagship editorial showcase, top 10 ranked chart, feeling mixes, and quick picks
      final extraFutures = Future.wait([
        SongRepository.getFlagshipShowcase(
          language: lang,
          heroMode: SettingsManager.homeHeroBannerMode,
        ),
        SongRepository.getTop10RankedCharts(language: lang),
        SongRepository.getFeelingMixes(language: lang),
        SongRepository.getQuickPicks(language: lang),
      ]);

      // SWR Step 2: Consolidated single-payload API request with 3s timeout so sleeping server never delays
      Map<String, dynamic>? unifiedFeed;
      try {
        unifiedFeed = await ApiClient.getHomeFeed(lang).timeout(const Duration(seconds: 3));
      } catch (_) {}

      final extra = await extraFutures;
      final heroShowcase = extra[0] as HeroShowcase;
      final top10Charts = extra[1] as List<RankedChartSong>;
      final feelingMixes = extra[2] as List<FeelingMix>;
      final quickPicks = extra[3] as List<Song>;

      if (unifiedFeed != null &&
          (unifiedFeed['madeForYou'] is List || unifiedFeed['trending'] is List)) {
        final localMadeForYou = await SongRepository.getMadeForYou(language: lang);
        final serverMadeForYou = SongRepository.filterByLanguage(_decodeSongList(unifiedFeed['madeForYou']), lang);
        final madeForYou = _filterCrossLanguageLeaks(
          localMadeForYou.isNotEmpty ? localMadeForYou : serverMadeForYou,
          lang,
        );
        final trending = _filterCrossLanguageLeaks(
          SongRepository.filterByLanguage(_decodeSongList(unifiedFeed['trendingMerged'] ?? unifiedFeed['trending']), lang),
          lang,
        );
        var youtubeTrending = _filterCrossLanguageLeaks(
          SongRepository.filterByLanguage(_decodeSongList(unifiedFeed['youtubeTrending']), lang),
          lang,
        );
        if (youtubeTrending.isEmpty) {
          try {
            youtubeTrending = _filterCrossLanguageLeaks(
              await YouTubeClient.getTrendingTracks(language: lang, limit: 15),
              lang,
            );
          } catch (_) {}
        }

        // Spotify Top 10 Hits (capped at 3s)
        List<Song> spotifyTop10 = [];
        try {
          final spTracks = await SpotifyImportService.getTop10Hits(lang)
              .timeout(const Duration(seconds: 3), onTimeout: () => <TrackEntity>[]);
          spotifyTop10 = _filterCrossLanguageLeaks(
            SongRepository.filterByLanguage(spTracks.map((t) => t.toSong()).toList(), lang),
            lang,
          );
        } catch (_) {}

        final newReleases = _filterCrossLanguageLeaks(
          SongRepository.filterByLanguage(_decodeSongList(unifiedFeed['newReleases']), lang),
          lang,
        );
        final rawPopularArtists = (unifiedFeed['popularArtists'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final popularArtists = await _enrichPopularArtists(rawPopularArtists, lang);

        final rawFeaturedAlbums = (unifiedFeed['featuredAlbums'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        // Strictly exclude single-song albums (song_count <= 1) from Home Page
        final featuredAlbums = rawFeaturedAlbums.where((a) {
          final count = int.tryParse(a['song_count']?.toString() ?? '0') ??
              (a['songs'] is List ? (a['songs'] as List).length : 2);
          final title = (a['title'] ?? '').toString().toLowerCase();
          return count > 1 && !title.contains('single');
        }).toList();

        final recentHistory = HistoryManager.getRecentSongs();

        _state = HomeFeedState(
          madeForYou: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(madeForYou)),
          trendingMerged: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(trending)),
          youtubeTrending: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(youtubeTrending)),
          spotifyTop10: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(spotifyTop10)),
          newReleases: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(newReleases)),
          popularArtists: popularArtists,
          featuredAlbums: featuredAlbums,
          recentHistory: recentHistory,
          heroShowcase: heroShowcase.tracks.isNotEmpty ? heroShowcase : _state.heroShowcase,
          top10Charts: top10Charts.isNotEmpty ? top10Charts : _state.top10Charts,
          feelingMixes: feelingMixes.isNotEmpty ? feelingMixes : _state.feelingMixes,
          quickPicks: quickPicks.isNotEmpty ? quickPicks : _state.quickPicks,
          activeFeeling: _state.activeFeeling,
          isLoading: false,
        );
        _persistFeedToCache(lang, _state);
        notifyListeners();

        // Silently prewarm top 3 tracks in background for instant playback
        final topSongs = _state.madeForYou.isNotEmpty ? _state.madeForYou : _state.trendingMerged;
        DefaultStreamResolver.prewarmSongs(topSongs, limit: 3);
        return;
      }

      // SWR Fallback: Parallel repository fetching with 3s timeout on Spotify
      final results = await Future.wait([
        SongRepository.getTrendingMerged(language: lang),
        SongRepository.getMadeForYou(language: lang),
        SongRepository.getNewReleases(language: lang),
        SongRepository.getPopularArtists(language: lang),
        SaavnClient.searchAlbums('$lang Top Hits', limit: 12, language: lang),
        YouTubeClient.getTrendingTracks(language: lang, limit: 15),
        SpotifyImportService.getTop10Hits(lang)
            .timeout(const Duration(seconds: 3), onTimeout: () => <TrackEntity>[])
            .catchError((_) => <TrackEntity>[]),
      ]);

      final trendingMerged = _filterCrossLanguageLeaks(results[0] as List<Song>, lang);
      final madeForYou = _filterCrossLanguageLeaks(results[1] as List<Song>, lang);
      final newReleases = _filterCrossLanguageLeaks(results[2] as List<Song>, lang);
      final rawPopularArtists = results[3] as List<Map<String, dynamic>>;
      final popularArtists = await _enrichPopularArtists(rawPopularArtists, lang);
      final rawFeaturedAlbums = results[4] as List<Map<String, dynamic>>;
      // Strictly exclude single-song albums (song_count <= 1)
      final featuredAlbums = rawFeaturedAlbums.where((a) {
        final count = int.tryParse(a['song_count']?.toString() ?? '0') ?? 2;
        final title = (a['title'] ?? '').toString().toLowerCase();
        return count > 1 && !title.contains('single');
      }).toList();
      final ytTrending = _filterCrossLanguageLeaks(results[5] as List<Song>, lang);
      final spTracks = results[6] as List<TrackEntity>;
      final spotifyTop10 = _filterCrossLanguageLeaks(
        SongRepository.filterByLanguage(spTracks.map((t) => t.toSong()).toList(), lang),
        lang,
      );
      final recentHistory = HistoryManager.getRecentSongs();

      final hasFreshData = madeForYou.isNotEmpty ||
          trendingMerged.isNotEmpty ||
          ytTrending.isNotEmpty ||
          spotifyTop10.isNotEmpty ||
          newReleases.isNotEmpty ||
          heroShowcase.tracks.isNotEmpty;

      if (hasFreshData || _state.isEmpty) {
        _state = HomeFeedState(
          madeForYou: madeForYou.isNotEmpty ? madeForYou : _state.madeForYou,
          trendingMerged: trendingMerged.isNotEmpty ? trendingMerged : _state.trendingMerged,
          youtubeTrending: ytTrending.isNotEmpty ? ytTrending : _state.youtubeTrending,
          spotifyTop10: spotifyTop10.isNotEmpty ? spotifyTop10 : _state.spotifyTop10,
          newReleases: newReleases.isNotEmpty ? newReleases : _state.newReleases,
          popularArtists: popularArtists.isNotEmpty ? popularArtists : _state.popularArtists,
          featuredAlbums: featuredAlbums.isNotEmpty ? featuredAlbums : _state.featuredAlbums,
          recentHistory: recentHistory.isNotEmpty ? recentHistory : _state.recentHistory,
          heroShowcase: heroShowcase.tracks.isNotEmpty ? heroShowcase : _state.heroShowcase,
          top10Charts: top10Charts.isNotEmpty ? top10Charts : _state.top10Charts,
          feelingMixes: feelingMixes.isNotEmpty ? feelingMixes : _state.feelingMixes,
          quickPicks: quickPicks.isNotEmpty ? quickPicks : _state.quickPicks,
          activeFeeling: _state.activeFeeling,
          isLoading: false,
        );
        if (hasFreshData) {
          _persistFeedToCache(lang, _state);
        }
      } else {
        _state = _state.copyWith(isLoading: false);
      }
      notifyListeners();

      // Silently prewarm top 3 tracks in background for instant playback
      final topSongs = _state.madeForYou.isNotEmpty ? _state.madeForYou : _state.trendingMerged;
      DefaultStreamResolver.prewarmSongs(topSongs, limit: 3);
    } catch (e, stack) {
      final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'HomeFeedProvider.loadFeed');
      if (_state.isEmpty) {
        _state = _state.copyWith(
          isLoading: false,
          error: appErr.userMessage,
          appError: appErr,
        );
      } else {
        _state = _state.copyWith(isLoading: false);
      }
      notifyListeners();
    }
  }
}

