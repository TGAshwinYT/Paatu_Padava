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
  static const double laplaceSmoothing = 0.2;

  String _songKey(Song s) => 'artist:${s.primaryArtist.toLowerCase().trim()}';

  /// Records a transition between track [from] and track [to].
  void recordTransition(Song from, Song to, {bool isPositive = true}) {
    final fromKey = _songKey(from);
    final toKey = _songKey(to);
    if (fromKey.isEmpty || toKey.isEmpty) return;

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

    final numerator = targetWeight + laplaceSmoothing;
    final denominator = totalRowWeight + (row.length * laplaceSmoothing);
    return (numerator / denominator).clamp(0.0, 1.0);
  }

  void clear() {
    _transitions.clear();
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
    final seedArtistTokens = seed.primaryArtist.toLowerCase().split(RegExp(r'\s+')).toSet();
    final candArtistTokens = cand.primaryArtist.toLowerCase().split(RegExp(r'\s+')).toSet();
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
    final seedTokens = '${seed.title} ${seed.album}'.toLowerCase().split(RegExp(r'[\s,-]+')).toSet();
    final candTokens = '${cand.title} ${cand.album}'.toLowerCase().split(RegExp(r'[\s,-]+')).toSet();
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
    artistSimilarity: 0.5, // Not 1.0 so we don't only recommend the exact same artist
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
  final MarkovTransitionMatrix _markovMatrix = MarkovTransitionMatrix();
  final Set<String> _sessionBlacklistIds = {};

  @override
  String get id => 'markov_cosine_radio';

  @override
  String get displayName => 'Markov-Cosine Radio Mix';

  @override
  String get description =>
      'Blends Markov Chain state transition probabilities with multi-dimensional Cosine Similarity vector space.';

  MarkovTransitionMatrix get markovMatrix => _markovMatrix;

  @override
  Future<List<Song>> getUpcomingTracks({
    required Song seedSong,
    required List<Song> queue,
    required List<Song> history,
    int count = 20,
  }) async {
    final existingIds = queue.map((s) => s.id).toSet();
    final existingKeys = queue.map((s) => s.cleanTitleKey).toSet();
    for (final h in history.take(15)) {
      existingIds.add(h.id);
      existingKeys.add(h.cleanTitleKey);
    }

    final candidatePool = <Song>[];

    // 1. Gather initial recommendation seeds from RadioEngine
    try {
      final radioTracks = await RadioEngine.buildSongRadio(
        seedSong,
        limit: count * 2,
      );
      candidatePool.addAll(radioTracks);
    } catch (e) {
      AppLogger.log('MarkovCosineRadio', 'RadioEngine pool notice: $e');
    }

    // 2. Fetch supplemental related songs from Saavn recommendations
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

    // 3. Score candidates with Cosine Similarity and Markov Transition probabilities
    final scoredCandidates = <MapEntry<Song, double>>[];

    for (final candidate in candidatePool) {
      if (existingIds.contains(candidate.id) || existingKeys.contains(candidate.cleanTitleKey)) {
        continue;
      }
      if (_sessionBlacklistIds.contains(candidate.id)) {
        continue;
      }
      if (QueueCooldownManager.isCoolingDown(candidate)) {
        continue;
      }

      final featureVec = SongFeatureVector.extractRelative(seedSong, candidate);
      final cosineSim = featureVec.cosineSimilarityTo(SongFeatureVector.ideal);
      final markovProb = _markovMatrix.getProbability(seedSong, candidate);

      // Blended Score: 60% Vector Cosine Similarity + 40% Markov Transition Probability
      final compositeScore = (0.60 * cosineSim) + (0.40 * markovProb);
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
    if (listenedSeconds < 15) {
      _sessionBlacklistIds.add(skippedSong.id);
      QueueCooldownManager.recordPlayed(skippedSong);
    }
  }

  @override
  void resetSession({Song? initialAnchor}) {
    _sessionBlacklistIds.clear();
  }
}
