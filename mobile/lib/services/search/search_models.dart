import '../../domain/models/app_error.dart';
import '../../models/song.dart';
import '../../data/repositories/song_repository.dart';
import '../favorites_manager.dart';
import '../history_manager.dart';

class RankSortKey {
  final double score;
  final int langMatch;
  final int albumMatch;
  final int exactMatch;
  final int titleMatch;
  final int isStudio;
  final int hasArt;
  final int arrivalIdx;
  final String albLower;
  final Song song;

  const RankSortKey({
    required this.score,
    required this.langMatch,
    required this.albumMatch,
    required this.exactMatch,
    required this.titleMatch,
    required this.isStudio,
    required this.hasArt,
    required this.arrivalIdx,
    required this.albLower,
    required this.song,
  });
}

class QueryIntent {
  final String rawQuery;
  final String cleanQuery;
  final String coreSubject;
  final String? detectedScript;
  final String? explicitLanguage;
  final String transliteratedQuery;
  final bool isRemixIntent;
  final String? didYouMeanSuggestion;
  final String? universalPhoneticVariant;

  const QueryIntent({
    required this.rawQuery,
    required this.cleanQuery,
    this.coreSubject = '',
    this.detectedScript,
    this.explicitLanguage,
    required this.transliteratedQuery,
    this.isRemixIntent = false,
    this.didYouMeanSuggestion,
    this.universalPhoneticVariant,
  });

  String get effectiveCoreQuery => coreSubject.isNotEmpty ? coreSubject : cleanQuery;
  String? get detectedLanguage => detectedScript;
  String? get explicitLanguageOverride => explicitLanguage?.toLowerCase();

  QueryIntent copyWith({
    String? rawQuery,
    String? cleanQuery,
    String? coreSubject,
    String? detectedScript,
    String? explicitLanguage,
    String? transliteratedQuery,
    bool? isRemixIntent,
    String? didYouMeanSuggestion,
    String? universalPhoneticVariant,
  }) {
    return QueryIntent(
      rawQuery: rawQuery ?? this.rawQuery,
      cleanQuery: cleanQuery ?? this.cleanQuery,
      coreSubject: coreSubject ?? this.coreSubject,
      detectedScript: detectedScript ?? this.detectedScript,
      explicitLanguage: explicitLanguage,
      transliteratedQuery: transliteratedQuery ?? this.transliteratedQuery,
      isRemixIntent: isRemixIntent ?? this.isRemixIntent,
      didYouMeanSuggestion: didYouMeanSuggestion ?? this.didYouMeanSuggestion,
      universalPhoneticVariant: universalPhoneticVariant ?? this.universalPhoneticVariant,
    );
  }
}

class SearchResults {
  final List<Song> songs;
  final List<Song> ytSongs;
  final List<Song> saavnSongs;
  final List<Song> audiusSongs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> playlists;
  final Map<String, dynamic>? topResult;
  final String? didYouMean;
  final AppError? error;
  final bool isFinal;
  final bool isCached;
  final bool isOfflineResult;

  SearchResults({
    this.songs = const [],
    this.ytSongs = const [],
    this.saavnSongs = const [],
    this.audiusSongs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.topResult,
    this.didYouMean,
    this.error,
    this.isFinal = false,
    this.isCached = false,
    this.isOfflineResult = false,
  });

  bool get isEmpty =>
      songs.isEmpty &&
      ytSongs.isEmpty &&
      saavnSongs.isEmpty &&
      audiusSongs.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty;
  bool get hasError => error != null;
}

/// Bundle containing text completions, matching songs, and matching albums for active typing.
class SearchTypeaheadBundle {
  final List<String> completions;
  final List<Song> songs;
  final List<Map<String, dynamic>> albums;

  const SearchTypeaheadBundle({
    this.completions = const [],
    this.songs = const [],
    this.albums = const [],
  });

  List<String> get suggestions => completions;
  bool get isEmpty => completions.isEmpty && songs.isEmpty && albums.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// Precomputed immutable context for O(1) user affinity lookups during multi-song ranking.
class UserAffinityContext {
  final Set<String> favoriteIds;
  final Set<String> favoriteArtists;
  final Set<String> favoriteAlbums;
  final Map<String, int> historyArtistPlayCounts;
  final Map<String, int> historyAlbumPlayCounts;
  final Set<String> historySongIds;

  const UserAffinityContext({
    required this.favoriteIds,
    required this.favoriteArtists,
    required this.favoriteAlbums,
    required this.historyArtistPlayCounts,
    required this.historyAlbumPlayCounts,
    required this.historySongIds,
  });

  factory UserAffinityContext.fromSongs({List<Song>? favorites, List<Song>? history}) {
    final favs = favorites ?? (FavoritesManager.favoritesNotifier.value);
    final hist = history ?? (HistoryManager.historyNotifier.value);

    final favIds = <String>{};
    final favArtists = <String>{};
    final favAlbums = <String>{};

    for (final f in favs) {
      favIds.add(f.id);
      final art = f.primaryArtist.toLowerCase().trim();
      if (art.isNotEmpty) {
        favArtists.add(art);
        favArtists.add(SongRepository.normalizeArtist(f.artist).toLowerCase().trim());
      }
      final alb = f.album.toLowerCase().trim();
      if (alb.isNotEmpty && alb != 'studio album' && alb != 'single' && alb != 'unknown') {
        favAlbums.add(alb);
      }
    }

    final histSongIds = <String>{};
    final histArtistCounts = <String, int>{};
    final histAlbumCounts = <String, int>{};

    for (final h in hist) {
      histSongIds.add(h.id);
      final art = h.primaryArtist.toLowerCase().trim();
      if (art.isNotEmpty) {
        histArtistCounts[art] = (histArtistCounts[art] ?? 0) + 1;
        final norm = SongRepository.normalizeArtist(h.artist).toLowerCase().trim();
        if (norm != art) histArtistCounts[norm] = (histArtistCounts[norm] ?? 0) + 1;
      }
      final alb = h.album.toLowerCase().trim();
      if (alb.isNotEmpty && alb != 'studio album' && alb != 'single' && alb != 'unknown') {
        histAlbumCounts[alb] = (histAlbumCounts[alb] ?? 0) + 2;
      }
    }

    return UserAffinityContext(
      favoriteIds: favIds,
      favoriteArtists: favArtists,
      favoriteAlbums: favAlbums,
      historyArtistPlayCounts: histArtistCounts,
      historyAlbumPlayCounts: histAlbumCounts,
      historySongIds: histSongIds,
    );
  }

  double computeAffinity(Song song) {
    if (favoriteIds.contains(song.id)) return 1.0;

    final candArtist = song.primaryArtist.toLowerCase().trim();
    final candAlbum = song.album.toLowerCase().trim();

    if (candArtist.isNotEmpty && favoriteArtists.contains(candArtist)) return 1.0;
    if (candAlbum.isNotEmpty && favoriteAlbums.contains(candAlbum)) return 0.95;

    if (historySongIds.contains(song.id)) return 0.90;

    int playCount = 0;
    if (candArtist.isNotEmpty) {
      playCount += historyArtistPlayCounts[candArtist] ?? 0;
    }
    if (candAlbum.isNotEmpty) {
      playCount += historyAlbumPlayCounts[candAlbum] ?? 0;
    }

    if (playCount >= 5) return 1.0;
    if (playCount >= 3) return 0.75;
    if (playCount == 2) return 0.50;
    if (playCount == 1) return 0.25;

    return 0.0;
  }
}
