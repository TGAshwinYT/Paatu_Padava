import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/cover_art_resolver.dart';

/// Reusable high-performance cover art widget for Paatu Padava.
///
/// Features:
/// 1. Decodes images at constrained memory dimensions via `memCacheWidth`/`memCacheHeight`
///    to eliminate scroll stutter and prevent high-res bitmap bloat in memory.
/// 2. Gracefully handles 16:9 YouTube video thumbnails: renders a blurred ambient
///    background fill behind a centered frame rather than awkward hard square crops.
/// 3. Asynchronously upgrades YouTube thumbnails to 1000x1000 studio square art
///    via [CoverArtResolver] in the background without blocking the UI.
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
    this.memCacheWidth = 150,
    this.memCacheHeight = 150,
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

  void _checkAndResolve() {
    final effectiveSong = widget.song;
    if (effectiveSong == null) {
      _resolvedUrl = widget.coverUrl;
      return;
    }

    final songId = effectiveSong.id;
    final cached = CoverArtResolver.getCachedCover(songId);
    if (cached != null && cached.isNotEmpty) {
      _resolvedUrl = cached;
      return;
    }

    _resolvedUrl = effectiveSong.coverUrl;

    if (widget.autoResolve) {
      CoverArtResolver.resolveCover(effectiveSong).then((url) {
        if (mounted && url.isNotEmpty && url != _resolvedUrl) {
          setState(() {
            _resolvedUrl = url;
          });
        }
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = (_resolvedUrl ?? widget.coverUrl ?? widget.song?.coverUrl ?? '').trim();
    final radius = widget.borderRadius ?? BorderRadius.circular(10);

    // 1. Empty cover or stock placeholder fallback: render neutral gradient
    if (url.isEmpty || url.contains('unsplash.com')) {
      return _buildPlaceholder(radius);
    }

    // 2. 16:9 YouTube video thumbnail: render with blurred ambient background
    if (CoverArtResolver.isYouTubeThumbnail(url)) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred ambient background
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  memCacheWidth: widget.memCacheWidth ?? 120,
                  memCacheHeight: widget.memCacheHeight ?? 120,
                  errorWidget: (_, __, ___) => _buildPlaceholder(radius),
                ),
              ),
              // Dimming scrim
              Container(color: Colors.black.withValues(alpha: 0.35)),
              // Contained foreground thumbnail
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                memCacheWidth: widget.memCacheWidth ?? 150,
                memCacheHeight: widget.memCacheHeight ?? 150,
                errorWidget: (_, __, ___) => _buildPlaceholder(radius),
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
          imageUrl: url,
          fit: widget.fit,
          memCacheWidth: widget.memCacheWidth,
          memCacheHeight: widget.memCacheHeight,
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
