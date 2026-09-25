import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';
import 'settings_manager.dart';
import 'fuzzy_search_service.dart';
import '../data/repositories/song_repository.dart';

class SearchResults {
  final List<Song> songs;
  final List<Song> ytSongs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> artists;
  final Map<String, dynamic>? topResult;

  SearchResults({
    this.songs = const [],
    this.ytSongs = const [],
    this.albums = const [],
    this.artists = const [],
    this.topResult,
  });

  bool get isEmpty => songs.isEmpty && ytSongs.isEmpty && albums.isEmpty && artists.isEmpty;
}

class SearchService {
  static const List<String> _knownLanguages = [
    'tamil',
    'telugu',
    'hindi',
    'english',
    'malayalam',
    'kannada',
    'punjabi',
    'marathi',
    'bengali',
  ];

  /// Enriches a search query with preferred language keyword (e.g., "Hi Nanna" -> "Hi Nanna Tamil")
  /// so dubbed soundtracks in the user's preferred regional language are prioritized over originals.
  static String buildLanguageBiasedQuery(String query, {String? language}) {
    final clean = query.trim();
    if (clean.isEmpty) return '';

    final prefLang = (language ??
            (SettingsManager.preferredLanguages.isNotEmpty
                ? SettingsManager.preferredLanguages.first
                : 'Tamil'))
        .trim();

    final lower = clean.toLowerCase();

    // If query already contains any explicit language name, respect user's explicit intent
    final hasExplicitLanguage = _knownLanguages.any((lang) => lower.contains(lang));
    if (hasExplicitLanguage) {
      return clean;
    }

    // Append the user's preferred language keyword
    return '$clean $prefLang';
  }

  /// High-precision search across JioSaavn & YouTube Music with 25-item limit,
  /// automatic language bias enrichment, and regional match re-ranking.
  static Future<SearchResults> searchUnified(
    String rawQuery, {
    String? language,
    int limit = 25,
  }) async {
    final cleanQuery = rawQuery.trim();
    if (cleanQuery.isEmpty) return SearchResults();

    final prefLang = (language ??
            (SettingsManager.preferredLanguages.isNotEmpty
                ? SettingsManager.preferredLanguages.first
                : 'Tamil'))
        .trim();

    final biasedQuery = buildLanguageBiasedQuery(cleanQuery, language: prefLang);
    final targetLangLower = prefLang.toLowerCase();

    try {
      // Execute parallel queries:
      // 1. Biased JioSaavn query ("Hi Nanna Tamil", limit: 25)
      // 2. Direct JioSaavn query ("Hi Nanna", limit: 25)
      // 3. YouTube Music query ("Hi Nanna Tamil", limit: 25)
      // 4. Albums & Artists search
      final results = await Future.wait([
        SaavnClient.search(biasedQuery, limit: limit, language: prefLang),
        if (biasedQuery != cleanQuery)
          SaavnClient.search(cleanQuery, limit: limit, language: prefLang)
        else
          Future.value(<Song>[]),
        YouTubeClient.search(biasedQuery, limit: limit),
        SaavnClient.searchAlbums(cleanQuery, limit: 12),
        SaavnClient.searchArtists(cleanQuery, limit: 12),
      ]);

      final biasedSaavn = results[0] as List<Song>;
      final rawSaavn = results[1] as List<Song>;
      final ytSongs = results[2] as List<Song>;
      final albums = results[3] as List<Map<String, dynamic>>;
      final artists = results[4] as List<Map<String, dynamic>>;

      // Merge JioSaavn tracks prioritizing biased results
      final List<Song> combinedSaavn = [];
      combinedSaavn.addAll(biasedSaavn);
      for (final s in rawSaavn) {
        if (!combinedSaavn.any((x) => x.id == s.id)) {
          combinedSaavn.add(s);
        }
      }

      // Re-rank by language match & title relevance
      final reRankedSaavn = _reRankByLanguageMatch(cleanQuery, combinedSaavn, targetLangLower);
      final cleanSaavn = SongRepository.deduplicateSongs(reRankedSaavn);

      // Re-rank YouTube tracks as well
      final reRankedYt = _reRankByLanguageMatch(cleanQuery, ytSongs, targetLangLower);
      final cleanYt = SongRepository.deduplicateSongs(reRankedYt);

      // Register with fuzzy index for instant typo tolerance
      FuzzySearchService.registerSongs(cleanSaavn);

      // Extract top result (preferring language-matched track)
      Map<String, dynamic>? topResult;
      if (cleanSaavn.isNotEmpty) {
        final top = cleanSaavn.first;
        topResult = {
          'type': 'song',
          'id': top.id,
          'title': top.title,
          'artist': top.artist,
          'cover_url': top.coverUrl,
          'duration': top.duration,
          'source': top.source,
        };
      }

      return SearchResults(
        songs: cleanSaavn,
        ytSongs: cleanYt,
        albums: albums,
        artists: artists,
        topResult: topResult,
      );
    } catch (e) {
      debugPrint('[SearchService] Search error: $e');
      return SearchResults();
    }
  }

  /// Re-ranks tracks so that songs matching the preferred language or containing
  /// language keywords in title/subtitle appear first.
  static List<Song> _reRankByLanguageMatch(
    String originalQuery,
    List<Song> songs,
    String targetLang,
  ) {
    if (songs.isEmpty) return [];

    final qLower = originalQuery.toLowerCase();
    final List<Song> exactLangMatches = [];
    final List<Song> titleLangMentions = [];
    final List<Song> otherMatches = [];

    for (final song in songs) {
      final sLang = song.language?.toLowerCase() ?? '';
      final sTitle = song.title.toLowerCase();
      final sArtist = song.artist.toLowerCase();

      final bool isTargetLang = sLang == targetLang;
      final bool titleContainsLang = sTitle.contains(targetLang);
      final bool matchesQueryExactly = sTitle.contains(qLower) || sArtist.contains(qLower);

      if (isTargetLang && matchesQueryExactly) {
        exactLangMatches.add(song);
      } else if (titleContainsLang) {
        titleLangMentions.add(song);
      } else {
        otherMatches.add(song);
      }
    }

    final List<Song> sorted = [];
    sorted.addAll(exactLangMatches);
    sorted.addAll(titleLangMentions);
    sorted.addAll(otherMatches);

    // Apply secondary fuzzy scoring against the user's original query
    return FuzzySearchService.reRankSongs(originalQuery, sorted);
  }
}
