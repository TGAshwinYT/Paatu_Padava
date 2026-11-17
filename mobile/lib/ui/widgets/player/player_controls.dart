import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../../logic/smart_shuffle_controller.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isCompact = AppDimensions.isCompact(context);
    final skipIconSize = isCompact ? 30.0 : 36.0;
    final secondaryIconSize = isCompact ? 22.0 : 26.0;
    final playBtnSize = isCompact ? 58.0 : 68.0;
    final playIconSize = isCompact ? 32.0 : 38.0;

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
              visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
              padding: isCompact ? const EdgeInsets.all(4.0) : const EdgeInsets.all(8.0),
              icon: Icon(icon, color: color, size: secondaryIconSize),
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
          visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
          padding: isCompact ? const EdgeInsets.all(4.0) : const EdgeInsets.all(8.0),
          icon: Icon(Icons.skip_previous_rounded, color: Colors.white, size: skipIconSize),
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
                width: playBtnSize,
                height: playBtnSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF6366F1),
                ),
                child: Center(
                  child: SizedBox(
                    width: isCompact ? 24 : 28,
                    height: isCompact ? 24 : 28,
                    child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
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
              borderRadius: BorderRadius.circular(playBtnSize / 2),
              child: Container(
                width: playBtnSize,
                height: playBtnSize,
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
                  size: playIconSize,
                ),
              ),
            );
          },
        ),

        // Next
        IconButton(
          visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
          padding: isCompact ? const EdgeInsets.all(4.0) : const EdgeInsets.all(8.0),
          icon: Icon(Icons.skip_next_rounded, color: Colors.white, size: skipIconSize),
          onPressed: () => audioHandler.skipToNext(),
        ),

        // Loop Mode
        StreamBuilder<LoopMode>(
          stream: audioHandler.player.loopModeStream,
          builder: (context, snapshot) {
            final loop = snapshot.data ?? LoopMode.off;
            final isLooping = loop != LoopMode.off;
            return IconButton(
              visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
              padding: isCompact ? const EdgeInsets.all(4.0) : const EdgeInsets.all(8.0),
              icon: Icon(
                loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: isLooping ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                size: secondaryIconSize,
              ),
              onPressed: () => audioHandler.toggleLoopMode(),
            );
          },
        ),
      ],
    );
  }
}
