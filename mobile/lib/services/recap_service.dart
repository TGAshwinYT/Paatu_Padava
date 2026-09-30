import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'history_manager.dart';
import 'supabase_service.dart';

/// Aggregated play statistics for a single song in the listening recap
class SongPlayStat {
  final Song song;
  final int playCount;
  final int totalSeconds;

  SongPlayStat({
    required this.song,
    required this.playCount,
    required this.totalSeconds,
  });

  int get totalMinutes => (totalSeconds / 60).round();
}

/// Aggregated play statistics for an artist
class ArtistPlayStat {
  final String artistName;
  final int playCount;
  final int totalSeconds;
  final String representativeCoverUrl;

  ArtistPlayStat({
    required this.artistName,
    required this.playCount,
    required this.totalSeconds,
    required this.representativeCoverUrl,
  });

  int get totalMinutes => (totalSeconds / 60).round();
}

/// Complete listening recap summary (Paatu Wrapped)
class ListeningRecap {
  final int totalMinutes;
  final int totalPlays;
  final int uniqueTracksCount;
  final int uniqueArtistsCount;
  final List<SongPlayStat> topSongs;
  final List<ArtistPlayStat> topArtists;
  final String listenerPersona;
  final String personaSubtitle;
  final String personaQuote;
  final int peakHour; // 0 - 23
  final DateTime generatedAt;

  ListeningRecap({
    required this.totalMinutes,
    required this.totalPlays,
    required this.uniqueTracksCount,
    required this.uniqueArtistsCount,
    required this.topSongs,
    required this.topArtists,
    required this.listenerPersona,
    required this.personaSubtitle,
    required this.personaQuote,
    required this.peakHour,
    required this.generatedAt,
  });

  String get peakHourFormatted {
    final h = peakHour % 24;
    final period = h >= 12 ? 'PM' : 'AM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH:00 $period';
  }

  bool get isEmpty => totalPlays == 0;
}

/// Service that computes listening analytics, top rankings, and persona classification
class ListeningRecapService {
  /// Default duration in seconds for tracks with missing/zero duration
  static const int fallbackTrackDurationSeconds = 210; // 3.5 minutes

  /// Generates a live recap using Supabase cloud history if authenticated,
  /// combined with local offline Hive playback history.
  static Future<ListeningRecap> generateRecap() async {
    final List<Map<String, dynamic>> combinedEntries = [];

    // 1. Fetch Supabase remote history if logged in
    final supaUser = SupabaseService.currentUser;
    final client = SupabaseService.client;
    if (supaUser != null && !supaUser.isAnonymous && client != null) {
      try {
        final List<dynamic> remoteRows = await client
            .from('user_history')
            .select('song_id, title, artist, cover_url, source, played_at')
            .eq('user_id', supaUser.id)
            .order('played_at', ascending: false)
            .limit(500);

        for (final row in remoteRows) {
          final songId = row['song_id']?.toString() ?? '';
          if (songId.isNotEmpty) {
            final playedAtStr = row['played_at']?.toString();
            final epoch = playedAtStr != null
                ? (DateTime.tryParse(playedAtStr)?.millisecondsSinceEpoch ?? 0)
                : 0;

            combinedEntries.add({
              'id': songId,
              'title': row['title'] ?? 'Unknown Song',
              'artist': row['artist'] ?? 'Various Artists',
              'cover_url': row['cover_url'] ?? '',
              'source': row['source'] ?? 'saavn',
              'duration': 0,
              'play_count': 1,
              'played_at': epoch,
              'timestamps': [epoch],
            });
          }
        }
      } catch (e) {
        debugPrint('[ListeningRecapService] Remote history query notice: $e');
      }
    }

    // 2. Fetch local Hive entries
    final localEntries = HistoryManager.getRawHistoryEntries();
    combinedEntries.addAll(localEntries);

    return generateRecapFromData(combinedEntries);
  }

  /// Pure computation function to generate [ListeningRecap] from raw entries.
  /// Facilitates unit testing with deterministic inputs.
  static ListeningRecap generateRecapFromData(List<Map<String, dynamic>> rawEntries) {
    if (rawEntries.isEmpty) {
      return ListeningRecap(
        totalMinutes: 0,
        totalPlays: 0,
        uniqueTracksCount: 0,
        uniqueArtistsCount: 0,
        topSongs: [],
        topArtists: [],
        listenerPersona: 'Curious Listener',
        personaSubtitle: 'Your musical story is just beginning',
        personaQuote: 'Play a few songs to unveil your unique sound signature.',
        peakHour: 20,
        generatedAt: DateTime.now(),
      );
    }

    final Map<String, _SongAccumulator> songAcc = {};
    final Map<String, _ArtistAccumulator> artistAcc = {};
    final List<int> hourDistribution = List.filled(24, 0);

    int totalPlays = 0;
    int totalSeconds = 0;

    for (final entry in rawEntries) {
      final id = entry['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final title = (entry['title'] ?? 'Unknown Song').toString();
      final artist = (entry['artist'] ?? 'Various Artists').toString();
      final coverUrl = (entry['cover_url'] ?? entry['coverUrl'] ?? '').toString();
      final source = (entry['source'] ?? 'saavn').toString();

      int duration = 0;
      if (entry['duration'] is num) {
        duration = (entry['duration'] as num).toInt();
      }
      if (duration <= 0) {
        duration = fallbackTrackDurationSeconds;
      }

      int plays = 1;
      if (entry['play_count'] is num) {
        plays = max(1, (entry['play_count'] as num).toInt());
      }

      totalPlays += plays;
      totalSeconds += duration * plays;

      // Extract playback timestamps for peak hour analysis
      if (entry['timestamps'] is List && (entry['timestamps'] as List).isNotEmpty) {
        for (final ts in entry['timestamps']) {
          if (ts is num && ts > 0) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
            hourDistribution[dt.hour]++;
          }
        }
      } else if (entry['played_at'] is num && (entry['played_at'] as num) > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch((entry['played_at'] as num).toInt());
        hourDistribution[dt.hour] += plays;
      }

      // Song Accumulation
      if (!songAcc.containsKey(id)) {
        songAcc[id] = _SongAccumulator(
          song: Song(
            id: id,
            title: title,
            artist: artist,
            album: (entry['album'] ?? '').toString(),
            duration: duration,
            coverUrl: coverUrl,
            source: source,
          ),
          playCount: plays,
          totalSeconds: duration * plays,
        );
      } else {
        songAcc[id]!.playCount += plays;
        songAcc[id]!.totalSeconds += duration * plays;
      }

      // Primary Artist Accumulation
      final primaryArtist = _extractPrimaryArtist(artist);
      if (!artistAcc.containsKey(primaryArtist)) {
        artistAcc[primaryArtist] = _ArtistAccumulator(
          artistName: primaryArtist,
          playCount: plays,
          totalSeconds: duration * plays,
          coverUrl: coverUrl,
        );
      } else {
        artistAcc[primaryArtist]!.playCount += plays;
        artistAcc[primaryArtist]!.totalSeconds += duration * plays;
      }
    }

    // Top Songs
    final sortedSongs = songAcc.values.toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    final topSongs = sortedSongs.take(5).map((e) => SongPlayStat(
      song: e.song,
      playCount: e.playCount,
      totalSeconds: e.totalSeconds,
    )).toList();

    // Top Artists
    final sortedArtists = artistAcc.values.toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    final topArtists = sortedArtists.take(5).map((e) => ArtistPlayStat(
      artistName: e.artistName,
      playCount: e.playCount,
      totalSeconds: e.totalSeconds,
      representativeCoverUrl: e.coverUrl,
    )).toList();

    // Peak listening hour
    int peakHour = 21; // default 9 PM
    int maxHourCount = -1;
    for (int h = 0; h < 24; h++) {
      if (hourDistribution[h] > maxHourCount) {
        maxHourCount = hourDistribution[h];
        peakHour = h;
      }
    }

    // Persona Calculation
    final persona = _determinePersona(
      peakHour: peakHour,
      totalPlays: totalPlays,
      topArtistPlays: topArtists.isNotEmpty ? topArtists.first.playCount : 0,
      uniqueArtistsCount: artistAcc.length,
    );

    return ListeningRecap(
      totalMinutes: (totalSeconds / 60).round(),
      totalPlays: totalPlays,
      uniqueTracksCount: songAcc.length,
      uniqueArtistsCount: artistAcc.length,
      topSongs: topSongs,
      topArtists: topArtists,
      listenerPersona: persona.title,
      personaSubtitle: persona.subtitle,
      personaQuote: persona.quote,
      peakHour: peakHour,
      generatedAt: DateTime.now(),
    );
  }

  static String _extractPrimaryArtist(String fullArtist) {
    if (fullArtist.isEmpty) return 'Various Artists';
    final parts = fullArtist.split(RegExp(r',|;|/|&|\bfeat\b|\bft\b', caseSensitive: false));
    return parts.first.trim();
  }

  static _PersonaInfo _determinePersona({
    required int peakHour,
    required int totalPlays,
    required int topArtistPlays,
    required int uniqueArtistsCount,
  }) {
    if (totalPlays > 0 && (topArtistPlays / totalPlays) >= 0.40) {
      return _PersonaInfo(
        title: 'Devoted Stan',
        subtitle: 'Unshakable Loyalty',
        quote: 'When you love an artist, you ride with them across every album and era.',
      );
    }

    if (uniqueArtistsCount >= 10 && (topArtistPlays / max(1, totalPlays)) < 0.20) {
      return _PersonaInfo(
        title: 'Sonic Nomad',
        subtitle: 'Boundless Curiosity',
        quote: 'Your taste refuses borders. You hop genres and explore soundscapes effortlessly.',
      );
    }

    if (peakHour >= 23 || peakHour <= 4) {
      return _PersonaInfo(
        title: 'Midnight Voyager',
        subtitle: 'Starlight Dreamer',
        quote: 'Your musical sanctuary comes alive after dark, where melodies hit deepest.',
      );
    }

    if (peakHour >= 5 && peakHour <= 10) {
      return _PersonaInfo(
        title: 'Dawn Energizer',
        subtitle: 'Morning Momentum',
        quote: 'You greet every sunrise with rhythm, setting the heartbeat of your day.',
      );
    }

    if (peakHour >= 11 && peakHour <= 16) {
      return _PersonaInfo(
        title: 'Flow Master',
        subtitle: 'Deep Focus Groove',
        quote: 'Music is your productivity engine, keeping you in an unbroken zone.',
      );
    }

    return _PersonaInfo(
      title: 'Sunset Harmonizer',
      subtitle: 'Evening Serenity',
      quote: 'As dusk sets in, you transition into pure acoustic calm and warm chords.',
    );
  }
}

class _SongAccumulator {
  final Song song;
  int playCount;
  int totalSeconds;

  _SongAccumulator({
    required this.song,
    required this.playCount,
    required this.totalSeconds,
  });
}

class _ArtistAccumulator {
  final String artistName;
  int playCount;
  int totalSeconds;
  final String coverUrl;

  _ArtistAccumulator({
    required this.artistName,
    required this.playCount,
    required this.totalSeconds,
    required this.coverUrl,
  });
}

class _PersonaInfo {
  final String title;
  final String subtitle;
  final String quote;

  _PersonaInfo({
    required this.title,
    required this.subtitle,
    required this.quote,
  });
}
