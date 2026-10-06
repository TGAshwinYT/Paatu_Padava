import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../../logic/smart_shuffle_controller.dart';
import '../../../services/player_handler.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 3-State Smart Shuffle AI Toggle
        ValueListenableBuilder<SmartShuffleMode>(
          valueListenable: audioHandler.shuffleModeNotifier,
          builder: (context, mode, _) {
            IconData icon;
            Color color;
            String tooltip;

            switch (mode) {
              case SmartShuffleMode.off:
                icon = Icons.shuffle_rounded;
                color = const Color(0xFF64748B);
                tooltip = 'Shuffle: Off (Tap for Standard)';
                break;
              case SmartShuffleMode.standard:
                icon = Icons.shuffle_rounded;
                color = const Color(0xFF6366F1);
                tooltip = 'Standard Shuffle (Tap for Smart)';
                break;
              case SmartShuffleMode.smart:
                icon = Icons.auto_awesome_rounded;
                color = const Color(0xFF1DB954);
                tooltip = 'Smart Shuffle AI (Recommendations Active)';
                break;
            }

            return IconButton(
              icon: Icon(icon, color: color, size: 26),
              tooltip: tooltip,
              onPressed: () {
                audioHandler.toggleSmartShuffle();
                final newMode = audioHandler.smartShuffleController.mode;
                final msg = newMode == SmartShuffleMode.smart
                    ? '✨ Smart Shuffle Enabled (AI Recommendations Interleaved)'
                    : (newMode == SmartShuffleMode.standard
                        ? '🔀 Standard Shuffle Enabled (Queue Reordered)'
                        : '➡️ Shuffle Off (Sequential Playback)');
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
                );
              },
            );
          },
        ),

        // Previous
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
          onPressed: () => audioHandler.skipToPrevious(),
        ),

        // Play / Pause
        StreamBuilder<PlayerState>(
          stream: audioHandler.player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processing = playerState?.processingState;
            final playing = playerState?.playing ?? false;

            if (processing == ProcessingState.loading || processing == ProcessingState.buffering) {
              return Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF6366F1),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  ),
                ),
              );
            }

            return InkWell(
              onTap: () {
                if (playing) {
                  audioHandler.pause();
                } else {
                  audioHandler.play();
                }
              },
              borderRadius: BorderRadius.circular(36),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            );
          },
        ),

        // Next
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
          onPressed: () => audioHandler.skipToNext(),
        ),

        // Loop Mode
        StreamBuilder<LoopMode>(
          stream: audioHandler.player.loopModeStream,
          builder: (context, snapshot) {
            final loop = snapshot.data ?? LoopMode.off;
            final isLooping = loop != LoopMode.off;
            return IconButton(
              icon: Icon(
                loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: isLooping ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                size: 26,
              ),
              onPressed: () => audioHandler.toggleLoopMode(),
            );
          },
        ),
      ],
    );
  }
}
