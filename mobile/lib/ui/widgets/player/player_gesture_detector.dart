import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/player_handler.dart';
import '../../../services/settings_manager.dart';
import 'volume_hud_overlay.dart';

/// Wraps player views (such as Album Artwork) with interactive touch gestures:
/// - Interactive Swipe Left: Card tracks user touch, slides off-screen, and transitions to Next Song
/// - Interactive Swipe Right: Card tracks user touch, slides off-screen, and transitions to Previous Song
/// - Incomplete Swipes: Card spring-bounces back to center if release is below commit threshold
/// - Swipe Up: Increase in-app music volume
/// - Swipe Down: Decrease in-app music volume
class PlayerGestureDetector extends StatefulWidget {
  final Widget child;

  const PlayerGestureDetector({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<PlayerGestureDetector> createState() => _PlayerGestureDetectorState();
}

class _PlayerGestureDetectorState extends State<PlayerGestureDetector>
    with SingleTickerProviderStateMixin {
  Timer? _hudDismissTimer;
  bool _isVolumeHudVisible = false;
  double _currentVolume = 1.0;

  // Interactive horizontal drag tracking & animation
  late final AnimationController _animController;
  Animation<double>? _slideAnimation;
  double _dragOffset = 0.0;
  bool _isDraggingHorizontal = false;
  bool _isDraggingVertical = false;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        if (_slideAnimation != null) {
          setState(() {
            _dragOffset = _slideAnimation!.value;
          });
        }
      });

    if (isAudioHandlerInitialized) {
      _currentVolume = audioHandler.userVolume;
    }
  }

  @override
  void dispose() {
    _hudDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _showVolumeHud(double vol) {
    _hudDismissTimer?.cancel();
    setState(() {
      _currentVolume = vol.clamp(0.0, 1.0);
      _isVolumeHudVisible = true;
    });

    _hudDismissTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _isVolumeHudVisible = false;
        });
      }
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!SettingsManager.isPlayerGesturesEnabled || _isTransitioning) return;
    if (_animController.isAnimating) {
      _animController.stop();
    }
    _isDraggingHorizontal = true;
    _isDraggingVertical = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!SettingsManager.isPlayerGesturesEnabled || _isTransitioning || !_isDraggingHorizontal) return;
    setState(() {
      _dragOffset += details.delta.dx;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!SettingsManager.isPlayerGesturesEnabled || _isTransitioning || !_isDraggingHorizontal) {
      _isDraggingHorizontal = false;
      return;
    }
    _isDraggingHorizontal = false;

    final screenWidth = MediaQuery.of(context).size.width;
    // User must move at least ~35% of the screen width to commit track change,
    // or provide an energetic fling gesture in that direction
    final commitThreshold = screenWidth * 0.35;
    final velocity = details.primaryVelocity ?? 0.0;

    final isCommittedLeft = _dragOffset < -commitThreshold || (velocity < -650 && _dragOffset < -40);
    final isCommittedRight = _dragOffset > commitThreshold || (velocity > 650 && _dragOffset > 40);

    if (isCommittedLeft) {
      _executeCommitTransition(isNext: true, screenWidth: screenWidth);
    } else if (isCommittedRight) {
      _executeCommitTransition(isNext: false, screenWidth: screenWidth);
    } else {
      // User didn't commit: smoothly bounce/spring back to center
      _animateBackToCenter();
    }
  }

  void _onHorizontalDragCancel() {
    _isDraggingHorizontal = false;
    if (!_isTransitioning && _dragOffset != 0.0) {
      _animateBackToCenter();
    }
  }

  /// Spring-animates card back to center if swipe didn't cross commit threshold
  void _animateBackToCenter() {
    final start = _dragOffset;
    _slideAnimation = Tween<double>(begin: start, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.duration = const Duration(milliseconds: 220);
    _animController.forward(from: 0.0);
  }

  /// Smoothly carries active card completely off-screen, switches track,
  /// then glides incoming card into center from opposite edge
  Future<void> _executeCommitTransition({
    required bool isNext,
    required double screenWidth,
  }) async {
    _isTransitioning = true;
    final exitTarget = isNext ? -screenWidth * 1.15 : screenWidth * 1.15;

    // 1. Smoothly accelerate out off-screen
    _slideAnimation = Tween<double>(begin: _dragOffset, end: exitTarget).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInCubic),
    );
    _animController.duration = const Duration(milliseconds: 170);
    try {
      await _animController.forward(from: 0.0);
    } catch (_) {}

    // 2. Trigger skip once card has fully departed
    HapticFeedback.lightImpact();
    if (isAudioHandlerInitialized) {
      if (isNext) {
        audioHandler.skipToNext();
      } else {
        audioHandler.skipToPrevious();
      }
    }

    if (!mounted) return;

    // 3. Incoming card glides in smoothly from opposite edge
    final enterStart = isNext ? screenWidth * 0.40 : -screenWidth * 0.40;
    _slideAnimation = Tween<double>(begin: enterStart, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.duration = const Duration(milliseconds: 240);
    try {
      await _animController.forward(from: 0.0);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _dragOffset = 0.0;
        _isTransitioning = false;
      });
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (!SettingsManager.isPlayerGesturesEnabled || _isTransitioning) return;
    if (_dragOffset.abs() > 10) return;
    _isDraggingVertical = true;
    _isDraggingHorizontal = false;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!SettingsManager.isPlayerGesturesEnabled || _isTransitioning || !_isDraggingVertical) return;

    // Moving up gives negative delta.dy -> increase volume
    // Full swipe distance (~220 pixels) spans 0.0 to 1.0 volume range
    const swipeSensitivity = 220.0;
    final deltaVolume = -details.delta.dy / swipeSensitivity;
    final newVolume = (_currentVolume + deltaVolume).clamp(0.0, 1.0);

    if ((newVolume - _currentVolume).abs() > 0.005 || newVolume == 0.0 || newVolume == 1.0) {
      _currentVolume = newVolume;
      if (isAudioHandlerInitialized) {
        audioHandler.setUserVolume(newVolume);
      }
      _showVolumeHud(newVolume);

      // Light haptic tick when hitting limits
      if (newVolume == 0.0 || newVolume == 1.0) {
        HapticFeedback.selectionClick();
      }
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isDraggingVertical = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.playerGesturesEnabledNotifier,
      builder: (context, gesturesEnabled, _) {
        if (!gesturesEnabled) {
          return widget.child;
        }

        final screenWidth = MediaQuery.of(context).size.width;
        final rotationAngle = (_dragOffset / 1400.0).clamp(-0.12, 0.12);
        final scaleFactor = (1.0 - (_dragOffset.abs() / 2500.0)).clamp(0.92, 1.0);
        final opacityFactor = (1.0 - (_dragOffset.abs() / (screenWidth * 1.3))).clamp(0.0, 1.0);

        return Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onHorizontalDragCancel: _onHorizontalDragCancel,
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: RepaintBoundary(
                child: Transform.translate(
                  offset: Offset(_dragOffset, 0),
                  child: Transform.rotate(
                    angle: rotationAngle,
                    child: Transform.scale(
                      scale: scaleFactor,
                      child: Opacity(
                        opacity: opacityFactor,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              ignoring: true,
              child: VolumeHudOverlay(
                volume: _currentVolume,
                isVisible: _isVolumeHudVisible,
              ),
            ),
          ],
        );
      },
    );
  }
}
