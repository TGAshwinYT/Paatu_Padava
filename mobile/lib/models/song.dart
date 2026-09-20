import 'dart:convert';

class Song {
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
  });

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
    };
  }

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    return Song(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Unknown Title',
      artist: map['artist']?.toString() ?? 'Unknown Artist',
      album: map['album']?.toString() ?? 'Unknown Album',
      albumId: map['albumId']?.toString(),
      artistId: map['artistId']?.toString(),
      coverUrl: map['coverUrl']?.toString() ?? '',
      streamUrl: map['streamUrl']?.toString(),
      duration: int.tryParse(map['duration']?.toString() ?? '0') ?? 0,
      isDownloaded: map['isDownloaded'] == true,
      localFilePath: map['localFilePath']?.toString(),
      downloadedAt: int.tryParse(map['downloadedAt']?.toString() ?? '0'),
      source: map['source']?.toString() ?? 'saavn',
      lyrics: map['lyrics']?.toString(),
    );
  }

  String toJson() => json.encode(toMap());

  factory Song.fromJson(String source) => Song.fromMap(json.decode(source));

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
    );
  }
}
