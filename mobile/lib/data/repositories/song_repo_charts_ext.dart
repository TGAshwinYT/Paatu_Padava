part of 'song_repository.dart';

Future<HeroShowcase> _getFlagshipShowcaseImpl({
  required String language,
  String heroMode = 'smart',
}) async {
  final isTamil = language.toLowerCase().trim() == 'tamil';
  final hour = DateTime.now().hour;

  final String timeGreeting;
  final List<Color> dynamicColors;
  if (hour >= 5 && hour < 12) {
    timeGreeting = isTamil ? 'காலை தென்றல் & மெல்லிசை' : 'Morning Acoustic & Melodies';
    dynamicColors = const [Color(0xFF0D9488), Color(0xFF0284C7)];
  } else if (hour >= 12 && hour < 17) {
    timeGreeting = isTamil ? 'மதிய ஓய்வு & இசை அலைகள்' : 'Afternoon Chillout & Flow';
    dynamicColors = const [Color(0xFF7C3AED), Color(0xFFEC4899)];
  } else if (hour >= 17 && hour < 22) {
    timeGreeting = isTamil ? 'மாலை கொண்டாட்டம் & ஹிட்ஸ்' : 'Evening Energy & Chartbusters';
    dynamicColors = const [Color(0xFF6366F1), Color(0xFF06B6D4)];
  } else {
    timeGreeting = isTamil ? 'இரவு அமைதி & லோஃபை' : 'Late Night Synth & Lofi Melodies';
    dynamicColors = const [Color(0xFF1E1B4B), Color(0xFF6B21A8)];
  }

  final String title;
  final String subtitle;
  final String description;
  final List<Color> gradientColors;

  if (heroMode == 'time_of_day') {
    title = '$language • $timeGreeting';
    subtitle = 'Curated soundscape matched to your local hour';
    description = 'Fresh streaming feed • Zero ads • Studio lossless audio';
    gradientColors = dynamicColors;
  } else if (heroMode == 'flagship') {
    title = isTamil ? "Today's Top Tamil Hits" : 'Top 50 • $language';
    subtitle = 'The hottest & most streamed tracks across the industry';
    description = 'Editorial Chart • Updated daily with verified master audio';
    gradientColors = const [Color(0xFF7C3AED), Color(0xFF06B6D4)];
  } else {
    title = isTamil ? "Today's Top Tamil Hits" : 'Top 50 • $language';
    subtitle = '$timeGreeting • Hottest chartbusters right now';
    description = 'Editorial Chart • Pure lossless streaming';
    gradientColors = dynamicColors;
  }

  List<Song> tracks = [];
  try {
    tracks = (await SongRepository.getTrendingMerged(language: language)).take(20).toList();
  } catch (e) {
    AppLogger.log('SongRepository', 'getFlagshipShowcase fallback: $e');
  }

  if (tracks.isEmpty) {
    try {
      final searchHits = await SaavnClient.search('Top $language Hits', limit: 20, language: language);
      tracks = SongRepository.deduplicateSongs(SongRepository.filterByLanguage(searchHits, language));
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
  }

  return HeroShowcase(
    title: title,
    subtitle: subtitle,
    description: description,
    coverUrl: tracks.isNotEmpty ? tracks.first.coverUrl : '',
    gradientColors: gradientColors,
    tracks: tracks,
  );
}

Future<List<RankedChartSong>> _getTop10RankedChartsImpl({required String language}) async {
  List<Song> rawSongs = [];
  try {
    rawSongs = await SongRepository.getTrendingMerged(language: language);
  } catch (e) {
    AppLogger.debug('SongRepository', 'Handled exception: $e');
  }

  if (rawSongs.length < 10) {
    try {
      final searchHits = await SaavnClient.search('Top $language Songs 2025', limit: 15, language: language);
      rawSongs.addAll(SongRepository.filterByLanguage(searchHits, language));
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
  }

  final distinctSongs = SongRepository.ensureDistinctCovers(
    SongRepository.deduplicateSongs(SongRepository.filterByLanguage(rawSongs, language)),
  ).take(10).toList();

  final List<RankedChartSong> ranked = [];
  for (int i = 0; i < distinctSongs.length; i++) {
    final song = distinctSongs[i];
    final rank = i + 1;
    final mod = song.id.hashCode.abs() % 5;
    final int change = rank == 1 ? 0 : (mod == 0 ? 1 : (mod == 1 ? -1 : (mod == 2 ? 2 : 0)));
    final bool isNew = rank != 1 && mod >= 4 && rank >= 7;
    ranked.add(RankedChartSong(rank: rank, song: song, rankChange: change, isNew: isNew));
  }
  return ranked;
}

Future<List<FeelingMix>> _getFeelingMixesImpl({required String language}) async {
  final isTamil = language.toLowerCase().trim() == 'tamil';
  final feelingDefs = [
    {
      'id': 'chill',
      'title': '🌙 Chill & Soul',
      'subtitle': isTamil ? 'மெல்லிசை & அமைதியான பாடல்கள்' : 'Relaxing acoustic & serene melodies',
      'icon': '🌙',
      'gradient': const [Color(0xFF1E1B4B), Color(0xFF4338CA)],
      'query': '$language Chill Acoustic Soul',
    },
    {
      'id': 'romance',
      'title': '❤️ Romantic Beats',
      'subtitle': isTamil ? 'காதல் பாடல்கள் & டூயட்' : 'Heartfelt love tracks & duets',
      'icon': '❤️',
      'gradient': const [Color(0xFF831843), Color(0xFFBE185D)],
      'query': '$language Romantic Love Hits',
    },
    {
      'id': 'kuthu',
      'title': '⚡ High Energy & Kuthu',
      'subtitle': isTamil ? 'குத்து பாட்டு & கொண்டாட்டம்' : 'Electrifying beats & workout power',
      'icon': '⚡',
      'gradient': const [Color(0xFF7C2D12), Color(0xFFEA580C)],
      'query': isTamil ? 'Tamil Kuthu Dance Hits' : '$language High Energy Party Hits',
    },
    {
      'id': 'focus',
      'title': '🎧 Deep Focus & Lofi',
      'subtitle': isTamil ? 'கவனம் & லோஃபை மெல்லிசை' : 'Calm beats & instrumental flow',
      'icon': '🎧',
      'gradient': const [Color(0xFF064E3B), Color(0xFF059669)],
      'query': '$language Lofi Instrumental Calm',
    },
    {
      'id': 'nostalgia',
      'title': '📻 90s & 2000s Nostalgia',
      'subtitle': isTamil ? 'பொற்கால நினைவுகள்' : 'Golden era evergreen classics',
      'icon': '📻',
      'gradient': const [Color(0xFF78350F), Color(0xFFD97706)],
      'query': isTamil ? 'Tamil 90s 2000s Evergreen Hits Ilaiyaraaja Rahman' : '$language 90s Evergreen Hits',
    },
    {
      'id': 'night',
      'title': '🌃 Late Night Drive',
      'subtitle': isTamil ? 'இரவு நேர இசை பயணம்' : 'Atmospheric synths & smooth vocals',
      'icon': '🌃',
      'gradient': const [Color(0xFF0F172A), Color(0xFF581C87)],
      'query': '$language Late Night Drive Midnight',
    },
  ];

  final futures = feelingDefs.map((def) async {
    try {
      final rawSongs = await SaavnClient.search(def['query'] as String, limit: 12, language: language);
      final filtered = SongRepository.ensureDistinctCovers(
        SongRepository.deduplicateSongs(SongRepository.filterByLanguage(rawSongs, language)),
      );
      return FeelingMix(
        feelingId: def['id'] as String,
        title: def['title'] as String,
        subtitle: def['subtitle'] as String,
        icon: def['icon'] as String,
        gradient: def['gradient'] as List<Color>,
        songs: filtered,
      );
    } catch (_) {
      return FeelingMix(
        feelingId: def['id'] as String,
        title: def['title'] as String,
        subtitle: def['subtitle'] as String,
        icon: def['icon'] as String,
        gradient: def['gradient'] as List<Color>,
        songs: const [],
      );
    }
  });

  final results = await Future.wait(futures);
  return results.where((m) => m.songs.isNotEmpty).toList();
}

Future<List<Song>> _getQuickPicksImpl({required String language}) async {
  final List<Song> picks = [];
  try {
    picks.addAll(await SongRepository.getMadeForYou(language: language));
  } catch (e) {
    AppLogger.debug('SongRepository', 'Handled exception: $e');
  }
  if (picks.length < 16) {
    try {
      picks.addAll(await SongRepository.getTrendingMerged(language: language));
    } catch (e) {
      AppLogger.debug('SongRepository', 'Handled exception: $e');
    }
  }
  return SongRepository.ensureDistinctCovers(
    SongRepository.deduplicateSongs(SongRepository.filterByLanguage(picks, language)),
  ).take(16).toList();
}
