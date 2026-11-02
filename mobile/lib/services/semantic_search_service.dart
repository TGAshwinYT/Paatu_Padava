import 'dart:math' as math;
import '../models/song.dart';

/// Dense 8-dimensional semantic vector representing musical mood, tempo, and intent.
class SemanticVector {
  final List<double> values;

  const SemanticVector(this.values);

  static const int dimensions = 8;

  // Semantic Dimensions:
  // 0: Energy / Workout / Mass
  // 1: Melancholy / Sadness / Heartbreak
  // 2: Romance / Love / Melody
  // 3: Chill / Lo-fi / Rainy / Late Night
  // 4: Devotional / Spiritual / Bhakti
  // 5: Retro / Golden Era / Vintage (80s, 90s)
  // 6: Folk / Village / Dappankuthu
  // 7: Uplifting / Motivation / Victory

  static const SemanticVector zero = SemanticVector([0, 0, 0, 0, 0, 0, 0, 0]);

  bool get isZero => values.every((v) => v == 0.0);

  /// Computes the magnitude (L2 Euclidean norm) of the vector.
  double get magnitude {
    double sum = 0.0;
    for (final v in values) {
      sum += v * v;
    }
    return math.sqrt(sum);
  }

  /// Returns an L2-normalized unit vector.
  SemanticVector normalized() {
    final mag = magnitude;
    if (mag == 0.0) return zero;
    return SemanticVector(values.map((v) => v / mag).toList(growable: false));
  }

  /// Computes the Cosine Similarity between this vector and [other] in [-1.0, 1.0].
  double cosineSimilarity(SemanticVector other) {
    final magA = magnitude;
    final magB = other.magnitude;
    if (magA == 0.0 || magB == 0.0) return 0.0;

    double dotProduct = 0.0;
    final len = math.min(values.length, other.values.length);
    for (int i = 0; i < len; i++) {
      dotProduct += values[i] * other.values[i];
    }
    return (dotProduct / (magA * magB)).clamp(-1.0, 1.0);
  }
}

/// Lightweight On-Device Semantic Search & Intent Vector Embeddings Engine.
///
/// Converts unstructured natural language intent (e.g. "rainy night sad drive",
/// "high energy gym kuthu", "acoustic 90s melody") into dense concept vectors
/// and scores music candidates using cosine similarity.
class SemanticSearchService {
  SemanticSearchService._();
  static final SemanticSearchService instance = SemanticSearchService._();

  // Concept vocabulary mapping keywords to dimension weights: (dimension_index, weight)
  static final Map<String, List<MapEntry<int, double>>> _conceptLexicon = {
    // 0: Energy / Workout / Mass
    'energy': [const MapEntry(0, 1.0)],
    'workout': [const MapEntry(0, 1.0)],
    'gym': [const MapEntry(0, 1.0)],
    'kuthu': [const MapEntry(0, 0.9), const MapEntry(6, 0.8)],
    'mass': [const MapEntry(0, 0.9)],
    'beat': [const MapEntry(0, 0.8)],
    'fast': [const MapEntry(0, 0.7)],
    'dance': [const MapEntry(0, 0.9)],
    'party': [const MapEntry(0, 0.9)],
    'edm': [const MapEntry(0, 0.9)],

    // 1: Melancholy / Sadness / Heartbreak
    'sad': [const MapEntry(1, 1.0)],
    'sogam': [const MapEntry(1, 1.0)],
    'heartbreak': [const MapEntry(1, 1.0)],
    'crying': [const MapEntry(1, 0.9)],
    'cry': [const MapEntry(1, 0.9)],
    'alone': [const MapEntry(1, 0.8), const MapEntry(3, 0.5)],
    'pain': [const MapEntry(1, 0.9)],
    'breakup': [const MapEntry(1, 1.0)],
    'depressed': [const MapEntry(1, 0.9)],
    'lonely': [const MapEntry(1, 0.9), const MapEntry(3, 0.6)],

    // 2: Romance / Love / Melody
    'love': [const MapEntry(2, 1.0)],
    'romantic': [const MapEntry(2, 1.0)],
    'romance': [const MapEntry(2, 1.0)],
    'kaadhal': [const MapEntry(2, 1.0)],
    'kadhal': [const MapEntry(2, 1.0)],
    'melody': [const MapEntry(2, 0.8), const MapEntry(3, 0.6)],
    'sweet': [const MapEntry(2, 0.7)],
    'duet': [const MapEntry(2, 0.9)],

    // 3: Chill / Lo-fi / Rainy / Late Night
    'chill': [const MapEntry(3, 1.0)],
    'rain': [const MapEntry(3, 0.9), const MapEntry(1, 0.4)],
    'rainy': [const MapEntry(3, 0.9), const MapEntry(1, 0.4)],
    'night': [const MapEntry(3, 0.8)],
    'late': [const MapEntry(3, 0.8)],
    'drive': [const MapEntry(3, 0.7)],
    'lofi': [const MapEntry(3, 1.0)],
    'calm': [const MapEntry(3, 0.9)],
    'peaceful': [const MapEntry(3, 0.9)],
    'acoustic': [const MapEntry(3, 0.9), const MapEntry(2, 0.5)],
    'slow': [const MapEntry(3, 0.8), const MapEntry(1, 0.4)],
    'sleep': [const MapEntry(3, 1.0)],

    // 4: Devotional / Spiritual / Bhakti
    'devotional': [const MapEntry(4, 1.0)],
    'god': [const MapEntry(4, 1.0)],
    'bhakti': [const MapEntry(4, 1.0)],
    'temple': [const MapEntry(4, 0.9)],
    'prayer': [const MapEntry(4, 0.9)],
    'divine': [const MapEntry(4, 0.9)],
    'slokam': [const MapEntry(4, 0.9)],
    'bhajan': [const MapEntry(4, 1.0)],

    // 5: Retro / Golden Era (80s, 90s)
    'retro': [const MapEntry(5, 1.0)],
    'vintage': [const MapEntry(5, 1.0)],
    'classic': [const MapEntry(5, 0.9)],
    '80s': [const MapEntry(5, 1.0)],
    '90s': [const MapEntry(5, 1.0)],
    'golden': [const MapEntry(5, 0.8)],
    'old': [const MapEntry(5, 0.9)],

    // 6: Folk / Village / Dappankuthu
    'folk': [const MapEntry(6, 1.0)],
    'village': [const MapEntry(6, 0.9)],
    'gramathu': [const MapEntry(6, 1.0)],
    'thiruvizha': [const MapEntry(6, 0.9), const MapEntry(0, 0.7)],
    'dappankuthu': [const MapEntry(6, 1.0), const MapEntry(0, 0.9)],

    // 7: Uplifting / Motivation / Victory
    'motivation': [const MapEntry(7, 1.0), const MapEntry(0, 0.7)],
    'motivational': [const MapEntry(7, 1.0), const MapEntry(0, 0.7)],
    'inspire': [const MapEntry(7, 0.9)],
    'victory': [const MapEntry(7, 1.0), const MapEntry(0, 0.8)],
    'success': [const MapEntry(7, 0.8)],
    'hope': [const MapEntry(7, 0.9), const MapEntry(2, 0.4)],
  };

  /// Projects a search query string into an 8D [SemanticVector].
  /// Returns null if the query contains no recognized mood/semantic intent keywords.
  SemanticVector? projectQuery(String query) {
    final clean = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    final tokens = clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);

    final List<double> vec = List<double>.filled(SemanticVector.dimensions, 0.0);
    bool hasMatch = false;

    for (final token in tokens) {
      final entries = _conceptLexicon[token];
      if (entries != null) {
        hasMatch = true;
        for (final entry in entries) {
          vec[entry.key] += entry.value;
        }
      }
    }

    if (!hasMatch) return null;
    return SemanticVector(vec).normalized();
  }

  /// Projects a [Song] metadata and attributes into an 8D [SemanticVector].
  SemanticVector projectSong(Song song) {
    final text = '${song.title} ${song.artist} ${song.album} ${song.matchedLyricSnippet ?? ""}'.toLowerCase();
    final clean = text.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    final tokens = clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);

    final List<double> vec = List<double>.filled(SemanticVector.dimensions, 0.0);

    for (final token in tokens) {
      final entries = _conceptLexicon[token];
      if (entries != null) {
        for (final entry in entries) {
          vec[entry.key] += entry.value;
        }
      }
    }

    // Artist heuristic boosts for regional creators
    final artistLower = song.artist.toLowerCase();
    if (artistLower.contains('anirudh') || artistLower.contains('santhosh narayanan')) {
      vec[0] += 0.5; // High energy / modern beats
    }
    if (artistLower.contains('ilaiyaraaja') || artistLower.contains('spb') || artistLower.contains('janaki')) {
      vec[5] += 0.7; // Retro / Golden era
    }
    if (artistLower.contains('sid sriram') || artistLower.contains('pradeep kumar')) {
      vec[2] += 0.6; // Romance / Melody
      vec[3] += 0.5; // Soulful / Chill
    }

    return SemanticVector(vec).normalized();
  }

  /// Calculates the semantic relevance score between a song and a query vector in [0.0, 1.0].
  double scoreSong(Song song, SemanticVector queryVec) {
    if (queryVec.isZero) return 0.0;
    final songVec = projectSong(song);
    if (songVec.isZero) return 0.0;

    final sim = queryVec.cosineSimilarity(songVec);
    return math.max(0.0, sim);
  }

  /// Re-ranks a list of songs by cosine semantic intent when the query contains mood keywords.
  List<Song> rankBySemanticIntent(
    List<Song> songs,
    String query, {
    double threshold = 0.20,
  }) {
    final queryVec = projectQuery(query);
    if (queryVec == null || queryVec.isZero) {
      return songs; // No mood intent; keep original relevance order
    }

    final scored = songs.map((s) {
      final score = scoreSong(s, queryVec);
      return MapEntry(s, score);
    }).toList();

    // Partition by threshold first to avoid non-transitive comparator contract violations
    final highScoring = <MapEntry<Song, double>>[];
    final remaining = <Song>[];

    for (final entry in scored) {
      if (entry.value >= threshold) {
        highScoring.add(entry);
      } else {
        remaining.add(entry.key);
      }
    }

    // Sort songs with high semantic similarity higher, preserving relative order of remaining
    highScoring.sort((a, b) => b.value.compareTo(a.value));

    return [...highScoring.map((e) => e.key), ...remaining];
  }
}
