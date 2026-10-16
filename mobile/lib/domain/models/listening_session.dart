import 'track_entity.dart';
import '../../models/song.dart';

/// Represents a continuous playback listening session (Spotify-style Album / Playlist grouping).
/// Formed when songs are played continuously back-to-back within a defined temporal window.
class ListeningSession {
  final String id;
  final String title;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<TrackEntity> tracks;

  const ListeningSession({
    required this.id,
    required this.title,
    required this.startedAt,
    required this.endedAt,
    required this.tracks,
  });

  /// Derives playback [Song] items from the underlying [TrackEntity] tracks.
  List<Song> get songs => tracks.map((t) => t.toSong()).toList();

  int get trackCount => tracks.length;

  /// Aggregates total duration across all tracks in seconds.
  int get totalDurationSeconds {
    return tracks.fold<int>(0, (sum, t) => sum + t.duration);
  }

  /// Human-readable duration format (e.g. "34 mins" or "1 hr 12 mins").
  String get formattedDuration {
    final totalSec = totalDurationSeconds;
    if (totalSec <= 0) return '$trackCount tracks';
    final hours = totalSec ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours hr${hours > 1 ? 's' : ''} ${mins > 0 ? '$mins min' : ''}';
    }
    return '$mins min${mins > 1 ? 's' : ''}';
  }

  /// Formatted date section (e.g. "Today", "Yesterday", "Monday, 14 Oct").
  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sessionDay = DateTime(startedAt.year, startedAt.month, startedAt.day);

    if (sessionDay == today) {
      return 'Today';
    } else if (sessionDay == yesterday) {
      return 'Yesterday';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${startedAt.day} ${months[startedAt.month - 1]}';
    }
  }

  /// Formatted start time (e.g. "4:15 PM").
  String get formattedStartTime {
    final hour = startedAt.hour;
    final minute = startedAt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// Compact subtitle (e.g. "Today at 4:15 PM • 8 songs • 26 mins").
  String get subtitle {
    return '$formattedDate at $formattedStartTime • $trackCount song${trackCount > 1 ? 's' : ''} • $formattedDuration';
  }

  /// Distinct album artwork URLs for collage rendering (up to 4).
  List<String> get coverUrls {
    final urls = <String>[];
    for (final track in tracks) {
      if (track.coverUrl.isNotEmpty && !urls.contains(track.coverUrl)) {
        urls.add(track.coverUrl);
        if (urls.length == 4) break;
      }
    }
    return urls;
  }

  /// Smart title generator based on session contents and playback time.
  static String generateTitle(List<TrackEntity> tracks, DateTime startedAt) {
    if (tracks.isEmpty) return 'Listening Session';

    // 1. Check if predominant album (>= 50% of songs)
    final albumCounts = <String, int>{};
    for (final t in tracks) {
      final cleanAlbum = t.album.trim();
      if (cleanAlbum.isNotEmpty &&
          !['popular hits', 'unknown album', 'unknown', 'various'].contains(cleanAlbum.toLowerCase())) {
        albumCounts[cleanAlbum] = (albumCounts[cleanAlbum] ?? 0) + 1;
      }
    }
    if (albumCounts.isNotEmpty) {
      final sortedAlbums = albumCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topAlbum = sortedAlbums.first;
      if (topAlbum.value >= 2 && topAlbum.value / tracks.length >= 0.5) {
        return '${topAlbum.key} Album Session';
      }
    }

    // 2. Check if predominant artist (>= 40% of songs)
    final artistCounts = <String, int>{};
    for (final t in tracks) {
      final primary = t.artist.split(',').first.split('&').first.trim();
      final lower = primary.toLowerCase();
      if (primary.isNotEmpty &&
          !['various', 'various artists', 'unknown', 'unknown artist'].contains(lower)) {
        artistCounts[primary] = (artistCounts[primary] ?? 0) + 1;
      }
    }
    if (artistCounts.isNotEmpty) {
      final sortedArtists = artistCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topArtist = sortedArtists.first;
      if (topArtist.value >= 2 && topArtist.value / tracks.length >= 0.4) {
        if (sortedArtists.length > 1) {
          return '${topArtist.key} & more';
        }
        return '${topArtist.key} Session';
      }
    }

    // 3. Fallback to time-of-day listening vibes
    final hour = startedAt.hour;
    if (hour >= 5 && hour < 12) {
      return 'Morning Listening Session';
    } else if (hour >= 12 && hour < 17) {
      return 'Afternoon Listening Session';
    } else if (hour >= 17 && hour < 22) {
      return 'Evening Listening Mix';
    } else {
      return 'Late Night Session';
    }
  }

  /// Creates a session from a sequence of tracks with auto-generated title.
  factory ListeningSession.fromTracks({
    required String id,
    required List<TrackEntity> tracks,
    required DateTime startedAt,
    required DateTime endedAt,
    String? customTitle,
  }) {
    final title = customTitle ?? generateTitle(tracks, startedAt);
    return ListeningSession(
      id: id,
      title: title,
      startedAt: startedAt,
      endedAt: endedAt,
      tracks: tracks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'tracks': tracks.map((t) => t.toMap()).toList(),
    };
  }

  factory ListeningSession.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List? ?? [];
    final tracks = rawTracks.map((m) => TrackEntity.fromMap(m as Map)).toList();
    final startedAt = DateTime.tryParse(json['startedAt']?.toString() ?? '') ?? DateTime.now();
    final endedAt = DateTime.tryParse(json['endedAt']?.toString() ?? '') ?? startedAt;

    return ListeningSession(
      id: json['id']?.toString() ?? 'session_${startedAt.millisecondsSinceEpoch}',
      title: json['title']?.toString() ?? generateTitle(tracks, startedAt),
      startedAt: startedAt,
      endedAt: endedAt,
      tracks: tracks,
    );
  }
}
