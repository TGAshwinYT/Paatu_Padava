import 'dart:async';
import '../models/song.dart';
import '../services/app_logger.dart';
import '../services/youtube_client.dart';
import '../services/saavn_client.dart';
import '../services/artist_sanitizer.dart';

/// Abstract contract for audio stream URL resolution.
/// Decouples queue management from provider-specific extraction, timeouts, and fallbacks.
abstract class StreamResolver {
  Future<String?> resolveStreamUrl(Song song);
  bool verifyAudioMatch(Song candidate, Song target);
}

/// Production implementation of [StreamResolver] handling multi-tier resolution:
/// 1. Direct provider extraction (YouTube / JioSaavn)
/// 2. Cross-provider fallback matching with audio verification
/// 3. Resilient timeout management
class DefaultStreamResolver implements StreamResolver {
  static const Duration _overallTimeout = Duration(seconds: 25);
  static const Duration _saavnSearchTimeout = Duration(seconds: 6);

  @override
  Future<String?> resolveStreamUrl(Song song) async {
    final sw = Stopwatch()..start();
    AppLogger.log(
      'StreamResolver',
      'Resolving stream for: "${song.title}" (${song.artist}) [source=${song.source}, id=${song.id}]',
    );

    try {
      final url = await _resolveStreamUrlInternal(song).timeout(_overallTimeout);
      sw.stop();
      if (url != null && url.isNotEmpty) {
        AppLogger.log('StreamResolver', 'Resolved stream for "${song.title}" in ${sw.elapsedMilliseconds}ms');
      } else {
        AppLogger.log('StreamResolver', 'Stream resolution returned empty for "${song.title}" after ${sw.elapsedMilliseconds}ms');
      }
      return url;
    } catch (e, stack) {
      sw.stop();
      AppLogger.recordError(e, stack, context: 'StreamResolver.resolveStreamUrl for "${song.title}" (${sw.elapsedMilliseconds}ms)');
      return null;
    }
  }

  Future<String?> _resolveStreamUrlInternal(Song song) async {
    if (song.source == 'youtube' || song.id.length == 11) {
      // 1. Direct YouTube stream resolution (User explicitly selected YouTube)
      try {
        final ytUrl = await YouTubeClient.getAudioStreamUrl(song.id, title: song.title, artist: song.artist);
        if (ytUrl != null && ytUrl.isNotEmpty) {
          return ytUrl;
        }
      } catch (e) {
        AppLogger.log('StreamResolver', 'Direct YouTube stream resolution notice: $e');
      }

      // 2. Fallback: Search JioSaavn if YouTube direct extraction failed or timed out
      try {
        final cleanTitle = YouTubeClient.cleanTitle(song.title);
        final cleanArtist = (song.artist.isNotEmpty && !ArtistSanitizer.isRecordLabelOrChannel(song.artist))
            ? song.artist
            : '';
        final query = cleanArtist.isNotEmpty ? '$cleanTitle $cleanArtist' : cleanTitle;
        AppLogger.log('StreamResolver', 'Attempting JioSaavn fallback for YouTube track "$cleanTitle" with query: "$query"');
        final saavnMatches = await SaavnClient.search(query, limit: 5).timeout(_saavnSearchTimeout);
        for (final match in saavnMatches) {
          if (match.streamUrl != null && match.streamUrl!.isNotEmpty && verifyAudioMatch(match, song)) {
            AppLogger.log('StreamResolver', 'JioSaavn fallback matched for YouTube track "${song.title}": "${match.title}"');
            song.streamUrl = match.streamUrl;
            return match.streamUrl;
          }
        }
      } catch (e) {
        AppLogger.log('StreamResolver', 'Saavn match fallback notice: $e');
      }
    } else {
      // Direct JioSaavn stream
      try {
        if (song.streamUrl != null && song.streamUrl!.isNotEmpty) {
          return song.streamUrl;
        }
        final matches = await SaavnClient.search('${song.title} ${song.artist}', limit: 3).timeout(_saavnSearchTimeout);
        for (final match in matches) {
          if (match.streamUrl != null && verifyAudioMatch(match, song)) {
            return match.streamUrl;
          }
        }
      } catch (e) {
        AppLogger.log('StreamResolver', 'Direct Saavn stream resolution notice: $e');
      }

      // 3. Fallback: If JioSaavn has no stream, attempt to resolve via YouTube
      try {
        final query = '${song.title} ${song.artist} audio';
        final ytMatches = await YouTubeClient.search(query, limit: 2);
        if (ytMatches.isNotEmpty) {
          final ytUrl = await YouTubeClient.getAudioStreamUrl(ytMatches.first.id, title: song.title, artist: song.artist);
          if (ytUrl != null && ytUrl.isNotEmpty) {
            return ytUrl;
          }
        }
      } catch (e) {
        AppLogger.log('StreamResolver', 'Saavn to YouTube fallback notice: $e');
      }
    }
    return null;
  }

  @override
  bool verifyAudioMatch(Song candidate, Song target) {
    return verifyMatch(candidate, target);
  }

  /// Static helper for audio match verification (can be used directly across the app)
  static bool verifyMatch(Song candidate, Song target) {
    final normTargetTitle = normalizeForComparison(target.title);
    final normCandTitle = normalizeForComparison(candidate.title);
    if (normTargetTitle.isEmpty || normCandTitle.isEmpty) return false;

    final bool isDirectTitleMatch = (normTargetTitle == normCandTitle ||
        normTargetTitle.contains(normCandTitle) ||
        normCandTitle.contains(normTargetTitle));

    // 1. Duration check:
    // If titles match directly or tracks are from YouTube, allow up to 45 seconds tolerance
    // (YouTube music videos frequently include intros, outros, skits, and dialogue)
    if (target.duration > 0 && candidate.duration > 0) {
      final diff = (candidate.duration - target.duration).abs();
      final allowedTolerance = (isDirectTitleMatch || target.source == 'youtube' || candidate.source == 'youtube') ? 45 : 15;
      if (diff > allowedTolerance) {
        return false;
      }
    }

    // 2. Title similarity check
    if (isDirectTitleMatch) {
      return true;
    }

    // Token overlap: Check if at least 70% of candidate words exist in target
    final candWords = normCandTitle.split(' ').where((w) => w.length > 2).toSet();
    final targetWords = normTargetTitle.split(' ').where((w) => w.length > 2).toSet();
    if (candWords.isNotEmpty && targetWords.isNotEmpty) {
      final intersection = candWords.intersection(targetWords);
      final overlapRatio = intersection.length / candWords.length;
      if (overlapRatio >= 0.70) {
        return true;
      }
    }

    return false;
  }

  static String normalizeForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'^@[a-z0-9_.]+\s*[-:|~–—]?\s*'), ' ')
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
