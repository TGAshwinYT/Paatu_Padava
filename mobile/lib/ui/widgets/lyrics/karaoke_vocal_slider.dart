import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/player_handler.dart';
import '../../../services/equalizer_service.dart';

/// Apple Music Sing-inspired vertical capsule slider for real-time in-place vocal attenuation.
/// Provides real-time Media3 DSP center cancellation with smooth 40ms sample interpolation
/// and haptic detents.
class KaraokeVocalSlider extends StatefulWidget {
  const KaraokeVocalSlider({super.key});

  @override
  State<KaraokeVocalSlider> createState() => _KaraokeVocalSliderState();
}

class _KaraokeVocalSliderState extends State<KaraokeVocalSlider> {
  bool _isDragging = false;
  int _lastDetentIndex = -1;

  void _handleDrag(Offset globalPosition) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(globalPosition);
    // Height is 150. Drag from bottom (0.0) to top (1.0)
    final rawFraction = 1.0 - (localPos.dy / box.size.height);
    final clampedFraction = rawFraction.clamp(0.0, 1.0);
    final newAttenuation = 1.0 - clampedFraction;

    audioHandler.setVocalAttenuation(newAttenuation);

    // Haptic notch feedback at 0.0, 0.25, 0.50, 0.75, 1.0
    final detentIndex = (clampedFraction * 4.0).round();
    if (detentIndex != _lastDetentIndex) {
      _lastDetentIndex = detentIndex;
      HapticFeedback.selectionClick();
    }
  }

  void _finishDrag() {
    if (mounted) {
      setState(() => _isDragging = false);
    }
  }

  String _getModeLabel(double vocalLevel, bool isDspActive) {
    if (vocalLevel <= 0.08) {
      return isDspActive ? 'DSP Vocal Cancel' : 'Vocal Reduce (EQ Fallback)';
    }
    if (vocalLevel <= 0.40) return 'Guide Vocal';
    if (vocalLevel <= 0.75) return 'Sing-Along';
    return 'Full Vocals';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: audioHandler.vocalAttenuationNotifier,
      builder: (context, attenuation, _) {
        final vocalLevel = (1.0 - attenuation).clamp(0.0, 1.0);
        final isMuted = vocalLevel <= 0.08;

        return ValueListenableBuilder<bool>(
          valueListenable: EqualizerService.isDspActiveNotifier,
          builder: (context, isDspActive, _) {
            final modeLabel = _getModeLabel(vocalLevel, isDspActive);

            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Floating Mode Tooltip (Visible during active dragging or when BGM is active)
                AnimatedOpacity(
                  opacity: (_isDragging || isMuted) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isMuted
                            ? const Color(0xFF06B6D4).withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isMuted
                              ? const Color(0xFF06B6D4).withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      modeLabel,
                      style: TextStyle(
                        color: isMuted ? const Color(0xFF06B6D4) : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Apple Music Sing Glassmorphic Capsule
                GestureDetector(
                  onVerticalDragStart: (details) {
                    setState(() => _isDragging = true);
                    _handleDrag(details.globalPosition);
                  },
                  onVerticalDragUpdate: (details) => _handleDrag(details.globalPosition),
                  onVerticalDragEnd: (_) => _finishDrag(),
                  onVerticalDragCancel: () => _finishDrag(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: 44,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.20),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isMuted
                                  ? const Color(0xFF06B6D4).withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            // 1. Subtle Haptic Detent Tick Marks
                            Positioned(
                              top: 37,
                              child: Container(width: 14, height: 1, color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            Positioned(
                              top: 75,
                              child: Container(width: 20, height: 1, color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            Positioned(
                              top: 117,
                              child: Container(width: 14, height: 1, color: Colors.white.withValues(alpha: 0.12)),
                            ),

                            // 2. Vertical Level Fluid Fill
                            FractionallySizedBox(
                              heightFactor: vocalLevel,
                              widthFactor: 1.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: isMuted
                                        ? [const Color(0xFF06B6D4), const Color(0xFF38BDF8)]
                                        : [const Color(0xFF6366F1), const Color(0xFF818CF8)],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),

                            // 3. Top Status / Percentage Badge
                            Positioned(
                              top: 10,
                              child: Text(
                                isMuted ? (isDspActive ? 'DSP' : 'EQ') : '${(vocalLevel * 100).round()}%',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMuted ? 10 : 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            // 4. Bottom Microphone Action Icon
                            Positioned(
                              bottom: 12,
                              child: Icon(
                                isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
