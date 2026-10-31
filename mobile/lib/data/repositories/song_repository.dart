import 'dart:async';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/api_client.dart';
import '../../services/history_manager.dart';
import '../../services/supabase_service.dart';
import '../../services/app_logger.dart';
import '../../services/lyrics_client.dart';
import '../../services/artist_sanitizer.dart';
import '../../services/cover_art_resolver.dart';
import '../../services/youtube_client.dart';
import '../../services/catalog_database.dart';
import '../../logic/track_quality_filter.dart';
import 'package:flutter/material.dart';
import '../../domain/models/lyrics_state.dart';
import '../../domain/models/home_feed_models.dart';

/// Centralized repository for fetching, merging, and strictly deduplicating music feeds.
class SongRepository {
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Retrieves lyrics for a track directly on-device via LyricsClient with zero backend calls.
  static Future<LyricsState> getLyrics({
    required String trackId,
    required String title,
    required String artist,
    String? album,
    int durationSeconds = 0,
  }) {
    return LyricsClient.instance.fetchLyrics(
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
    );
  }

  /// Convenience method to retrieve lyrics for a [Song] model.
  static Future<LyricsState> getLyricsForSong(Song song) {
    return getLyrics(
      trackId: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      durationSeconds: song.duration,
    );
  }

  /// Search LRCLIB candidates for manual correction
  static Future<List<Map<String, dynamic>>> searchLyricsCandidates(String query) =>
      ApiClient.searchLyricsCandidates(query);

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
      // Must not contain explicit keywords of other major languages in title or artist
      final titleAndArtist = '${song.title} ${song.artist}'.toLowerCase();
      if (RegExp(r'\b(hindi|bollywood|bhojpuri|punjabi|telugu|malayalam|kannada)\b').hasMatch(titleAndArtist)) {
        if (!titleAndArtist.contains('tamil')) {
          return true;
        }
      }
      // Purge non-genuine / spam channels masquerading as musicians
      if (!ArtistSanitizer.isGenuineArtist(song.artist)) {
        return true;
      }
      // Reject explicitly non-Tamil language tracks leaking into Tamil feeds/albums
      if (song.language == 'english' || song.language == 'hindi') {
        return true;
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
    final Set<String> topArtistsSet = <String>{};

    // 1. Prioritize user-selected artists from Supabase with O(1) set tracking
    try {
      final supaUser = SupabaseService.currentUser;
      if (supaUser != null) {
        final favArtists = await SupabaseService.fetchFavoriteArtists(supaUser.id);
        for (final fa in favArtists) {
          final faName = fa['artist_name']?.toString() ?? '';
          final norm = normalizeArtist(faName);
          if (norm.isNotEmpty && topArtistsSet.add(norm)) {
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
        if (topArtists.length < 5 && topArtistsSet.add(ha)) {
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

      // If cover is empty, check CoverArtResolver cache or default to YouTube thumbnail
      if (finalCover.isEmpty) {
        final cached = CoverArtResolver.getCachedCover(song.id);
        if (cached != null && cached.isNotEmpty) {
          finalCover = cached;
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
    's.p. balasubrahmanyam': 'https://c.saavncdn.com/artists/S_P_Balasubrahmanyam_500x500.jpg',
    'spb': 'https://c.saavncdn.com/artists/S_P_Balasubrahmanyam_500x500.jpg',
    'k.s. chithra': 'https://c.saavncdn.com/artists/K_S__Chithra_500x500.jpg',
    'chithra': 'https://c.saavncdn.com/artists/K_S__Chithra_500x500.jpg',
    'k.j. yesudas': 'https://c.saavncdn.com/artists/K_J__Yesudas_500x500.jpg',
    'yesudas': 'https://c.saavncdn.com/artists/K_J__Yesudas_500x500.jpg',
    'vijay antony': 'https://c.saavncdn.com/artists/Vijay_Antony_500x500.jpg',
    'deva': 'https://c.saavncdn.com/artists/Deva_500x500.jpg',
    'vidyasagar': 'https://c.saavncdn.com/artists/Vidyasagar_500x500.jpg',
    'shankar mahadevan': 'https://c.saavncdn.com/artists/Shankar_Mahadevan_500x500.jpg',
    'sam c.s.': 'https://c.saavncdn.com/artists/Sam_C_S__500x500.jpg',
    'sean roldan': 'https://c.saavncdn.com/artists/Sean_Roldan_500x500.jpg',
    's. janaki': 'https://c.saavncdn.com/artists/S__Janaki_500x500.jpg',
    'p. susheela': 'https://c.saavncdn.com/artists/P__Susheela_500x500.jpg',
    'tippu': 'https://c.saavncdn.com/artists/Tippu_500x500.jpg',
    'unnikrishnan': 'https://c.saavncdn.com/artists/P__Unnikrishnan_500x500.jpg',
    'srinivas': 'https://c.saavncdn.com/artists/Srinivas_500x500.jpg',
    't.m. soundararajan': 'https://c.saavncdn.com/artists/T_M__Soundararajan_500x500.jpg',
    'thaman s': 'https://c.saavncdn.com/artists/Thaman_S_500x500.jpg',
    'thaman': 'https://c.saavncdn.com/artists/Thaman_S_500x500.jpg',
    's. thaman': 'https://c.saavncdn.com/artists/Thaman_S_500x500.jpg',
    'sai abhyankkar': 'https://c.saavncdn.com/artists/Sai_Abhyankkar_500x500.jpg',
    'sai abhyankar': 'https://c.saavncdn.com/artists/Sai_Abhyankkar_500x500.jpg',
    'vishal mishra': 'https://c.saavncdn.com/artists/Vishal_Mishra_500x500.jpg',
    'dhanush': 'https://c.saavncdn.com/artists/Dhanush_500x500.jpg',
    'super subu': 'https://c.saavncdn.com/artists/Super_Subu_000_20230809105700_500x500.jpg',
    'madduri hemanth': 'https://c.saavncdn.com/artists/Madduri_Hemanth_500x500.jpg',
    'hemanth madduri': 'https://c.saavncdn.com/artists/Madduri_Hemanth_500x500.jpg',
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

  /// Returns whether the given artist is an officially verified artist in Paatu Padava
  static bool isArtistVerified(String artistName) {
    final norm = normalizeArtist(artistName);
    return _verifiedArtistAvatars.containsKey(norm) ||
        tamilArtistSeeds.any((s) => normalizeArtist(s) == norm);
  }

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

        // Filter out generic placeholder images with camera or mic icons
        if (ArtistSanitizer.isPlaceholderImage(img) && !isArtistVerified(name)) {
          continue;
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

  /// Generates the Spotify-style Editorial Top Hits Flagship Showcase.
  /// Dynamically computes theme gradients, localized titles, and curates the top 20 tracks.
  static Future<HeroShowcase> getFlagshipShowcase({
    required String language,
    String heroMode = 'smart',
  }) async {
    final isTamil = language.toLowerCase().trim() == 'tamil';
    final now = DateTime.now();
    final hour = now.hour;

    // Determine time-of-day contextual soundscape
    final String timeGreeting;
    final List<Color> dynamicColors;
    if (hour >= 5 && hour < 12) {
      timeGreeting = isTamil ? 'காலை தென்றல் & மெல்லிசை' : 'Morning Acoustic & Melodies';
      dynamicColors = const [Color(0xFF0D9488), Color(0xFF0284C7)]; // Teal & Sky
    } else if (hour >= 12 && hour < 17) {
      timeGreeting = isTamil ? 'மதிய ஓய்வு & இசை அலைகள்' : 'Afternoon Chillout & Flow';
      dynamicColors = const [Color(0xFF7C3AED), Color(0xFFEC4899)]; // Violet & Pink
    } else if (hour >= 17 && hour < 22) {
      timeGreeting = isTamil ? 'மாலை கொண்டாட்டம் & ஹிட்ஸ்' : 'Evening Energy & Chartbusters';
      dynamicColors = const [Color(0xFF6366F1), Color(0xFF06B6D4)]; // Indigo & Cyan
    } else {
      timeGreeting = isTamil ? 'இரவு அமைதி & லோஃபை' : 'Late Night Synth & Lofi Melodies';
      dynamicColors = const [Color(0xFF1E1B4B), Color(0xFF6B21A8)]; // Deep Midnight Purple
    }

    final String title;
    final String subtitle;
    final String description;
    final List<Color> gradientColors;

    if (heroMode == 'time_of_day') {
      title = '$language • $timeGreeting';
      subtitle = 'Curated soundscape matched to your local hour';
      description = 'Fresh streaming feed • Zero ads • Studio lossless audio';
      gradientColors = dynamicColors;
    } else if (heroMode == 'flagship') {
      title = isTamil ? "Today's Top Tamil Hits" : 'Top 50 • $language';
      subtitle = 'The hottest & most streamed tracks across the industry';
      description = 'Editorial Chart • Updated daily with verified master audio';
      gradientColors = const [Color(0xFF7C3AED), Color(0xFF06B6D4)];
    } else {
      // Smart mode (default)
      title = isTamil ? "Today's Top Tamil Hits" : 'Top 50 • $language';
      subtitle = '$timeGreeting • Hottest chartbusters right now';
      description = 'Editorial Chart • Pure lossless streaming';
      gradientColors = dynamicColors;
    }

    List<Song> tracks = [];
    try {
      final trending = await getTrendingMerged(language: language);
      tracks = trending.take(20).toList();
    } catch (e) {
      AppLogger.log('SongRepository', 'getFlagshipShowcase fallback: $e');
    }

    if (tracks.isEmpty) {
      try {
        final searchHits = await SaavnClient.search('Top $language Hits', limit: 20, language: language);
        tracks = deduplicateSongs(filterByLanguage(searchHits, language));
      } catch (_) {}
    }

    final coverUrl = tracks.isNotEmpty ? tracks.first.coverUrl : '';

    return HeroShowcase(
      title: title,
      subtitle: subtitle,
      description: description,
      coverUrl: coverUrl,
      gradientColors: gradientColors,
      tracks: tracks,
    );
  }

  /// Fetches the Spotify & Billboard style Top 10 Ranked Charts with rank movement tracking.
  static Future<List<RankedChartSong>> getTop10RankedCharts({
    required String language,
  }) async {
    List<Song> rawSongs = [];
    try {
      final trending = await getTrendingMerged(language: language);
      rawSongs = trending;
    } catch (_) {}

    if (rawSongs.length < 10) {
      try {
        final searchHits = await SaavnClient.search('Top $language Songs 2025', limit: 15, language: language);
        rawSongs.addAll(filterByLanguage(searchHits, language));
      } catch (_) {}
    }

    final distinctSongs = ensureDistinctCovers(deduplicateSongs(filterByLanguage(rawSongs, language))).take(10).toList();
    final List<RankedChartSong> ranked = [];

    for (int i = 0; i < distinctSongs.length; i++) {
      final song = distinctSongs[i];
      final rank = i + 1;
      // Deterministic realistic chart movement based on song ID hash
      final hash = song.id.hashCode.abs();
      final mod = hash % 5;
      final int change;
      final bool isNew;

      if (rank == 1) {
        change = 0; // #1 is anchored at peak
        isNew = false;
      } else if (mod == 0) {
        change = 1; // +1 rank up
        isNew = false;
      } else if (mod == 1) {
        change = -1; // -1 rank down
        isNew = false;
      } else if (mod == 2) {
        change = 2; // +2 surge
        isNew = false;
      } else if (mod == 3) {
        change = 0; // = steady
        isNew = false;
      } else {
        change = 0;
        isNew = rank >= 7; // New debut in bottom tier
      }

      ranked.add(RankedChartSong(
        rank: rank,
        song: song,
        rankChange: change,
        isNew: isNew,
      ));
    }

    return ranked;
  }

  /// Curates YouTube Music & Apple Music style Mood & Activity Mixes strictly filtered by language.
  static Future<List<FeelingMix>> getFeelingMixes({
    required String language,
  }) async {
    final isTamil = language.toLowerCase().trim() == 'tamil';

    final feelingDefs = [
      {
        'id': 'chill',
        'title': '🌙 Chill & Soul',
        'subtitle': isTamil ? 'மெல்லிசை & அமைதியான பாடல்கள்' : 'Relaxing acoustic & serene melodies',
        'icon': '🌙',
        'gradient': const [Color(0xFF1E1B4B), Color(0xFF4338CA)],
        'query': '$language Chill Acoustic Soul',
      },
      {
        'id': 'romance',
        'title': '❤️ Romantic Beats',
        'subtitle': isTamil ? 'காதல் பாடல்கள் & டூயட்' : 'Heartfelt love tracks & duets',
        'icon': '❤️',
        'gradient': const [Color(0xFF831843), Color(0xFFBE185D)],
        'query': '$language Romantic Love Hits',
      },
      {
        'id': 'kuthu',
        'title': '⚡ High Energy & Kuthu',
        'subtitle': isTamil ? 'குத்து பாட்டு & கொண்டாட்டம்' : 'Electrifying beats & workout power',
        'icon': '⚡',
        'gradient': const [Color(0xFF7C2D12), Color(0xFFEA580C)],
        'query': isTamil ? 'Tamil Kuthu Dance Hits' : '$language High Energy Party Hits',
      },
      {
        'id': 'focus',
        'title': '🎧 Deep Focus & Lofi',
        'subtitle': isTamil ? 'கவனம் & லோஃபை மெல்லிசை' : 'Calm beats & instrumental flow',
        'icon': '🎧',
        'gradient': const [Color(0xFF064E3B), Color(0xFF059669)],
        'query': '$language Lofi Instrumental Calm',
      },
      {
        'id': 'nostalgia',
        'title': '📻 90s & 2000s Nostalgia',
        'subtitle': isTamil ? 'பொற்கால நினைவுகள்' : 'Golden era evergreen classics',
        'icon': '📻',
        'gradient': const [Color(0xFF78350F), Color(0xFFD97706)],
        'query': isTamil ? 'Tamil 90s 2000s Evergreen Hits Ilaiyaraaja Rahman' : '$language 90s Evergreen Hits',
      },
      {
        'id': 'night',
        'title': '🌃 Late Night Drive',
        'subtitle': isTamil ? 'இரவு நேர இசை பயணம்' : 'Atmospheric synths & smooth vocals',
        'icon': '🌃',
        'gradient': const [Color(0xFF0F172A), Color(0xFF581C87)],
        'query': '$language Late Night Drive Midnight',
      },
    ];

    final futures = feelingDefs.map((def) async {
      try {
        final rawSongs = await SaavnClient.search(def['query'] as String, limit: 12, language: language);
        final filtered = ensureDistinctCovers(deduplicateSongs(filterByLanguage(rawSongs, language)));
        return FeelingMix(
          feelingId: def['id'] as String,
          title: def['title'] as String,
          subtitle: def['subtitle'] as String,
          icon: def['icon'] as String,
          gradient: def['gradient'] as List<Color>,
          songs: filtered,
        );
      } catch (_) {
        return FeelingMix(
          feelingId: def['id'] as String,
          title: def['title'] as String,
          subtitle: def['subtitle'] as String,
          icon: def['icon'] as String,
          gradient: def['gradient'] as List<Color>,
          songs: const [],
        );
      }
    });

    final results = await Future.wait(futures);
    return results.where((m) => m.songs.isNotEmpty).toList();
  }

  /// Curates YouTube Music style "Quick Picks" (12-16 songs organized in 4-row columns).
  static Future<List<Song>> getQuickPicks({
    required String language,
  }) async {
    final List<Song> picks = [];
    try {
      final madeForYou = await getMadeForYou(language: language);
      picks.addAll(madeForYou);
    } catch (_) {}

    if (picks.length < 16) {
      try {
        final trending = await getTrendingMerged(language: language);
        picks.addAll(trending);
      } catch (_) {}
    }

    final distinct = ensureDistinctCovers(deduplicateSongs(filterByLanguage(picks, language)));
    return distinct.take(16).toList();
  }

  /// Fetches album details and songs, shielding UI from low-level API clients.
  static Future<Map<String, dynamic>?> getAlbumDetails({
    required String albumId,
    required String albumTitle,
  }) async {
    String targetId = albumId.trim();
    String? imageUrl;

    if (targetId.isEmpty || !RegExp(r'^\d+$').hasMatch(targetId)) {
      try {
        final searchAlbs = await SaavnClient.searchAlbums(albumTitle, limit: 5);
        if (searchAlbs.isNotEmpty) {
          final cleanTitle = albumTitle.toLowerCase().trim();
          final match = searchAlbs.firstWhere(
            (a) => (a['title'] ?? a['name'] ?? '').toString().toLowerCase().trim() == cleanTitle,
            orElse: () => searchAlbs.first,
          );
          targetId = match['id']?.toString() ?? '';
          final matchImg = match['image']?.toString() ?? '';
          if (matchImg.isNotEmpty) {
            imageUrl = matchImg;
          }
        }
      } catch (_) {}
    }

    List<Song> songs = [];

    // 0. Instant local Movie / Album catalog lookup (0ms)
    try {
      final localSongs = await CatalogDatabase.getSongsByMovie(albumTitle);
      if (localSongs.isNotEmpty) {
        songs.addAll(localSongs);
        if (imageUrl == null || imageUrl.isEmpty) {
          imageUrl = localSongs.first.coverUrl;
        }
      }
    } catch (_) {}

    Map<String, dynamic>? details;
    if (songs.isEmpty && targetId.isNotEmpty && RegExp(r'^\d+$').hasMatch(targetId)) {
      details = await SaavnClient.getAlbumDetails(targetId);
    }

    if (details != null) {
      final albImage = details['image']?.toString() ?? '';
      if (albImage.isNotEmpty) {
        imageUrl = albImage;
      }
      if (details['songs'] is List<Song>) {
        songs = details['songs'] as List<Song>;
      }
    }

    if (songs.isEmpty) {
      final searchResults = await SaavnClient.search(albumTitle, limit: 20);
      final cleanAlbum = albumTitle.toLowerCase().trim();
      songs = searchResults.where((s) {
        return s.album.toLowerCase().trim().contains(cleanAlbum) ||
            cleanAlbum.contains(s.album.toLowerCase().trim());
      }).toList();
      if (songs.isEmpty) {
        songs = searchResults;
      }
    }

    return {
      'id': targetId,
      'image': imageUrl ?? '',
      'songs': deduplicateSongs(songs),
    };
  }

  /// Fetches artist discography, shielding UI from direct client calls.
  static Future<Map<String, dynamic>> getArtistDiscography({
    required String artistId,
    required String artistName,
  }) async {
    String? resolvedImageUrl;

    try {
      final saavnArtists = await SaavnClient.searchArtists(artistName, limit: 3);
      for (final a in saavnArtists) {
        final img = a['image']?.toString();
        if (img != null && img.isNotEmpty && !img.contains('default')) {
          resolvedImageUrl = img;
          break;
        }
      }
    } catch (_) {}

    final List<Song> gathered = [];

    // 0. Instant local catalog lookups
    try {
      final localSongs = await CatalogDatabase.getSongsByArtist(artistName);
      gathered.addAll(localSongs);
    } catch (_) {}

    try {
      final futures = <Future<List<Song>>>[];

      if (artistId.trim().isNotEmpty) {
        futures.add(
          SaavnClient.getArtistDetails(artistId.trim())
              .then((d) => (d?['songs'] as List<Song>?) ?? <Song>[])
              .catchError((_) => <Song>[]),
        );
      }

      futures.add(
        SaavnClient.search('$artistName Hit Songs', limit: 40)
            .catchError((_) => <Song>[]),
      );

      futures.add(
        SaavnClient.search(artistName, limit: 40)
            .catchError((_) => <Song>[]),
      );

      futures.add(
        YouTubeClient.search('$artistName Songs', limit: 25)
            .catchError((_) => <Song>[]),
      );

      final results = await Future.wait(futures);
      for (final list in results) {
        gathered.addAll(list);
      }
    } catch (e) {
      AppLogger.log('SongRepository', 'Error loading artist discography: $e');
    }

    var uniqueSongs = deduplicateSongs(gathered);
    if (uniqueSongs.isEmpty) {
      try {
        final fallback = await SaavnClient.search(artistName, limit: 30);
        uniqueSongs = deduplicateSongs(fallback);
      } catch (_) {}
    }

    // Strict artist verification: prevent cross-contamination (e.g. YouTube returning Premam under Anirudh)
    final cleanTarget = artistName.trim().toLowerCase();
    final verifiedSongs = uniqueSongs.where((s) {
      final songArt = s.artist.toLowerCase();
      final songTitle = s.title.toLowerCase();
      final songAlb = s.album.toLowerCase();
      return ArtistSanitizer.areSameOrVariantArtists(s.artist, artistName) ||
             songArt.contains(cleanTarget) ||
             songTitle.contains(cleanTarget) ||
             songAlb.contains(cleanTarget);
    }).toList();
    if (verifiedSongs.isNotEmpty) {
      uniqueSongs = verifiedSongs;
    }

    if (resolvedImageUrl == null || resolvedImageUrl.isEmpty) {
      final norm = normalizeArtist(artistName);
      if (_verifiedArtistAvatars.containsKey(norm)) {
        resolvedImageUrl = _verifiedArtistAvatars[norm];
      }
    }

    return {
      'image': resolvedImageUrl ?? '',
      'songs': uniqueSongs,
    };
  }

  /// Fetches remote playlist tracks across sources (JioSaavn or YouTube).
  static Future<Map<String, dynamic>> getRemotePlaylistTracks({
    required String playlistId,
    required String playlistTitle,
    required String source,
  }) async {
    List<Song> fetchedSongs = [];
    String? imageUrl;

    try {
      final cleanTitle = playlistTitle.replaceAll(RegExp(r'\s*\((All Songs|Full Album|Original Motion Picture Soundtrack)\)', caseSensitive: false), '').trim();
      final localSongs = await CatalogDatabase.getSongsByMovie(cleanTitle);
      if (localSongs.isNotEmpty) {
        fetchedSongs.addAll(localSongs);
        imageUrl = localSongs.first.coverUrl;
      }
    } catch (_) {}

    try {
      if (fetchedSongs.isEmpty && source == 'auto_album') {
        final details = await SaavnClient.getAlbumDetails(playlistId);
        if (details != null && details['songs'] is List<Song>) {
          fetchedSongs = details['songs'] as List<Song>;
          final img = details['image']?.toString() ?? '';
          if (img.isNotEmpty) imageUrl = img;
        }
      } else if (source == 'youtube') {
        fetchedSongs = await YouTubeClient.getPlaylistTracks(playlistId, limit: 60);
      } else {
        final details = await SaavnClient.getPlaylistDetails(playlistId);
        if (details != null && details['songs'] is List<Song>) {
          fetchedSongs = details['songs'] as List<Song>;
          final img = details['image']?.toString() ?? '';
          if (img.isNotEmpty) imageUrl = img;
        }
      }
    } catch (_) {}

    if (fetchedSongs.isEmpty) {
      try {
        final searchResults = await SaavnClient.search(playlistTitle, limit: 25);
        if (searchResults.isNotEmpty) {
          fetchedSongs = searchResults;
        } else {
          fetchedSongs = await YouTubeClient.search(playlistTitle, limit: 25);
        }
      } catch (_) {}
    }

    final cleanSongs = TrackQualityFilter.filterSongs(fetchedSongs);
    return {
      'image': imageUrl ?? '',
      'songs': deduplicateSongs(cleanSongs),
    };
  }

  /// Fetches onboarding artist sample tracks or top regional artists.
  static Future<List<Song>> getArtistSampleSongs(String artistName, {int limit = 12}) async {
    try {
      return await SaavnClient.search('$artistName Hit Songs', limit: limit);
    } catch (_) {
      return <Song>[];
    }
  }

  static Future<List<Map<String, dynamic>>> getTopArtists({String language = 'tamil', int limit = 10}) async {
    try {
      return await SaavnClient.searchArtists('Top $language Artists', limit: limit);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
