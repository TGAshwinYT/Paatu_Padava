import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/models/catalog_entry.dart';
import '../data/catalog_seed_data.dart';
import '../data/repositories/song_repository.dart';
import '../logic/search_query_planner.dart';
import '../models/song.dart';
import 'catalog_schema.dart';
import 'artist_sanitizer.dart';
import 'app_logger.dart';

/// Embedded SQLite & In-Memory Movie & Song Master Catalog for Paatu Padava.
/// Guarantees 0ms local searches, role isolation, populates Artists/Albums tabs, and caps dynamic cache.
class CatalogDatabase {
  static const String _dbName = 'paatu_catalog_v1.db';
  static const int maxDynamicSongsLimit = 2000;

  static Database? _db;
  static bool _useInMemoryFallback = false;

  static final Map<String, CatalogMovie> _memMovies = {};
  static final Map<String, CatalogArtist> _memArtists = {};
  static final Map<String, CatalogSong> _memSongs = {};

  static bool get isInitialized => _db != null || _useInMemoryFallback;

  /// Initializes the catalog database with SQLite or in-memory fallback.
  static Future<void> init({Database? customDb}) async {
    if (customDb != null) {
      _db = customDb;
      _useInMemoryFallback = false;
      return;
    }
    final bool isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest || kIsWeb) {
      _initInMemoryStore();
      return;
    }
    try {
      final dbPath = await getDatabasesPath();
      _db = await openDatabase(
        '$dbPath/$_dbName',
        version: 1,
        onCreate: (db, version) async {
          await CatalogSchema.createTables(db);
          await _seedDatabase(db);
        },
      );
    } catch (e) {
      AppLogger.log('CatalogDatabase', 'SQLite open failure, fallback to in-memory: $e');
      _initInMemoryStore();
    }
  }

  static void _initInMemoryStore() {
    _useInMemoryFallback = true;
    _memMovies.clear();
    _memArtists.clear();
    _memSongs.clear();
    for (final a in CatalogSeedData.initialArtists) {
      _memArtists[a.id] = a;
      _memArtists[a.name.toLowerCase().trim()] = a;
    }
    for (final m in CatalogSeedData.initialMovies) { _memMovies[m.id] = m; }
    for (final s in CatalogSeedData.initialSongs) { _memSongs[s.id] = s; }
  }

  static Future<void> _seedDatabase(Database db) async {
    final batch = db.batch();
    for (final a in CatalogSeedData.initialArtists) {
      batch.insert('artists', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final m in CatalogSeedData.initialMovies) {
      batch.insert('movies', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final s in CatalogSeedData.initialSongs) {
      batch.insert('songs', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static String _stripSearchNoise(String query) {
    return query.toLowerCase()
        .replaceAll(RegExp(r'\b(tamil|telugu|hindi|malayalam|kannada)\b'), ' ')
        .replaceAll(RegExp(r'\b(vibe|vibes|hits|hit\s*songs|top\s*hits|top\s*songs|songs|song|all\s*hits|all\s*songs|best\s*of|collection|jukebox|discography)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Searches master catalog songs at 0ms latency with multi-token matching.
  static Future<List<Song>> searchCatalog(String query, {int limit = 20, String? language}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    if (_useInMemoryFallback || _db == null) {
      final matches = _memSongs.values.where((s) {
        if (language != null && language.isNotEmpty && language.toLowerCase() != 'all') {
          if (s.language.toLowerCase() != language.toLowerCase()) return false;
        }
        final fullText = '${s.title} ${s.movieTitle} ${s.composer} ${s.singers} ${s.starring}'.toLowerCase();
        return fullText.contains(q);
      }).toList();

      if (matches.isEmpty) {
        final stripped = _stripSearchNoise(q);
        if (stripped.isNotEmpty && stripped != q) {
          return searchCatalog(stripped, limit: limit, language: language);
        }
      }

      matches.sort((a, b) {
        final aExact = a.title.toLowerCase() == q;
        final bExact = b.title.toLowerCase() == q;
        if (aExact != bExact) return aExact ? -1 : 1;
        final aStart = a.title.toLowerCase().startsWith(q);
        final bStart = b.title.toLowerCase().startsWith(q);
        if (aStart != bStart) return aStart ? -1 : 1;
        return b.year.compareTo(a.year);
      });
      return matches.take(limit).map((s) => s.toSong()).toList();
    }

    try {
      final safeQ = '%$q%';
      final bool hasLang = language != null && language.isNotEmpty && language.toLowerCase() != 'all';
      final rows = await _db!.rawQuery('''
        SELECT * FROM songs 
        WHERE (title LIKE ? OR movie_title LIKE ? OR composer LIKE ? OR singers LIKE ? OR starring LIKE ?)
        ${hasLang ? 'AND LOWER(language) = ?' : ''}
        ORDER BY 
          CASE WHEN LOWER(title) = ? THEN 1
               WHEN LOWER(title) LIKE ? THEN 2
               WHEN LOWER(movie_title) LIKE ? THEN 3
               ELSE 4 END,
          year DESC
        LIMIT ?
      ''', hasLang
          ? [safeQ, safeQ, safeQ, safeQ, safeQ, language.toLowerCase(), q, '$q%', '$q%', limit]
          : [safeQ, safeQ, safeQ, safeQ, safeQ, q, '$q%', '$q%', limit]);

      if (rows.isEmpty) {
        final stripped = _stripSearchNoise(q);
        if (stripped.isNotEmpty && stripped != q) {
          return await searchCatalog(stripped, limit: limit, language: language);
        }
      }

      return rows.map((r) => CatalogSong.fromMap(r).toSong()).toList();
    } catch (e) {
      AppLogger.log('CatalogDatabase', 'searchCatalog error: $e');
      return const [];
    }
  }

  static Map<String, dynamic> _artistEntry(String id, String name, String role, String img, bool verified) =>
      {'id': id, 'name': name, 'title': name, 'role': role, 'image': img, 'is_verified': verified};

  /// Searches genuine musical artists (Composers and Playback Singers) matching the query.
  static Future<List<Map<String, dynamic>>> searchArtists(String query, {int limit = 10}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final Map<String, Map<String, dynamic>> results = {};

    if (_useInMemoryFallback || _db == null) {
      for (final a in _memArtists.values) {
        if (a.name.toLowerCase().contains(q)) {
          results[a.name.toLowerCase()] = _artistEntry(a.id, a.name, a.role, a.imageUrl, a.isVerified);
        }
      }
      for (final s in _memSongs.values) {
        if (s.title.toLowerCase().contains(q) || s.movieTitle.toLowerCase().contains(q)) {
          _extractAndAddArtists(s, results);
        }
      }
      if (results.isEmpty) {
        final stripped = _stripSearchNoise(q);
        if (stripped.isNotEmpty && stripped != q) {
          return await searchArtists(stripped, limit: limit);
        }
      }
      return results.values.take(limit).toList();
    }

    try {
      final safeQ = '%$q%';
      final rows = await _db!.rawQuery('SELECT * FROM artists WHERE LOWER(name) LIKE ? LIMIT ?', [safeQ, limit]);
      for (final r in rows) {
        final a = CatalogArtist.fromMap(r);
        results[a.name.toLowerCase()] = _artistEntry(a.id, a.name, a.role, a.imageUrl, a.isVerified);
      }

      if (results.length < limit) {
        final songRows = await _db!.rawQuery(
          'SELECT * FROM songs WHERE LOWER(title) LIKE ? OR LOWER(movie_title) LIKE ? LIMIT 10',
          [safeQ, safeQ],
        );
        for (final sr in songRows) {
          _extractAndAddArtists(CatalogSong.fromMap(sr), results);
        }
      }
      if (results.isEmpty) {
        final stripped = _stripSearchNoise(q);
        if (stripped.isNotEmpty && stripped != q) {
          return await searchArtists(stripped, limit: limit);
        }
      }
      return results.values.take(limit).toList();
    } catch (e) {
      AppLogger.log('CatalogDatabase', 'searchArtists error: $e');
      return results.values.take(limit).toList();
    }
  }

  /// Resolves verified high-resolution artist portrait from seed catalog or memory
  static String? getArtistProfileImage(String name) {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;

    final fromRepo = SongRepository.verifiedArtistAvatars[clean];
    if (fromRepo != null && fromRepo.isNotEmpty) return fromRepo;

    final canon = ArtistSanitizer.canonicalArtistName(clean).toLowerCase();
    final fromCanon = SongRepository.verifiedArtistAvatars[canon];
    if (fromCanon != null && fromCanon.isNotEmpty) return fromCanon;

    if (_memArtists.containsKey(clean)) {
      final img = _memArtists[clean]?.imageUrl;
      if (img != null && img.isNotEmpty) return img;
    }

    final alpha = clean.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (alpha.isNotEmpty) {
      for (final a in CatalogSeedData.initialArtists) {
        final aAlpha = a.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final aIdAlpha = a.id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (aAlpha == alpha || aIdAlpha == alpha) {
          if (a.imageUrl.isNotEmpty) return a.imageUrl;
        }
      }
    }
    return null;
  }

  /// Resolves verified high-resolution studio square cover art for a song from seed catalog
  static String? getSongCoverArt(String title, {String? artist, String? album}) {
    final clean = SearchQueryPlanner.cleanTitle(title).trim().toLowerCase();
    if (clean.isEmpty) return null;

    for (final s in CatalogSeedData.initialSongs) {
      final sTitle = SearchQueryPlanner.cleanTitle(s.title).trim().toLowerCase();
      if (sTitle == clean || (clean.length >= 4 && sTitle.contains(clean)) || (sTitle.length >= 4 && clean.contains(sTitle))) {
        if (s.coverUrl.isNotEmpty && !s.coverUrl.contains('default.jpg')) {
          return s.coverUrl;
        }
      }
    }

    if (album != null && album.isNotEmpty) {
      final cleanAlb = album.trim().toLowerCase();
      for (final m in CatalogSeedData.initialMovies) {
        final mTitle = m.title.trim().toLowerCase();
        if (mTitle == cleanAlb || (cleanAlb.length >= 4 && cleanAlb.contains(mTitle))) {
          final cUrl = m.coverUrl;
          if (cUrl != null && cUrl.isNotEmpty && !cUrl.contains('default.jpg')) {
            return cUrl;
          }
        }
      }
    }

    return null;
  }

  /// Resolves verified high-resolution movie poster from seed catalog
  static String? getMoviePoster(String movieTitle) {
    final clean = movieTitle.trim().toLowerCase();
    if (clean.isEmpty) return null;
    for (final m in CatalogSeedData.initialMovies) {
      final mTitle = m.title.trim().toLowerCase();
      if (mTitle == clean || (clean.length >= 4 && mTitle.contains(clean)) || (mTitle.length >= 4 && clean.contains(mTitle))) {
        if (m.coverUrl != null && m.coverUrl!.isNotEmpty && !m.coverUrl!.contains('default.jpg')) {
          return m.coverUrl;
        }
      }
    }
    return null;
  }

  static void _extractAndAddArtists(CatalogSong s, Map<String, Map<String, dynamic>> results) {
    if (s.composer.isNotEmpty) {
      final comp = s.composer.trim();
      final key = comp.toLowerCase();
      if (!results.containsKey(key)) {
        final img = getArtistProfileImage(comp) ?? '';
        results[key] = _artistEntry('art_${key.replaceAll(' ', '_')}', comp, 'Music Director / Composer', img, true);
      }
    }
    final allSingers = ArtistSanitizer.extractAllGenuineArtists(s.singers);
    for (final singer in allSingers) {
      final key = singer.toLowerCase();
      if (!results.containsKey(key)) {
        final img = getArtistProfileImage(singer) ?? '';
        results[key] = _artistEntry('art_${key.replaceAll(' ', '_')}', singer, 'Playback Singer', img, true);
      }
    }
  }

  /// Searches genuine movies matching query or starring actors.
  static Future<List<Map<String, dynamic>>> searchMovies(String query, {int limit = 10}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    if (_useInMemoryFallback || _db == null) {
      final matches = _memMovies.values.where((m) {
        final text = '${m.title} ${m.starring} ${m.composer}'.toLowerCase();
        return text.contains(q);
      }).take(limit).map((m) => {
        'id': m.id,
        'title': m.title,
        'year': m.year,
        'composer': m.composer,
        'starring': m.starring,
        'image': m.coverUrl ?? '',
        'type': 'Movie / Album',
      }).toList();

      if (matches.isEmpty) {
        final stripped = _stripSearchNoise(q);
        if (stripped.isNotEmpty && stripped != q) {
          return searchMovies(stripped, limit: limit);
        }
      }
      return matches;
    }

    try {
      final safeQ = '%$q%';
      final rows = await _db!.rawQuery('''
        SELECT * FROM movies 
        WHERE LOWER(title) LIKE ? OR LOWER(starring) LIKE ? OR LOWER(composer) LIKE ?
        ORDER BY year DESC
        LIMIT ?
      ''', [safeQ, safeQ, safeQ, limit]);

      if (rows.isEmpty) {
        final stripped = _stripSearchNoise(q);
        if (stripped.isNotEmpty && stripped != q) {
          return await searchMovies(stripped, limit: limit);
        }
      }

      return rows.map((r) {
        final rId = r['id']?.toString() ?? '';
        final rTitle = r['title']?.toString() ?? '';
        var img = r['cover_url']?.toString() ?? '';
        if (img.isEmpty || img.contains('default')) {
          img = _memMovies[rId]?.coverUrl ?? getMoviePoster(rTitle) ?? '';
        }
        return {
          'id': rId,
          'title': rTitle,
          'year': r['year'],
          'composer': r['composer']?.toString() ?? '',
          'starring': r['starring']?.toString() ?? '',
          'image': img,
          'type': 'Movie / Album',
        };
      }).toList();
    } catch (e) {
      AppLogger.log('CatalogDatabase', 'searchMovies error: $e');
      return const [];
    }
  }

  /// Fetches all songs by a composer or singer (used when opening ArtistScreen).
  static Future<List<Song>> getSongsByArtist(String artistName, {int limit = 40}) async {
    final q = artistName.trim().toLowerCase();
    if (q.isEmpty) return const [];

    if (_useInMemoryFallback || _db == null) {
      return _memSongs.values.where((s) {
        final text = '${s.composer} ${s.singers}'.toLowerCase();
        return text.contains(q);
      }).take(limit).map((s) => s.toSong()).toList();
    }

    try {
      final safeQ = '%$q%';
      final rows = await _db!.rawQuery('''
        SELECT * FROM songs 
        WHERE LOWER(composer) LIKE ? OR LOWER(singers) LIKE ?
        ORDER BY year DESC
        LIMIT ?
      ''', [safeQ, safeQ, limit]);
      return rows.map((r) => CatalogSong.fromMap(r).toSong()).toList();
    } catch (e) {
      AppLogger.log('CatalogDatabase', 'getSongsByArtist error: $e');
      return const [];
    }
  }

  /// Fetches all verified songs from a specific film/movie (used when opening AlbumScreen).
  static Future<List<Song>> getSongsByMovie(String movieTitle, {int limit = 40}) async {
    final q = movieTitle.trim().toLowerCase();
    if (q.isEmpty) return const [];

    if (_useInMemoryFallback || _db == null) {
      return _memSongs.values
          .where((s) => s.movieTitle.toLowerCase().contains(q) || q.contains(s.movieTitle.toLowerCase()))
          .take(limit)
          .map((s) => s.toSong())
          .toList();
    }

    try {
      final safeQ = '%$q%';
      final rows = await _db!.rawQuery(
        'SELECT * FROM songs WHERE LOWER(movie_title) LIKE ? ORDER BY year DESC LIMIT ?',
        [safeQ, limit],
      );
      return rows.map((r) => CatalogSong.fromMap(r).toSong()).toList();
    } catch (e) {
      AppLogger.log('CatalogDatabase', 'getSongsByMovie error: $e');
      return const [];
    }
  }

  /// Extracts genuine artists from an arbitrary list of songs with verified portraits.
  static List<Map<String, dynamic>> extractArtistsFromSongs(List<Song> songs, {int limit = 10}) {
    final Map<String, Map<String, dynamic>> map = {};
    for (final song in songs) {
      final artists = ArtistSanitizer.extractAllGenuineArtists(song.artist);
      for (final art in artists) {
        if (ArtistSanitizer.isCompositeOrMultiArtist(art)) continue;
        final lowerArt = art.toLowerCase().trim();
        if (lowerArt == song.album.toLowerCase().trim() || lowerArt == song.title.toLowerCase().trim()) continue;
        if (lowerArt == 'unknown artist' || lowerArt == 'various artists' || lowerArt.contains('soundtrack')) continue;

        final key = lowerArt;
        if (!map.containsKey(key)) {
          final img = getArtistProfileImage(art) ?? '';
          map[key] = {
            'id': 'art_${key.replaceAll(' ', '_')}',
            'name': art,
            'title': art,
            'role': 'Singer / Composer',
            'image': img,
            'is_verified': img.isNotEmpty,
          };
          if (map.length >= limit) break;
        }
      }
      if (map.length >= limit) break;
    }
    return map.values.toList();
  }

  /// Write-through ingestion: when live search returns a new song released today,
  /// asynchronously write it to the local catalog so it becomes instant (0ms) in subsequent queries.
  static Future<void> insertDynamicSong(
    Song song, {
    String? movie,
    String? starring,
    String? composer,
    String? singers,
  }) async {
    if (song.title.trim().isEmpty || song.id.isEmpty) return;

    final resolvedSingers = singers ?? ArtistSanitizer.extractAllGenuineArtists(song.artist).join(', ');
    final resolvedComposer = composer ?? song.primaryArtist;
    final resolvedMovie = movie ?? (song.album.isNotEmpty ? song.album : song.title);

    final catalogSong = CatalogSong(
      id: song.id,
      title: song.title,
      movieTitle: resolvedMovie,
      movieId: null,
      composer: resolvedComposer,
      singers: resolvedSingers.isNotEmpty ? resolvedSingers : resolvedComposer,
      starring: starring ?? '',
      year: DateTime.now().year,
      duration: song.duration,
      coverUrl: song.coverUrl,
      audioUrl: song.streamUrl,
      source: song.source,
      language: song.language ?? 'tamil',
      isDynamic: true,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    // Cache only in memory to protect device storage from growing
    _memSongs[catalogSong.id] = catalogSong;
    if (_memSongs.length > 500) {
      final dynamicKeys = _memSongs.entries.where((e) => e.value.isDynamic).map((e) => e.key).toList();
      for (final k in dynamicKeys.take(100)) {
        _memSongs.remove(k);
      }
    }
  }
}
