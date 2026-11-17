import 'package:flutter/material.dart';

enum DeviceTier { compact, standard, tablet }
enum TextScaleTier { dense, card, flow }

/// Centralized Responsive Layout & DPI Adaptation Engine for Paatu Padava.
/// Ensures consistent, pixel-perfect scaling across diverse screen resolutions,
/// device pixel ratios (DPI), and OS accessibility text scale factors.
class AppDimensions {
  /// Base design viewport width (standard modern flagship phone in dp)
  static const double baselineWidth = 390.0;
  static const double baselineHeight = 844.0;

  // ── Device Breakpoints ──
  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 340;
  static bool isStandard(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 340 && w < 600;
  }
  static bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;
  static bool isShortScreen(BuildContext context) => MediaQuery.sizeOf(context).height < 640;
  static bool isLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  /// Categorizes device into high-level tiers
  static DeviceTier deviceTier(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) return DeviceTier.compact;
    if (w >= 600) return DeviceTier.tablet;
    return DeviceTier.standard;
  }

  /// Dynamic horizontal screen padding that adapts to screen density:
  /// • Compact (<340dp): 12dp to preserve tile room
  /// • Standard (340-600dp): 16dp to 20dp
  /// • Tablets (>=600dp): 28dp
  static double screenPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) return 12.0;
    if (w < 412) return 16.0;
    if (w < 600) return 20.0;
    return 28.0;
  }

  /// Resolves exact physical pixel dimensions for memory image caching,
  /// preventing thumbnail blurriness on 3.0x (xxhdpi) and 4.0x (xxxhdpi) screens.
  static int memCachePhysical(BuildContext context, double logicalDp) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    return (logicalDp * dpr).ceil();
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

  /// 3-Tier contextual typography scaler:
  /// • Dense (0.85x - 1.20x): Transport controls, badges, timers
  /// • Card (0.85x - 1.35x): Headings, shelf cards, titles
  /// • Flow (0.85x - 1.80x): Scrollable reading (lyrics, biographies)
  static TextScaler textScalerFor(BuildContext context, TextScaleTier tier) {
    final base = MediaQuery.textScalerOf(context);
    switch (tier) {
      case TextScaleTier.dense:
        return base.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.20);
      case TextScaleTier.card:
        return base.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.35);
      case TextScaleTier.flow:
        return base.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.80);
    }
  }

  /// Responsive cover art dimension for song list tiles (46dp compact, 50dp standard, 56dp tablet)
  static double songTileCoverSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) return 44.0;
    if (w < 360) return 46.0;
    if (w >= 600) return 56.0;
    return 50.0;
  }

  /// Dynamic card width for horizontal song & album carousels
  static double homeCardWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 600) return (w * 0.22).clamp(140.0, 200.0);
    if (w < 340) return (w * 0.44).clamp(110.0, 140.0);
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

  /// Safe artwork dimension calculator for FullPlayerScreen that strictly guarantees
  /// lowerLimit <= upperLimit, eliminating ArgumentError crashes in split-screen or landscape.
  static double safeArtworkSize(BuildContext context, {required double maxAvailable}) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isShort = isShortScreen(context);
    final targetIdeal = isShort ? screenWidth * 0.50 : screenWidth * 0.78;
    final upper = maxAvailable > 0 ? maxAvailable : 340.0;
    final lower = (upper < 120.0) ? upper : 120.0;
    return targetIdeal.clamp(lower, upper);
  }

  /// Adaptive grid column count calculator based on available content width.
  static int gridCrossAxisCount(BuildContext context, {double targetTileWidth = 160.0}) {
    final available = MediaQuery.sizeOf(context).width - (screenPadding(context) * 2);
    return (available / targetTileWidth).floor().clamp(2, 6);
  }

  /// Hairline border thickness scaled to physical pixel resolution.
  static double hairline(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return dpr > 0 ? (1.0 / dpr) : 1.0;
  }

  /// Unified bottom clearance ensuring scroll views are never obscured by
  /// the persistent MiniPlayer and BottomNavigationBar, without double-counting nav bars.
  ///
  /// • In Tab Screens (inNavTab: true):
  ///   miniPlayerHeight (78) + (extendBody ? bottomNavHeight (56) + bottomInset : 0) + spacing
  /// • In Pushed Detail Screens (inNavTab: false):
  ///   miniPlayerHeight (78) + safeArea.bottom + spacing
  static double bottomClearance(
    BuildContext context, {
    bool? hasActiveTrack,
    bool hasBottomNav = true,
    bool isInsideBottomNavTab = true,
    bool extendBody = false,
  }) {
    const miniPlayerHeight = 78.0;
    const spacing = 12.0;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final bool showMiniPlayer = hasActiveTrack ?? true;
    double clearance = spacing;
    if (showMiniPlayer) {
      clearance += miniPlayerHeight;
    }

    final bool inNavTab = hasBottomNav && isInsideBottomNavTab;
    if (inNavTab) {
      if (extendBody) {
        clearance += 56.0 + bottomInset;
      }
    } else {
      clearance += bottomInset;
    }
    return clearance;
  }
}
