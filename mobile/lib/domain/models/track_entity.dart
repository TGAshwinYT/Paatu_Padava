import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../models/song.dart';

/// Unified Clean Architecture Domain Entity for all audio tracks in Paatu Paadava.
/// Guarantees centralized string sanitization, deduplication across multi-source catalogs,
/// and bidirectional interop with audio player handlers and persistence layers.
class TrackEntity {
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Centralized robust string sanitization via HtmlUnescape
  static String sanitize(dynamic text, {String fallback = ''}) {
    if (text == null) return fallback;
    final str = text.toString().trim();
    if (str.isEmpty) return fallback;
    try {
      final unescaped = _unescape.convert(str).trim();
      return unescaped.isEmpty ? fallback : unescaped;
    } catch (_) {
      return str.isEmpty ? fallback : str;
    }
  }

  final String id;
  final String title;
  final String artist;
  final String album;
  final String? albumId;
  final String? artistId;
  final String coverUrl;
  final String? streamUrl;
  final int duration;
  final bool isDownloaded;
  final String? localFilePath;
  final int? downloadedAt;
  final String source; // 'saavn', 'youtube', 'offline'
  final String? lyrics;
  final String? language;
  final bool isSmartRecommended;

  TrackEntity({
    required this.id,
    required String title,
    required String artist,
    String album = '',
    this.albumId,
    this.artistId,
    required this.coverUrl,
    this.streamUrl,
    this.duration = 0,
    this.isDownloaded = false,
    this.localFilePath,
    this.downloadedAt,
    this.source = 'saavn',
    this.lyrics,
    this.language,
    this.isSmartRecommended = false,
    this.versions = const [],
  })  : title = sanitize(title, fallback: 'Unknown Title'),
        artist = sanitize(artist, fallback: 'Unknown Artist'),
        album = sanitize(album, fallback: 'Unknown Album');

  final List<TrackEntity> versions;

  /// Canonical deduplication key: normalizes title and artist to match tracks across sources
  String get deduplicationKey => '${title.trim().toLowerCase()}_${artist.trim().toLowerCase()}';

  /// Primary artist: extracts the first primary artist before commas, ampersands, or feature tags
  String get primaryArtist {
    final lower = artist.toLowerCase();
    final parts = lower.split(RegExp(r'[,&/|]|\bfeat\.?\b|\bft\.?\b|\bwith\b'));
    final first = parts.isNotEmpty ? parts.first.trim() : lower.trim();
    return first.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
  }

  /// Normalized title: strips brackets, parentheses (From film, remix, lofi tags), punctuation
  String get normalizedTitle {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\b(remix|lofi|lo-fi|live|acoustic|cover|soundtrack|ost)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Duration bucketed into 3-second bands (±3s tolerance)
  int get durationBand => (duration > 0) ? (duration / 3).round() * 3 : 0;

  /// Base key for grouping all releases, dubs, and versions of the same song
  String get canonicalBaseKey => '${normalizedTitle}___$primaryArtist';

  /// Strict key for identical recording/track matching (normalized title + primary artist + duration ±3s)
  String get canonicalSongKey => '${normalizedTitle}___${primaryArtist}___$durationBand';

  /// Tags version type like Remix, Lofi, Live, From film, Acoustic, Cover, or Original
  String get versionTag {
    final lower = title.toLowerCase();
    if (lower.contains('remix') || lower.contains('mix') || lower.contains('club')) return 'Remix';
    if (lower.contains('lofi') || lower.contains('lo-fi') || lower.contains('chill') || lower.contains('slowed')) return 'Lofi';
    if (lower.contains('live') || lower.contains('unplugged') || lower.contains('concert')) return 'Live';
    if (lower.contains('acoustic') || lower.contains('piano')) return 'Acoustic';
    if (lower.contains('cover') || lower.contains('tribute')) return 'Cover';
    if (lower.contains('from ') || lower.contains('soundtrack') || lower.contains('film') || lower.contains('ost')) return 'From film';
    return 'Original';
  }

  /// Checks if artwork is official high-res album art rather than a video thumbnail
  bool get hasOfficialAlbumArt {
    if (coverUrl.isEmpty) return false;
    final lower = coverUrl.toLowerCase();
    if (lower.contains('ytimg.com') || lower.contains('youtube.com')) return false;
    return lower.contains('saavncdn.com') || lower.contains('jiosaavn') || source == 'saavn';
  }

  /// Groups versions of the same song into one canonical TrackEntity with attached versions
  static List<TrackEntity> groupTracks(List<TrackEntity> tracks, {String? preferredLanguage}) {
    if (tracks.isEmpty) return [];

    final Map<String, List<TrackEntity>> groups = {};
    for (final track in tracks) {
      final key = track.canonicalBaseKey;
      groups.putIfAbsent(key, () => []).add(track);
    }

    final List<TrackEntity> result = [];
    final prefLangLower = preferredLanguage?.toLowerCase().trim();

    for (final group in groups.values) {
      if (group.isEmpty) continue;

      // Sort group members to elect the best primary track:
      // 1. Prefer official album art (JioSaavn high-res)
      // 2. Prefer JioSaavn source over YouTube
      // 3. Prefer matching preferred language
      // 4. Prefer Original over Remix/Lofi for primary entry
      group.sort((a, b) {
        if (a.hasOfficialAlbumArt && !b.hasOfficialAlbumArt) return -1;
        if (!a.hasOfficialAlbumArt && b.hasOfficialAlbumArt) return 1;

        if (a.source == 'saavn' && b.source != 'saavn') return -1;
        if (a.source != 'saavn' && b.source == 'saavn') return 1;

        if (prefLangLower != null && prefLangLower.isNotEmpty) {
          final aMatch = a.language?.toLowerCase() == prefLangLower;
          final bMatch = b.language?.toLowerCase() == prefLangLower;
          if (aMatch && !bMatch) return -1;
          if (!aMatch && bMatch) return 1;
        }

        final aIsOriginal = a.versionTag == 'Original';
        final bIsOriginal = b.versionTag == 'Original';
        if (aIsOriginal && !bIsOriginal) return -1;
        if (!aIsOriginal && bIsOriginal) return 1;

        return 0;
      });

      final primary = group.first;
      final alternateVersions = group.skip(1).toList();

      result.add(TrackEntity(
        id: primary.id,
        title: primary.title,
        artist: primary.artist,
        album: primary.album,
        albumId: primary.albumId,
        artistId: primary.artistId,
        coverUrl: primary.coverUrl,
        streamUrl: primary.streamUrl,
        duration: primary.duration,
        isDownloaded: primary.isDownloaded,
        localFilePath: primary.localFilePath,
        downloadedAt: primary.downloadedAt,
        source: primary.source,
        lyrics: primary.lyrics,
        language: primary.language,
        isSmartRecommended: primary.isSmartRecommended,
        versions: alternateVersions,
      ));
    }

    return result;
  }

  /// Converts this domain entity to legacy Song model for seamless framework compatibility
  Song toSong() {
    return Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      albumId: albumId,
      artistId: artistId,
      coverUrl: coverUrl,
      streamUrl: streamUrl,
      duration: duration,
      isDownloaded: isDownloaded,
      localFilePath: localFilePath,
      downloadedAt: downloadedAt,
      source: source,
      lyrics: lyrics,
      language: language,
      isSmartRecommended: isSmartRecommended,
      versions: versions.map((v) => v.toSong()).toList(),
    );
  }

  /// Creates a domain TrackEntity from a Song model
  factory TrackEntity.fromSong(Song song) {
    return TrackEntity(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      albumId: song.albumId,
      artistId: song.artistId,
      coverUrl: song.coverUrl,
      streamUrl: song.streamUrl,
      duration: song.duration,
      isDownloaded: song.isDownloaded,
      localFilePath: song.localFilePath,
      downloadedAt: song.downloadedAt,
      source: song.source,
      lyrics: song.lyrics,
      language: song.language,
      isSmartRecommended: song.isSmartRecommended,
      versions: song.versions.map((v) => TrackEntity.fromSong(v)).toList(),
    );
  }

  /// Converts to audio_service MediaItem for lock screen and system notification
  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: duration > 0 ? Duration(seconds: duration) : null,
      artUri: coverUrl.isNotEmpty ? Uri.tryParse(coverUrl) : null,
      extras: {
        'streamUrl': streamUrl,
        'source': source,
        'isDownloaded': isDownloaded,
        'localFilePath': localFilePath,
        'language': language,
        'deduplicationKey': deduplicationKey,
      },
    );
  }

  /// Creates a TrackEntity from an audio_service MediaItem
  factory TrackEntity.fromMediaItem(MediaItem item) {
    return TrackEntity(
      id: item.id,
      title: item.title,
      artist: item.artist ?? 'Unknown Artist',
      album: item.album ?? '',
      duration: item.duration?.inSeconds ?? 0,
      coverUrl: item.artUri?.toString() ?? '',
      streamUrl: item.extras?['streamUrl']?.toString(),
      source: item.extras?['source']?.toString() ?? 'saavn',
      isDownloaded: item.extras?['isDownloaded'] == true,
      localFilePath: item.extras?['localFilePath']?.toString(),
      language: item.extras?['language']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumId': albumId,
      'artistId': artistId,
      'coverUrl': coverUrl,
      'streamUrl': streamUrl,
      'duration': duration,
      'isDownloaded': isDownloaded,
      'localFilePath': localFilePath,
      'downloadedAt': downloadedAt,
      'source': source,
      'lyrics': lyrics,
      'language': language,
      'isSmartRecommended': isSmartRecommended,
      'deduplicationKey': deduplicationKey,
    };
  }

  factory TrackEntity.fromMap(Map<dynamic, dynamic> map) {
    return TrackEntity(
      id: map['id']?.toString() ?? '',
      title: sanitize(map['title'], fallback: 'Unknown Title'),
      artist: sanitize(map['artist'], fallback: 'Unknown Artist'),
      album: sanitize(map['album'], fallback: 'Unknown Album'),
      albumId: map['albumId']?.toString(),
      artistId: map['artistId']?.toString(),
      coverUrl: map['coverUrl']?.toString() ?? '',
      streamUrl: map['streamUrl']?.toString(),
      duration: int.tryParse(map['duration']?.toString() ?? '0') ?? 0,
      isDownloaded: map['isDownloaded'] == true,
      localFilePath: map['localFilePath']?.toString(),
      downloadedAt: int.tryParse(map['downloadedAt']?.toString() ?? '0'),
      source: map['source']?.toString() ?? 'saavn',
      lyrics: map['lyrics'] != null ? sanitize(map['lyrics']) : null,
      language: map['language']?.toString(),
      isSmartRecommended: map['isSmartRecommended'] == true,
    );
  }

  String toJson() => json.encode(toMap());

  factory TrackEntity.fromJson(String source) => TrackEntity.fromMap(json.decode(source));

  TrackEntity copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumId,
    String? artistId,
    String? coverUrl,
    String? streamUrl,
    int? duration,
    bool? isDownloaded,
    String? localFilePath,
    int? downloadedAt,
    String? source,
    String? lyrics,
    String? language,
    bool? isSmartRecommended,
  }) {
    return TrackEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      artistId: artistId ?? this.artistId,
      coverUrl: coverUrl ?? this.coverUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      duration: duration ?? this.duration,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      localFilePath: localFilePath ?? this.localFilePath,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      source: source ?? this.source,
      lyrics: lyrics ?? this.lyrics,
      language: language ?? this.language,
      isSmartRecommended: isSmartRecommended ?? this.isSmartRecommended,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TrackEntity &&
        (other.id == id || other.deduplicationKey == deduplicationKey);
  }

  @override
  int get hashCode => deduplicationKey.hashCode;

  @override
  String toString() => 'TrackEntity(id: $id, title: $title, artist: $artist, source: $source)';
}
