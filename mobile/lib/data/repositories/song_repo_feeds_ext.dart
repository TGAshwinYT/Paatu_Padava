part of 'song_repository.dart';

Future<List<Song>> _getMadeForYouImpl({required String language}) async {
  final List<Song> candidates = [];
  final List<String> topArtists = [];
  final Set<String> topArtistsSet = <String>{};

  try {
    final supaUser = SupabaseService.currentUser;
    if (supaUser != null) {
      final favArtists = await SupabaseService.fetchFavoriteArtists(supaUser.id);
      for (final fa in favArtists) {
        final faName = fa['artist_name']?.toString() ?? '';
        final norm = SongRepository.normalizeArtist(faName);
        if (norm.isNotEmpty && topArtistsSet.add(norm)) topArtists.add(norm);
      }
    }
  } catch (e) {
    AppLogger.log('SongRepository', 'Favorite artists fetch notice: $e');
  }

  final history = HistoryManager.getHistory();
  if (history.isNotEmpty) {
    final Map<String, int> artistCounts = {};
    for (final s in history) {
      final norm = SongRepository.normalizeArtist(s.artist);
      if (norm.isNotEmpty && norm != 'various artists') {
        artistCounts[norm] = (artistCounts[norm] ?? 0) + 1;
      }
    }
    final sortedHistoryArtists = artistCounts.keys.toList()
      ..sort((a, b) => (artistCounts[b] ?? 0).compareTo(artistCounts[a] ?? 0));
    for (final ha in sortedHistoryArtists) {
      if (topArtists.length < 5 && topArtistsSet.add(ha)) topArtists.add(ha);
    }
  }

  if (topArtists.isNotEmpty) {
    final artistFutures = topArtists.take(4).map((artistName) {
      return SaavnClient.search('$artistName $language', limit: 8, language: language);
    });
    for (final list in await Future.wait(artistFutures)) {
      candidates.addAll(list);
    }
  }

  try {
    candidates.addAll(await ApiClient.fetchForYou());
  } catch (e) {
    AppLogger.log('SongRepository', 'ApiClient recommendations fallback: $e');
  }

  if (candidates.length < 8) {
    candidates.addAll(await SaavnClient.search('$language Melodies Hits', limit: 15, language: language));
  }

  final filteredCandidates = SongRepository.filterByLanguage(candidates, language);
  final deduplicated = SongRepository.deduplicateSongs(
    filteredCandidates.isNotEmpty ? filteredCandidates : candidates,
  );
  return SongRepository.ensureDistinctCovers(deduplicated);
}

List<Song> _ensureDistinctCoversImpl(List<Song> songs) {
  if (songs.isEmpty) return songs;
  final List<Song> distinct = [];
  for (final song in songs) {
    String finalCover = song.coverUrl.trim();
    if (finalCover.isEmpty) {
      final cached = CoverArtResolver.getCachedCover(song.id);
      if (cached != null && cached.isNotEmpty) {
        finalCover = cached;
      } else if (song.source == 'youtube' || song.id.length == 11) {
        finalCover = 'https://img.youtube.com/vi/${song.id}/hqdefault.jpg';
      }
    }
    if (finalCover.startsWith('http://')) {
      finalCover = finalCover.replaceFirst('http://', 'https://');
    }
    distinct.add(song.copyWith(coverUrl: finalCover));
  }
  return distinct;
}

Future<List<Song>> _getTrendingMergedImpl({required String language}) async {
  final results = await Future.wait([
    SaavnClient.getTrending(language: language),
    ApiClient.fetchYouTubeTrending(language: language),
  ]);
  final saavnSongs = SongRepository.filterByLanguage(results[0], language);
  final ytSongs = SongRepository.filterByLanguage(results[1], language);

  final List<Song> interleaved = [];
  final maxLen = saavnSongs.length > ytSongs.length ? saavnSongs.length : ytSongs.length;
  for (int i = 0; i < maxLen; i++) {
    if (i < saavnSongs.length) interleaved.add(saavnSongs[i]);
    if (i < ytSongs.length) interleaved.add(ytSongs[i]);
  }
  return SongRepository.deduplicateSongs(interleaved);
}

Future<List<Song>> _getNewReleasesImpl({required String language}) async {
  final songs = await SaavnClient.search('Latest $language Releases', limit: 25, language: language);
  final filtered = SongRepository.filterByLanguage(songs, language);
  return SongRepository.deduplicateSongs(filtered.isNotEmpty ? filtered : songs);
}
