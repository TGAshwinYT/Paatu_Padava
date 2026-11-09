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

/// Spotify-Style 2x3 Quick Tile representation with 1-tap playback
class HomeQuickTile {
  final String id;
  final String title;
  final String? subtitle;
  final String coverUrl;
  final List<Color> gradient;
  final List<Song> tracks;
  final String type; // 'liked' | 'history' | 'mix' | 'album' | 'hits'

  const HomeQuickTile({
    required this.id,
    required this.title,
    this.subtitle,
    required this.coverUrl,
    required this.gradient,
    required this.tracks,
    required this.type,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'coverUrl': coverUrl,
    'gradient': gradient.map((c) => c.value).toList(),
    'tracks': tracks.map((t) => t.toMap()).toList(),
    'type': type,
  };

  factory HomeQuickTile.fromMap(Map<String, dynamic> map) => HomeQuickTile(
    id: map['id']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    subtitle: map['subtitle']?.toString(),
    coverUrl: map['coverUrl']?.toString() ?? '',
    gradient: (map['gradient'] as List<dynamic>?)
            ?.map((v) => Color((v as num).toInt()))
            .toList() ??
        [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
    tracks: (map['tracks'] as List<dynamic>?)
            ?.map((t) => Song.fromMap(t as Map<String, dynamic>))
            .toList() ??
        [],
    type: map['type']?.toString() ?? 'mix',
  );
}

/// Spotify-Style Multi-Artist Clustered Daily Mix
class DailyMix {
  final int index; // 1, 2, 3, 4
  final String title; // "Daily Mix 1"
  final String subtitle; // "Anirudh Ravichander, Yuvan Shankar Raja..."
  final String coverUrl;
  final Color accentColor;
  final List<Song> tracks;

  const DailyMix({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.accentColor,
    required this.tracks,
  });

  Map<String, dynamic> toMap() => {
    'index': index,
    'title': title,
    'subtitle': subtitle,
    'coverUrl': coverUrl,
    'accentColor': accentColor.value,
    'tracks': tracks.map((t) => t.toMap()).toList(),
  };

  factory DailyMix.fromMap(Map<String, dynamic> map) => DailyMix(
    index: (map['index'] as num?)?.toInt() ?? 1,
    title: map['title']?.toString() ?? 'Daily Mix',
    subtitle: map['subtitle']?.toString() ?? '',
    coverUrl: map['coverUrl']?.toString() ?? '',
    accentColor: Color((map['accentColor'] as num?)?.toInt() ?? 0xFF10B981),
    tracks: (map['tracks'] as List<dynamic>?)
            ?.map((t) => Song.fromMap(t as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

/// Decades & Golden Era Playlist Collection (90s, 2000s, 2010s, 2024)
class DecadeMix {
  final String decade; // '90s' | '2000s' | '2010s' | '2024'
  final String title;
  final String subtitle;
  final String coverUrl;
  final List<Color> gradient;
  final List<Song> tracks;

  const DecadeMix({
    required this.decade,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.gradient,
    required this.tracks,
  });

  Map<String, dynamic> toMap() => {
    'decade': decade,
    'title': title,
    'subtitle': subtitle,
    'coverUrl': coverUrl,
    'gradient': gradient.map((c) => c.value).toList(),
    'tracks': tracks.map((t) => t.toMap()).toList(),
  };

  factory DecadeMix.fromMap(Map<String, dynamic> map) => DecadeMix(
    decade: map['decade']?.toString() ?? '90s',
    title: map['title']?.toString() ?? '',
    subtitle: map['subtitle']?.toString() ?? '',
    coverUrl: map['coverUrl']?.toString() ?? '',
    gradient: (map['gradient'] as List<dynamic>?)
            ?.map((v) => Color((v as num).toInt()))
            .toList() ??
        [const Color(0xFFF59E0B), const Color(0xFFD97706)],
    tracks: (map['tracks'] as List<dynamic>?)
            ?.map((t) => Song.fromMap(t as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
