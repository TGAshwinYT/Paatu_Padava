import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../../services/favorites_manager.dart';
import '../widgets/queue_sheet.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({Key? key}) : super(key: key);

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  bool _showLyrics = false;
  final ScrollController _lyricsScrollController = ScrollController();

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _openSleepTimerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.bedtime_rounded, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text('Sleep Timer', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sleepTimerOption('15 Minutes', const Duration(minutes: 15)),
            _sleepTimerOption('30 Minutes', const Duration(minutes: 30)),
            _sleepTimerOption('45 Minutes', const Duration(minutes: 45)),
            _sleepTimerOption('60 Minutes', const Duration(minutes: 60)),
            const Divider(color: Colors.white10),
            ListTile(
              title: const Text('Turn Off Sleep Timer', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                audioHandler.cancelSleepTimer();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sleepTimerOption(String title, Duration duration) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white70)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF64748B)),
      onTap: () {
        audioHandler.setSleepTimer(duration);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Music will stop in $title'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, song, _) {
        if (song == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0E1A),
            body: Center(
              child: Text('No song playing', style: TextStyle(color: Colors.white70)),
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0A0E1A),
          body: Stack(
            children: [
              // Ambient Glowing Album Art Background (BloomeeTunes style)
              if (song.coverUrl.isNotEmpty)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.22,
                    child: CachedNetworkImage(
                      imageUrl: song.coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                  child: Container(
                    color: const Color(0xFF0A0E1A).withOpacity(0.85),
                  ),
                ),
              ),

              // Main Player Interface
              SafeArea(
                child: Column(
                  children: [
                    // Top App Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131B2E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Text(
                              song.source == 'offline'
                                  ? 'OFFLINE LOSSLESS'
                                  : (song.source == 'youtube' ? 'YOUTUBE MUSIC' : 'JIOSAAVN 320KBPS'),
                              style: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontSize: 11,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              ValueListenableBuilder<Duration?>(
                                valueListenable: audioHandler.sleepTimerRemainingNotifier,
                                builder: (context, remaining, _) {
                                  return IconButton(
                                    icon: Icon(
                                      remaining != null ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                                      color: remaining != null ? const Color(0xFF6366F1) : Colors.white70,
                                    ),
                                    tooltip: 'Sleep Timer',
                                    onPressed: _openSleepTimerDialog,
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 26),
                                tooltip: 'Open Queue',
                                onPressed: () => QueueSheet.show(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Tab Switcher: Artwork / Lyrics
                            Container(
                              height: 36,
                              width: 180,
                              decoration: BoxDecoration(
                                color: const Color(0xFF131B2E),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withOpacity(0.06)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _showLyrics = false),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: !_showLyrics ? const Color(0xFF6366F1) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'Cover',
                                            style: TextStyle(
                                              color: !_showLyrics ? Colors.white : const Color(0xFF94A3B8),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _showLyrics = true),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: _showLyrics ? const Color(0xFF6366F1) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'Lyrics',
                                            style: TextStyle(
                                              color: _showLyrics ? Colors.white : const Color(0xFF94A3B8),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Middle Content: Album Artwork or Lyrics View
                            SizedBox(
                              height: MediaQuery.of(context).size.width * 0.82,
                              child: _showLyrics
                                  ? _buildLyricsView(song)
                                  : _buildArtworkView(song),
                            ),

                            // Song Title, Artist, and Favorite Row
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
                                      const SizedBox(height: 4),
                                      Text(
                                        song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ValueListenableBuilder<List<Song>>(
                                  valueListenable: FavoritesManager.favoritesNotifier,
                                  builder: (context, _, __) {
                                    final isFav = FavoritesManager.isFavorite(song.id);
                                    return IconButton(
                                      icon: Icon(
                                        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                        color: isFav ? const Color(0xFFEC4899) : Colors.white70,
                                        size: 28,
                                      ),
                                      onPressed: () {
                                        FavoritesManager.toggleFavorite(song);
                                      },
                                    );
                                  },
                                ),
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
                                        inactiveTrackColor: const Color(0xFF1E293B),
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

                            // Main Controls: Smart Shuffle, Prev, Play/Pause, Next, Repeat
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Smart Shuffle AI Toggle
                                ValueListenableBuilder<bool>(
                                  valueListenable: audioHandler.isSmartShuffleNotifier,
                                  builder: (context, isSmartShuffle, _) {
                                    return IconButton(
                                      icon: Icon(
                                        Icons.auto_awesome_rounded,
                                        color: isSmartShuffle ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                                        size: 26,
                                      ),
                                      tooltip: 'Smart Shuffle (Recommendation Graph)',
                                      onPressed: () {
                                        audioHandler.toggleSmartShuffle();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(!isSmartShuffle
                                                ? 'Smart Shuffle Enabled (AI Transition Graph)'
                                                : 'Smart Shuffle Disabled (Standard Order)'),
                                            duration: const Duration(seconds: 1),
                                          ),
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
                            ),

                            // Bottom Auto Radio Bar
                            InkWell(
                              onTap: () async {
                                final count = await audioHandler.addRadioMix();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(count > 0 ? 'Added $count similar songs to queue!' : 'Queue updated with recommendations.'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF131B2E),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.radio_rounded, size: 16, color: Color(0xFF6366F1)),
                                    SizedBox(width: 8),
                                    Text(
                                      'Start Radio • Auto-Mix Similar Songs',
                                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtworkView(Song song) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.78,
        height: MediaQuery.of(context).size.width * 0.78,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.35),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
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
    );
  }

  Widget _buildLyricsView(Song song) {
    return ValueListenableBuilder<String?>(
      valueListenable: audioHandler.currentLyricsNotifier,
      builder: (context, lyrics, _) {
        if (lyrics == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lyrics_rounded, size: 48, color: Color(0xFF64748B)),
                SizedBox(height: 12),
                Text(
                  'No lyrics found for this track',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                ),
              ],
            ),
          );
        }

        // Parse LRC format if available
        final lrcRegex = RegExp(r'^\[(\d+):(\d+(?:\.\d+)?)\](.*)');
        final rawLines = lyrics.split('\n');
        final bool isLrc = rawLines.any((l) => lrcRegex.hasMatch(l.trim()));

        if (!isLrc) {
          // Render plain text lyrics
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF131B2E).withOpacity(0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: SingleChildScrollView(
              child: Text(
                lyrics,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.8,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }

        // Parse synchronized LRC lines
        final List<_LrcLine> parsedLines = [];
        for (final line in rawLines) {
          final match = lrcRegex.firstMatch(line.trim());
          if (match != null) {
            final min = int.tryParse(match.group(1)!) ?? 0;
            final sec = double.tryParse(match.group(2)!) ?? 0.0;
            final text = match.group(3)?.trim() ?? '';
            if (text.isNotEmpty) {
              parsedLines.add(_LrcLine(
                timestamp: Duration(milliseconds: ((min * 60 + sec) * 1000).toInt()),
                text: text,
              ));
            }
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E).withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: StreamBuilder<Duration>(
            stream: audioHandler.player.positionStream,
            builder: (context, snapshot) {
              final pos = snapshot.data ?? Duration.zero;
              int activeIdx = parsedLines.lastIndexWhere((l) => l.timestamp <= pos);
              if (activeIdx == -1 && parsedLines.isNotEmpty) activeIdx = 0;

              return ListView.builder(
                controller: _lyricsScrollController,
                itemCount: parsedLines.length,
                itemBuilder: (context, idx) {
                  final line = parsedLines[idx];
                  final isActive = idx == activeIdx;

                  return GestureDetector(
                    onTap: () => audioHandler.seek(line.timestamp),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        line.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white38,
                          fontSize: isActive ? 18 : 14,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
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

class _LrcLine {
  final Duration timestamp;
  final String text;
  _LrcLine({required this.timestamp, required this.text});
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
          return const IconButton(
            icon: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
            onPressed: null,
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
            await DownloadManager.downloadSong(song);
          },
        );
      },
    );
  }
}
