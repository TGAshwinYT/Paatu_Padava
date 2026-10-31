import '../models/song.dart';
import '../services/search_service.dart';
import '../services/radio_engine.dart';
import '../services/blacklist_manager.dart';
import '../services/settings_manager.dart';
import '../services/favorites_manager.dart';
import '../services/download_manager.dart';
import '../services/history_manager.dart';
import '../services/youtube_client.dart';
import '../services/app_logger.dart';
import 'search_query_planner.dart';

class MoodPlaylistResult {
  final String title;
  final String description;
  final String prompt;
  final String moodEmoji;
  final List<Song> tracks;

  const MoodPlaylistResult({
    required this.title,
    required this.description,
    required this.prompt,
    required this.moodEmoji,
    required this.tracks,
  });
}

class MoodPlaylistGenerator {
  static const List<Map<String, String>> quickMoodPresets = [
    {
      'title': 'Rainy Evening Calm',
      'prompt': 'rainy evening calm acoustic melodies',
      'emoji': '🌧️',
    },
    {
      'title': 'High Energy Gym',
      'prompt': 'high energy workout motivational beats',
      'emoji': '⚡',
    },
    {
      'title': 'Late Night Drive',
      'prompt': 'late night highway drive soulful hits',
      'emoji': '🌙',
    },
    {
      'title': 'Lofi Study Chill',
      'prompt': 'lofi calm study chill focus melodies',
      'emoji': '🎧',
    },
    {
      'title': 'Romantic Melodies',
      'prompt': 'heartfelt romantic love evergreen melodies',
      'emoji': '❤️',
    },
    {
      'title': '90s Nostalgia',
      'prompt': '90s golden vintage classic hits',
      'emoji': '📻',
    },
    {
      'title': 'Party Dance',
      'prompt': 'dance party club celebration beats',
      'emoji': '💃',
    },
    {
      'title': 'Acoustic Morning',
      'prompt': 'peaceful acoustic coffee morning breeze',
      'emoji': '☕',
    },
  ];

  /// Detects whether user explicitly specified a language in prompt
  static String? detectLanguageInPrompt(String prompt) {
    final lower = prompt.toLowerCase();
    final knownLanguages = [
      'tamil',
      'hindi',
      'telugu',
      'malayalam',
      'kannada',
      'english',
      'punjabi',
      'bengali',
      'marathi',
      'bhojpuri',
      'gujarati',
    ];
    for (final lang in knownLanguages) {
      if (RegExp('\\b$lang\\b').hasMatch(lower)) {
        return lang;
      }
    }
    return null;
  }

  /// Determines an appropriate emoji based on prompt keywords
  static String detectMoodEmoji(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('sad') || lower.contains('cry') || lower.contains('alone') || lower.contains('breakup') || lower.contains('broken')) return '💔';
    if (lower.contains('rain') || lower.contains('monsoon')) return '🌧️';
    if (lower.contains('workout') || lower.contains('gym') || lower.contains('energy') || lower.contains('kuthu')) return '⚡';
    if (lower.contains('night') || lower.contains('drive') || lower.contains('dark')) return '🌙';
    if (lower.contains('lofi') || lower.contains('study') || lower.contains('focus') || lower.contains('calm')) return '🎧';
    if (lower.contains('romance') || lower.contains('love') || lower.contains('heart')) return '❤️';
    if (lower.contains('90') || lower.contains('vintage') || lower.contains('retro') || lower.contains('classic')) return '📻';
    if (lower.contains('party') || lower.contains('dance') || lower.contains('club')) return '💃';
    if (lower.contains('morning') || lower.contains('coffee') || lower.contains('peace')) return '☕';
    return '✨';
  }

  /// Formats a clean, stylish title from prompt
  static String formatTitle(String prompt) {
    final clean = prompt.trim();
    if (clean.isEmpty) return 'Mood Mix';

    for (final preset in quickMoodPresets) {
      if (preset['prompt']!.toLowerCase() == clean.toLowerCase()) {
        return preset['title']!;
      }
    }

    final words = clean.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).toList();

    var title = words.join(' ');
    if (!title.toLowerCase().endsWith('mix') && !title.toLowerCase().endsWith('playlist')) {
      title = '$title Mix';
    }
    return title;
  }

  /// Generates a curated playlist using the RadioEngine candidate generation & session-aware scoring.
  static Future<MoodPlaylistResult> generate({
    required String prompt,
    int targetCount = 20,
    String? preferredLanguage,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      throw ArgumentError('Mood or description prompt cannot be empty');
    }

    final emoji = detectMoodEmoji(cleanPrompt);
    final title = formatTitle(cleanPrompt);

    final explicitLang = detectLanguageInPrompt(cleanPrompt);
    final targetLang = explicitLang ??
        preferredLanguage ??
        SettingsManager.preferredLanguages.firstOrNull ??
        'tamil';

    AppLogger.log('MoodPlaylistGenerator', 'Generating playlist for "$cleanPrompt" (language: $targetLang)');

    // 1. Gather Anchor Candidates via Search
    final candidates = <Song>[];
    final seenIds = <String>{};

    void addCandidate(Song s) {
      if (s.title.trim().isEmpty) return;
      if (BlacklistManager.isBlacklisted(s)) return;
      if (seenIds.contains(s.id) || seenIds.contains(s.canonicalBaseKey)) return;
      seenIds.add(s.id);
      if (s.canonicalBaseKey.isNotEmpty) seenIds.add(s.canonicalBaseKey);
      candidates.add(s);
    }

    final plannedQuery = SearchQueryPlanner.forCategory(
      cleanPrompt,
      preferredLanguage: targetLang,
      explicitLanguage: explicitLang,
    );

    try {
      final searchRes = await SearchService.searchSongsTab(cleanPrompt, language: targetLang, limit: 10);
      for (final s in searchRes) {
        addCandidate(s);
      }
    } catch (e) {
      AppLogger.log('MoodPlaylistGenerator', 'Primary search error: $e');
    }

    if (candidates.length < 5 && plannedQuery != cleanPrompt) {
      try {
        final categoryRes = await SearchService.searchSongsTab(plannedQuery, language: targetLang, limit: 10);
        for (final s in categoryRes) {
          addCandidate(s);
        }
      } catch (e) {
        AppLogger.log('MoodPlaylistGenerator', 'Category search error: $e');
      }
    }

    // Supplement with YouTube search for broad descriptors
    if (candidates.length < 5) {
      try {
        final ytRes = await YouTubeClient.search('$targetLang $cleanPrompt', limit: 10);
        for (final s in ytRes) {
          addCandidate(s);
        }
      } catch (e) {
        AppLogger.log('MoodPlaylistGenerator', 'YouTube search fallback error: $e');
      }
    }

    // Local library fallback matching keywords if offline or search yielded nothing
    if (candidates.isEmpty) {
      final localPool = <Song>[
        ...FavoritesManager.getFavorites(),
        ...DownloadManager.getDownloadedSongs(),
        ...HistoryManager.getHistory(),
      ];
      final promptTokens = cleanPrompt.toLowerCase().split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
      for (final s in localPool) {
        final meta = '${s.title} ${s.artist} ${s.album} ${s.language}'.toLowerCase();
        if (promptTokens.any((t) => meta.contains(t))) {
          addCandidate(s);
        }
      }
      if (candidates.isEmpty && localPool.isNotEmpty) {
        for (final s in localPool.take(5)) {
          addCandidate(s);
        }
      }
    }

    if (candidates.isEmpty) {
      return MoodPlaylistResult(
        title: title,
        description: 'No matches found for "$cleanPrompt". Try a different description.',
        prompt: cleanPrompt,
        moodEmoji: emoji,
        tracks: const [],
      );
    }

    // 2. Select Anchor Seeds & Feed into RadioEngine
    final seeds = candidates.take(2).toList();
    final primarySeed = seeds.first;

    final radioTracks = await RadioEngine.buildSongRadio(primarySeed, limit: targetCount);

    final finalTracks = <Song>[];
    final finalSeen = <String>{};

    for (final s in radioTracks) {
      if (BlacklistManager.isBlacklisted(s)) continue;
      final key = s.canonicalBaseKey.isNotEmpty ? s.canonicalBaseKey : s.id;
      if (!finalSeen.contains(key)) {
        finalSeen.add(key);
        finalTracks.add(s);
      }
      if (finalTracks.length >= targetCount) break;
    }

    // If second seed exists and we haven't reached targetCount, blend secondary seed
    if (seeds.length > 1 && finalTracks.length < targetCount) {
      try {
        final secondaryRadio = await RadioEngine.buildSongRadio(seeds[1], limit: targetCount);
        for (final s in secondaryRadio) {
          if (BlacklistManager.isBlacklisted(s)) continue;
          final key = s.canonicalBaseKey.isNotEmpty ? s.canonicalBaseKey : s.id;
          if (!finalSeen.contains(key)) {
            finalSeen.add(key);
            finalTracks.add(s);
          }
          if (finalTracks.length >= targetCount) break;
        }
      } catch (_) {}
    }

    // Supplement with remaining candidates if still below targetCount
    if (finalTracks.length < targetCount) {
      for (final c in candidates) {
        final key = c.canonicalBaseKey.isNotEmpty ? c.canonicalBaseKey : c.id;
        if (!finalSeen.contains(key)) {
          finalSeen.add(key);
          finalTracks.add(c);
        }
        if (finalTracks.length >= targetCount) break;
      }
    }

    final description = 'Curated from "$cleanPrompt" • ${finalTracks.length} tracks • Tailored with Radio Engine session intelligence';

    return MoodPlaylistResult(
      title: title,
      description: description,
      prompt: cleanPrompt,
      moodEmoji: emoji,
      tracks: finalTracks,
    );
  }
}
