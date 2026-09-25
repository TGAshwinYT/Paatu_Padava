import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:html_unescape/html_unescape.dart';

class Song {
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Robust helper to unescape HTML entities like &quot;, &#039;, &amp;, etc.
  static String sanitize(dynamic text, {String fallback = ''}) {
    if (text == null) return fallback;
    final str = text.toString();
    if (str.isEmpty) return fallback;
    try {
      return _unescape.convert(str);
    } catch (_) {
      return str;
    }
  }

  final String id;
  final String title;
  final String artist;
  final String album;
  final String? albumId;
  final String? artistId;
  final String coverUrl;
  String? streamUrl;
  final int duration;
  bool isDownloaded;
  String? localFilePath;
  int? downloadedAt;
  final String source; // 'saavn', 'youtube', 'offline'
  String? lyrics;
  final String? language;
  final bool isSmartRecommended;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
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
  });

  /// Canonical deduplication key: normalizes title and artist to match tracks across sources
  String get deduplicationKey => '${title.trim().toLowerCase()}_${artist.trim().toLowerCase()}';

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
    };
  }

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    return Song(
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

  factory Song.fromJson(String source) => Song.fromMap(json.decode(source));

  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      album: album,
      title: title,
      artist: artist,
      duration: Duration(seconds: duration),
      artUri: Uri.tryParse(coverUrl),
      extras: {
        'source': source,
        'streamUrl': streamUrl,
        'isSmartRecommended': isSmartRecommended,
        'language': language,
      },
    );
  }

  factory Song.fromMediaItem(MediaItem item) {
    return Song(
      id: item.id,
      title: item.title,
      artist: item.artist ?? '',
      album: item.album ?? '',
      coverUrl: item.artUri?.toString() ?? '',
      duration: item.duration?.inSeconds ?? 0,
      streamUrl: item.extras?['streamUrl']?.toString(),
      source: item.extras?['source']?.toString() ?? 'saavn',
      language: item.extras?['language']?.toString(),
      isSmartRecommended: item.extras?['isSmartRecommended'] == true,
    );
  }

  Song copyWith({
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
    return Song(
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
}
