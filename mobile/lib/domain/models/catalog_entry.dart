import '../../models/song.dart';

/// Clean model representing a verified film in the Master Movie Catalog
class CatalogMovie {
  final String id;
  final String title;
  final int year;
  final String composer;
  final String starring;
  final String? director;
  final String language;
  final String? coverUrl;

  const CatalogMovie({
    required this.id,
    required this.title,
    required this.year,
    required this.composer,
    required this.starring,
    this.director,
    this.language = 'tamil',
    this.coverUrl,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'year': year,
    'composer': composer,
    'starring': starring,
    'director': director,
    'language': language,
    'cover_url': coverUrl,
  };

  factory CatalogMovie.fromMap(Map<String, dynamic> map) => CatalogMovie(
    id: map['id']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    year: int.tryParse(map['year']?.toString() ?? '0') ?? 0,
    composer: map['composer']?.toString() ?? '',
    starring: map['starring']?.toString() ?? '',
    director: map['director']?.toString(),
    language: map['language']?.toString() ?? 'tamil',
    coverUrl: map['cover_url']?.toString(),
  );
}

/// Clean model representing a verified musical artist (Composer, Playback Singer, Lyricist)
class CatalogArtist {
  final String id;
  final String name;
  final String role; // 'Composer', 'Playback Singer', 'Lyricist'
  final String imageUrl;
  final bool isVerified;

  const CatalogArtist({
    required this.id,
    required this.name,
    this.role = 'Playback Singer',
    this.imageUrl = '',
    this.isVerified = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'role': role,
    'image_url': imageUrl,
    'is_verified': isVerified ? 1 : 0,
  };

  factory CatalogArtist.fromMap(Map<String, dynamic> map) => CatalogArtist(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    role: map['role']?.toString() ?? 'Playback Singer',
    imageUrl: map['image_url']?.toString() ?? '',
    isVerified: (map['is_verified'] == 1 || map['is_verified'] == true),
  );
}

/// Curated film track with strict separation of roles:
/// - [composer]: The music director who scored the song
/// - [singers]: The actual vocalists who performed the track
/// - [starring]: The film cast (actors/actresses) appearing on screen
class CatalogSong {
  final String id;
  final String title;
  final String movieTitle;
  final String? movieId;
  final String composer;
  final String singers;
  final String starring;
  final int year;
  final int duration;
  final String coverUrl;
  final String? audioUrl;
  final String source;
  final String language;
  final bool isDynamic; // True if write-through ingested from live search
  final int createdAt;

  const CatalogSong({
    required this.id,
    required this.title,
    required this.movieTitle,
    this.movieId,
    required this.composer,
    required this.singers,
    required this.starring,
    required this.year,
    this.duration = 0,
    required this.coverUrl,
    this.audioUrl,
    this.source = 'saavn',
    this.language = 'tamil',
    this.isDynamic = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'movie_title': movieTitle,
    'movie_id': movieId,
    'composer': composer,
    'singers': singers,
    'starring': starring,
    'year': year,
    'duration': duration,
    'cover_url': coverUrl,
    'audio_url': audioUrl,
    'source': source,
    'language': language,
    'is_dynamic': isDynamic ? 1 : 0,
    'created_at': createdAt,
  };

  factory CatalogSong.fromMap(Map<String, dynamic> map) => CatalogSong(
    id: map['id']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    movieTitle: map['movie_title']?.toString() ?? '',
    movieId: map['movie_id']?.toString(),
    composer: map['composer']?.toString() ?? '',
    singers: map['singers']?.toString() ?? '',
    starring: map['starring']?.toString() ?? '',
    year: int.tryParse(map['year']?.toString() ?? '0') ?? 0,
    duration: int.tryParse(map['duration']?.toString() ?? '0') ?? 0,
    coverUrl: map['cover_url']?.toString() ?? '',
    audioUrl: map['audio_url']?.toString(),
    source: map['source']?.toString() ?? 'saavn',
    language: map['language']?.toString() ?? 'tamil',
    isDynamic: (map['is_dynamic'] == 1 || map['is_dynamic'] == true),
    createdAt: int.tryParse(map['created_at']?.toString() ?? '0') ?? 0,
  );

  /// Converts catalog song entry to unified runtime [Song] entity
  Song toSong() {
    // Primary credit shows genuine singers, or composer if singers uncredited
    final credit = singers.isNotEmpty ? singers : composer;
    return Song(
      id: id,
      title: title,
      artist: credit,
      album: movieTitle.isNotEmpty ? movieTitle : 'Single',
      coverUrl: coverUrl,
      streamUrl: audioUrl,
      duration: duration,
      source: source,
      language: language,
    );
  }
}
