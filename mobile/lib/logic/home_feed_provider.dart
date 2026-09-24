import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/settings_manager.dart';
import '../services/history_manager.dart';
import '../services/saavn_client.dart';
import '../data/repositories/song_repository.dart';

class HomeFeedState {
  final List<Song> madeForYou;
  final List<Song> trendingMerged;
  final List<Song> newReleases;
  final List<Map<String, dynamic>> popularArtists;
  final List<Map<String, dynamic>> featuredAlbums;
  final List<Song> recentHistory;
  final bool isLoading;
  final String? error;

  const HomeFeedState({
    this.madeForYou = const [],
    this.trendingMerged = const [],
    this.newReleases = const [],
    this.popularArtists = const [],
    this.featuredAlbums = const [],
    this.recentHistory = const [],
    this.isLoading = false,
    this.error,
  });

  HomeFeedState copyWith({
    List<Song>? madeForYou,
    List<Song>? trendingMerged,
    List<Song>? newReleases,
    List<Map<String, dynamic>>? popularArtists,
    List<Map<String, dynamic>>? featuredAlbums,
    List<Song>? recentHistory,
    bool? isLoading,
    String? error,
  }) {
    return HomeFeedState(
      madeForYou: madeForYou ?? this.madeForYou,
      trendingMerged: trendingMerged ?? this.trendingMerged,
      newReleases: newReleases ?? this.newReleases,
      popularArtists: popularArtists ?? this.popularArtists,
      featuredAlbums: featuredAlbums ?? this.featuredAlbums,
      recentHistory: recentHistory ?? this.recentHistory,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Unified Home Feed provider orchestrating JioSaavn, YouTube Music, and User Taste recommendations.
class HomeFeedProvider extends ChangeNotifier {
  static final HomeFeedProvider instance = HomeFeedProvider._internal();
  factory HomeFeedProvider() => instance;
  HomeFeedProvider._internal();

  HomeFeedState _state = const HomeFeedState(isLoading: true);
  HomeFeedState get state => _state;

  String _currentLanguage = 'Tamil';
  String get currentLanguage => _currentLanguage;

  Future<void> init() async {
    final prefLangs = SettingsManager.preferredLanguages;
    if (prefLangs.isNotEmpty) {
      _currentLanguage = prefLangs.first;
    }
    await loadFeed();
  }

  void setLanguage(String lang) {
    if (_currentLanguage == lang) return;
    _currentLanguage = lang;
    loadFeed();
  }

  Future<void> loadFeed({bool forceRefresh = false}) async {
    _state = _state.copyWith(isLoading: true, error: null);
    notifyListeners();

    try {
      final lang = _currentLanguage;

      // In parallel (Future.wait), fetch:
      // 1. JioSaavn + YouTube Merged Trending
      // 2. User Taste Mix (Made For You)
      // 3. New Language Releases
      // 4. Popular Artists with High-Res Avatars
      // 5. Featured Albums
      // 6. Recent History
      final results = await Future.wait([
        SongRepository.getTrendingMerged(language: lang),
        SongRepository.getMadeForYou(language: lang),
        SongRepository.getNewReleases(language: lang),
        SongRepository.getPopularArtists(language: lang),
        SaavnClient.searchAlbums('$lang Hit Albums', limit: 12),
      ]);

      final trendingMerged = results[0] as List<Song>;
      final madeForYou = results[1] as List<Song>;
      final newReleases = results[2] as List<Song>;
      final popularArtists = results[3] as List<Map<String, dynamic>>;
      final featuredAlbums = results[4] as List<Map<String, dynamic>>;
      final recentHistory = HistoryManager.getRecentSongs();

      _state = HomeFeedState(
        madeForYou: madeForYou,
        trendingMerged: trendingMerged,
        newReleases: newReleases,
        popularArtists: popularArtists,
        featuredAlbums: featuredAlbums,
        recentHistory: recentHistory,
        isLoading: false,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(isLoading: false, error: e.toString());
      notifyListeners();
    }
  }
}
