import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Interactive & dynamic visual frequency response curve canvas for the 5-band Equalizer.
/// Renders a smooth cubic Catmull-Rom or Bézier spline connecting the 5 frequency bands
/// with an ethereal gradient glow, dB grid markings, and illuminated node anchors.
class EqualizerCurveCanvas extends StatelessWidget {
  final List<double> bands;
  final double height;
  final bool showLabels;

  const EqualizerCurveCanvas({
    Key? key,
    required this.bands,
    this.height = 100,
    this.showLabels = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: CustomPaint(
        painter: _EqualizerCurvePainter(
          bands: bands,
          showLabels: showLabels,
        ),
      ),
    );
  }
}

class _EqualizerCurvePainter extends CustomPainter {
  final List<double> bands;
  final bool showLabels;

  _EqualizerCurvePainter({
    required this.bands,
    required this.showLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final zeroY = height / 2;

    // Draw grid lines: +10dB, 0dB, -10dB
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    final zeroLinePaint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.25)
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, height * 0.1), Offset(width, height * 0.1), gridPaint);
    canvas.drawLine(Offset(0, zeroY), Offset(width, zeroY), zeroLinePaint);
    canvas.drawLine(Offset(0, height * 0.9), Offset(width, height * 0.9), gridPaint);

    // Calculate node coordinates for each of the 5 bands
    final pointCount = bands.length;
    final points = <Offset>[];

    for (int i = 0; i < pointCount; i++) {
      final x = (i + 0.5) * (width / pointCount);
      final gain = bands[i].clamp(-10.0, 10.0);
      // Map gain (-10 to +10) to Y (bottom to top, inverted in canvas)
      // +10 dB -> height * 0.1
      // 0 dB   -> height * 0.5
      // -10 dB -> height * 0.9
      final normalized = (gain + 10.0) / 20.0; // 0.0 to 1.0
      final y = height * 0.9 - normalized * (height * 0.8);
      points.add(Offset(x, y));
    }

    // Build smooth cubic curve through points
    final path = Path();
    final fillPath = Path();

    // Start with a gentle entry from x=0
    final firstPoint = points.first;
    path.moveTo(0, (zeroY + firstPoint.dy) / 2);
    fillPath.moveTo(0, height);
    fillPath.lineTo(0, (zeroY + firstPoint.dy) / 2);

    for (int i = 0; i < points.length; i++) {
      if (i == 0) {
        path.quadraticBezierTo(
          firstPoint.dx * 0.4,
          firstPoint.dy,
          firstPoint.dx,
          firstPoint.dy,
        );
        fillPath.quadraticBezierTo(
          firstPoint.dx * 0.4,
          firstPoint.dy,
          firstPoint.dx,
          firstPoint.dy,
        );
      } else {
        final prev = points[i - 1];
        final curr = points[i];
        final controlX1 = prev.dx + (curr.dx - prev.dx) / 2;
        final controlX2 = prev.dx + (curr.dx - prev.dx) / 2;

        path.cubicTo(
          controlX1,
          prev.dy,
          controlX2,
          curr.dy,
          curr.dx,
          curr.dy,
        );
        fillPath.cubicTo(
          controlX1,
          prev.dy,
          controlX2,
          curr.dy,
          curr.dx,
          curr.dy,
        );
      }
    }

    final lastPoint = points.last;
    path.quadraticBezierTo(
      width - (width - lastPoint.dx) * 0.4,
      lastPoint.dy,
      width,
      (zeroY + lastPoint.dy) / 2,
    );
    fillPath.quadraticBezierTo(
      width - (width - lastPoint.dx) * 0.4,
      lastPoint.dy,
      width,
      (zeroY + lastPoint.dy) / 2,
    );
    fillPath.lineTo(width, height);
    fillPath.close();

    // Draw gradient fill beneath the curve
    final fillGradient = ui.Gradient.linear(
      Offset(0, height * 0.1),
      Offset(0, height),
      [
        const Color(0xFF06B6D4).withValues(alpha: 0.28),
        const Color(0xFF8B5CF6).withValues(alpha: 0.12),
        Colors.transparent,
      ],
      [0.0, 0.65, 1.0],
    );
    final fillPaint = Paint()
      ..shader = fillGradient
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw curve stroke with glowing gradient
    final strokeGradient = ui.Gradient.linear(
      Offset.zero,
      Offset(width, 0),
      const [
        Color(0xFF06B6D4), // Cyan
        Color(0xFF6366F1), // Indigo
        Color(0xFFA855F7), // Purple
        Color(0xFFEC4899), // Pink
      ],
      const [0.0, 0.33, 0.66, 1.0],
    );

    // Outer glow
    final glowPaint = Paint()
      ..shader = strokeGradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawPath(path, glowPaint);

    // Main sharp line
    final strokePaint = Paint()
      ..shader = strokeGradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Draw glowing node dots at each band coordinate
    for (int i = 0; i < points.length; i++) {
      final p = points[i];

      // Outer ring glow
      final nodeGlow = Paint()
        ..color = const Color(0xFF06B6D4).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(p, 6, nodeGlow);

      // Node background
      final nodeBg = Paint()..color = const Color(0xFF0F172A);
      canvas.drawCircle(p, 4.5, nodeBg);

      // Node center
      final nodeCenter = Paint()
        ..color = const Color(0xFF06B6D4)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 2.5, nodeCenter);
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerCurvePainter oldDelegate) {
    if (oldDelegate.bands.length != bands.length) return true;
    for (int i = 0; i < bands.length; i++) {
      if (oldDelegate.bands[i] != bands[i]) return true;
    }
    return false;
  }
}
