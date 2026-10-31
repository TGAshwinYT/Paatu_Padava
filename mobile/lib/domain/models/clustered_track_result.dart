import '../../models/song.dart';

/// Categorization of search candidates based on audio authority and intent.
enum ContentClassification {
  /// Studio release from JioSaavn 320kbps or YouTube Music Official Audio / Topic track.
  officialTrack,

  /// Remix, Mashup, Slowed+Reverb, 8D, BGM, Lo-Fi, Live Cover, or Fan Creation.
  fanMixOrVersion,

  /// Non-music video: Movie reviews, public reactions, interviews, press meets, trailers, shorts.
  rejectedJunk,
}

/// Clustered search result node grouping official studio tracks with child fan mixes.
class ClusteredTrackResult {
  final Song primaryTrack;
  final ContentClassification category;
  final double confidenceScore; // 0.0 to 1.0 (relevance & authority)
  final List<Song> alternateVersions;

  const ClusteredTrackResult({
    required this.primaryTrack,
    required this.category,
    required this.confidenceScore,
    this.alternateVersions = const [],
  });

  bool get hasAlternateVersions => alternateVersions.isNotEmpty;

  ClusteredTrackResult copyWith({
    Song? primaryTrack,
    ContentClassification? category,
    double? confidenceScore,
    List<Song>? alternateVersions,
  }) {
    return ClusteredTrackResult(
      primaryTrack: primaryTrack ?? this.primaryTrack,
      category: category ?? this.category,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      alternateVersions: alternateVersions ?? this.alternateVersions,
    );
  }
}

/// Types of music collections in search results.
enum CollectionType {
  album,
  playlist,
  vibeMix,
}

/// Lightweight collection summary for two-phase lazy track hydration.
class CollectionSummary {
  final String id;
  final String title;
  final String subtitle;
  final String artworkUrl;
  final CollectionType type;
  final int? trackCount;

  const CollectionSummary({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    required this.type,
    this.trackCount,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'artworkUrl': artworkUrl,
        'type': type.name,
        'trackCount': trackCount,
      };

  factory CollectionSummary.fromMap(Map<String, dynamic> map) {
    return CollectionSummary(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      subtitle: map['subtitle']?.toString() ?? '',
      artworkUrl: map['artworkUrl']?.toString() ?? map['image']?.toString() ?? '',
      type: CollectionType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => CollectionType.album,
      ),
      trackCount: (map['trackCount'] as num?)?.toInt(),
    );
  }
}

/// Immutable classified search payload cached in LRU cache for 0ms in-memory filter pill switching.
class ClassifiedSearchPayload {
  final String query;
  final List<ClusteredTrackResult> clusteredSongs;
  final List<CollectionSummary> albums;
  final List<CollectionSummary> playlists;
  final List<Map<String, dynamic>> artists;
  final ClusteredTrackResult? topResult;
  final String? didYouMean;

  const ClassifiedSearchPayload({
    required this.query,
    this.clusteredSongs = const [],
    this.albums = const [],
    this.playlists = const [],
    this.artists = const [],
    this.topResult,
    this.didYouMean,
  });

  bool get isEmpty =>
      clusteredSongs.isEmpty && albums.isEmpty && playlists.isEmpty && artists.isEmpty && topResult == null;

  /// Filters official studio songs only.
  List<ClusteredTrackResult> get officialSongs =>
      clusteredSongs.where((c) => c.category == ContentClassification.officialTrack).toList();

  /// Filters fanbase mixes, mashups, and BGMs.
  List<Song> get mixesAndBgm {
    final List<Song> list = [];
    for (final c in clusteredSongs) {
      if (c.category == ContentClassification.fanMixOrVersion) {
        list.add(c.primaryTrack);
      }
      list.addAll(c.alternateVersions);
    }
    return list;
  }
}
