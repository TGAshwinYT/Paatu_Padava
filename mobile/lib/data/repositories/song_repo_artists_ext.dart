part of 'song_repository.dart';

Future<List<Map<String, dynamic>>> _getPopularArtistsImpl({required String language}) async {
  final isTamil = language.toLowerCase().trim() == 'tamil';

  try {
    final rawArtists = await SaavnClient.searchArtists('Top $language Artists', limit: 16, language: language);
    final List<Map<String, dynamic>> enriched = [];

    for (final artist in rawArtists) {
      if (!SaavnClient.isGenuineMusicArtist(artist)) continue;
      final name = Song.sanitize(artist['name']?.toString() ?? 'Artist');

      // Reject artists with mismatched scripts against target language
      final dummySong = Song(id: '', title: name, artist: name, album: '', coverUrl: '');
      if (SongRepository.isLanguageMismatch(dummySong, language)) continue;

      String img = artist['image']?.toString() ?? '';

      // Check verified high-res avatar map first
      final vAvatar = SongRepository.getVerifiedAvatar(name);
      if (vAvatar.isNotEmpty) {
        img = vAvatar;
      } else if (img.contains('50x50') || img.contains('150x150')) {
        img = img.replaceAll('50x50', '500x500').replaceAll('150x150', '500x500');
      }

      // Never use a song's cover image as an artist profile image
      final isSongCover = img.contains('/albums/') ||
          img.contains('/songs/') ||
          (img.contains('c.saavncdn.com') && !img.contains('/artists/'));
      if (isSongCover) {
        img = vAvatar;
      }

      // Filter out generic placeholder images with camera or mic icons
      if (ArtistSanitizer.isPlaceholderImage(img) && !SongRepository.isArtistVerified(name)) {
        continue;
      }

      enriched.add({
        'id': artist['id']?.toString() ?? '',
        'name': name,
        'image': img,
      });
    }

    // When Tamil is selected, ensure all 7 core Tamil artist seeds are present
    if (isTamil) {
      for (final seed in SongRepository.tamilArtistSeeds.reversed) {
        final existingIdx = enriched.indexWhere((a) =>
            ArtistSanitizer.areSameOrVariantArtists(a['name']?.toString() ?? '', seed));
        final seedAvatar = SongRepository.getVerifiedAvatar(seed);
        if (existingIdx >= 0) {
          final existing = enriched.removeAt(existingIdx);
          existing['name'] = seed;
          if (seedAvatar.isNotEmpty) existing['image'] = seedAvatar;
          enriched.insert(0, existing);
        } else {
          enriched.insert(0, {
            'id': 'seed_${SongRepository.normalizeArtist(seed)}',
            'name': seed,
            'image': seedAvatar,
          });
        }
      }
    }

    // Prioritize user's favorite artists from Supabase
    try {
      final supaUser = SupabaseService.currentUser;
      if (supaUser != null) {
        final favArtists = await SupabaseService.fetchFavoriteArtists(supaUser.id);
        for (final fa in favArtists.reversed) {
          final faName = fa['artist_name']?.toString() ?? '';
          final customImg = fa['artist_image']?.toString();
          final vAvatar = SongRepository.getVerifiedAvatar(faName);
          final avatar = (customImg != null && customImg.isNotEmpty)
              ? customImg
              : (vAvatar.isNotEmpty ? vAvatar : '');
          if (!enriched.any((a) => ArtistSanitizer.areSameOrVariantArtists(a['name']?.toString() ?? '', faName))) {
            enriched.insert(0, {
              'id': 'fav_${SongRepository.normalizeArtist(faName)}',
              'name': faName,
              'image': avatar.isNotEmpty ? avatar : (SongRepository._verifiedArtistAvatars.values.firstOrNull ?? ''),
            });
          }
        }
      }
    } catch (e) {
      AppLogger.log('SongRepository', 'Enriching favorite artists fallback: $e');
    }

    // Deduplicate canonical variants (e.g. "A.R. Rahman" vs "A. R. Rahman")
    final List<Map<String, dynamic>> deduped = [];
    for (final a in enriched) {
      final name = a['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      if (!deduped.any((existing) => ArtistSanitizer.areSameOrVariantArtists(existing['name']?.toString() ?? '', name))) {
        deduped.add(a);
      }
    }

    if (deduped.isNotEmpty) {
      return deduped;
    }
  } catch (e) {
    AppLogger.log('SongRepository', 'getPopularArtists fallback: $e');
  }

  // Verified fallback curated list for South Indian / Tamil music
  if (isTamil) {
    return SongRepository.tamilArtistSeeds.map((seed) {
      final norm = SongRepository.normalizeArtist(seed);
      return {
        'id': 'seed_$norm',
        'name': seed,
        'image': SongRepository._verifiedArtistAvatars[norm] ?? '',
      };
    }).toList();
  }

  return SongRepository._verifiedArtistAvatars.entries.map((e) {
    final titleCaseName = e.key
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
    return {
      'id': e.key,
      'name': titleCaseName,
      'image': e.value,
    };
  }).toList();
}
