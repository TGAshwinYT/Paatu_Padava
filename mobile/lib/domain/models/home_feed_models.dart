import 'package:flutter/material.dart';
import '../../models/song.dart';

/// Flagship Spotify-Style Top Hits Editorial Showcase Hero
class HeroShowcase {
  final String title;
  final String subtitle;
  final String description;
  final String coverUrl;
  final List<Color> gradientColors;
  final List<Song> tracks;

  const HeroShowcase({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.coverUrl,
    required this.gradientColors,
    required this.tracks,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'coverUrl': coverUrl,
    'gradientColors': gradientColors.map((c) => c.value).toList(),
    'tracks': tracks.map((t) => t.toMap()).toList(),
  };

  factory HeroShowcase.fromMap(Map<String, dynamic> map) => HeroShowcase(
    title: map['title']?.toString() ?? 'Top Hits',
    subtitle: map['subtitle']?.toString() ?? '',
    description: map['description']?.toString() ?? '',
    coverUrl: map['coverUrl']?.toString() ?? '',
    gradientColors: (map['gradientColors'] as List<dynamic>?)
            ?.map((v) => Color((v as num).toInt()))
            .toList() ??
        [const Color(0xFF7C3AED), const Color(0xFF06B6D4)],
    tracks: (map['tracks'] as List<dynamic>?)
            ?.map((t) => Song.fromMap(t as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

/// Spotify & Billboard Style Ranked Top 10 Track Entry
class RankedChartSong {
  final int rank;
  final Song song;
  final int rankChange; // +1, -1, 0, or 999 for 'NEW'
  final bool isNew;

  const RankedChartSong({
    required this.rank,
    required this.song,
    this.rankChange = 0,
    this.isNew = false,
  });

  Map<String, dynamic> toMap() => {
    'rank': rank,
    'song': song.toMap(),
    'rankChange': rankChange,
    'isNew': isNew,
  };

  factory RankedChartSong.fromMap(Map<String, dynamic> map) => RankedChartSong(
    rank: (map['rank'] as num?)?.toInt() ?? 1,
    song: Song.fromMap(map['song'] as Map<String, dynamic>),
    rankChange: (map['rankChange'] as num?)?.toInt() ?? 0,
    isNew: map['isNew'] as bool? ?? false,
  );
}

/// YouTube Music & Apple Music Style Mood & Feeling Mix Bundle
class FeelingMix {
  final String feelingId;
  final String title;
  final String subtitle;
  final String icon;
  final List<Color> gradient;
  final List<Song> songs;

  const FeelingMix({
    required this.feelingId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.songs,
  });

  Map<String, dynamic> toMap() => {
    'feelingId': feelingId,
    'title': title,
    'subtitle': subtitle,
    'icon': icon,
    'gradient': gradient.map((c) => c.value).toList(),
    'songs': songs.map((s) => s.toMap()).toList(),
  };

  factory FeelingMix.fromMap(Map<String, dynamic> map) => FeelingMix(
    feelingId: map['feelingId']?.toString() ?? 'all',
    title: map['title']?.toString() ?? '',
    subtitle: map['subtitle']?.toString() ?? '',
    icon: map['icon']?.toString() ?? '✨',
    gradient: (map['gradient'] as List<dynamic>?)
            ?.map((v) => Color((v as num).toInt()))
            .toList() ??
        [const Color(0xFF7C3AED), const Color(0xFF9333EA)],
    songs: (map['songs'] as List<dynamic>?)
            ?.map((s) => Song.fromMap(s as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
