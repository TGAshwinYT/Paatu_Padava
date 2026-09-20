import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../screens/full_player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, song, _) {
        if (song == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, anim1, anim2) => const FullPlayerScreen(),
                  transitionsBuilder: (context, anim1, anim2, child) {
                    const begin = Offset(0.0, 1.0);
                    const end = Offset.zero;
                    const curve = Curves.easeOutCubic;
                    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                    return SlideTransition(position: anim1.drive(tween), child: child);
                  },
                ),
              );
            },
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.96),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    // Top Tiny Playback Progress Line
                    StreamBuilder<Duration>(
                      stream: audioHandler.player.positionStream,
                      builder: (context, snapshot) {
                        final pos = snapshot.data?.inMilliseconds.toDouble() ?? 0.0;
                        final total = audioHandler.player.duration?.inMilliseconds.toDouble() ?? 
                            (song.duration > 0 ? song.duration * 1000.0 : 1.0);
                        final fraction = (total > 0) ? (pos / total).clamp(0.0, 1.0) : 0.0;

                        return LinearProgressIndicator(
                          value: fraction,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                          minHeight: 2.5,
                        );
                      },
                    ),

                    // Main Row
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: Row(
                          children: [
                            // Thumbnail
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: (song.localFilePath != null && File(song.localFilePath!).existsSync())
                                    ? Image.file(
                                        File(song.localFilePath!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _coverFallback(),
                                      )
                                    : (song.coverUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: song.coverUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => Container(color: const Color(0xFF334155)),
                                            errorWidget: (_, __, ___) => _coverFallback(),
                                          )
                                        : _coverFallback()),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Song Title & Artist
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Mini Download Indicator
                            ValueListenableBuilder<Map<String, double>>(
                              valueListenable: DownloadManager.activeDownloads,
                              builder: (context, activeDownloads, _) {
                                final isDownloaded = DownloadManager.isDownloaded(song.id);
                                final isDownloading = activeDownloads.containsKey(song.id);

                                if (isDownloaded) {
                                  return const Icon(Icons.check_circle_rounded, size: 20, color: Color(0xFF10B981));
                                }
                                if (isDownloading) {
                                  return const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Color(0xFF6366F1), strokeWidth: 2),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),

                            // Play / Pause
                            StreamBuilder<PlayerState>(
                              stream: audioHandler.player.playerStateStream,
                              builder: (context, snapshot) {
                                final state = snapshot.data;
                                final playing = state?.playing ?? false;
                                final processing = state?.processingState;

                                if (processing == ProcessingState.loading || processing == ProcessingState.buffering) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                                    ),
                                  );
                                }

                                return IconButton(
                                  icon: Icon(
                                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    if (playing) {
                                      audioHandler.pause();
                                    } else {
                                      audioHandler.play();
                                    }
                                  },
                                );
                              },
                            ),

                            // Next
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 26),
                              onPressed: () => audioHandler.skipToNext(),
                            ),
                          ],
                        ),
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

  Widget _coverFallback() {
    return Container(
      color: const Color(0xFF334155),
      child: const Icon(Icons.music_note_rounded, color: Colors.white54, size: 24),
    );
  }
}
