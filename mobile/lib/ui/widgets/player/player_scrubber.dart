import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';

/// Standalone playback scrubber widget that isolates seek bar re-renders
/// from the parent player screen. Prevents UI churn by gating stream updates
/// behind an internal `_isDragging` flag during interactive scrubbing.
///
/// Shows THREE layers on the track, like Spotify / YouTube Music:
///   1. played part      (bright indigo, up to the thumb)
///   2. buffered part    (translucent white, from the thumb to how much audio is
///                        already downloaded) <- Slider.secondaryTrackValue
///   3. not yet loaded   (dark)
class PlayerScrubber extends StatefulWidget {
  final Song song;

  const PlayerScrubber({
    Key? key,
    required this.song,
  }) : super(key: key);

  /// mm:ss, or h:mm:ss when the track is an hour or longer (the old formatter
  /// showed "00:xx" for anything past 59:59 because of `minutes.remainder(60)`).
  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  State<PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends State<PlayerScrubber> {
  bool _isDragging = false;
  double _dragPositionMs = 0.0;

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

          return StreamBuilder<Duration>(
            stream: audioHandler.player.bufferedPositionStream,
            initialData: audioHandler.player.bufferedPosition,
            builder: (context, bufSnap) {
              final bufferedMs = (bufSnap.data ?? Duration.zero).inMilliseconds.toDouble();
              // Never draw buffered behind the playhead, never beyond the end.
              final bufferedClamped = bufferedMs.clamp(displayedMs.clamp(0.0, maxVal), maxVal);
              final percent = maxVal > 0 ? (bufferedMs / maxVal * 100).clamp(0.0, 100.0).round() : 0;
              final fullyLoaded = percent >= 99;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      trackHeight: 4,
                      activeTrackColor: const Color(0xFF6366F1),
                      secondaryActiveTrackColor: Colors.white38, // "downloaded" segment
                      inactiveTrackColor: const Color(0xFF1E293B),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      min: 0,
                      max: maxVal,
                      value: displayedMs.clamp(0.0, maxVal),
                      secondaryTrackValue: bufferedClamped.toDouble(),
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
                      children: [
                        Text(
                          PlayerScrubber.formatDuration(displayedPosition),
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                        Expanded(
                          child: Center(
                            // Only shown while the song is still loading; hidden at 0% and when complete.
                            child: (percent > 0 && !fullyLoaded)
                                ? Text(
                                    '$percent% loaded',
                                    key: const Key('scrubber_loaded_percent'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF475569), fontSize: 11),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                        Text(
                          PlayerScrubber.formatDuration(totalDuration),
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
