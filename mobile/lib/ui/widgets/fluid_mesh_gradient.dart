import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:paatu_padava_mobile/services/app_logger.dart';

/// High-performance fluid mesh gradient that renders animated luminous radial blobs.
/// Optimized for 60/120fps with zero full-screen BackdropFilter GPU blurs,
/// isolated in a RepaintBoundary with reusable Paint caches and 32x32 palette decoding.
class FluidMeshGradient extends StatefulWidget {
  final String? imageUrl;
  final Widget? child;
  final double blurSigma;
  final double opacity;
  final bool animate;

  const FluidMeshGradient({
    super.key,
    required this.imageUrl,
    this.child,
    this.blurSigma = 70.0,
    this.opacity = 0.55,
    this.animate = true,
  });

  @override
  State<FluidMeshGradient> createState() => _FluidMeshGradientState();
}

class _FluidMeshGradientState extends State<FluidMeshGradient>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static final Map<String, List<Color>> _paletteCache = {};

  late AnimationController _controller;
  List<Color> _colors = const [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Purple
    Color(0xFF06B6D4), // Cyan
    Color(0xFFEC4899), // Pink
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    if (widget.animate) {
      _controller.repeat();
    }

    _extractColors();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_controller.isAnimating) _controller.stop();
    } else if (state == AppLifecycleState.resumed && widget.animate) {
      if (!_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(FluidMeshGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _extractColors();
    }
    if (oldWidget.animate != widget.animate) {
      if (widget.animate) {
        if (!_controller.isAnimating) _controller.repeat();
      } else {
        if (_controller.isAnimating) _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _extractColors() async {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    if (_paletteCache.containsKey(url)) {
      if (mounted) {
        setState(() {
          _colors = _paletteCache[url]!;
        });
      }
      return;
    }

    try {
      // Decode a lightweight 16x16 thumbnail for instant sub-millisecond dominant color extraction
      final imageProvider = ResizeImage(
        CachedNetworkImageProvider(url),
        width: 16,
        height: 16,
      );

      final completer = Completer<ui.Image>();
      final stream = imageProvider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (err, stack) {
          if (!completer.isCompleted) completer.completeError(err);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final uiImage = await completer.future.timeout(const Duration(seconds: 3));
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final candidates = <Color>[];

      for (int i = 0; i < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        final a = bytes[i + 3];
        if (a < 128) continue;

        final max = math.max(r, math.max(g, b));
        final min = math.min(r, math.min(g, b));
        final l = (max + min) / 510.0;
        final s = (max == min) ? 0.0 : (l <= 0.5 ? (max - min) / (max + min) : (max - min) / (510.0 - max - min));

        // Filter for vibrant, colorful pixels
        if (s > 0.25 && l > 0.20 && l < 0.85) {
          final c = Color.fromARGB(255, r, g, b);
          // Check if sufficiently distinct from existing candidates
          final isDistinct = candidates.every((existing) {
            final dr = ((existing.r * 255).round() - r).abs();
            final dg = ((existing.g * 255).round() - g).abs();
            final db = ((existing.b * 255).round() - b).abs();
            return (dr + dg + db) > 60;
          });
          if (isDistinct) {
            candidates.add(c);
            if (candidates.length >= 4) break;
          }
        }
      }

      if (candidates.isNotEmpty) {
        while (candidates.length < 4) {
          candidates.add(candidates.first.withValues(alpha: 0.8));
        }
        if (_paletteCache.length >= 50) {
          _paletteCache.remove(_paletteCache.keys.first);
        }
        _paletteCache[url] = candidates.take(4).toList();
        if (mounted) {
          setState(() {
            _colors = _paletteCache[url]!;
          });
        }
      }
    } catch (e) {
      AppLogger.debug('FluidMeshGradient', 'Handled exception: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base dark backdrop
        const ColoredBox(color: Color(0xFF0A0E1A)),

        // Animated Fluid Mesh Blobs isolated in a RepaintBoundary
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value * 2 * math.pi;

                return CustomPaint(
                  painter: _FluidMeshPainter(
                    colors: _colors,
                    progress: t,
                    opacity: widget.opacity,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),

        // Contrast Vignette Overlay
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0A0E1A).withValues(alpha: 0.40),
                  Colors.transparent,
                  const Color(0xFF0A0E1A).withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),

        // Child Content (Player, Controls, Lyrics)
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _FluidMeshPainter extends CustomPainter {
  final List<Color> colors;
  final double progress;
  final double opacity;

  // Cached reusable Paint instances to eliminate per-frame allocations
  static final List<Paint> _cachedPaints = List.generate(4, (_) => Paint());

  _FluidMeshPainter({
    required this.colors,
    required this.progress,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;

    final c1 = colors[0].withValues(alpha: opacity);
    final c2 = colors.length > 1 ? colors[1].withValues(alpha: opacity * 0.9) : c1;
    final c3 = colors.length > 2 ? colors[2].withValues(alpha: opacity * 0.85) : c2;
    final c4 = colors.length > 3 ? colors[3].withValues(alpha: opacity * 0.8) : c1;

    // Harmonic sinusoidal displacement trajectories
    final p1 = Offset(
      size.width * (0.30 + 0.18 * math.sin(progress)),
      size.height * (0.28 + 0.15 * math.cos(progress)),
    );
    final r1 = size.width * 0.55;

    final p2 = Offset(
      size.width * (0.72 + 0.16 * math.cos(progress * 1.2)),
      size.height * (0.38 + 0.16 * math.sin(progress * 1.2)),
    );
    final r2 = size.width * 0.50;

    final p3 = Offset(
      size.width * (0.35 + 0.20 * math.sin(progress * 0.8 + 1.0)),
      size.height * (0.75 + 0.14 * math.cos(progress * 0.8 + 1.0)),
    );
    final r3 = size.width * 0.60;

    final p4 = Offset(
      size.width * (0.80 + 0.14 * math.sin(progress * 1.4 + 2.0)),
      size.height * (0.80 + 0.12 * math.cos(progress * 1.4 + 2.0)),
    );
    final r4 = size.width * 0.48;

    // Draw multi-stop soft radial gradient spheres without heavy GPU BackdropFilter passes
    _drawRadialBlob(canvas, _cachedPaints[0], p1, r1, c1);
    _drawRadialBlob(canvas, _cachedPaints[1], p2, r2, c2);
    _drawRadialBlob(canvas, _cachedPaints[2], p3, r3, c3);
    _drawRadialBlob(canvas, _cachedPaints[3], p4, r4, c4);
  }

  void _drawRadialBlob(Canvas canvas, Paint paint, Offset center, double radius, Color color) {
    paint.shader = RadialGradient(
      colors: [
        color,
        color.withValues(alpha: color.a * 0.70),
        color.withValues(alpha: color.a * 0.25),
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.35, 0.70, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _FluidMeshPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.colors != colors ||
        oldDelegate.opacity != opacity;
  }
}
