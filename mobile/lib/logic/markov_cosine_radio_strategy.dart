import 'dart:math' as math;
import '../models/song.dart';
import '../services/app_logger.dart';
import '../services/queue_cooldown_manager.dart';
import '../services/radio_engine.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';
import 'next_track_strategy.dart';

/// Markov Transition State Matrix tracking transition frequencies between tracks/artists.
class MarkovTransitionMatrix {
  final Map<String, Map<String, double>> _transitions = {};
  final Set<String> _knownStates = {};
  static const double laplaceSmoothing = 0.2;

  String _songKey(Song s) => 'artist:${QueueCooldownManager.normalizeArtistKey(s.primaryArtist)}';

  /// Records a transition between track [from] and track [to].
  void recordTransition(Song from, Song to, {bool isPositive = true}) {
    final fromKey = _songKey(from);
    final toKey = _songKey(to);
    if (fromKey.isEmpty || toKey.isEmpty) return;

    _knownStates.add(fromKey);
    _knownStates.add(toKey);

    final row = _transitions.putIfAbsent(fromKey, () => <String, double>{});
    final currentWeight = row[toKey] ?? 0.0;

    if (isPositive) {
      row[toKey] = currentWeight + 1.0;
    } else {
      // Negative transition penalty (skip)
      row[toKey] = math.max(0.0, currentWeight - 0.5);
    }
  }

  /// Calculates Laplace-smoothed transition probability P(to | from).
  double getProbability(Song from, Song to) {
    final fromKey = _songKey(from);
    final toKey = _songKey(to);
    if (fromKey.isEmpty || toKey.isEmpty) return 0.1;

    final row = _transitions[fromKey];
    if (row == null || row.isEmpty) return 0.1;

    final targetWeight = row[toKey] ?? 0.0;
    double totalRowWeight = 0.0;
    for (final w in row.values) {
      totalRowWeight += w;
    }

    final vocabSize = math.max(5, _knownStates.length);
    final numerator = targetWeight + laplaceSmoothing;
    final denominator = totalRowWeight + (vocabSize * laplaceSmoothing);
    return (numerator / denominator).clamp(0.0, 1.0);
  }

  void clear() {
    _transitions.clear();
    _knownStates.clear();
  }
}

/// Multi-Dimensional Feature Vector for Cosine Similarity Calculation.
class SongFeatureVector {
  final double artistSimilarity;
  final double languageMatch;
  final double eraProximity;
  final double durationAffinity;
  final double tokenOverlap;

  const SongFeatureVector({
    required this.artistSimilarity,
    required this.languageMatch,
    required this.eraProximity,
    required this.durationAffinity,
    required this.tokenOverlap,
  });

  /// Computes a balanced relative score using multi-dimensional weights:
  /// 35% artist affinity, 30% language match, 15% era proximity, 10% duration affinity, 10% title/album token overlap.
  double get compositeVectorScore {
    return (0.35 * artistSimilarity) +
        (0.30 * languageMatch) +
        (0.15 * eraProximity) +
        (0.10 * durationAffinity) +
        (0.10 * tokenOverlap);
  }

  /// Computes cosine similarity between this vector and [other].
  double cosineSimilarityTo(SongFeatureVector other) {
    final dotProduct = (artistSimilarity * other.artistSimilarity) +
        (languageMatch * other.languageMatch) +
        (eraProximity * other.eraProximity) +
        (durationAffinity * other.durationAffinity) +
        (tokenOverlap * other.tokenOverlap);

    final normA = math.sqrt(
      (artistSimilarity * artistSimilarity) +
          (languageMatch * languageMatch) +
          (eraProximity * eraProximity) +
          (durationAffinity * durationAffinity) +
          (tokenOverlap * tokenOverlap),
    );

    final normB = math.sqrt(
      (other.artistSimilarity * other.artistSimilarity) +
          (other.languageMatch * other.languageMatch) +
          (other.eraProximity * other.eraProximity) +
          (other.durationAffinity * other.durationAffinity) +
          (other.tokenOverlap * other.tokenOverlap),
    );

    if (normA == 0.0 || normB == 0.0) return 0.0;
    return (dotProduct / (normA * normB)).clamp(0.0, 1.0);
  }

  /// Extracts normalized feature vector comparing candidate [cand] relative to [seed].
  static SongFeatureVector extractRelative(Song seed, Song cand) {
    // 1. Artist Token Jaccard Similarity
    final seedArtist = QueueCooldownManager.normalizeArtistKey(seed.primaryArtist);
    final candArtist = QueueCooldownManager.normalizeArtistKey(cand.primaryArtist);
    final seedArtistTokens = seedArtist.split(RegExp(r'\s+')).toSet();
    final candArtistTokens = candArtist.split(RegExp(r'\s+')).toSet();
    final intersection = seedArtistTokens.intersection(candArtistTokens).length;
    final union = seedArtistTokens.union(candArtistTokens).length;
    final artistSim = union > 0 ? (intersection / union) : 0.0;

    // 2. Language Match
    final seedLang = seed.language?.toLowerCase().trim();
    final candLang = cand.language?.toLowerCase().trim();
    final prefLangs = SettingsManager.preferredLanguages.map((l) => l.toLowerCase().trim()).toSet();
    double langScore = 0.3;
    if (seedLang != null && candLang != null && seedLang == candLang) {
      langScore = 1.0;
    } else if (candLang != null && prefLangs.contains(candLang)) {
      langScore = 0.8;
    }

    // 3. Era / Year Proximity
    int extractYear(Song s) {
      final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch('${s.album} ${s.title}');
      return match != null ? int.tryParse(match.group(1)!) ?? 2023 : 2023;
    }
    final seedYear = extractYear(seed);
    final candYear = extractYear(cand);
    final yearDiff = (seedYear - candYear).abs();
    final eraScore = math.max(0.1, 1.0 - (yearDiff / 15.0));

    // 4. Duration Affinity
    final seedDur = seed.duration;
    final candDur = cand.duration;
    double durScore = 0.5;
    if (seedDur > 0 && candDur > 0) {
      final ratio = candDur / seedDur;
      durScore = (ratio >= 0.7 && ratio <= 1.4) ? 1.0 : math.max(0.2, 1.0 - (ratio - 1.0).abs());
    }

    // 5. Title / Album Token Overlap
    final seedTokens = '${seed.cleanTitleKey} ${seed.album}'.toLowerCase().split(RegExp(r'[\s,-]+')).toSet();
    final candTokens = '${cand.cleanTitleKey} ${cand.album}'.toLowerCase().split(RegExp(r'[\s,-]+')).toSet();
    final tokenInter = seedTokens.intersection(candTokens).length;
    final tokenScore = math.min(1.0, tokenInter * 0.3);

    return SongFeatureVector(
      artistSimilarity: artistSim,
      languageMatch: langScore,
      eraProximity: eraScore,
      durationAffinity: durScore,
      tokenOverlap: tokenScore,
    );
  }

  /// Reference ideal vector where all dimensions align perfectly.
  static const SongFeatureVector ideal = SongFeatureVector(
    artistSimilarity: 0.5,
    languageMatch: 1.0,
    eraProximity: 1.0,
    durationAffinity: 1.0,
    tokenOverlap: 0.2,
  );
}

/// Advanced Markov Chain & Cosine Similarity Radio Strategy.
/// Blends probabilistic transition graphs with vector space similarity to produce
/// infinite, smooth, anti-fatigued personalized radio mixes.
class MarkovCosineRadioStrategy implements NextTrackStrategy {
  static final MarkovTransitionMatrix _globalMarkovMatrix = MarkovTransitionMatrix();
  final Set<String> _sessionBlacklistIds = {};
  Song? _lastSeedSong;

  @override
  String get id => 'markov_cosine_radio';

  @override
  String get displayName => 'Markov-Cosine Radio Mix';

  @override
  String get description =>
      'Blends Markov Chain state transition probabilities with multi-dimensional feature vector similarity.';

  MarkovTransitionMatrix get markovMatrix => _globalMarkovMatrix;

  @override
  void recordTransition(Song from, Song to, {bool isPositive = true}) {
    _globalMarkovMatrix.recordTransition(from, to, isPositive: isPositive);
    AppLogger.log(
      'MarkovCosineRadio',
      'Learned transition "${from.primaryArtist}" -> "${to.primaryArtist}" (positive: $isPositive)',
    );
  }

  @override
  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 20,
  }) async {
    _lastSeedSong = seedSong;
    final existingIds = queue.map((s) => s.id).toSet();
    final existingKeys = queue.map((s) => s.cleanTitleKey).toSet();
    
    // Cap history exclusions to last 50 tracks to avoid pool starvation
    final recentHistory = history.length > 50 ? history.sublist(history.length - 50) : history;
    for (final h in recentHistory) {
      existingIds.add(h.id);
      if (h.cleanTitleKey.isNotEmpty) existingKeys.add(h.cleanTitleKey);
    }

    final candidatePool = <Song>[];

    // 1. Fetch seed recommendations via RadioEngine (InnerTube & Saavn mix)
    try {
      final radioTracks = await RadioEngine.buildSongRadio(
        seedSong,
        limit: count * 2,
      );
      candidatePool.addAll(radioTracks);
    } catch (e) {
      AppLogger.log('MarkovCosineRadio', 'RadioEngine pool notice: $e');
    }

    // 2. Fetch supplemental candidates from primary artist
    try {
      if (candidatePool.length < count) {
        final query = '${seedSong.primaryArtist} ${seedSong.language ?? "Tamil"}';
        final searchResults = await SaavnClient.search(
          query,
          limit: count,
          language: seedSong.language ?? 'tamil',
        );
        candidatePool.addAll(searchResults);
      }
    } catch (e) {
      AppLogger.log('MarkovCosineRadio', 'Saavn pool notice: $e');
    }

    // 3. Score candidates with Relative Vector Feature Score, Markov Transition probabilities, and Session-Aware Boosts
    final scoredCandidates = <MapEntry<Song, double>>[];
    final filteredPool = RadioEngine.applyHardFiltering(
      seedSong: seedSong,
      candidates: candidatePool,
      queue: queue,
      history: recentHistory,
      targetLanguage: seedSong.language,
    );

    final seedYear = RadioEngine.extractReleaseYear(seedSong);
    final recentArtists = QueueCooldownManager.getRecentArtists(window: 2)
        .map((a) => QueueCooldownManager.normalizeArtistKey(a))
        .toSet();

    for (final candidate in filteredPool) {
      if (_sessionBlacklistIds.contains(candidate.id)) {
        continue;
      }

      final featureVec = SongFeatureVector.extractRelative(seedSong, candidate);
      final vectorScore = featureVec.compositeVectorScore;
      final markovProb = _globalMarkovMatrix.getProbability(seedSong, candidate);

      // Blended Score: 60% Multi-Dimensional Vector Score + 40% Markov Transition Probability
      double compositeScore = (0.60 * vectorScore) + (0.40 * markovProb);

      // Era proximity boost (±4 years)
      final cYear = RadioEngine.extractReleaseYear(candidate);
      if (seedYear != null && cYear != null && (seedYear - cYear).abs() <= 4) {
        compositeScore += 0.25;
      }

      // Music Director / Composer boost
      if (RadioEngine.isSharedMusicDirectorOrComposer(seedSong, candidate)) {
        compositeScore += 0.30;
      }

      // Anti-fatigue penalty: -0.50 if candidate's primary artist played in the last 2 songs
      final cArtist = QueueCooldownManager.normalizeArtistKey(candidate.primaryArtist);
      if (cArtist.isNotEmpty && recentArtists.contains(cArtist)) {
        compositeScore -= 0.50;
      }

      scoredCandidates.add(MapEntry(candidate, compositeScore));
    }

    // Sort descending by composite score
    scoredCandidates.sort((a, b) => b.value.compareTo(a.value));

    final rawSorted = scoredCandidates.map((e) => e.key).toList();

    // 4. Enforce Artist Dispersion and No-Back-To-Back rules
    final dispersed = enforceArtistDispersionAndNoBackToBack(
      rawSorted,
      seedArtist: seedSong.primaryArtist,
      maxPerArtist: 2,
      count: count,
    );

    return dispersed;
  }

  @override
  void recordSkip(Song skippedSong, {required int listenedSeconds}) {
    if (listenedSeconds < 30) {
      _sessionBlacklistIds.add(skippedSong.id);
      QueueCooldownManager.recordPlayed(skippedSong);
      if (_lastSeedSong != null) {
        _globalMarkovMatrix.recordTransition(_lastSeedSong!, skippedSong, isPositive: false);
      }
    }
  }

  @override
  void resetSession({Song? initialAnchor}) {
    _sessionBlacklistIds.clear();
    _lastSeedSong = initialAnchor;
  }
}
