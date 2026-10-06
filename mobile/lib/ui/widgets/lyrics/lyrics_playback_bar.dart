import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';

class LyricsPlaybackBar extends StatelessWidget {
  final Song? song;

  const LyricsPlaybackBar({
    super.key,
    required this.song,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 10,
            bottom: MediaQuery.of(context).padding.bottom + 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mini Seek Progress Bar
              StreamBuilder<Duration>(
                stream: audioHandler.throttledPositionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final totalDuration = audioHandler.player.duration ?? Duration(seconds: song?.duration ?? 0);
                  final posMs = position.inMilliseconds.toDouble();
                  final totalMs = totalDuration.inMilliseconds.toDouble();
                  final maxVal = (totalMs > posMs && totalMs > 0) ? totalMs : (posMs + 1);

                  return Row(
                    children: [
                      Text(
                        _formatDuration(position),
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: const Color(0xFF06B6D4),
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            min: 0,
                            max: maxVal,
                            value: posMs.clamp(0.0, maxVal),
                            onChanged: (val) {
                              audioHandler.seek(Duration(milliseconds: val.toInt()));
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(totalDuration),
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  );
                },
              ),

              // Compact Playback Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Smart Shuffle
                  ValueListenableBuilder<bool>(
                    valueListenable: audioHandler.isSmartShuffleNotifier,
                    builder: (context, isSmart, _) {
                      return IconButton(
                        icon: Icon(
                          Icons.auto_awesome_rounded,
                          size: 22,
                          color: isSmart ? const Color(0xFF9333EA) : Colors.white38,
                        ),
                        onPressed: () => audioHandler.toggleSmartShuffle(),
                      );
                    },
                  ),

                  // Previous
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 30),
                    onPressed: () => audioHandler.skipToPrevious(),
                  ),

                  // Play / Pause
                  StreamBuilder<PlayerState>(
                    stream: audioHandler.player.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final playing = playerState?.playing ?? false;
                      final processing = playerState?.processingState;

                      if (processing == ProcessingState.loading || processing == ProcessingState.buffering) {
                        return const SizedBox(
                          width: 46,
                          height: 46,
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Color(0xFF06B6D4), strokeWidth: 2.5),
                            ),
                          ),
                        );
                      }

                      return InkWell(
                        onTap: () => playing ? audioHandler.pause() : audioHandler.play(),
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF9333EA),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF9333EA).withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      );
                    },
                  ),

                  // Next
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 30),
                    onPressed: () => audioHandler.skipToNext(),
                  ),

                  // Loop mode
                  StreamBuilder<LoopMode>(
                    stream: audioHandler.player.loopModeStream,
                    builder: (context, snapshot) {
                      final loop = snapshot.data ?? LoopMode.off;
                      final isLooping = loop != LoopMode.off;
                      return IconButton(
                        icon: Icon(
                          loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          size: 22,
                          color: isLooping ? const Color(0xFF06B6D4) : Colors.white38,
                        ),
                        onPressed: () => audioHandler.toggleLoopMode(),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
