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
  final bool isUserEnqueued;
  final String? addedBy;
  final List<Song> versions;

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
    this.isUserEnqueued = false,
    this.addedBy,
    this.versions = const [],
  });

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

  /// Checks whether this song is the same musical recording, cover, or cross-language dub of another song
  bool isSameSongOrDub(Song other) {
    if (id.isNotEmpty && id == other.id) return true;
    if (canonicalBaseKey == other.canonicalBaseKey) return true;
    if (canonicalSongKey == other.canonicalSongKey) return true;

    // Cross-language dub matching:
    // If the composer / primary artist matches and the duration is within ±4 seconds,
    // they represent the same musical piece released in alternate languages.
    final bool sameArtist = primaryArtist.isNotEmpty &&
        other.primaryArtist.isNotEmpty &&
        primaryArtist == other.primaryArtist;
    final bool durationMatch = duration > 0 &&
        other.duration > 0 &&
        (duration - other.duration).abs() <= 4;
    if (sameArtist && durationMatch) return true;

    // Album match with duration within ±4 seconds
    final bool sameAlbum = album.isNotEmpty &&
        other.album.isNotEmpty &&
        album.toLowerCase().trim() == other.album.toLowerCase().trim();
    if (sameAlbum && durationMatch) return true;

    // Title similarity for alternate language tags e.g. "(Telugu)", "(Hindi)", "(Tamil)"
    final lowerTitle = title.toLowerCase();
    final otherLower = other.title.toLowerCase();
    final dubRegex = RegExp(r'\b(telugu|tamil|hindi|kannada|malayalam|dubbed|dub|version)\b');
    if ((dubRegex.hasMatch(lowerTitle) || dubRegex.hasMatch(otherLower)) && durationMatch) {
      return true;
    }

    return false;
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
      'isUserEnqueued': isUserEnqueued,
      'addedBy': addedBy,
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
      isUserEnqueued: map['isUserEnqueued'] == true,
      addedBy: map['addedBy']?.toString() ?? map['added_by']?.toString(),
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
        'isUserEnqueued': isUserEnqueued,
        'language': language,
        'addedBy': addedBy,
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
      isUserEnqueued: item.extras?['isUserEnqueued'] == true,
      addedBy: item.extras?['addedBy']?.toString(),
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
    bool? isUserEnqueued,
    String? addedBy,
    List<Song>? versions,
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
      isUserEnqueued: isUserEnqueued ?? this.isUserEnqueued,
      addedBy: addedBy ?? this.addedBy,
      versions: versions ?? this.versions,
    );
  }
}
