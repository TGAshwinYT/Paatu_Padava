import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/player_handler.dart';

/// Apple Music Sing-inspired vertical capsule slider for real-time vocal attenuation.
class KaraokeVocalSlider extends StatelessWidget {
  const KaraokeVocalSlider({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: audioHandler.vocalAttenuationNotifier,
      builder: (context, attenuation, _) {
        // attenuation: 0.0 (100% vocals) -> 1.0 (0% vocals / 100% attenuated)
        final vocalLevel = (1.0 - attenuation).clamp(0.0, 1.0);
        final isMuted = vocalLevel <= 0.05;

        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 44,
              height: 140,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(22),
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
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final localPos = box.globalToLocal(details.globalPosition);
                  // Height is 140. Drag from bottom (0.0) to top (1.0)
                  final rawFraction = 1.0 - (localPos.dy / box.size.height);
                  final clamped = rawFraction.clamp(0.0, 1.0);
                  final newAttenuation = 1.0 - clamped;
                  audioHandler.setVocalAttenuation(newAttenuation);
                  if (clamped == 0.0 || clamped == 1.0 || (clamped - 0.5).abs() < 0.05) {
                    HapticFeedback.selectionClick();
                  }
                },
                onTap: () {
                  // Toggle between full vocal and pure instrumental
                  HapticFeedback.mediumImpact();
                  if (vocalLevel > 0.5) {
                    audioHandler.setVocalAttenuation(1.0); // 0% vocals (Karaoke)
                  } else {
                    audioHandler.setVocalAttenuation(0.0); // 100% vocals
                  }
                },
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Vertical Level Fill
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
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),

                    // Top Status / Percentage Badge
                    Positioned(
                      top: 10,
                      child: Text(
                        isMuted
                            ? 'BGM'
                            : '${(vocalLevel * 100).round()}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMuted ? 10 : 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Bottom Microphone Icon
                    Positioned(
                      bottom: 10,
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
        );
      },
    );
  }
}
