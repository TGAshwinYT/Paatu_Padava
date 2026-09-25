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
    final str = text.toString();
    if (str.isEmpty) return fallback;
    try {
      return _unescape.convert(str).trim();
    } catch (_) {
      return str.trim();
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
  })  : title = sanitize(title, fallback: 'Unknown Title'),
        artist = sanitize(artist, fallback: 'Unknown Artist'),
        album = sanitize(album, fallback: 'Unknown Album');

  /// Canonical deduplication key: normalizes title and artist to match tracks across sources
  String get deduplicationKey => '${title.trim().toLowerCase()}_${artist.trim().toLowerCase()}';

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
