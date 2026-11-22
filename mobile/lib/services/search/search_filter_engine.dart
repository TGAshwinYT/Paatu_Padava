import '../../models/song.dart';
import '../artist_sanitizer.dart';
import '../settings_manager.dart';
import '../../data/repositories/song_repository.dart';
import 'query_normalizer.dart';

/// Pure entity filtering, language-sanitization, and album/playlist synthesis algorithms.
class SearchFilterEngine {
  /// Strictly filters search artists by language, purging foreign/mismatched artists
  static List<Map<String, dynamic>> filterArtistsByLanguage(
    List<Map<String, dynamic>> artists, {
    String? language,
    required String query,
  }) {
    final filtered = <Map<String, dynamic>>[];
    final cleanLang = (language != null && language.isNotEmpty && language.toLowerCase() != 'all')
        ? language.toLowerCase().trim()
        : null;
    final qLower = query.toLowerCase().trim();

    for (final item in artists) {
      final name = (item['name'] ?? item['title'] ?? '').toString().trim();
      final norm = SongRepository.normalizeArtist(name);
      if (norm.isEmpty) continue;

      if (!ArtistSanitizer.isGenuineArtist(name)) continue;

      if (cleanLang != null) {
        final artistLang = (item['language'] ?? item['more_info']?['language'] ?? '').toString().toLowerCase().trim();
        final isDirectNameMatch = name.toLowerCase() == qLower || name.toLowerCase().contains(qLower);
        if (!isDirectNameMatch && artistLang.isNotEmpty && artistLang != cleanLang) {
          continue;
        }
      }

      final img = item['image']?.toString();
      final hasRealImage = !ArtistSanitizer.isPlaceholderImage(img) || SongRepository.isArtistVerified(name);

      filtered.add({
        ...item,
        'image': hasRealImage ? (img ?? '') : '',
      });
    }
    return filtered;
  }

  /// Strictly filters out single-song releases, fake albums, and unrelated compilations
  static List<Map<String, dynamic>> filterGenuineAlbums(
    List<Map<String, dynamic>> rawAlbums, {
    String? query,
    String? preferredLanguage,
    List<String>? preferredLanguages,
  }) {
    final valid = <Map<String, dynamic>>[];
    final cleanQuery = (query ?? '').trim().toLowerCase();
    final queryTokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();

    for (final alb in rawAlbums) {
      final songCount = int.tryParse(alb['song_count']?.toString() ?? '0') ?? 0;
      final title = (alb['title'] ?? '').toString().toLowerCase();
      final artist = (alb['artist'] ?? '').toString().toLowerCase();

      final cleanBaseTitle = title.split(' - ').first.replaceAll(RegExp(r'\s*\((From|OST|Original).*\)', caseSensitive: false), '').trim();
      final isDirectEntityMatch = cleanQuery.length >= 2 &&
          (QueryNormalizer.isAlbumOrMovieEntityMatch(title, cleanQuery) || cleanBaseTitle == cleanQuery || title.startsWith(cleanQuery));

      final isFromSongList = alb['source_type'] == 'extracted_song_album' || alb['is_movie'] == true;
      if (!isDirectEntityMatch && !isFromSongList && (songCount <= 1 || title.contains('single') || title.contains('teaser'))) {
        continue;
      }

      if (cleanQuery.length >= 2 && queryTokens.isNotEmpty) {
        final titleTokens = title.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
        final artistTokens = artist.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
        final isRelevant = isDirectEntityMatch ||
            title.contains(cleanQuery) ||
            cleanQuery.contains(title) ||
            artist.contains(cleanQuery) ||
            titleTokens.intersection(queryTokens).isNotEmpty ||
            artistTokens.intersection(queryTokens).isNotEmpty;
        if (!isRelevant) {
          continue;
        }
      }

      valid.add({
        ...alb,
        'type': 'Album',
        'is_single': false,
      });
    }

    if (cleanQuery.isNotEmpty) {
      valid.sort((a, b) {
        final tA = (a['title'] ?? '').toString().toLowerCase().trim();
        final tB = (b['title'] ?? '').toString().toLowerCase().trim();
        final matchA = QueryNormalizer.isAlbumOrMovieEntityMatch(tA, cleanQuery);
        final matchB = QueryNormalizer.isAlbumOrMovieEntityMatch(tB, cleanQuery);
        if (matchA != matchB) return matchA ? -1 : 1;

        final eqA = tA == cleanQuery || (tA.contains(' - ') && tA.split(' - ').first.trim() == cleanQuery);
        final eqB = tB == cleanQuery || (tB.contains(' - ') && tB.split(' - ').first.trim() == cleanQuery);
        if (eqA != eqB) return eqA ? -1 : 1;
        final isMovieA = a['is_movie'] == true || a['source_type'] == 'extracted_song_album';
        final isMovieB = b['is_movie'] == true || b['source_type'] == 'extracted_song_album';
        if (isMovieA != isMovieB) return isMovieA ? -1 : 1;

        final Set<String> targetLangs = {};
        if (preferredLanguage != null && preferredLanguage.trim().isNotEmpty) {
          targetLangs.add(preferredLanguage.trim().toLowerCase());
        }
        if (preferredLanguages != null) {
          for (final l in preferredLanguages) {
            final t = l.trim().toLowerCase();
            if (t.isNotEmpty) targetLangs.add(t);
          }
        }
        if (targetLangs.isNotEmpty) {
          final aLang = (a['language'] ?? '').toString().toLowerCase().trim();
          final bLang = (b['language'] ?? '').toString().toLowerCase().trim();
          final aMatch = targetLangs.contains(aLang) || targetLangs.any((l) => tA.contains(l));
          final bMatch = targetLangs.contains(bLang) || targetLangs.any((l) => tB.contains(l));
          if (aMatch != bMatch) return aMatch ? -1 : 1;
        }

        final scA = int.tryParse(a['song_count']?.toString() ?? '0') ?? 0;
        final scB = int.tryParse(b['song_count']?.toString() ?? '0') ?? 0;
        if ((scA > 1) != (scB > 1)) {
          return (scB > 1) ? 1 : -1;
        }
        return scB.compareTo(scA);
      });
    }
    return valid;
  }

  /// Filters playlists to ensure query relevance and language alignment
  static List<Map<String, dynamic>> filterPlaylistsByRelevanceAndLanguage(
    List<Map<String, dynamic>> rawPlaylists, {
    required String query,
    String? language,
  }) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty) return rawPlaylists;

    final queryTokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
    final userPrefList = SettingsManager.preferredLanguages;
    final prefLang = (language ?? (userPrefList.isNotEmpty ? userPrefList.first : '')).toLowerCase().trim();
    final foreignLangRegex = RegExp(r'\b(kannada|marathi|bhojpuri|punjabi|haryanvi|bengali|gujarati)\b', caseSensitive: false);

    final filtered = <Map<String, dynamic>>[];
    for (final p in rawPlaylists) {
      if (p['source'] == 'auto_album' || p['source'] == 'auto_hits') { filtered.add(p); continue; }
      final title = (p['title'] ?? p['name'] ?? '').toString().toLowerCase().trim();
      if (title.isEmpty) continue;

      final playlistLang = (p['language'] ?? p['more_info']?['language'] ?? '').toString().toLowerCase().trim();
      if (foreignLangRegex.hasMatch(playlistLang) || foreignLangRegex.hasMatch(title)) {
        if (!cleanQuery.contains('kannada') && !cleanQuery.contains('marathi') && !cleanQuery.contains('punjabi') && !title.contains(prefLang)) {
          continue;
        }
      }

      if (queryTokens.length >= 2) {
        final matchesPhrase = title.contains(cleanQuery) || cleanQuery.contains(title);
        final matchesAllTokensAsWords = queryTokens.every((token) =>
            RegExp(r'\b' + RegExp.escape(token) + r'\b', caseSensitive: false).hasMatch(title));
        if (!matchesPhrase && !matchesAllTokensAsWords) {
          continue;
        }
      } else if (queryTokens.isNotEmpty) {
        final token = queryTokens.first;
        if (!RegExp(r'\b' + RegExp.escape(token) + r'\b', caseSensitive: false).hasMatch(title)) {
          continue;
        }
      }

      if (p['source'] == 'youtube') {
        final count = int.tryParse(p['song_count']?.toString() ?? '0') ?? 0;
        if (count < 2) continue;
      }

      filtered.add(p);
    }
    return filtered;
  }

  /// Dynamically extracts and synthesizes clean movie and soundtrack albums from a list of songs
  static List<Map<String, dynamic>> extractAlbumsFromSongList(
    List<Song> songs, {
    String? query,
    List<Map<String, dynamic>>? existingAlbums,
    List<String>? preferredLanguages,
  }) {
    final List<Map<String, dynamic>> result = existingAlbums != null ? List.from(existingAlbums) : [];
    final Set<String> seenAlbumNames = {
      for (final a in result) (a['title'] ?? '').toString().toLowerCase().trim()
    };
    final qClean = (query ?? '').toLowerCase().trim();

    final RegExp fromMovieRegex = RegExp(
      r'[\(\[]\s*(?:from|ost|soundtrack\s+from)\s+["\x27\u201c\u201d\u2018\u2019]?([^"\x27\u201c\u201d\u2018\u2019\)\]]+)["\x27\u201c\u201d\u2018\u2019]?\s*[\)\]]',
      caseSensitive: false,
    );

    for (final s in songs) {
      String candidateAlbum = s.album.trim();

      if (candidateAlbum.isEmpty ||
          candidateAlbum.toLowerCase() == 'single' ||
          candidateAlbum.toLowerCase() == 'unknown' ||
          candidateAlbum.toLowerCase() == 'unknown album' ||
          candidateAlbum.toLowerCase() == s.title.toLowerCase().trim() ||
          candidateAlbum.toLowerCase().endsWith('- single')) {
        final match = fromMovieRegex.firstMatch(s.title) ?? fromMovieRegex.firstMatch(s.album);
        if (match != null) {
          final extracted = match.group(1)?.trim();
          if (extracted != null && extracted.isNotEmpty) {
            candidateAlbum = extracted;
          }
        }
      }

      candidateAlbum = candidateAlbum
          .replaceAll(RegExp(r'\s*-\s*Single$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*\((?:Original Motion Picture Soundtrack|OST|Original Soundtrack)\)$', caseSensitive: false), '')
          .trim();

      final albLower = candidateAlbum.toLowerCase();
      if (albLower.isEmpty ||
          albLower == 'single' ||
          albLower == 'unknown' ||
          albLower == 'unknown album' ||
          albLower == 'various artists' ||
          albLower == 'studio album') {
        continue;
      }

      if (seenAlbumNames.add(albLower)) {
        final isMovie = s.album.toLowerCase().contains('from') ||
            s.title.toLowerCase().contains('from') ||
            (qClean.isNotEmpty && QueryNormalizer.isAlbumOrMovieEntityMatch(candidateAlbum, qClean));
        result.add({
          'id': candidateAlbum.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase(),
          'title': candidateAlbum,
          'artist': s.artist,
          'image': s.coverUrl,
          'type': 'Album',
          'is_movie': isMovie,
          'source': s.source,
        });
      }
    }
    return result;
  }
}
