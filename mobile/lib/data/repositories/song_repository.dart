import 'dart:async';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/api_client.dart';
import '../../services/history_manager.dart';
import '../../services/supabase_service.dart';
import '../../services/app_logger.dart';
import '../../services/lyrics_client.dart';
import '../../domain/models/lyrics_state.dart';

/// Centralized repository for fetching, merging, and strictly deduplicating music feeds.
class SongRepository {
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Retrieves lyrics for a track directly on-device via LyricsClient with zero backend calls.
  static Future<LyricsState> getLyrics({
    required String trackId,
    required String title,
    required String artist,
    int durationSeconds = 0,
  }) {
    return LyricsClient.instance.fetchLyrics(
      trackId: trackId,
      title: title,
      artist: artist,
      durationSeconds: durationSeconds,
    );
  }

  /// Convenience method to retrieve lyrics for a [Song] model.
  static Future<LyricsState> getLyricsForSong(Song song) {
    return getLyrics(
      trackId: song.id,
      title: song.title,
      artist: song.artist,
      durationSeconds: song.duration,
    );
  }

  /// Normalizes a song title by stripping metadata tags, HTML entities, and punctuation.
  static String normalizeTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';
    var clean = _unescape.convert(Song.sanitize(rawTitle));

    // Strip leading @handle mentions (e.g. "@SaiAbhyankkar - Pavazha Malli")
    clean = clean.replaceAll(RegExp(r'^@[a-zA-Z0-9_.]+\s*[-:|~–—]?\s*'), '');

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

  /// Strict cross-language barrier check to eliminate language contamination
  /// (e.g. Hindi songs leaking into Tamil feeds, search cards, and trending carousels).
  static bool isLanguageMismatch(Song song, String targetLanguage) {
    final target = targetLanguage.toLowerCase().trim();
    if (target.isEmpty) return false;

    // 1. Explicit metadata language check from Saavn/API
    if (song.language != null && song.language!.isNotEmpty) {
      final sLang = song.language!.toLowerCase().trim();
      if (sLang != target) {
        if (target == 'english' && sLang == 'english') return false;
        // Explicitly labeled under a different language (e.g. 'hindi' when target is 'tamil')
        return true;
      }
    }

    // 2. Text and script analysis on title, artist, and album
    final combined = '${song.title} ${song.artist} ${song.album}'.toLowerCase();

    if (target == 'tamil') {
      // Must not contain foreign scripts
      if (RegExp(r'[\u0900-\u097F\u0C00-\u0C7F\u0D00-\u0D7F\u0C80-\u0CFF]').hasMatch(combined)) {
        return true;
      }
      // Must not contain explicit keywords of other major languages unless explicitly labeled as Tamil
      if (RegExp(r'\b(hindi|bollywood|bhojpuri|punjabi|telugu|malayalam|kannada)\b').hasMatch(combined)) {
        if (!combined.contains('tamil')) {
          return true;
        }
      }
    } else if (target == 'telugu') {
      if (RegExp(r'[\u0900-\u097F\u0B80-\u0BFF\u0D00-\u0D7F\u0C80-\u0CFF]').hasMatch(combined)) {
        return true;
      }
      if (RegExp(r'\b(hindi|bollywood|tamil|malayalam|kannada|punjabi)\b').hasMatch(combined) && !combined.contains('telugu')) {
        return true;
      }
    } else if (target == 'malayalam') {
      if (RegExp(r'[\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF]').hasMatch(combined)) {
        return true;
      }
      if (RegExp(r'\b(hindi|bollywood|tamil|telugu|kannada|punjabi)\b').hasMatch(combined) && !combined.contains('malayalam')) {
        return true;
      }
    } else if (target == 'hindi') {
      if (RegExp(r'[\u0B80-\u0BFF\u0C00-\u0C7F\u0D00-\u0D7F\u0C80-\u0CFF]').hasMatch(combined)) {
        return true;
      }
      if (RegExp(r'\b(tamil|telugu|malayalam|kannada)\b').hasMatch(combined) && !combined.contains('hindi')) {
        return true;
      }
    } else if (target == 'kannada') {
      if (RegExp(r'[\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0D00-\u0D7F]').hasMatch(combined)) {
        return true;
      }
      if (RegExp(r'\b(hindi|bollywood|tamil|telugu|malayalam|punjabi)\b').hasMatch(combined) && !combined.contains('kannada')) {
        return true;
      }
    }

    return false;
  }

  /// Filters an iterable of songs to strictly exclude cross-language leaks.
  static List<Song> filterByLanguage(Iterable<Song> songs, String targetLanguage) {
    return songs.where((s) => !isLanguageMismatch(s, targetLanguage)).toList();
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

    final filteredCandidates = filterByLanguage(candidates, language);
    final deduplicated = deduplicateSongs(filteredCandidates.isNotEmpty ? filteredCandidates : candidates);
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

  /// Fetches and interleaves Trending tracks across JioSaavn (320kbps) & YouTube Music
  /// while strictly enforcing regional language boundaries to prevent cross-language leaks.
  static Future<List<Song>> getTrendingMerged({required String language}) async {
    final results = await Future.wait([
      SaavnClient.getTrending(language: language),
      ApiClient.fetchYouTubeTrending(language: language),
    ]);

    final saavnSongs = filterByLanguage(results[0], language);
    final ytSongs = filterByLanguage(results[1], language);

    final List<Song> interleaved = [];
    final maxLen = saavnSongs.length > ytSongs.length ? saavnSongs.length : ytSongs.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < saavnSongs.length) interleaved.add(saavnSongs[i]);
      if (i < ytSongs.length) interleaved.add(ytSongs[i]);
    }

    return deduplicateSongs(interleaved);
  }

  /// Fetches New Releases for the selected language strictly isolated by language.
  static Future<List<Song>> getNewReleases({required String language}) async {
    final songs = await SaavnClient.search('Latest $language Releases', limit: 25, language: language);
    final filtered = filterByLanguage(songs, language);
    return deduplicateSongs(filtered.isNotEmpty ? filtered : songs);
  }

  /// High-resolution verified artist avatars for popular regional artists.
  static const Map<String, String> verifiedArtistAvatars = {
    'anirudh ravichander': 'https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg',
    'a.r. rahman': 'https://c.saavncdn.com/artists/AR_Rahman_002_20210120084455_500x500.jpg',
    'harris jayaraj': 'https://c.saavncdn.com/artists/Harris_Jayaraj_500x500.jpg',
    'yuvan shankar raja': 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg',
    'sid sriram': 'https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg',
    'ilaiyaraaja': 'https://c.saavncdn.com/artists/Ilaiyaraaja_500x500.jpg',
    'hiphop tamizha': 'https://c.saavncdn.com/artists/Hiphop_Tamizha_500x500.jpg',
    'santhosh narayanan': 'https://c.saavncdn.com/artists/Santhosh_Narayanan_500x500.jpg',
    'g.v. prakash': 'https://c.saavncdn.com/artists/G_V__Prakash_Kumar_003_20251113063655_500x500.jpg',
    'g.v. prakash kumar': 'https://c.saavncdn.com/artists/G_V__Prakash_Kumar_003_20251113063655_500x500.jpg',
    'pradeep kumar': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg',
    'd. imman': 'https://c.saavncdn.com/artists/D__Imman_500x500.jpg',
    'shreya ghoshal': 'https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg',
    'jonita gandhi': 'https://c.saavncdn.com/artists/Jonita_Gandhi_500x500.jpg',
    'dhee': 'https://c.saavncdn.com/artists/Dhee_20180510121326_500x500.jpg',
    'kaushik krish': 'https://c.saavncdn.com/artists/Kaushik_Krish_500x500.jpg',
    'karthik': 'https://c.saavncdn.com/artists/Karthik_500x500.jpg',
    'haricharan': 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg',
    'chinmayi': 'https://c.saavncdn.com/artists/Chinmayi_Sripada_500x500.jpg',
    'swetha mohan': 'https://c.saavncdn.com/artists/Shweta_Mohan_500x500.jpg',
    's.p. balasubrahmanyam': 'https://c.saavncdn.com/artists/S_P__Balasubrahmanyam_500x500.jpg',
    'k.s. chithra': 'https://c.saavncdn.com/artists/K_S__Chithra_500x500.jpg',
  };

  static const Map<String, String> _verifiedArtistAvatars = verifiedArtistAvatars;

  /// Verified core Tamil artist seeds. Guaranteed to never leak Bollywood/Hindi singers in Tamil mode.
  static const List<String> tamilArtistSeeds = [
    'Anirudh Ravichander',
    'A.R. Rahman',
    'Yuvan Shankar Raja',
    'Harris Jayaraj',
    'G.V. Prakash',
    'Sid Sriram',
    'Santhosh Narayanan',
  ];

  /// Fetches Popular Artists with high-res avatars, replacing low-res or generic placeholder icons.
  static Future<List<Map<String, dynamic>>> getPopularArtists({required String language}) async {
    final isTamil = language.toLowerCase().trim() == 'tamil';

    try {
      final rawArtists = await SaavnClient.searchArtists('Top $language Artists', limit: 16, language: language);
      final List<Map<String, dynamic>> enriched = [];

      for (final artist in rawArtists) {
        if (!SaavnClient.isGenuineMusicArtist(artist)) continue;
        final name = Song.sanitize(artist['name']?.toString() ?? 'Artist');
        final norm = normalizeArtist(name);

        // When Tamil is selected, strictly reject Bollywood / Hindi singers and non-Tamil scripts
        if (isTamil) {
          if (RegExp(r'[\u0900-\u097F]').hasMatch(name)) continue;
          const hindiSingers = {
            'arijit singh',
            'neha kakkar',
            'badshah',
            'jubin nautiyal',
            'atif aslam',
            'vishal mishra',
            'darshan raval',
            'armaan malik',
            'yo yo honey singh',
            'b praak',
            'guru randhawa',
            'tony kakkar',
            'sonu nigam',
            'kumar sanu',
            'alka yagnik',
            'udith narayan',
          };
          if (hindiSingers.contains(norm)) continue;
        }

        String img = artist['image']?.toString() ?? '';

        // Check verified high-res avatar map first
        if (_verifiedArtistAvatars.containsKey(norm)) {
          img = _verifiedArtistAvatars[norm]!;
        } else if (img.contains('50x50') || img.contains('150x150')) {
          img = img.replaceAll('50x50', '500x500').replaceAll('150x150', '500x500');
        }

        // Never use a song's cover image as an artist profile image
        final isSongCover = img.contains('/albums/') ||
            img.contains('/songs/') ||
            (img.contains('c.saavncdn.com') && !img.contains('/artists/'));
        if (isSongCover) {
          img = _verifiedArtistAvatars[norm] ?? '';
        }

        enriched.add({
          'id': artist['id']?.toString() ?? '',
          'name': name,
          'image': img,
        });
      }

      // When Tamil is selected, ensure all 7 core Tamil artist seeds are present
      if (isTamil) {
        for (final seed in tamilArtistSeeds.reversed) {
          final normSeed = normalizeArtist(seed);
          final existingIdx = enriched.indexWhere((a) => normalizeArtist(a['name']?.toString() ?? '') == normSeed);
          final seedAvatar = _verifiedArtistAvatars[normSeed] ?? '';
          if (existingIdx >= 0) {
            final existing = enriched.removeAt(existingIdx);
            enriched.insert(0, existing);
          } else {
            enriched.insert(0, {
              'id': 'seed_$normSeed',
              'name': seed,
              'image': seedAvatar,
            });
          }
        }
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
    if (isTamil) {
      return tamilArtistSeeds.map((seed) {
        final norm = normalizeArtist(seed);
        return {
          'id': 'seed_$norm',
          'name': seed,
          'image': _verifiedArtistAvatars[norm] ?? '',
        };
      }).toList();
    }

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
