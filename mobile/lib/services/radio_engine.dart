import 'dart:math';
import '../core/dsa/bloom_filter.dart';
import '../data/repositories/song_repository.dart';
import '../logic/markov_cosine_radio_strategy.dart';
import '../logic/next_track_strategy.dart';
import '../logic/track_quality_filter.dart';
import '../models/song.dart';
import 'app_logger.dart';
import 'download_manager.dart';
import 'favorites_manager.dart';
import 'history_manager.dart';
import 'queue_cooldown_manager.dart';
import 'saavn_client.dart';
import 'settings_manager.dart';
import 'youtube_client.dart';

class RadioEngine {
  static final Set<String> _knownMusicDirectors = {
    'a r rahman',
    'ar rahman',
    'anirudh',
    'anirudh ravichander',
    'yuvan',
    'yuvan shankar raja',
    'harris jayaraj',
    'ilaiyaraaja',
    'ilayaraja',
    'santhosh narayanan',
    'gv prakash',
    'gv prakash kumar',
    'g v prakash kumar',
    'd imman',
    'imman',
    'deva',
    'vidyasagar',
    'keeravaani',
    'm m keeravaani',
    'pritam',
    'vishal shekhar',
    'ajay atul',
    'amit trivedi',
    'hiphop tamizha',
    'ghibran',
    'sam cs',
    'thaman',
    'thaman s',
    'devi sri prasad',
    'dsp',
    'sushin shyam',
    'shaan rahman',
    'deepak dev',
    'bijibal',
    'jassie gift',
    'm s viswanathan',
    'kv mahadevan',
    'ravichandran',
    'siddharth vipin',
    'justin prabhakaran',
    'leon james',
    'dhibu ninan thomas',
    'sean roldan',
    'sachin jigar',
    'meet bros',
    'shankar ehsaan loy',
    'himesh reshammiya',
    'anu malik',
    'mithoon',
    'jakes bejoy',
    'hesham abdul wahab',
    'govind vasantha',
  };

  /// Extracts the 4-digit release year from album or title metadata if available.
  static int? extractReleaseYear(Song song) {
    final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch('${song.album} ${song.title}');
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Determines if two songs share a music director or composer.
  static bool isSharedMusicDirectorOrComposer(Song a, Song b) {
    Set<String> extractArtists(Song s) {
      final raw = '${s.artist}, ${s.primaryArtist}';
      return raw
          .toLowerCase()
          .split(RegExp(r'[,&/|;]|\bfeat\.?\b|\bft\.?\b|\bwith\b'))
          .map((e) => QueueCooldownManager.normalizeArtistKey(e))
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    final artistsA = extractArtists(a);
    final artistsB = extractArtists(b);
    final intersection = artistsA.intersection(artistsB);

    if (intersection.isEmpty) return false;

    for (final shared in intersection) {
      if (_knownMusicDirectors.contains(shared)) return true;
      for (final md in _knownMusicDirectors) {
        if (shared == md || shared.contains(md) || md.contains(shared)) {
          return true;
        }
      }
    }

    final primaryA = QueueCooldownManager.normalizeArtistKey(a.primaryArtist);
    final primaryB = QueueCooldownManager.normalizeArtistKey(b.primaryArtist);
    if (primaryA.isNotEmpty && primaryA == primaryB && _knownMusicDirectors.contains(primaryA)) {
      return true;
    }

    return false;
  }

  /// 1. CANDIDATE GENERATION:
  /// Generates a session-aware candidate pool (~40 tracks):
  /// - Source A (60% ~ 24 tracks): YT Music "Up Next" / Automix API (InnerTube `next` endpoint with `videoId` + `RDAMVM`)
  /// - Source B (30% ~ 12 tracks): JioSaavn `reco.getreco` by `pid`
  /// - Source C (10% ~ 4 tracks): Local History & Markov-Cosine vector similarity
  static Future<List<Song>> generateCandidatePool({
    required Song seedSong,
    String? targetLanguage,
    List<Song> history = const [],
    int totalCount = 40,
  }) async {
    final prefLangs = SettingsManager.preferredLanguages;
    final targetLang = (targetLanguage != null && targetLanguage.isNotEmpty)
        ? targetLanguage.toLowerCase().trim()
        : (seedSong.language != null && seedSong.language!.isNotEmpty)
            ? seedSong.language!.toLowerCase().trim()
            : (prefLangs.firstOrNull ?? 'tamil').toLowerCase().trim();

    final ytLimit = (totalCount * 0.60).round(); // ~24
    final saavnLimit = (totalCount * 0.30).round(); // ~12
    final localLimit = max(1, totalCount - ytLimit - saavnLimit); // ~4

    final results = await Future.wait([
      // Source A (60%): YT Music "Up Next" / Automix API
      () async {
        try {
          final ytId = (seedSong.source == 'youtube' && seedSong.id.length == 11) ? seedSong.id : null;
          List<Song> tracks = [];
          if (ytId != null) {
            tracks = await YouTubeClient.getUpNextAutomix(ytId, limit: ytLimit);
          }
          if (tracks.isEmpty) {
            tracks = await YouTubeClient.getRadioTracks(seedSong, limit: ytLimit);
          }
          return tracks;
        } catch (e) {
          AppLogger.log('RadioEngine', 'Source A (YouTube Automix) fallback: $e');
          return <Song>[];
        }
      }(),

      // Source B (30%): JioSaavn reco.getreco by pid
      () async {
        try {
          return await SaavnClient.getRelatedSongs(seedSong.id, language: targetLang);
        } catch (e) {
          AppLogger.log('RadioEngine', 'Source B (JioSaavn Reco) fallback: $e');
          return <Song>[];
        }
      }(),

      // Source C (10%): Local History & Markov-Cosine vector similarity
      () async {
        try {
          final pool = <Song>[];
          if (history.isNotEmpty) {
            pool.addAll(history);
          } else {
            try {
              pool.addAll(HistoryManager.getHistory());
            } catch (_) {}
            try {
              pool.addAll(FavoritesManager.getFavorites());
            } catch (_) {}
            try {
              pool.addAll(DownloadManager.getDownloadedSongs());
            } catch (_) {}
          }

          if (pool.isEmpty) return <Song>[];

          final scored = <MapEntry<double, Song>>[];
          final seenKeys = <String>{seedSong.canonicalBaseKey, seedSong.id};

          for (final s in pool) {
            if (s.title.trim().isEmpty) continue;
            final key = s.canonicalBaseKey;
            if (seenKeys.contains(key) || seenKeys.contains(s.id)) continue;
            if (s.isSameSongOrDub(seedSong)) continue;

            final vector = SongFeatureVector.extractRelative(seedSong, s);
            final score = vector.compositeVectorScore;
            seenKeys.add(key);
            scored.add(MapEntry(score, s.copyWith(isSmartRecommended: true)));
          }

          scored.sort((a, b) => b.key.compareTo(a.key));
          return scored.take(localLimit).map((e) => e.value).toList();
        } catch (e) {
          AppLogger.log('RadioEngine', 'Source C (Markov-Cosine Local) fallback: $e');
          return <Song>[];
        }
      }(),
    ]);

    final ytTracks = results[0];
    final saavnTracks = results[1];
    final localTracks = results[2];

    // Interleave candidates according to 3:2:1 ratio
    final List<Song> combined = [];
    int yIdx = 0;
    int sIdx = 0;
    int lIdx = 0;

    while (yIdx < ytTracks.length || sIdx < saavnTracks.length || lIdx < localTracks.length) {
      for (int i = 0; i < 3 && yIdx < ytTracks.length; i++) {
        combined.add(ytTracks[yIdx++]);
      }
      for (int i = 0; i < 2 && sIdx < saavnTracks.length; i++) {
        combined.add(saavnTracks[sIdx++]);
      }
      for (int i = 0; i < 1 && lIdx < localTracks.length; i++) {
        combined.add(localTracks[lIdx++]);
      }
    }

    return combined;
  }

  /// 2. HARD FILTERING:
  /// Prunes invalid or repetitive candidates based on:
  /// - BloomFilter check against last 50 songs in history, queue, and seed
  /// - QueueCooldownManager (last 75 tracks rolling cooldown)
  /// - TrackQualityFilter (drops < 60s or > 600s / 10m, mixes, compilations, streams)
  /// - Strict target language match (drops language mismatches)
  /// - Anti-cross-language dubs against seed song, queue, and previously accepted candidates
  static List<Song> applyHardFiltering({
    required Song seedSong,
    required List<Song> candidates,
    List<Song> queue = const [],
    List<Song> history = const [],
    String? targetLanguage,
  }) {
    final targetLang = (targetLanguage != null && targetLanguage.isNotEmpty)
        ? targetLanguage.toLowerCase().trim()
        : (seedSong.language != null && seedSong.language!.isNotEmpty)
            ? seedSong.language!.toLowerCase().trim()
            : null;

    final bloom = BloomFilter(expectedElements: 200);
    final Set<String> fastExclusions = {};

    void addExclusion(Song s) {
      bloom.add(s.id);
      fastExclusions.add(s.id);
      if (s.canonicalBaseKey.isNotEmpty) {
        bloom.add(s.canonicalBaseKey);
        fastExclusions.add(s.canonicalBaseKey);
      }
      if (s.cleanTitleKey.isNotEmpty) {
        bloom.add(s.cleanTitleKey);
        fastExclusions.add(s.cleanTitleKey);
      }
    }

    addExclusion(seedSong);
    for (final q in queue) {
      addExclusion(q);
    }
    final recentHistory = history.length > 50 ? history.sublist(history.length - 50) : history;
    for (final h in recentHistory) {
      addExclusion(h);
    }

    final List<Song> accepted = [];
    final Set<String> seenKeys = {};

    for (final c in candidates) {
      if (c.title.trim().isEmpty) continue;
      final id = c.id;
      final baseKey = c.canonicalBaseKey;
      final titleKey = c.cleanTitleKey;

      // 1. BloomFilter + Fast Exclusions check (last 50 history + queue + seed)
      if (fastExclusions.contains(id) ||
          fastExclusions.contains(baseKey) ||
          (titleKey.isNotEmpty && fastExclusions.contains(titleKey)) ||
          bloom.contains(id) ||
          bloom.contains(baseKey)) {
        continue;
      }

      // 2. QueueCooldownManager (last 75 songs cooldown buffer)
      if (QueueCooldownManager.isCoolingDown(c)) {
        continue;
      }

      // 3. TrackQualityFilter: drop < 60s or > 600s / 10m, streams, and mixes
      if (c.duration > 0 && (c.duration < 60 || c.duration > 600)) {
        continue;
      }
      if (!TrackQualityFilter.shouldKeep(title: c.title, durationSec: c.duration, allowUnknownDuration: false)) {
        continue;
      }

      // 4. Target language lockdown
      if (targetLang != null && targetLang.isNotEmpty) {
        if (c.language != null && c.language!.isNotEmpty) {
          final cLang = c.language!.toLowerCase().trim();
          if (cLang != targetLang) continue;
        }
      }

      // 5. Anti-cross-language dub check against seed, queue, and accepted candidates
      if (c.isSameSongOrDub(seedSong)) continue;
      if (queue.any((q) => c.isSameSongOrDub(q))) continue;
      if (accepted.any((a) => c.isSameSongOrDub(a))) continue;

      // 6. Local accepted seen keys deduplication
      if (seenKeys.contains(id) || seenKeys.contains(baseKey) || (titleKey.isNotEmpty && seenKeys.contains(titleKey))) {
        continue;
      }

      seenKeys.add(id);
      seenKeys.add(baseKey);
      if (titleKey.isNotEmpty) seenKeys.add(titleKey);

      accepted.add(c.copyWith(
        isSmartRecommended: true,
        language: targetLang ?? c.language,
      ));
    }

    return accepted;
  }

  /// 3. SESSION-AWARE SCORING & DIVERSITY RE-RANKING:
  /// Scores candidates using session-aware features:
  /// - Multi-dimensional base vector similarity (artist, language, era, duration, token overlap)
  /// - Era proximity boost: +0.25 if candidate release year is within ±4 years of seed
  /// - Music Director / Composer boost: +0.30 if seed and candidate share a composer
  /// - Language match boost: +0.20 if same language
  /// - Anti-fatigue penalty: -0.50 if candidate's primary artist played in the last 2 songs
  static List<Song> scoreAndReRankCandidates({
    required Song seedSong,
    required List<Song> candidates,
    List<Song> history = const [],
    List<String> lastPlayedArtists = const [],
  }) {
    if (candidates.isEmpty) return [];

    final seedYear = extractReleaseYear(seedSong);
    final seedLang = seedSong.language?.toLowerCase().trim();

    final recentArtists = lastPlayedArtists.isNotEmpty
        ? lastPlayedArtists.map((a) => QueueCooldownManager.normalizeArtistKey(a)).toSet()
        : QueueCooldownManager.getRecentArtists(window: 2).map((a) => QueueCooldownManager.normalizeArtistKey(a)).toSet();

    final scored = <MapEntry<double, Song>>[];

    for (final c in candidates) {
      final vector = SongFeatureVector.extractRelative(seedSong, c);
      double score = vector.compositeVectorScore;

      // 1. Era proximity boost (±4 years)
      final cYear = extractReleaseYear(c);
      if (seedYear != null && cYear != null && (seedYear - cYear).abs() <= 4) {
        score += 0.25;
      }

      // 2. Music Director / Composer boost
      if (isSharedMusicDirectorOrComposer(seedSong, c)) {
        score += 0.30;
      }

      // 3. Language match boost
      if (seedLang != null && c.language != null && seedLang == c.language!.toLowerCase().trim()) {
        score += 0.20;
      }

      // 4. Anti-fatigue penalty: -0.50 if same artist played in the last 2 songs
      final cArtist = QueueCooldownManager.normalizeArtistKey(c.primaryArtist);
      if (cArtist.isNotEmpty && recentArtists.contains(cArtist)) {
        score -= 0.50;
      }

      scored.add(MapEntry(score, c));
    }

    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.map((e) => e.value).toList();
  }

  /// Builds a curated 50-track discovery radio mix based on a seed song.
  /// Combines YouTube Music's native automix graph (genre-aligned RDAMVM graph traversal),
  /// JioSaavn unthrottled 320kbps recommendations, artist top hits, contextual recommendations,
  /// and regional trending tracks while enforcing artist diversity, strict language lockdown,
  /// and anti-cross-language dub deduplication.
  static Future<List<Song>> buildSongRadio(Song seedSong, {int limit = 50}) async {
    final prefLangs = SettingsManager.preferredLanguages;
    final targetLang = (seedSong.language != null && seedSong.language!.isNotEmpty)
        ? seedSong.language!.toLowerCase()
        : (prefLangs.firstOrNull ?? 'tamil').toLowerCase();

    // 1. Candidate Generation (~40-50 tracks)
    final candidatePool = await generateCandidatePool(
      seedSong: seedSong,
      targetLanguage: targetLang,
      totalCount: max(40, limit),
    );

    // If pool is shallow, supplement with trending/hits
    if (candidatePool.length < limit) {
      try {
        final trending = await SongRepository.getTrendingMerged(language: targetLang);
        candidatePool.addAll(trending);
      } catch (_) {}
    }

    // 2. Hard Filtering
    final filtered = applyHardFiltering(
      seedSong: seedSong,
      candidates: candidatePool,
      targetLanguage: targetLang,
    );

    // 3. Session-Aware Scoring & Diversity Re-Ranking
    final ranked = scoreAndReRankCandidates(
      seedSong: seedSong,
      candidates: filtered,
    );

    // 4. Enforce Artist Dispersion & Zero Back-to-Back Duplicates
    final shaped = enforceArtistDispersionAndNoBackToBack(
      ranked,
      seedArtist: seedSong.primaryArtist,
      count: limit - 1,
    );

    return [seedSong, ...shaped];
  }

  /// Pure filtering and diversity shaping logic (Backward-compatible helper)
  static List<Song> shapeRadioQueue({
    required Song seedSong,
    required List<Song> candidatePool,
    String? targetLanguage,
    int limit = 50,
  }) {
    final targetLang = (targetLanguage != null && targetLanguage.isNotEmpty)
        ? targetLanguage.toLowerCase()
        : (seedSong.language?.toLowerCase() ?? 'tamil');

    final filtered = applyHardFiltering(
      seedSong: seedSong,
      candidates: candidatePool,
      targetLanguage: targetLang,
    );

    final ranked = scoreAndReRankCandidates(
      seedSong: seedSong,
      candidates: filtered,
    );

    final shaped = enforceArtistDispersionAndNoBackToBack(
      ranked,
      seedArtist: seedSong.primaryArtist,
      count: limit - 1,
    );

    return [seedSong, ...shaped];
  }
}
