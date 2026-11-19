import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/cover_art_resolver.dart';
import '../../services/catalog_database.dart';
import '../../services/download_manager.dart';

/// Reusable high-performance cover art widget for Paatu Padava.
///
/// Features:
/// 1. Decodes images at constrained memory dimensions via dynamic layout-derived `memCacheWidth`
///    (setting only one dimension to preserve native aspect ratio) eliminating scroll stutter.
/// 2. Gracefully handles 16:9 YouTube video thumbnails: single decode with sleek ambient container
///    rather than costly duplicate decodes and per-tile GPU blurs.
/// 3. Asynchronously upgrades YouTube thumbnails to 1000x1000 studio square art
///    via [CoverArtResolver] in the background with bounded concurrency and negative caching.
/// 4. Renders a sleek neutral gradient placeholder when no cover exists (never stock photos).
class CoverArtImage extends StatefulWidget {
  final Song? song;
  final String? coverUrl;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final bool autoResolve;
  final Widget? errorWidget;

  const CoverArtImage({
    super.key,
    this.song,
    this.coverUrl,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.memCacheHeight,
    this.autoResolve = true,
    this.errorWidget,
  });

  @override
  State<CoverArtImage> createState() => _CoverArtImageState();
}

class _CoverArtImageState extends State<CoverArtImage> {
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _checkAndResolve();
  }

  @override
  void didUpdateWidget(covariant CoverArtImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song?.id != widget.song?.id || oldWidget.coverUrl != widget.coverUrl) {
      _resolvedUrl = null;
      _checkAndResolve();
    }
  }

  static String? _normalizePath(String? path) {
    if (path == null || path.isEmpty) return null;
    final trimmed = path.trim();
    if (trimmed.startsWith('file://')) {
      try {
        return Uri.parse(trimmed).toFilePath();
      } catch (_) {
        return trimmed.replaceFirst('file://', '');
      }
    }
    return trimmed;
  }

  void _checkAndResolve() {
    final effectiveSong = widget.song;
    if (effectiveSong == null) {
      _resolvedUrl = widget.coverUrl;
      return;
    }

    final songId = effectiveSong.id;
    final cached = CoverArtResolver.getCachedCover(songId);
    if (cached != null && cached.isNotEmpty && !CoverArtResolver.isPlaylistCover(cached)) {
      _resolvedUrl = cached;
      return;
    }

    final hasValidCover = effectiveSong.coverUrl.isNotEmpty &&
        !CoverArtResolver.isPlaylistCover(effectiveSong.coverUrl) &&
        !effectiveSong.coverUrl.startsWith('file://') &&
        !effectiveSong.coverUrl.startsWith('/') &&
        !effectiveSong.coverUrl.contains(':\\');
    if (hasValidCover) {
      _resolvedUrl = effectiveSong.coverUrl;
    } else {
      final catalogArt = CatalogDatabase.getSongCoverArt(effectiveSong.title, artist: effectiveSong.artist, album: effectiveSong.album) ??
          CatalogDatabase.getMoviePoster(effectiveSong.album);
      if (catalogArt != null && catalogArt.isNotEmpty) {
        _resolvedUrl = catalogArt;
      }
    }

    final isAlreadyHighRes = _resolvedUrl != null &&
        (_resolvedUrl!.contains('500x500') ||
         _resolvedUrl!.contains('i.scdn.co') ||
         _resolvedUrl!.contains('mzstatic.com') ||
         _resolvedUrl!.contains('aac.saavncdn.com') ||
         _resolvedUrl!.contains('dzcdn.net'));

    if (widget.autoResolve && !isAlreadyHighRes) {
      CoverArtResolver.resolveCover(effectiveSong).then((url) {
        if (mounted && url.isNotEmpty && url != _resolvedUrl && !CoverArtResolver.isPlaylistCover(url)) {
          setState(() {
            _resolvedUrl = url;
          });
        }
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = (_resolvedUrl ?? widget.coverUrl ?? widget.song?.coverUrl ?? '').trim();
    final url = CoverArtResolver.isPlaylistCover(rawUrl) ? '' : rawUrl;
    final radius = widget.borderRadius ?? BorderRadius.circular(10);

    // Dynamic resolution derivation: set ONLY ONE dimension to preserve aspect ratio
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final layoutDim = widget.width ?? widget.height ?? 60.0;
    final int? effectiveCacheWidth = widget.memCacheWidth ??
        (widget.memCacheHeight == null ? (layoutDim * dpr).clamp(64.0, 1024.0).round() : null);
    final int? effectiveCacheHeight = widget.memCacheHeight;

    // 0. Local offline artwork: If song is downloaded or local cover exists on disk, load directly from file
    final candidateLocal = _normalizePath(widget.song?.localCoverPath) ??
        (widget.song != null ? _normalizePath(DownloadManager.getLocalCoverPath(widget.song!.id)) : null) ??
        _normalizePath(widget.coverUrl) ??
        _normalizePath(rawUrl);

    if (candidateLocal != null && (candidateLocal.startsWith('/') || candidateLocal.contains(':\\') || candidateLocal.contains(':/'))) {
      final localFile = File(candidateLocal);
      if (localFile.existsSync()) {
        return ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Image.file(
              localFile,
              fit: widget.fit,
              errorBuilder: (_, __, ___) => widget.errorWidget ?? _buildPlaceholder(radius),
            ),
          ),
        );
      }
    }

    // Fallback: If local file path failed or is missing, recover remote cover or catalog art
    var effectiveUrl = url;
    if (effectiveUrl.startsWith('/') || effectiveUrl.contains(':\\') || effectiveUrl.startsWith('file://')) {
      final catalogArt = widget.song != null
          ? (CatalogDatabase.getSongCoverArt(widget.song!.title, artist: widget.song!.artist, album: widget.song!.album) ??
              CatalogDatabase.getMoviePoster(widget.song!.album))
          : null;
      effectiveUrl = catalogArt ?? CoverArtResolver.getCachedCover(widget.song?.id ?? '') ?? '';
    }

    // 1. Empty cover or stock placeholder fallback or unresolvable file URI: render neutral gradient
    if (effectiveUrl.isEmpty || effectiveUrl.contains('unsplash.com') || effectiveUrl.startsWith('file://') || effectiveUrl.startsWith('/') || effectiveUrl.contains(':\\')) {
      return widget.errorWidget ?? _buildPlaceholder(radius);
    }

    // 2. 16:9 YouTube video thumbnail: single decode with ambient letterbox backdrop
    if (CoverArtResolver.isYouTubeThumbnail(effectiveUrl)) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E1B2E), Color(0xFF0F0D17)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              CachedNetworkImage(
                imageUrl: effectiveUrl,
                fit: BoxFit.cover,
                memCacheWidth: effectiveCacheWidth,
                memCacheHeight: effectiveCacheHeight,
                placeholder: (_, __) => _buildPlaceholder(radius),
                errorWidget: (_, __, ___) => widget.errorWidget ?? _buildPlaceholder(radius),
              ),
            ],
          ),
        ),
      );
    }

    // 3. High-res studio square artwork
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: CachedNetworkImage(
          imageUrl: effectiveUrl,
          fit: widget.fit,
          memCacheWidth: effectiveCacheWidth,
          memCacheHeight: effectiveCacheHeight,
          placeholder: (_, __) => _buildPlaceholder(radius),
          errorWidget: (_, __, ___) => widget.errorWidget ?? _buildPlaceholder(radius),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BorderRadius radius) {
    final iconSize = (widget.width != null && widget.width! > 0)
        ? (widget.width! * 0.45).clamp(14.0, 56.0)
        : 22.0;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B2E), Color(0xFF110E1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.3),
          size: iconSize,
        ),
      ),
    );
  }
}
