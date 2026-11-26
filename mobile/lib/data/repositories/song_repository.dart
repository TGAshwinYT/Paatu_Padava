import 'dart:async';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/settings_manager.dart';
import '../../services/api_client.dart';
import '../../services/history_manager.dart';
import '../../services/supabase_service.dart';
import '../../services/app_logger.dart';
import '../../services/lyrics_client.dart';
import '../../services/player_handler.dart';
import '../../services/artist_sanitizer.dart';
import '../../services/cover_art_resolver.dart';
import '../../services/youtube_client.dart';
import '../../services/catalog_database.dart';
import '../catalog_artists_seed.dart';
import '../../logic/search_query_planner.dart';
import 'package:flutter/material.dart';
import '../../domain/models/lyrics_state.dart';
import '../../domain/models/home_feed_models.dart';
import '../../core/dsa/minhash.dart';

part 'song_repo_details_ext.dart';
part 'song_repo_charts_ext.dart';
part 'song_repo_feeds_ext.dart';
part 'song_repo_avatars.dart';
part 'song_repo_artists_ext.dart';
part 'song_repo_lyrics_ext.dart';

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
  }) =>
      _getLyricsImpl(
        trackId: trackId,
        title: title,
        artist: artist,
        album: album,
        durationSeconds: durationSeconds,
      );

  /// Convenience method to retrieve lyrics for a [Song] model.
  static Future<LyricsState> getLyricsForSong(Song song) => _getLyricsForSongImpl(song);

  /// Search LRCLIB candidates for manual correction
  static Future<List<Map<String, dynamic>>> searchLyricsCandidates(String query) =>
      _searchLyricsCandidatesImpl(query);

  // Pre-compiled regular expressions to eliminate hot-loop recompilation on UI thread
  static final RegExp _handleRegex = RegExp(r'^@[a-zA-Z0-9_.]+\s*[-:|~–—]?\s*');
  static final RegExp _fromMovieRegex = RegExp(
    r'\s*[\(\[][Ff]rom\s+["\u201c\u201d\u2018\u2019]?[^)\u201d\]]+["\u201c\u201d\u2018\u2019]?[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _soundtrackRegex = RegExp(
    r'\s*[\(\[][^)\u201d\]]*(?:motion picture|soundtrack|ost)[^)\u201d\]]*[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _remasterRegex = RegExp(
    r'\s*[\(\[][^)\u201d\]]*remaster(?:ed)?[^)\u201d\]]*[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _officialMediaRegex = RegExp(
    r'\s*[\(\[][^)\u201d\]]*(?:official|audio|lyric|video|lyrical)[^)\u201d\]]*[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _featRegex = RegExp(
    r'\s*[\(\[][Ff](?:eat\.?|t\.)[^)\u201d\]]*[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _pipeSuffixRegex = RegExp(r'\|.*$');
  static final RegExp _liveSuffixRegex = RegExp(
    r'\s*-\s*(?:live|single|stereo|mono|edit|remaster(?:ed)?(?:\s*\d{4})?)$',
    caseSensitive: false,
  );
  static final RegExp _stripPunctuationRegex = RegExp(r'[^\w\s\u0B80-\u0BFF\u0C00-\u0C7F\u0900-\u097F]');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _artistSplitRegex = RegExp(r'[,&/]|(?:\s+feat\.?|\s+ft\.?)', caseSensitive: false);

  /// Normalizes a song title by stripping metadata tags, HTML entities, and punctuation.
  static String normalizeTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';
    var clean = _unescape.convert(Song.sanitize(rawTitle));

    // Strip leading @handle mentions (e.g. "@SaiAbhyankkar - Pavazha Malli")
    clean = clean.replaceAll(_handleRegex, '');

    // Remove: (From "Movie"), [From "Movie"], (From Movie)
    clean = clean.replaceAll(_fromMovieRegex, '');

    // Remove: (Original Motion Picture Soundtrack), (OST), [Soundtrack Version]
    clean = clean.replaceAll(_soundtrackRegex, '');

    // Remove: [Remastered...], (Remastered...)
    clean = clean.replaceAll(_remasterRegex, '');

    // Remove: (Official Video), [Official Audio], (Lyric Video), [Lyrical]
    clean = clean.replaceAll(_officialMediaRegex, '');

    // Remove: (Feat. ...), [feat. ...]
    clean = clean.replaceAll(_featRegex, '');

    // Remove pipe suffixes: | ...
    clean = clean.replaceAll(_pipeSuffixRegex, '');

    // Suffix " - Live" or " - Single" or " - From ..."
    clean = clean.replaceAll(_liveSuffixRegex, '');

    // Strip non-alphanumeric chars for strict fuzzy key comparison
    clean = clean.replaceAll(_stripPunctuationRegex, '').toLowerCase().trim();
    clean = clean.replaceAll(_whitespaceRegex, ' ');
    return clean;
  }

  /// Normalizes an artist name to the primary artist, stripped of punctuation.
  static String normalizeArtist(String rawArtist) {
    if (rawArtist.isEmpty) return '';
    final clean = _unescape.convert(Song.sanitize(rawArtist));
    final first = clean.split(_artistSplitRegex).first.trim();
    return first.replaceAll(_stripPunctuationRegex, '').toLowerCase().trim();
  }

  static const Set<String> _devanagariLanguages = {
    'hindi',
    'marathi',
    'bhojpuri',
    'sanskrit',
    'rajasthani',
    'maithili',
    'konkani',
    'nepali',
  };

  /// Strict cross-language barrier check to eliminate language contamination
  /// (e.g. Hindi songs leaking into Tamil feeds, search cards, and trending carousels).
  static bool isLanguageMismatch(Song song, String targetLanguage) =>
      _isLanguageMismatchImpl(song, targetLanguage);

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

  /// Deduplicates songs using 64-permutation MinHash sketch signatures for O(1) cross-source fingerprinting.
  static List<Song> deduplicateByMinHash(Iterable<Song> songs, {double threshold = 0.85}) {
    final List<Song> result = [];
    final List<MinHashSignature> signatures = [];

    for (final song in songs) {
      final sig = MinHash.instance.computeTrackSignature(
        title: song.title,
        artist: song.artist,
        album: song.album,
      );

      bool isDupe = false;
      for (final existing in signatures) {
        if (sig.isDuplicate(existing, threshold: threshold)) {
          isDupe = true;
          break;
        }
      }

      if (!isDupe) {
        signatures.add(sig);
        result.add(song);
      }
    }
    return result;
  }

  /// Groups multiple versions and sources into canonical songs with an attached versions list.
  /// Prefers official album art and high-fidelity source for the primary entry.
  static List<Song> groupCanonicalSongs(
    Iterable<Song> songs, {
    String? preferredLanguage,
    List<String>? preferredLanguages,
  }) {
    if (songs.isEmpty) return [];

    final List<List<Song>> groups = [];
    for (final s in songs) {
      if (s.title.trim().isEmpty) continue;
      bool matched = false;
      for (final group in groups) {
        final rep = group.first;
        if (rep.id == s.id ||
            (rep.canonicalBaseKey.isNotEmpty && rep.canonicalBaseKey == s.canonicalBaseKey) ||
            SearchQueryPlanner.isSameSong(
              titleA: rep.title,
              artistsA: rep.artist,
              titleB: s.title,
              artistsB: s.artist,
            ) ||
            (rep.cleanTitleKey.isNotEmpty &&
                rep.cleanTitleKey == s.cleanTitleKey &&
                (s.duration == 0 || rep.duration == 0 || (rep.duration - s.duration).abs() <= 12))) {
          group.add(s);
          matched = true;
          break;
        }
      }
      if (!matched) {
        groups.add([s]);
      }
    }

    final List<Song> canonicalList = [];
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

    for (final group in groups) {
      if (group.isEmpty) continue;

      group.sort((a, b) {
        // 1. Preferred language matching (multi-language parity: promote user's preferred language as primary)
        if (targetLangs.isNotEmpty) {
          final aLang = a.language?.toLowerCase().trim() ?? '';
          final bLang = b.language?.toLowerCase().trim() ?? '';
          final aMatch = targetLangs.contains(aLang) || targetLangs.any((l) => a.title.toLowerCase().contains(l));
          final bMatch = targetLangs.contains(bLang) || targetLangs.any((l) => b.title.toLowerCase().contains(l));
          if (aMatch && !bMatch) return -1;
          if (!aMatch && bMatch) return 1;
        }

        // 2. Official album art preference
        if (a.hasOfficialAlbumArt && !b.hasOfficialAlbumArt) return -1;
        if (!a.hasOfficialAlbumArt && b.hasOfficialAlbumArt) return 1;

        // 3. High fidelity source preference (Saavn 320kbps over YouTube)
        if (a.source == 'saavn' && b.source != 'saavn') return -1;
        if (a.source != 'saavn' && b.source == 'saavn') return 1;

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
  static Future<List<Song>> getMadeForYou({required String language}) =>
      _getMadeForYouImpl(language: language);

  static List<Song> ensureDistinctCovers(List<Song> songs) =>
      _ensureDistinctCoversImpl(songs);

  static Future<List<Song>> getTrendingMerged({required String language}) =>
      _getTrendingMergedImpl(language: language);

  static Future<List<Song>> getNewReleases({required String language}) =>
      _getNewReleasesImpl(language: language);

  static const Map<String, String> verifiedArtistAvatars = _verifiedArtistAvatarsMap;
  static const Map<String, String> _verifiedArtistAvatars = _verifiedArtistAvatarsMap;
  static final Map<String, String> _dynamicArtistAvatarCache = {};

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

  /// Safely resolves a verified high-resolution avatar for any artist,
  /// matching across punctuation variants, casing, and canonical alias mappings.
  static String getVerifiedAvatar(String artistName) {
    if (artistName.isEmpty) return '';
    final clean = _unescape.convert(Song.sanitize(artistName)).trim();
    final lower = clean.toLowerCase();
    if (_dynamicArtistAvatarCache.containsKey(lower)) {
      return _dynamicArtistAvatarCache[lower]!;
    }
    if (_verifiedArtistAvatars.containsKey(lower)) {
      return _verifiedArtistAvatars[lower]!;
    }
    final norm = normalizeArtist(clean);
    if (_dynamicArtistAvatarCache.containsKey(norm)) {
      return _dynamicArtistAvatarCache[norm]!;
    }
    if (_verifiedArtistAvatars.containsKey(norm)) {
      return _verifiedArtistAvatars[norm]!;
    }
    final canon = ArtistSanitizer.canonicalArtistName(clean).toLowerCase();
    if (_dynamicArtistAvatarCache.containsKey(canon)) {
      return _dynamicArtistAvatarCache[canon]!;
    }
    if (_verifiedArtistAvatars.containsKey(canon)) {
      return _verifiedArtistAvatars[canon]!;
    }
    final alpha = clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final entry in _dynamicArtistAvatarCache.entries) {
      final entryAlpha = entry.key.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (entryAlpha.isNotEmpty && entryAlpha == alpha) {
        return entry.value;
      }
    }
    for (final entry in _verifiedArtistAvatars.entries) {
      final entryAlpha = entry.key.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (entryAlpha.isNotEmpty && entryAlpha == alpha) {
        return entry.value;
      }
    }
    for (final entry in _dynamicArtistAvatarCache.entries) {
      if (ArtistSanitizer.areSameOrVariantArtists(entry.key, clean)) {
        return entry.value;
      }
    }
    for (final entry in _verifiedArtistAvatars.entries) {
      if (ArtistSanitizer.areSameOrVariantArtists(entry.key, clean)) {
        return entry.value;
      }
    }
    return '';
  }

  /// Returns whether the given artist is an officially verified artist in Paatu Padava
  static bool isArtistVerified(String artistName) {
    return getVerifiedAvatar(artistName).isNotEmpty ||
        tamilArtistSeeds.any((s) => ArtistSanitizer.areSameOrVariantArtists(s, artistName));
  }

  /// Fetches Popular Artists with high-res avatars, replacing low-res or generic placeholder icons.
  static Future<List<Map<String, dynamic>>> getPopularArtists({required String language}) =>
      _getPopularArtistsImpl(language: language);

  /// Generates the Spotify-style Editorial Top Hits Flagship Showcase.
  /// Dynamically computes theme gradients, localized titles, and curates the top 20 tracks.
  static Future<HeroShowcase> getFlagshipShowcase({
    required String language,
    String heroMode = 'smart',
  }) =>
      _getFlagshipShowcaseImpl(language: language, heroMode: heroMode);

  static Future<List<RankedChartSong>> getTop10RankedCharts({required String language}) =>
      _getTop10RankedChartsImpl(language: language);

  static Future<List<FeelingMix>> getFeelingMixes({required String language}) =>
      _getFeelingMixesImpl(language: language);

  static Future<List<Song>> getQuickPicks({required String language}) =>
      _getQuickPicksImpl(language: language);

  /// Fetches album details and songs, shielding UI from low-level API clients.
  static Future<Map<String, dynamic>?> getAlbumDetails({
    required String albumId,
    required String albumTitle,
  }) =>
      _getAlbumDetailsImpl(albumId: albumId, albumTitle: albumTitle);

  static Future<Map<String, dynamic>> getArtistDiscography({
    required String artistId,
    required String artistName,
  }) =>
      _getArtistDiscographyImpl(artistId: artistId, artistName: artistName);

  /// Fetches remote playlist tracks across sources (JioSaavn or YouTube).
  static Future<Map<String, dynamic>> getRemotePlaylistTracks({
    required String playlistId,
    required String playlistTitle,
    required String source,
  }) async {
    List<Song> fetchedSongs = [];
    String? imageUrl;

    try {
      if (source == 'auto_album') {
        final details = await SaavnClient.getAlbumDetails(playlistId);
        if (details != null && details['songs'] is List<Song>) {
          fetchedSongs = details['songs'] as List<Song>;
          final img = details['image']?.toString() ?? '';
          if (img.isNotEmpty) imageUrl = img;
        }
      } else if (source == 'youtube') {
        fetchedSongs = await YouTubeClient.getPlaylistTracks(playlistId, limit: 150);
      } else {
        final details = await SaavnClient.getPlaylistDetails(playlistId);
        if (details != null && details['songs'] is List<Song>) {
          fetchedSongs = details['songs'] as List<Song>;
          final img = details['image']?.toString() ?? '';
          if (img.isNotEmpty) imageUrl = img;
        }
      }
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }

    // Fallback: Local catalog if remote playlist had no tracks
    if (fetchedSongs.isEmpty) {
      try {
        final cleanTitle = playlistTitle.replaceAll(RegExp(r'\s*\((All Songs|Full Album|Original Motion Picture Soundtrack)\)', caseSensitive: false), '').trim();
        final localSongs = await CatalogDatabase.getSongsByMovie(cleanTitle);
        if (localSongs.isNotEmpty) {
          fetchedSongs.addAll(localSongs);
          imageUrl = localSongs.first.coverUrl;
        }
      } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
    }

    if (fetchedSongs.isEmpty) {
      try {
        final searchResults = await SaavnClient.search(playlistTitle, limit: 25);
        if (searchResults.isNotEmpty) {
          fetchedSongs = searchResults;
        } else {
          fetchedSongs = await YouTubeClient.search(playlistTitle, limit: 25);
        }
      } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
    }

    // Preserve all distinct curated tracks by unique ID (do not strip titles/durations)
    final List<Song> distinctTracks = [];
    final Set<String> seenIds = {};
    for (final s in fetchedSongs) {
      if (s.id.isNotEmpty && seenIds.add(s.id)) {
        distinctTracks.add(s);
      }
    }

    return {
      'image': imageUrl,
      'songs': distinctTracks,
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
    final seed = CatalogArtistsSeed.getArtistsForLanguage(language, limit: limit);
    if (seed.isNotEmpty) {
      return seed.map((a) => {
        'id': a.id,
        'name': a.name,
        'role': a.role,
        'image': a.imageUrl,
        'language': a.language,
      }).toList();
    }
    try {
      return await SaavnClient.searchArtists(language, limit: limit);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// Resolves verified high-resolution artist avatar from memory cache, local CatalogDatabase, or remote providers.
  static Future<String?> resolveArtistAvatar(String artistName) async {
    final norm = normalizeArtist(artistName);
    if (_dynamicArtistAvatarCache.containsKey(norm)) {
      return _dynamicArtistAvatarCache[norm];
    }
    if (_verifiedArtistAvatars.containsKey(norm)) {
      return _verifiedArtistAvatars[norm];
    }
    final catalogImg = CatalogDatabase.getArtistProfileImage(artistName);
    if (catalogImg != null && catalogImg.isNotEmpty) {
      _dynamicArtistAvatarCache[norm] = catalogImg;
      return catalogImg;
    }
    try {
      final saavnArtists = await SaavnClient.searchArtists(artistName, limit: 3);
      for (final a in saavnArtists) {
        final aImg = (a['image'] ?? '').toString();
        if (aImg.isNotEmpty) {
          _dynamicArtistAvatarCache[norm] = aImg;
          return aImg;
        }
      }
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
    return null;
  }
}
