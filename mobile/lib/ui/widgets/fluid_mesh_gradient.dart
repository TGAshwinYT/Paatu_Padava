import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class FluidMeshGradient extends StatefulWidget {
  final String? imageUrl;
  final Widget? child;
  final double blurSigma;
  final double opacity;
  final bool animate;

  const FluidMeshGradient({
    Key? key,
    required this.imageUrl,
    this.child,
    this.blurSigma = 70.0,
    this.opacity = 0.55,
    this.animate = true,
  }) : super(key: key);

  @override
  State<FluidMeshGradient> createState() => _FluidMeshGradientState();
}

class _FluidMeshGradientState extends State<FluidMeshGradient> with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(FluidMeshGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _extractColors();
    }
  }

  @override
  void dispose() {
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
      final imageProvider = CachedNetworkImageProvider(url);
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 16,
      );

      final extracted = <Color>[];

      if (palette.vibrantColor != null) extracted.add(palette.vibrantColor!.color);
      if (palette.lightVibrantColor != null) extracted.add(palette.lightVibrantColor!.color);
      if (palette.darkVibrantColor != null) extracted.add(palette.darkVibrantColor!.color);
      if (palette.dominantColor != null) extracted.add(palette.dominantColor!.color);
      if (palette.mutedColor != null) extracted.add(palette.mutedColor!.color);

      // Filter out overly dark or grayscale colors
      final vibrantList = extracted.where((c) {
        final hsl = HSLColor.fromColor(c);
        return hsl.saturation > 0.15 && hsl.lightness > 0.15 && hsl.lightness < 0.85;
      }).toList();

      if (vibrantList.length >= 2) {
        while (vibrantList.length < 4) {
          vibrantList.add(vibrantList.first.withOpacity(0.8));
        }
        _paletteCache[url] = vibrantList.take(4).toList();
        if (mounted) {
          setState(() {
            _colors = _paletteCache[url]!;
          });
        }
      }
    } catch (_) {
      // Fallback to default vibrant palette
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base dark backdrop
        Container(color: const Color(0xFF0A0E1A)),

        // Animated Fluid Mesh Blobs
        AnimatedBuilder(
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

        // Deep Gaussian Blur for smooth luminous fluid effect
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: widget.blurSigma, sigmaY: widget.blurSigma),
            child: Container(
              color: Colors.transparent,
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
                  const Color(0xFF0A0E1A).withOpacity(0.40),
                  Colors.transparent,
                  const Color(0xFF0A0E1A).withOpacity(0.85),
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

  _FluidMeshPainter({
    required this.colors,
    required this.progress,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;

    final c1 = colors[0].withOpacity(opacity);
    final c2 = colors.length > 1 ? colors[1].withOpacity(opacity * 0.9) : c1;
    final c3 = colors.length > 2 ? colors[2].withOpacity(opacity * 0.85) : c2;
    final c4 = colors.length > 3 ? colors[3].withOpacity(opacity * 0.8) : c1;

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

    // Draw radial gradient spheres
    _drawRadialBlob(canvas, p1, r1, c1);
    _drawRadialBlob(canvas, p2, r2, c2);
    _drawRadialBlob(canvas, p3, r3, c3);
    _drawRadialBlob(canvas, p4, r4, c4);
  }

  void _drawRadialBlob(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withOpacity(0.0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _FluidMeshPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.colors != colors;
  }
}
