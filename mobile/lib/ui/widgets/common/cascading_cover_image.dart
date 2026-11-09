import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../services/cover_art_resolver.dart';

/// 3-Tier Cascading Cover Art Widget.
///
/// Implements progressive image loading:
/// - Tier 1 (0ms): Deterministic ThumbHash / HSL gradient placeholder (zero network delay).
/// - Tier 2 (< 80ms): Fast low-resolution thumbnail (50x50 / 150x150) fetched or served from cache.
/// - Tier 3 (JIT): Full 500x500 / studio master artwork with smooth cross-fade transition.
class CascadingCoverImage extends StatelessWidget {
  final String imageUrl;
  final String? lowResUrl;
  final String? seed;
  final double width;
  final double height;
  final double borderRadius;
  final BoxFit fit;
  final Widget? overlay;

  const CascadingCoverImage({
    super.key,
    required this.imageUrl,
    this.lowResUrl,
    this.seed,
    this.width = 50,
    this.height = 50,
    this.borderRadius = 10,
    this.fit = BoxFit.cover,
    this.overlay,
  });

  /// Derives an instantaneous low-res thumbnail URL from a high-res Saavn/YouTube URL.
  static String? deriveLowResUrl(String highRes) {
    if (highRes.isEmpty) return null;

    // JioSaavn: 500x500 -> 50x50 or 150x150
    if (highRes.contains('500x500')) {
      return highRes.replaceAll('500x500', '150x150');
    }

    // YouTube: maxresdefault / hqdefault -> default
    if (highRes.contains('maxresdefault.jpg')) {
      return highRes.replaceAll('maxresdefault.jpg', 'default.jpg');
    }
    if (highRes.contains('hqdefault.jpg')) {
      return highRes.replaceAll('hqdefault.jpg', 'default.jpg');
    }

    return null;
  }

  /// Builds the 0ms instant ThumbHash / HSL ambient placeholder.
  Widget _buildThumbHashPlaceholder({double? iconSize}) {
    final effectiveSeed = seed ?? imageUrl;
    final hash = effectiveSeed.hashCode.abs();
    final hue1 = (hash % 360).toDouble();
    final hue2 = ((hash ~/ 360 + 50) % 360).toDouble();
    final color1 = HSLColor.fromAHSL(1.0, hue1, 0.40, 0.20).toColor();
    final color2 = HSLColor.fromAHSL(1.0, hue2, 0.50, 0.14).toColor();

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color1, color2],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.35),
          size: iconSize ?? (width * 0.40).clamp(16.0, 36.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLowRes = lowResUrl ?? deriveLowResUrl(imageUrl);
    final hasDistinctLowRes = effectiveLowRes != null && effectiveLowRes != imageUrl;

    Widget imageContent;

    if (imageUrl.isEmpty || CoverArtResolver.isPlaylistCover(imageUrl)) {
      imageContent = _buildThumbHashPlaceholder();
    } else {
      imageContent = CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: (width * 2.5).toInt(),
        memCacheHeight: (height * 2.5).toInt(),
        fadeInDuration: const Duration(milliseconds: 220),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (context, _) {
          // Tier 2: Render low-res thumbnail if available while Tier 3 (HQ) loads
          if (hasDistinctLowRes) {
            return CachedNetworkImage(
              imageUrl: effectiveLowRes,
              width: width,
              height: height,
              fit: fit,
              memCacheWidth: 100,
              memCacheHeight: 100,
              placeholder: (_, __) => _buildThumbHashPlaceholder(),
              errorWidget: (_, __, ___) => _buildThumbHashPlaceholder(),
            );
          }
          // Tier 1: 0ms ThumbHash fallback
          return _buildThumbHashPlaceholder();
        },
        errorWidget: (context, _, __) {
          if (hasDistinctLowRes) {
            return CachedNetworkImage(
              imageUrl: effectiveLowRes,
              width: width,
              height: height,
              fit: fit,
              errorWidget: (_, __, ___) => _buildThumbHashPlaceholder(),
            );
          }
          return _buildThumbHashPlaceholder();
        },
      );
    }

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: imageContent,
      ),
    );

    if (overlay != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          clipped,
          overlay!,
        ],
      );
    }

    return clipped;
  }
}
