import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({Key? key}) : super(key: key);

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, song, _) {
        if (song == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B0F19),
            body: Center(
              child: Text(
                'No song playing',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0B0F19),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            centerTitle: true,
            title: Column(
              children: [
                Text(
                  'PLAYING FROM ${song.source.toUpperCase()}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.album.isNotEmpty ? song.album : 'Paatu Padava',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.queue_music_rounded, color: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Queue has ${audioHandler.playlist.length} songs'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Album Artwork
                  Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.78,
                      height: MediaQuery.of(context).size.width * 0.78,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.25),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: (song.localFilePath != null && File(song.localFilePath!).existsSync())
                            ? Image.file(
                                File(song.localFilePath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _defaultCover(),
                              )
                            : (song.coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: song.coverUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: const Color(0xFF1E293B),
                                      child: const Center(
                                        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => _defaultCover(),
                                  )
                                : _defaultCover()),
                      ),
                    ),
                  ),

                  // Title, Artist, and Download Button Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _DownloadActionButton(song: song),
                    ],
                  ),

                  // Seek Bar & Timers
                  StreamBuilder<Duration>(
                    stream: audioHandler.player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final totalDuration = audioHandler.player.duration ?? Duration(seconds: song.duration);
                      final posMs = position.inMilliseconds.toDouble();
                      final totalMs = totalDuration.inMilliseconds.toDouble();
                      final maxVal = (totalMs > posMs && totalMs > 0) ? totalMs : (posMs + 1);

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              trackHeight: 4,
                              activeTrackColor: const Color(0xFF6366F1),
                              inactiveTrackColor: const Color(0xFF334155),
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
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
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

                  // Media Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Shuffle toggle
                      StreamBuilder<bool>(
                        stream: audioHandler.player.shuffleModeEnabledStream,
                        builder: (context, snapshot) {
                          final shuffle = snapshot.data ?? false;
                          return IconButton(
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: shuffle ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                              size: 26,
                            ),
                            onPressed: () => audioHandler.setShuffle(!shuffle),
                          );
                        },
                      ),

                      // Previous
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                        onPressed: () => audioHandler.skipToPrevious(),
                      ),

                      // Play / Pause Circle Button
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
                                    color: const Color(0xFF6366F1).withOpacity(0.4),
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

                      // Repeat toggle
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
                  ),

                  // Bottom Audio Quality Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.offline_bolt_rounded, size: 14, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          song.source == 'offline'
                              ? 'OFFLINE LOSSLESS • LOCAL STORAGE'
                              : '320 KBPS • DIRECT CLIENT STREAM',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _defaultCover() {
    return Container(
      color: const Color(0xFF1E293B),
      child: const Center(
        child: Icon(Icons.music_note_rounded, size: 60, color: Color(0xFF6366F1)),
      ),
    );
  }
}

class _DownloadActionButton extends StatelessWidget {
  final Song song;
  const _DownloadActionButton({required this.song});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: DownloadManager.activeDownloads,
      builder: (context, activeDownloads, _) {
        final isDownloading = activeDownloads.containsKey(song.id);
        final progress = activeDownloads[song.id] ?? 0.0;
        final isDownloaded = DownloadManager.isDownloaded(song.id);

        if (isDownloaded) {
          return IconButton(
            icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Song is saved offline! Plays without internet.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          );
        }

        if (isDownloading) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                color: const Color(0xFF6366F1),
                strokeWidth: 3,
              ),
            ),
          );
        }

        return IconButton(
          icon: const Icon(Icons.download_for_offline_outlined, color: Colors.white70, size: 28),
          onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading "${song.title}" for offline playback...'),
                duration: const Duration(seconds: 2),
              ),
            );
            final success = await DownloadManager.downloadSong(song);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? 'Downloaded "${song.title}"!' : 'Download failed. Check connection.',
                  ),
                  backgroundColor: success ? const Color(0xFF10B981) : Colors.redAccent,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        );
      },
    );
  }
}
