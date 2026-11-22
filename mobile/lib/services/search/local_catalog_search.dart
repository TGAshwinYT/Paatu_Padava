import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../catalog_database.dart';
import '../download_manager.dart';
import '../app_logger.dart';
import 'search_models.dart';

/// Handles fast local SQLite Master Catalog queries and offline in-memory downloaded songs searching.
class LocalCatalogSearch {
  /// Performs fast in-memory title, artist, and album fuzzy search across downloaded songs for offline resilience.
  static List<Song> searchDownloadedSongs(String query) {
    try {
      final downloaded = DownloadManager.getDownloadedSongs();
      if (downloaded.isEmpty || query.trim().isEmpty) return const [];
      final q = query.trim().toLowerCase();
      final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      final matched = downloaded.where((song) {
        final t = song.title.toLowerCase();
        final a = song.artist.toLowerCase();
        final alb = song.album.toLowerCase();

        if (t.contains(q) || a.contains(q) || alb.contains(q)) return true;
        if (tokens.isNotEmpty && tokens.every((tok) => t.contains(tok) || a.contains(tok) || alb.contains(tok))) {
          return true;
        }
        return false;
      }).toList();

      matched.sort((a, b) {
        final aTitle = a.title.toLowerCase();
        final bTitle = b.title.toLowerCase();
        final aStarts = aTitle.startsWith(q) ? 1 : 0;
        final bStarts = bTitle.startsWith(q) ? 1 : 0;
        if (aStarts != bStarts) return bStarts.compareTo(aStarts);
        final aContains = aTitle.contains(q) ? 1 : 0;
        final bContains = bTitle.contains(q) ? 1 : 0;
        if (aContains != bContains) return bContains.compareTo(aContains);
        return 0;
      });

      return matched;
    } catch (e) {
      debugPrint('[LocalCatalogSearch] searchDownloadedSongs error: $e');
      return const [];
    }
  }

  /// Searches local Master Catalog for songs with query fallback (core, clean, transliterated).
  static Future<List<Song>> searchCatalogSongs(
    QueryIntent intent, {
    String? language,
    int limit = 25,
  }) async {
    try {
      final catQuery = intent.effectiveCoreQuery;
      var songs = await CatalogDatabase.searchCatalog(
        catQuery,
        limit: limit,
        language: language,
      );
      if (songs.isEmpty && catQuery != intent.cleanQuery) {
        songs = await CatalogDatabase.searchCatalog(
          intent.cleanQuery,
          limit: limit,
          language: language,
        );
      }
      if (songs.isEmpty && intent.transliteratedQuery != intent.cleanQuery) {
        songs = await CatalogDatabase.searchCatalog(
          intent.transliteratedQuery,
          limit: limit,
          language: language,
        );
      }
      return songs;
    } catch (e, stack) {
      AppLogger.log('LocalCatalogSearch', 'searchCatalogSongs error: $e', level: LogLevel.warn);
      AppLogger.recordError(e, stack, context: 'searchCatalogSongs failed for "${intent.cleanQuery}"');
      return const [];
    }
  }

  /// Searches local Master Catalog for movies/albums with query fallback.
  static Future<List<Map<String, dynamic>>> searchCatalogMovies(
    QueryIntent intent, {
    int limit = 8,
  }) async {
    try {
      final catQuery = intent.effectiveCoreQuery;
      var movies = await CatalogDatabase.searchMovies(catQuery, limit: limit);
      if (movies.isEmpty && catQuery != intent.cleanQuery) {
        movies = await CatalogDatabase.searchMovies(intent.cleanQuery, limit: limit);
      }
      if (movies.isEmpty && intent.transliteratedQuery != intent.cleanQuery) {
        movies = await CatalogDatabase.searchMovies(intent.transliteratedQuery, limit: limit);
      }
      return movies;
    } catch (e, stack) {
      AppLogger.log('LocalCatalogSearch', 'searchCatalogMovies error: $e', level: LogLevel.warn);
      AppLogger.recordError(e, stack, context: 'searchCatalogMovies failed for "${intent.cleanQuery}"');
      return const [];
    }
  }

  /// Searches local Master Catalog for verified artists with query fallback.
  static Future<List<Map<String, dynamic>>> searchCatalogArtists(
    QueryIntent intent, {
    int limit = 6,
  }) async {
    try {
      final catQuery = intent.effectiveCoreQuery;
      var artists = await CatalogDatabase.searchArtists(catQuery, limit: limit);
      if (artists.isEmpty && catQuery != intent.cleanQuery) {
        artists = await CatalogDatabase.searchArtists(intent.cleanQuery, limit: limit);
      }
      if (artists.isEmpty && intent.transliteratedQuery != intent.cleanQuery) {
        artists = await CatalogDatabase.searchArtists(intent.transliteratedQuery, limit: limit);
      }
      return artists;
    } catch (e, stack) {
      AppLogger.log('LocalCatalogSearch', 'searchCatalogArtists error: $e', level: LogLevel.warn);
      AppLogger.recordError(e, stack, context: 'searchCatalogArtists failed for "${intent.cleanQuery}"');
      return const [];
    }
  }
}
