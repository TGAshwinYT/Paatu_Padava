part of 'song_repository.dart';

Future<Map<String, dynamic>?> _getAlbumDetailsImpl({
  required String albumId,
  required String albumTitle,
}) async {
  String targetId = albumId.trim();
  String? imageUrl;

  if (targetId.isEmpty || !RegExp(r'^\d+$').hasMatch(targetId)) {
    try {
      final searchAlbs = await SaavnClient.searchAlbums(albumTitle, limit: 15);
      if (searchAlbs.isNotEmpty) {
        final cleanTitle = albumTitle.toLowerCase().trim();
        final match = searchAlbs.firstWhere(
          (a) {
            final t = (a['title'] ?? a['name'] ?? '').toString().toLowerCase().trim();
            return t == cleanTitle || t.contains(cleanTitle) || cleanTitle.contains(t);
          },
          orElse: () => searchAlbs.first,
        );
        targetId = match['id']?.toString() ?? '';
        final matchImg = match['image']?.toString() ?? '';
        if (matchImg.isNotEmpty) imageUrl = matchImg;
      }
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
  }

  List<Song> songs = [];
  Map<String, dynamic>? details;

  if (targetId.isNotEmpty && RegExp(r'^\d+$').hasMatch(targetId)) {
    details = await SaavnClient.getAlbumDetails(targetId);
    if (details != null) {
      final albImage = details['image']?.toString() ?? '';
      if (albImage.isNotEmpty) imageUrl = albImage;
      if (details['songs'] is List<Song>) songs = details['songs'] as List<Song>;
    }
  }

  if (songs.isEmpty) {
    try {
      final localSongs = await CatalogDatabase.getSongsByMovie(albumTitle);
      if (localSongs.isNotEmpty) {
        songs.addAll(localSongs);
        if (imageUrl == null || imageUrl.isEmpty) imageUrl = localSongs.first.coverUrl;
      }
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
  }

  if (songs.isEmpty) {
    final searchResults = await SaavnClient.search(albumTitle, limit: 20);
    final cleanAlbum = albumTitle.toLowerCase().trim();
    songs = searchResults.where((s) {
      return s.album.toLowerCase().trim().contains(cleanAlbum) ||
          cleanAlbum.contains(s.album.toLowerCase().trim());
    }).toList();
    if (songs.isEmpty) songs = searchResults;
  }

  if (songs.length <= 2) {
    try {
      String cleanMovieName = '';
      final fromPattern = RegExp(
        r'(?:from|ost|soundtrack)\s*["\u201C\u2018\x27]?([^"\x27\)\u201D\u2019]+)',
        caseSensitive: false,
      );
      final matchInTitle = fromPattern.firstMatch(albumTitle);
      if (matchInTitle != null) cleanMovieName = matchInTitle.group(1)?.trim() ?? '';
      if (cleanMovieName.isEmpty && songs.isNotEmpty) {
        final matchInAlbum = fromPattern.firstMatch(songs.first.album);
        if (matchInAlbum != null) cleanMovieName = matchInAlbum.group(1)?.trim() ?? '';
        if (cleanMovieName.isEmpty) {
          final matchInSongTitle = fromPattern.firstMatch(songs.first.title);
          if (matchInSongTitle != null) cleanMovieName = matchInSongTitle.group(1)?.trim() ?? '';
        }
      }
      if (cleanMovieName.isEmpty) {
        cleanMovieName = albumTitle
            .replaceAll(RegExp(r'\s*-\s*(Tamil|Telugu|Hindi|Malayalam|Kannada).*$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*\((From|OST|Original|Soundtrack).*\)', caseSensitive: false), '')
            .trim();
      }

      if (cleanMovieName.isNotEmpty && cleanMovieName.length >= 2) {
        String detectedLang = (details?['language'] ?? '').toString().toLowerCase().trim();
        if (detectedLang.isEmpty && songs.isNotEmpty && songs.first.language != null) {
          detectedLang = songs.first.language!.toLowerCase().trim();
        }
        if (detectedLang.isEmpty) {
          final lowerTitle = albumTitle.toLowerCase();
          for (final l in ['tamil', 'telugu', 'hindi', 'malayalam', 'kannada']) {
            if (lowerTitle.contains(l)) { detectedLang = l; break; }
          }
        }
        if (detectedLang.isEmpty) {
          detectedLang = SettingsManager.preferredLanguages.isNotEmpty
              ? SettingsManager.preferredLanguages.first.toLowerCase().trim()
              : 'tamil';
        }

        final extraSongs = await SaavnClient.search('$cleanMovieName $detectedLang'.trim(), limit: 30);
        final cleanBase = cleanMovieName.toLowerCase();
        for (final es in extraSongs) {
          final tLower = es.title.toLowerCase();
          final aLower = es.album.toLowerCase();
          if (!SongRepository.isLanguageMismatch(es, detectedLang) &&
              (tLower.contains(cleanBase) || aLower.contains(cleanBase)) &&
              !songs.any((x) => x.id == es.id)) {
            songs.add(es);
          }
        }
      }
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
  }

  imageUrl = (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.contains('default'))
      ? imageUrl
      : (CatalogDatabase.getMoviePoster(albumTitle) ?? (songs.isNotEmpty ? songs.first.coverUrl : ''));

  return {
    'id': targetId,
    'image': imageUrl,
    'songs': SongRepository.deduplicateSongs(songs),
  };
}

Future<Map<String, dynamic>> _getArtistDiscographyImpl({
  required String artistId,
  required String artistName,
}) async {
  String? resolvedImageUrl;
  try {
    final saavnArtists = await SaavnClient.searchArtists(artistName, limit: 3);
    for (final a in saavnArtists) {
      final img = a['image']?.toString();
      if (img != null && img.isNotEmpty && !img.contains('default')) {
        resolvedImageUrl = img;
        break;
      }
    }
  } catch (e) {
    AppLogger.debug('SongRepository', 'Handled exception: $e');
  }

  final List<Song> gathered = [];
  try {
    gathered.addAll(await CatalogDatabase.getSongsByArtist(artistName));
  } catch (e) {
    AppLogger.debug('SongRepository', 'Handled exception: $e');
  }

  try {
    final futures = <Future<List<Song>>>[];
    if (artistId.trim().isNotEmpty) {
      futures.add(
        SaavnClient.getArtistDetails(artistId.trim())
            .then((d) => (d?['songs'] as List<Song>?) ?? <Song>[])
            .catchError((_) => <Song>[]),
      );
    }
    futures.add(SaavnClient.search('$artistName Hit Songs', limit: 40).catchError((_) => <Song>[]));
    futures.add(SaavnClient.search(artistName, limit: 40).catchError((_) => <Song>[]));
    futures.add(YouTubeClient.search('$artistName Songs', limit: 25).catchError((_) => <Song>[]));

    final results = await Future.wait(futures);
    for (final list in results) {
      gathered.addAll(list);
    }
  } catch (e) {
    AppLogger.log('SongRepository', 'Error loading artist discography: $e');
  }

  var uniqueSongs = SongRepository.deduplicateSongs(gathered);
  if (uniqueSongs.isEmpty) {
    try {
      uniqueSongs = SongRepository.deduplicateSongs(await SaavnClient.search(artistName, limit: 30));
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
  }

  final cleanTarget = artistName.trim().toLowerCase();
  final verifiedSongs = uniqueSongs.where((s) {
    return ArtistSanitizer.areSameOrVariantArtists(s.artist, artistName) ||
        s.artist.toLowerCase().contains(cleanTarget) ||
        s.title.toLowerCase().contains(cleanTarget) ||
        s.album.toLowerCase().contains(cleanTarget);
  }).toList();
  if (verifiedSongs.isNotEmpty) uniqueSongs = verifiedSongs;

  if (resolvedImageUrl == null || resolvedImageUrl.isEmpty) {
    final norm = SongRepository.normalizeArtist(artistName);
    if (SongRepository._verifiedArtistAvatars.containsKey(norm)) {
      resolvedImageUrl = SongRepository._verifiedArtistAvatars[norm];
    }
  }

  return {'image': resolvedImageUrl ?? '', 'songs': uniqueSongs};
}
