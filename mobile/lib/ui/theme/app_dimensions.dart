import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Centralized Responsive Layout & DPI Adaptation Engine for Paatu Padava.
/// Ensures consistent, pixel-perfect scaling across diverse screen resolutions,
/// device pixel ratios (DPI), and OS accessibility text scale factors.
class AppDimensions {
  /// Base design viewport width (standard modern flagship phone in dp)
  static const double baselineWidth = 390.0;
  static const double baselineHeight = 844.0;

  // ── Device Breakpoints ──
  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 360;
  static bool isStandard(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 360 && w < 600;
  }
  static bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;

  /// Dynamic horizontal screen padding that adapts to screen density:
  /// • Compact (<360dp): 12dp to preserve tile room
  /// • Standard (360-600dp): 16dp to 20dp
  /// • Tablets (>=600dp): 28dp
  static double screenPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 12.0;
    if (w < 412) return 16.0;
    if (w < 600) return 20.0;
    return 28.0;
  }

  /// Clamps OS text scaling factor to a safe, readable range (0.85x to 1.30x)
  /// for dense audio control bars and list tiles to prevent RenderFlex overflows.
  static TextScaler clampedTextScaler(
    BuildContext context, {
    double min = 0.85,
    double max = 1.30,
  }) {
    return MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: min,
      maxScaleFactor: max,
    );
  }

  /// Responsive cover art dimension for song list tiles (46dp compact, 50dp standard, 56dp tablet)
  static double songTileCoverSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 46.0;
    if (w >= 600) return 56.0;
    return 50.0;
  }

  /// Dynamic card width for horizontal song & album carousels
  static double homeCardWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 600) return (w * 0.22).clamp(140.0, 200.0);
    if (w < 360) return (w * 0.40).clamp(120.0, 150.0);
    return (w * 0.36).clamp(130.0, 180.0);
  }

  /// Dynamic carousel container height taking both card image and scaled text into account
  static double homeCarouselHeight(BuildContext context, double cardWidth) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.35);
    final textAllowance = (56.0 * scale).ceilToDouble();
    return cardWidth + textAllowance;
  }

  /// Proportionally scales a dimension relative to baseline phone width (390dp),
  /// clamped to prevent extremes on small screens or large tablets.
  static double responsive(
    BuildContext context,
    double size, {
    double minScale = 0.85,
    double maxScale = 1.25,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    final ratio = (w / baselineWidth).clamp(minScale, maxScale);
    return (size * ratio).roundToDouble();
  }
}
