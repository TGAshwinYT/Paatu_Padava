import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';

/// Standalone playback scrubber widget that isolates seek bar re-renders
/// from the parent player screen. Prevents UI churn by gating stream updates
/// behind an internal `_isDragging` flag during interactive scrubbing.
class PlayerScrubber extends StatefulWidget {
  final Song song;

  const PlayerScrubber({
    Key? key,
    required this.song,
  }) : super(key: key);

  @override
  State<PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends State<PlayerScrubber> {
  bool _isDragging = false;
  double _dragPositionMs = 0.0;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: audioHandler.throttledPositionStream,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final totalDuration =
              audioHandler.player.duration ?? Duration(seconds: widget.song.duration);
          final posMs = position.inMilliseconds.toDouble();
          final totalMs = totalDuration.inMilliseconds.toDouble();
          final maxVal = (totalMs > posMs && totalMs > 0) ? totalMs : (posMs + 1);

          final displayedMs = _isDragging ? _dragPositionMs : posMs;
          final displayedPosition =
              _isDragging ? Duration(milliseconds: _dragPositionMs.toInt()) : position;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  trackHeight: 4,
                  activeTrackColor: const Color(0xFF6366F1),
                  inactiveTrackColor: const Color(0xFF1E293B),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  min: 0,
                  max: maxVal,
                  value: displayedMs.clamp(0.0, maxVal),
                  onChangeStart: (val) {
                    setState(() {
                      _isDragging = true;
                      _dragPositionMs = val;
                    });
                  },
                  onChanged: (val) {
                    setState(() {
                      _dragPositionMs = val;
                    });
                  },
                  onChangeEnd: (val) {
                    setState(() {
                      _isDragging = false;
                    });
                    audioHandler.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(displayedPosition),
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                    Text(
                      _formatDuration(totalDuration),
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
