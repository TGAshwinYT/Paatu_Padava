import 'dart:async';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/api_client.dart';
import '../../services/history_manager.dart';
import '../../services/supabase_service.dart';

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
  /// If [existing] is provided, prevents appending duplicates to active lists/feeds.
  static List<Song> deduplicateSongs(
    Iterable<Song> songs, {
    Iterable<Song>? existing,
  }) {
    final Set<String> seenIds = {};
    final Set<String> seenKeys = {};
    final List<Song> result = [];

    // Pre-populate with existing items to prevent duplicates across pagination or state rebuilds
    if (existing != null) {
      for (final song in existing) {
        if (song.id.isNotEmpty) {
          seenIds.add(song.id);
        }
        final key = '${normalizeTitle(song.title)}__${normalizeArtist(song.artist)}';
        if (key.length > 3) {
          seenKeys.add(key);
        }
      }
    }

    for (final song in songs) {
      if (song.title.trim().isEmpty) continue;

      final id = song.id.trim();
      final key = '${normalizeTitle(song.title)}__${normalizeArtist(song.artist)}';

      // Duplicate check: unique id or identical normalized title + artist
      if (id.isNotEmpty && seenIds.contains(id)) {
        continue;
      }
      if (key.length > 3 && seenKeys.contains(key)) {
        continue;
      }

      if (id.isNotEmpty) seenIds.add(id);
      if (key.length > 3) seenKeys.add(key);
      result.add(song);
    }

    return result;
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
    } catch (_) {}

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
    } catch (_) {}

    // Fallback if candidates are scarce
    if (candidates.length < 8) {
      final fallback = await SaavnClient.search('$language Melodies Hits', limit: 15, language: language);
      candidates.addAll(fallback);
    }

    return deduplicateSongs(candidates);
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
  };

  /// Fetches Popular Artists with high-res avatars, replacing low-res or generic placeholder icons.
  static Future<List<Map<String, dynamic>>> getPopularArtists({required String language}) async {
    try {
      final rawArtists = await SaavnClient.searchArtists('Top $language Artists', limit: 12);
      final List<Map<String, dynamic>> enriched = [];

      for (final artist in rawArtists) {
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
      } catch (_) {}

      if (enriched.isNotEmpty) {
        return enriched;
      }
    } catch (_) {}

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
