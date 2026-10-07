import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/player_handler.dart';
import '../../../services/settings_manager.dart';
import 'volume_hud_overlay.dart';

/// Wraps player views (such as Album Artwork) with interactive touch gestures:
/// - Swipe Left: Skip to Next Song
/// - Swipe Right: Skip to Previous Song
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

class _PlayerGestureDetectorState extends State<PlayerGestureDetector> {
  Timer? _hudDismissTimer;
  bool _isVolumeHudVisible = false;
  double _currentVolume = 1.0;

  // Horizontal swipe tracking
  double _horizontalDragDistance = 0.0;

  @override
  void initState() {
    super.initState();
    if (isAudioHandlerInitialized) {
      _currentVolume = audioHandler.player.volume;
    }
  }

  @override
  void dispose() {
    _hudDismissTimer?.cancel();
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
    _horizontalDragDistance = 0.0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _horizontalDragDistance += details.delta.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!SettingsManager.isPlayerGesturesEnabled) return;

    final velocity = details.primaryVelocity ?? 0.0;
    const minDistance = 45.0;
    const minVelocity = 280.0;

    // Swipe Left (Right to Left) -> Next Track
    if (_horizontalDragDistance < -minDistance || velocity < -minVelocity) {
      HapticFeedback.lightImpact();
      if (isAudioHandlerInitialized) {
        audioHandler.skipToNext();
      }
    }
    // Swipe Right (Left to Right) -> Previous Track
    else if (_horizontalDragDistance > minDistance || velocity > minVelocity) {
      HapticFeedback.lightImpact();
      if (isAudioHandlerInitialized) {
        audioHandler.skipToPrevious();
      }
    }

    _horizontalDragDistance = 0.0;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!SettingsManager.isPlayerGesturesEnabled) return;

    // Moving up gives negative delta.dy -> increase volume
    // Full swipe distance (~220 pixels) spans 0.0 to 1.0 volume range
    const swipeSensitivity = 220.0;
    final deltaVolume = -details.delta.dy / swipeSensitivity;
    final newVolume = (_currentVolume + deltaVolume).clamp(0.0, 1.0);

    if ((newVolume - _currentVolume).abs() > 0.005 || newVolume == 0.0 || newVolume == 1.0) {
      _currentVolume = newVolume;
      if (isAudioHandlerInitialized) {
        audioHandler.player.setVolume(newVolume);
      }
      _showVolumeHud(newVolume);

      // Light haptic tick when hitting limits
      if (newVolume == 0.0 || newVolume == 1.0) {
        HapticFeedback.selectionClick();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.playerGesturesEnabledNotifier,
      builder: (context, gesturesEnabled, _) {
        if (!gesturesEnabled) {
          return widget.child;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              child: widget.child,
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
