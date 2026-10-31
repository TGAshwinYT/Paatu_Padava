import '../domain/models/catalog_entry.dart';
import 'catalog_artists_seed.dart';
import 'catalog_movies_seed.dart';
import 'catalog_songs_seed.dart';

/// Pre-seeded master catalog containing verified South Indian/Tamil cinema discography
/// with 100% accurate role isolation between Composers, Playback Singers, and Cast Members.
class CatalogSeedData {
  static List<CatalogArtist> get initialArtists => CatalogArtistsSeed.data;
  static List<CatalogMovie> get initialMovies => CatalogMoviesSeed.data;
  static List<CatalogSong> get initialSongs => CatalogSongsSeed.data;
}
