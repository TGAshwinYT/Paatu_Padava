import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';

/// Floating notification pill notifying user that an authentic studio instrumental/karaoke
/// stem is available, allowing one-tap seamless position-matched switching.
class StudioKaraokePill extends StatelessWidget {
  const StudioKaraokePill({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: audioHandler.isKaraokeModeNotifier,
      builder: (context, isKaraoke, _) {
        if (!isKaraoke) return const SizedBox.shrink();

        return ValueListenableBuilder<Song?>(
          valueListenable: audioHandler.studioKaraokeTrackNotifier,
          builder: (context, karaokeSong, _) {
            if (karaokeSong == null) return const SizedBox.shrink();

            return ValueListenableBuilder<bool>(
              valueListenable: audioHandler.isUsingStudioKaraokeNotifier,
              builder: (context, isUsingStudio, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isUsingStudio
                            ? const Color(0xFF06B6D4).withValues(alpha: 0.25)
                            : const Color(0xFF0F172A).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isUsingStudio
                              ? const Color(0xFF06B6D4).withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUsingStudio ? Icons.check_circle_rounded : Icons.music_note_rounded,
                            size: 16,
                            color: isUsingStudio ? const Color(0xFF06B6D4) : Colors.cyanAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isUsingStudio
                                ? 'Studio BGM Active'
                                : 'Studio Karaoke Found',
                            style: TextStyle(
                              color: isUsingStudio ? const Color(0xFF06B6D4) : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!isUsingStudio) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => audioHandler.switchToStudioKaraoke(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF06B6D4),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Switch',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => audioHandler.switchBackFromStudioKaraoke(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Original',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
