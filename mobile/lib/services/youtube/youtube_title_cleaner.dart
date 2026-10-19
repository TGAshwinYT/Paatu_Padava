import 'dart:core';
import '../../models/song.dart';

/// Utilities for cleaning YouTube titles and extracting video/playlist identifiers.
class YouTubeTitleCleaner {
  /// Cleans noise, tags, and promotional markers from YouTube video titles.
  static String cleanTitle(String title) {
    var cleaned = Song.sanitize(title);
    // Remove leading @handle mentions (e.g. "@SaiAbhyankkar - Pavazha Malli" -> "Pavazha Malli")
    cleaned = cleaned.replaceAll(RegExp(r'^@[a-zA-Z0-9_.]+\s*[-:|~–—]?\s*'), '');
    // Strip anything after pipe '|'
    cleaned = cleaned.replaceAll(RegExp(r'\|.*$'), ' ');
    // Remove bracketed info like [Official Video], (4K), | Lyrical, (Tamil), etc.
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ');
    // Strip multi-word video/song markers first, then single words
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(full\s*video(?:\s*song)?|video\s*song|audio\s*song|lyric(?:al)?\s*video(?:\s*song)?|official\s*(?:video|audio|music\s*video)|full\s*song|teaser|trailer|promo|visuali[sz]er|4k|8k|hd|uhd|1080p|720p)\b', caseSensitive: false),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\b(official|video|audio|lyric|lyrical)\b', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Strip leading or trailing hyphens, colons, slashes, or tildes
    cleaned = cleaned.replaceAll(RegExp(r'^[\s\-–—:~|/,.\+]+|[\s\-–—:~|/,.\+]+$'), '').trim();
    return cleaned.isNotEmpty ? cleaned : Song.sanitize(title);
  }

  /// Extracts 11-character video ID from YouTube, YouTube Music, or youtu.be URLs
  static String? extractVideoId(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return null;
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) return clean;
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?|shorts)\/|.*[?&]v=)|youtu\.be\/|music\.youtube\.com\/(?:watch\?v=|shorts\/))([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(clean);
    return match?.group(1);
  }

  /// Extracts playlist ID (e.g. PL..., RD..., etc.) from a YouTube playlist URL
  static String? extractPlaylistId(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return null;
    final regExp = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)', caseSensitive: false);
    final match = regExp.firstMatch(clean);
    if (match != null) return match.group(1);
    if (clean.startsWith('PL') || clean.startsWith('RD') || clean.startsWith('OLAK5uy_')) {
      return clean;
    }
    return null;
  }
}
