import 'dart:convert';
import 'track_entity.dart';

/// Timestamped playback history entry model matching Spotify and YouTube Music specifications.
/// Encapsulates the played domain [TrackEntity], exact [playedAt] timestamp,
/// and calendar-day equality semantics.
class HistoryEntry {
  final TrackEntity track;
  final DateTime playedAt;

  const HistoryEntry({
    required this.track,
    required this.playedAt,
  });

  /// Serializes the history entry to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'track': track.toMap(),
      'playedAt': playedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() => toJson();

  /// Deserializes a history entry from JSON or legacy flat maps.
  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final trackData = json['track'];
    final TrackEntity parsedTrack;
    if (trackData is Map) {
      parsedTrack = TrackEntity.fromMap(trackData);
    } else {
      // Legacy flat map fallback where track fields were stored at the root of the entry
      parsedTrack = TrackEntity.fromMap(json);
    }

    final rawPlayedAt = json['playedAt'] ?? json['played_at'];
    final DateTime parsedTime;
    if (rawPlayedAt is String) {
      parsedTime = DateTime.tryParse(rawPlayedAt) ?? DateTime.now();
    } else if (rawPlayedAt is num) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(rawPlayedAt.toInt());
    } else {
      parsedTime = DateTime.now();
    }

    return HistoryEntry(
      track: parsedTrack,
      playedAt: parsedTime,
    );
  }

  factory HistoryEntry.fromMap(Map<dynamic, dynamic> map) {
    return HistoryEntry.fromJson(Map<String, dynamic>.from(map));
  }

  /// History entry equality based on track.id and calendar date (year, month, day).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HistoryEntry &&
        other.track.id == track.id &&
        other.playedAt.year == playedAt.year &&
        other.playedAt.month == playedAt.month &&
        other.playedAt.day == playedAt.day;
  }

  @override
  int get hashCode => Object.hash(
        track.id,
        playedAt.year,
        playedAt.month,
        playedAt.day,
      );

  /// Helper to format date sections: "Today", "Yesterday", or formatted date (e.g. "Saturday, 10 October").
  static String formatDateSection(DateTime date, [DateTime? nowOverride]) {
    final now = nowOverride ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final targetDate = DateTime(date.year, date.month, date.day);

    if (targetDate == today) {
      return 'Today';
    } else if (targetDate == yesterday) {
      return 'Yesterday';
    } else {
      const weekdayNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      const monthNames = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      final weekday = weekdayNames[date.weekday - 1];
      final month = monthNames[date.month - 1];
      return '$weekday, ${date.day} $month';
    }
  }

  /// Date section label computed relative to current time.
  String get dateSection => formatDateSection(playedAt);

  /// Formats playback timestamp (e.g., "10:45 AM" or relative time like "25m ago").
  static String formatTimestamp(DateTime time, [DateTime? nowOverride]) {
    final now = nowOverride ?? DateTime.now();
    final diff = now.difference(time);

    if (diff.isNegative) {
      return _formatClockTime(time);
    }
    if (diff.inSeconds < 60) {
      return 'Just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 6) {
      return '${diff.inHours}h ago';
    }
    return _formatClockTime(time);
  }

  static String _formatClockTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final formattedHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$formattedHour:$minute $period';
  }

  /// Formatted playback time subtitle.
  String get formattedTime => formatTimestamp(playedAt);

  HistoryEntry copyWith({
    TrackEntity? track,
    DateTime? playedAt,
  }) {
    return HistoryEntry(
      track: track ?? this.track,
      playedAt: playedAt ?? this.playedAt,
    );
  }

  @override
  String toString() => 'HistoryEntry(id: ${track.id}, title: ${track.title}, playedAt: $playedAt)';
}
