import 'dart:async';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/api_client.dart';
import '../../services/history_manager.dart';
import '../../services/supabase_service.dart';
import '../../services/app_logger.dart';

/// Centralized repository for fetching, merging, and strictly deduplicating music feeds.
class SongRepository {
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Normalizes a song title by stripping metadata tags, HTML entities, and punctuation.
  static String normalizeTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';
    var clean = _unescape.convert(Song.sanitize(rawTitle));

    // Remove: (From "Movie"), [From "Movie"], (From Movie)
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][Ff]rom\s+["\u201c\u201d\u2018\u2019]?[^)\u201d\]]+["\u201c\u201d\u2018\u2019]?[\)\]]', caseSensitive: false),
      '',
    );

    // Remove: (Original Motion Picture Soundtrack), (OST), [Soundtrack Version]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:motion picture|soundtrack|ost)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // Remove: [Remastered...], (Remastered...)
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*remaster(?:ed)?[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // Remove: (Official Video), [Official Audio], (Lyric Video), [Lyrical]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][^)\u201d\]]*(?:official|audio|lyric|video|lyrical)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // Remove: (Feat. ...), [feat. ...]
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[][Ff](?:eat\.?|t\.)[^)\u201d\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // Remove pipe suffixes: | ...
    clean = clean.replaceAll(RegExp(r'\|.*$'), '');

    // Suffix " - Live" or " - Single" or " - From ..."
    clean = clean.replaceAll(RegExp(r'\s*-\s*(?:live|single|stereo|mono|edit|remaster(?:ed)?(?:\s*\d{4})?)$', caseSensitive: false), '');

    // Strip non-alphanumeric chars for strict fuzzy key comparison
    clean = clean.replaceAll(RegExp(r'[^\w\s\u0B80-\u0BFF\u0C00-\u0C7F\u0900-\u097F]'), '').toLowerCase().trim();
    clean = clean.replaceAll(RegExp(r'\s+'), ' ');
    return clean;
  }

  /// Normalizes an artist name to the primary artist, stripped of punctuation.
  static String normalizeArtist(String rawArtist) {
    if (rawArtist.isEmpty) return '';
    final clean = _unescape.convert(Song.sanitize(rawArtist));
    final first = clean.split(RegExp(r'[,&/]|(?:\s+feat\.?|\s+ft\.?)', caseSensitive: false)).first.trim();
    return first.replaceAll(RegExp(r'[^\w\s\u0B80-\u0BFF\u0C00-\u0C7F\u0900-\u097F]'), '').toLowerCase().trim();
  }

  /// Deduplicates songs by both unique ID and normalized `title + artist`.
  /// Deduplicates songs by unique ID, normalized `title + artist`, AND cross-artist composition matching (`cleanTitleKey` + duration).
  /// If [existing] is provided, prevents appending duplicates to active lists/feeds.
  static List<Song> deduplicateSongs(
    Iterable<Song> songs, {
    Iterable<Song>? existing,
  }) {
    final Set<String> seenIds = {};
    final Set<String> seenKeys = {};
    final Map<String, List<int>> seenCompositions = {};
    final List<Song> result = [];

    void recordSongKeys(Song s) {
      if (s.id.isNotEmpty) seenIds.add(s.id);
      final key = '${normalizeTitle(s.title)}__${normalizeArtist(s.artist)}';
      if (key.length > 3) seenKeys.add(key);
      final titleKey = s.cleanTitleKey;
      if (titleKey.length > 2) {
        seenCompositions.putIfAbsent(titleKey, () => []).add(s.duration);
      }
    }

    // Pre-populate with existing items to prevent duplicates across pagination or state rebuilds
    if (existing != null) {
      for (final song in existing) {
        recordSongKeys(song);
      }
    }

    for (final song in songs) {
      if (song.title.trim().isEmpty) continue;

      final id = song.id.trim();
      final key = '${normalizeTitle(song.title)}__${normalizeArtist(song.artist)}';
      final titleKey = song.cleanTitleKey;

      // 1. Direct ID match
      if (id.isNotEmpty && seenIds.contains(id)) {
        continue;
      }

      // 2. Exact normalized title + artist match
      if (key.length > 3 && seenKeys.contains(key)) {
        continue;
      }

      // 3. Cross-artist composition match (same song composition title with matching duration)
      if (titleKey.length > 2) {
        final existingDurations = seenCompositions[titleKey];
        if (existingDurations != null) {
          final isDupe = existingDurations.any((d) =>
            song.duration == 0 || d == 0 || (song.duration - d).abs() <= 12
          );
          if (isDupe) continue;
        }
      }

      recordSongKeys(song);
      result.add(song);
    }
    return result;
  }

  /// Groups multiple versions and sources into canonical songs with an attached versions list.
  /// Prefers official album art and high-fidelity source for the primary entry.
  static List<Song> groupCanonicalSongs(
    Iterable<Song> songs, {
    String? preferredLanguage,
  }) {
    if (songs.isEmpty) return [];

    final Map<String, List<Song>> groups = {};
    for (final s in songs) {
      if (s.title.trim().isEmpty) continue;
      final key = s.canonicalBaseKey;
      groups.putIfAbsent(key.isNotEmpty ? key : s.id, () => []).add(s);
    }

    final List<Song> canonicalList = [];
    final prefLangLower = preferredLanguage?.toLowerCase().trim();

    for (final group in groups.values) {
      if (group.isEmpty) continue;

      group.sort((a, b) {
        // 1. Official album art preference
        if (a.hasOfficialAlbumArt && !b.hasOfficialAlbumArt) return -1;
        if (!a.hasOfficialAlbumArt && b.hasOfficialAlbumArt) return 1;

        // 2. High fidelity source preference (Saavn 320kbps over YouTube)
        if (a.source == 'saavn' && b.source != 'saavn') return -1;
        if (a.source != 'saavn' && b.source == 'saavn') return 1;

        // 3. Preferred language matching
        if (prefLangLower != null && prefLangLower.isNotEmpty) {
          final aMatch = a.language?.toLowerCase() == prefLangLower;
          final bMatch = b.language?.toLowerCase() == prefLangLower;
          if (aMatch && !bMatch) return -1;
          if (!aMatch && bMatch) return 1;
        }

        // 4. Prefer Original track over remix/lofi for primary entry
        final aOrig = a.versionTag == 'Original';
        final bOrig = b.versionTag == 'Original';
        if (aOrig && !bOrig) return -1;
        if (!aOrig && bOrig) return 1;

        return 0;
      });

      final primary = group.first;
      final alternateVersions = group.skip(1).toList();
      canonicalList.add(primary.copyWith(versions: alternateVersions));
    }

    return canonicalList;
  }

  /// Fetches User Taste Mix ("Made For You") based on Supabase favorite artists and most frequently played artists in History.
  static Future<List<Song>> getMadeForYou({required String language}) async {
    final List<Song> candidates = [];
    final List<String> topArtists = [];

    // 1. Prioritize user-selected artists from Supabase
    try {
      final supaUser = SupabaseService.currentUser;
      if (supaUser != null) {
        final favArtists = await SupabaseService.fetchFavoriteArtists(supaUser.id);
        for (final fa in favArtists) {
          final faName = fa['artist_name']?.toString() ?? '';
          final norm = normalizeArtist(faName);
          if (norm.isNotEmpty && !topArtists.contains(norm)) {
            topArtists.add(norm);
          }
        }
      }
    } catch (e) {
      AppLogger.log('SongRepository', 'Favorite artists fetch notice: $e');
    }

    // 2. Supplement with top played artists from local History
    final history = HistoryManager.getHistory();
    if (history.isNotEmpty) {
      final Map<String, int> artistCounts = {};
      for (final s in history) {
        final norm = normalizeArtist(s.artist);
        if (norm.isNotEmpty && norm != 'various artists') {
          artistCounts[norm] = (artistCounts[norm] ?? 0) + 1;
        }
      }

      final sortedHistoryArtists = artistCounts.keys.toList()
        ..sort((a, b) => (artistCounts[b] ?? 0).compareTo(artistCounts[a] ?? 0));

      for (final ha in sortedHistoryArtists) {
        if (!topArtists.contains(ha) && topArtists.length < 5) {
          topArtists.add(ha);
        }
      }
    }

    // 3. Fetch tracks for top artists in parallel
    if (topArtists.isNotEmpty) {
      final artistFutures = topArtists.take(4).map((artistName) {
        return SaavnClient.search('$artistName $language', limit: 8, language: language);
      });

      final artistResults = await Future.wait(artistFutures);
      for (final list in artistResults) {
        candidates.addAll(list);
      }
    }

    // Also fetch recommendations from backend
    try {
      final forYou = await ApiClient.fetchForYou();
      candidates.addAll(forYou);
    } catch (e) {
      AppLogger.log('SongRepository', 'ApiClient recommendations fallback: $e');
    }

    // Fallback if candidates are scarce
    if (candidates.length < 8) {
      final fallback = await SaavnClient.search('$language Melodies Hits', limit: 15, language: language);
      candidates.addAll(fallback);
    }

    final deduplicated = deduplicateSongs(candidates);
    return ensureDistinctCovers(deduplicated);
  }

  /// Ensures all tracks have valid, authentic artwork without stripping genuine album art.
  /// If a track's artwork is completely empty, falls back to the high-res artist avatar
  /// or high-res YouTube video thumbnail.
  static List<Song> ensureDistinctCovers(List<Song> songs) {
    if (songs.isEmpty) return songs;

    final List<Song> distinct = [];

    for (final song in songs) {
      String finalCover = song.coverUrl.trim();

      // Only attempt fallback if the cover is completely missing/empty
      if (finalCover.isEmpty) {
        final normArtist = normalizeArtist(song.artist);
        String? artistAvatar = _verifiedArtistAvatars[normArtist];

        if (artistAvatar == null && song.artist.contains(',')) {
          final firstArtist = normalizeArtist(song.artist.split(',').first);
          artistAvatar = _verifiedArtistAvatars[firstArtist];
        }

        if (artistAvatar != null) {
          finalCover = artistAvatar;
        } else if (song.source == 'youtube' || song.id.length == 11) {
          finalCover = 'https://img.youtube.com/vi/${song.id}/hqdefault.jpg';
        }
      }

      // Ensure HTTPS protocol
      if (finalCover.startsWith('http://')) {
        finalCover = finalCover.replaceFirst('http://', 'https://');
      }

      distinct.add(song.copyWith(coverUrl: finalCover));
    }

    return distinct;
  }

  /// Fetches and interleaves Trending tracks across JioSaavn (320kbps) & YouTube Music.
  static Future<List<Song>> getTrendingMerged({required String language}) async {
    final results = await Future.wait([
      SaavnClient.getTrending(language: language),
      ApiClient.fetchYouTubeTrending(language: language),
    ]);

    final saavnSongs = results[0];
    final ytSongs = results[1];

    final List<Song> interleaved = [];
    final maxLen = saavnSongs.length > ytSongs.length ? saavnSongs.length : ytSongs.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < saavnSongs.length) interleaved.add(saavnSongs[i]);
      if (i < ytSongs.length) interleaved.add(ytSongs[i]);
    }

    return deduplicateSongs(interleaved);
  }

  /// Fetches New Releases for the selected language.
  static Future<List<Song>> getNewReleases({required String language}) async {
    final songs = await SaavnClient.search('Latest $language Releases', limit: 20, language: language);
    return deduplicateSongs(songs);
  }

  /// High-resolution verified artist avatars for popular regional artists.
  static const Map<String, String> _verifiedArtistAvatars = {
    'anirudh ravichander': 'https://c.saavncdn.com/artists/Anirudh_Ravichander_004_20231018104445_500x500.jpg',
    'a.r. rahman': 'https://c.saavncdn.com/artists/A_R__Rahman_002_20210219084131_500x500.jpg',
    'harris jayaraj': 'https://c.saavncdn.com/artists/Harris_Jayaraj_500x500.jpg',
    'yuvan shankar raja': 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg',
    'sid sriram': 'https://c.saavncdn.com/artists/Sid_Sriram_003_20230224102607_500x500.jpg',
    'ilaiyaraaja': 'https://c.saavncdn.com/artists/Ilaiyaraaja_004_20220602053931_500x500.jpg',
    'hiphop tamizha': 'https://c.saavncdn.com/artists/Hiphop_Tamizha_500x500.jpg',
    'santhosh narayanan': 'https://c.saavncdn.com/artists/Santhosh_Narayanan_500x500.jpg',
    'g.v. prakash kumar': 'https://c.saavncdn.com/artists/G_V__Prakash_Kumar_500x500.jpg',
    'pradeep kumar': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg',
    'd. imman': 'https://c.saavncdn.com/artists/D__Imman_500x500.jpg',
    'shreya ghoshal': 'https://c.saavncdn.com/artists/Shreya_Ghoshal_004_20221118121516_500x500.jpg',
    'jonita gandhi': 'https://c.saavncdn.com/artists/Jonita_Gandhi_500x500.jpg',
    'dhee': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg',
    'kaushik krish': 'https://c.saavncdn.com/artists/Kaushik_Krish_500x500.jpg',
    'karthik': 'https://c.saavncdn.com/artists/Karthik_500x500.jpg',
    'haricharan': 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg',
    'chinmayi': 'https://c.saavncdn.com/artists/Chinmayi_Sripada_500x500.jpg',
    'swetha mohan': 'https://c.saavncdn.com/artists/Shweta_Mohan_500x500.jpg',
    's.p. balasubrahmanyam': 'https://c.saavncdn.com/artists/S_P__Balasubrahmanyam_500x500.jpg',
    'k.s. chithra': 'https://c.saavncdn.com/artists/K_S__Chithra_500x500.jpg',
  };

  /// Fetches Popular Artists with high-res avatars, replacing low-res or generic placeholder icons.
  static Future<List<Map<String, dynamic>>> getPopularArtists({required String language}) async {
    try {
      final rawArtists = await SaavnClient.searchArtists('Top $language Artists', limit: 16);
      final List<Map<String, dynamic>> enriched = [];

      for (final artist in rawArtists) {
        if (!SaavnClient.isGenuineMusicArtist(artist)) continue;
        final name = Song.sanitize(artist['name']?.toString() ?? 'Artist');
        final norm = normalizeArtist(name);
        String img = artist['image']?.toString() ?? '';

        // Check verified high-res avatar map first
        if (_verifiedArtistAvatars.containsKey(norm)) {
          img = _verifiedArtistAvatars[norm]!;
        } else if (img.contains('50x50') || img.contains('150x150')) {
          img = img.replaceAll('50x50', '500x500').replaceAll('150x150', '500x500');
        }

        enriched.add({
          'id': artist['id']?.toString() ?? '',
          'name': name,
          'image': img,
        });
      }

      // Prioritize user's favorite artists from Supabase
      try {
        final supaUser = SupabaseService.currentUser;
        if (supaUser != null) {
          final favArtists = await SupabaseService.fetchFavoriteArtists(supaUser.id);
          for (final fa in favArtists.reversed) {
            final faName = fa['artist_name']?.toString() ?? '';
            final norm = normalizeArtist(faName);
            final customImg = fa['artist_image']?.toString();
            final avatar = (customImg != null && customImg.isNotEmpty)
                ? customImg
                : (_verifiedArtistAvatars[norm] ?? '');
            if (!enriched.any((a) => normalizeArtist(a['name']?.toString() ?? '') == norm)) {
              enriched.insert(0, {
                'id': 'fav_$norm',
                'name': faName,
                'image': avatar.isNotEmpty ? avatar : (_verifiedArtistAvatars.values.firstOrNull ?? ''),
              });
            }
          }
        }
      } catch (e) {
        AppLogger.log('SongRepository', 'Enriching favorite artists fallback: $e');
      }

      if (enriched.isNotEmpty) {
        return enriched;
      }
    } catch (e) {
      AppLogger.log('SongRepository', 'getPopularArtists fallback: $e');
    }

    // Verified fallback curated list for South Indian / Tamil music
    return _verifiedArtistAvatars.entries.map((e) {
      final titleCaseName = e.key
          .split(' ')
          .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
          .join(' ');
      return {
        'id': e.key,
        'name': titleCaseName,
        'image': e.value,
      };
    }).toList();
  }
}
