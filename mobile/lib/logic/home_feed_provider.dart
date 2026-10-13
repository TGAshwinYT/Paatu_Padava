import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

class HomeFeedState {
  final List<Song> madeForYou;
  final List<Song> trendingMerged;
  final List<Song> youtubeTrending;
  final List<Song> newReleases;
  final List<Map<String, dynamic>> popularArtists;
  final List<Map<String, dynamic>> featuredAlbums;
  final List<Song> recentHistory;
  final bool isLoading;
  final String? error;
  final AppError? appError;

  const HomeFeedState({
    this.madeForYou = const [],
    this.trendingMerged = const [],
    this.youtubeTrending = const [],
    this.newReleases = const [],
    this.popularArtists = const [],
    this.featuredAlbums = const [],
    this.recentHistory = const [],
    this.isLoading = false,
    this.error,
    this.appError,
  });

  bool get isEmpty =>
      madeForYou.isEmpty &&
      trendingMerged.isEmpty &&
      youtubeTrending.isEmpty &&
      newReleases.isEmpty &&
      popularArtists.isEmpty &&
      featuredAlbums.isEmpty;

  HomeFeedState copyWith({
    List<Song>? madeForYou,
    List<Song>? trendingMerged,
    List<Song>? youtubeTrending,
    List<Song>? newReleases,
    List<Map<String, dynamic>>? popularArtists,
    List<Map<String, dynamic>>? featuredAlbums,
    List<Song>? recentHistory,
    bool? isLoading,
    String? error,
    AppError? appError,
  }) {
    return HomeFeedState(
      madeForYou: madeForYou ?? this.madeForYou,
      trendingMerged: trendingMerged ?? this.trendingMerged,
      youtubeTrending: youtubeTrending ?? this.youtubeTrending,
      newReleases: newReleases ?? this.newReleases,
      popularArtists: popularArtists ?? this.popularArtists,
      featuredAlbums: featuredAlbums ?? this.featuredAlbums,
      recentHistory: recentHistory ?? this.recentHistory,
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

  static const String _cacheBoxName = 'home_feed_cache';

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
    await loadFeed();
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
      loadFeed();
    }
  }

  void setLanguage(String lang) {
    if (_currentLanguage == lang) return;
    _currentLanguage = lang;
    loadFeed();
  }

  Future<Box?> _getCacheBox() async {
    try {
      if (Hive.isBoxOpen(_cacheBoxName)) {
        return Hive.box(_cacheBoxName);
      }
      return await Hive.openBox(_cacheBoxName);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCachedFeed(String lang) async {
    try {
      final box = await _getCacheBox();
      if (box == null) return;
      final raw = box.get('feed_$lang');
      if (raw is Map) {
        final madeForYou = _decodeSongList(raw['madeForYou']);
        final trendingMerged = _decodeSongList(raw['trendingMerged'] ?? raw['trending']);
        final youtubeTrending = _decodeSongList(raw['youtubeTrending']);
        final newReleases = _decodeSongList(raw['newReleases']);
        final popularArtists = (raw['popularArtists'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final featuredAlbums = (raw['featuredAlbums'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final recentHistory = HistoryManager.getRecentSongs();

        if (madeForYou.isNotEmpty || trendingMerged.isNotEmpty || youtubeTrending.isNotEmpty) {
          _state = HomeFeedState(
            madeForYou: madeForYou,
            trendingMerged: trendingMerged,
            youtubeTrending: youtubeTrending,
            newReleases: newReleases,
            popularArtists: popularArtists,
            featuredAlbums: featuredAlbums,
            recentHistory: recentHistory,
            isLoading: true, // SWR: quietly revalidating in background
          );
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[HomeFeedProvider] SWR cache read error: $e');
    }
  }

  Future<void> _persistFeedToCache(String lang, HomeFeedState feed) async {
    try {
      final box = await _getCacheBox();
      if (box == null) return;
      await box.put('feed_$lang', {
        'madeForYou': feed.madeForYou.map((s) => s.toMap()).toList(),
        'trendingMerged': feed.trendingMerged.map((s) => s.toMap()).toList(),
        'youtubeTrending': feed.youtubeTrending.map((s) => s.toMap()).toList(),
        'newReleases': feed.newReleases.map((s) => s.toMap()).toList(),
        'popularArtists': feed.popularArtists,
        'featuredAlbums': feed.featuredAlbums,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      });
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

  /// Loads feed applying Stale-While-Revalidate (SWR):
  /// 1. Instantly renders local Hive cached feed on cold launch
  /// 2. Fetches unified /api/music/home-feed endpoint in background
  /// 3. Falls back to parallel providers if backend is unreachable
  /// 4. Defensively avoids flashing error view when partial/cached data exists
  Future<void> loadFeed({bool forceRefresh = false}) async {
    final lang = _currentLanguage;

    // SWR Step 1: Render cached state instantly if available
    if (!forceRefresh && _state.isEmpty) {
      await _loadCachedFeed(lang);
    } else {
      _state = _state.copyWith(isLoading: true, error: null);
      notifyListeners();
    }

    try {
      // SWR Step 2: Consolidated single-payload API request
      final unifiedFeed = await ApiClient.getHomeFeed(lang);
      if (unifiedFeed != null &&
          (unifiedFeed['madeForYou'] is List || unifiedFeed['trending'] is List)) {
        final madeForYou = SongRepository.filterByLanguage(_decodeSongList(unifiedFeed['madeForYou']), lang);
        final trending = SongRepository.filterByLanguage(_decodeSongList(unifiedFeed['trendingMerged'] ?? unifiedFeed['trending']), lang);
        var youtubeTrending = SongRepository.filterByLanguage(_decodeSongList(unifiedFeed['youtubeTrending']), lang);
        if (youtubeTrending.isEmpty) {
          try {
            youtubeTrending = await YouTubeClient.getTrendingTracks(language: lang, limit: 15);
          } catch (_) {}
        }
        final newReleases = SongRepository.filterByLanguage(_decodeSongList(unifiedFeed['newReleases']), lang);
        final popularArtists = (unifiedFeed['popularArtists'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final featuredAlbums = (unifiedFeed['featuredAlbums'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final recentHistory = HistoryManager.getRecentSongs();

        _state = HomeFeedState(
          madeForYou: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(madeForYou)),
          trendingMerged: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(trending)),
          youtubeTrending: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(youtubeTrending)),
          newReleases: SongRepository.ensureDistinctCovers(SongRepository.deduplicateSongs(newReleases)),
          popularArtists: popularArtists,
          featuredAlbums: featuredAlbums,
          recentHistory: recentHistory,
          isLoading: false,
        );
        _persistFeedToCache(lang, _state);
        notifyListeners();
        return;
      }

      // SWR Fallback: Parallel repository fetching if consolidated endpoint returned empty/null
      final results = await Future.wait([
        SongRepository.getTrendingMerged(language: lang),
        SongRepository.getMadeForYou(language: lang),
        SongRepository.getNewReleases(language: lang),
        SongRepository.getPopularArtists(language: lang),
        SaavnClient.searchAlbums('$lang Hit Albums', limit: 12),
        YouTubeClient.getTrendingTracks(language: lang, limit: 15),
      ]);

      final trendingMerged = results[0] as List<Song>;
      final madeForYou = results[1] as List<Song>;
      final newReleases = results[2] as List<Song>;
      final popularArtists = results[3] as List<Map<String, dynamic>>;
      final featuredAlbums = results[4] as List<Map<String, dynamic>>;
      final ytTrending = results[5] as List<Song>;
      final recentHistory = HistoryManager.getRecentSongs();

      _state = HomeFeedState(
        madeForYou: madeForYou,
        trendingMerged: trendingMerged,
        youtubeTrending: ytTrending,
        newReleases: newReleases,
        popularArtists: popularArtists,
        featuredAlbums: featuredAlbums,
        recentHistory: recentHistory,
        isLoading: false,
      );
      _persistFeedToCache(lang, _state);
      notifyListeners();
    } catch (e, stack) {
      final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'HomeFeedProvider.loadFeed');
      // Defensive: Only expose error view if ALL providers fail and no local cached data exists
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

