import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../../domain/models/lyrics_state.dart';
import '../../services/player_handler.dart';
import '../../services/favorites_manager.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/fluid_mesh_gradient.dart';
import '../widgets/player/synced_lyrics_embed.dart';
import '../widgets/player/player_download_button.dart';
import '../widgets/player/player_equalizer_sheet.dart';
import '../widgets/player/player_controls.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({Key? key}) : super(key: key);

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  bool _showLyrics = false;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
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

  void _showRadioAndMixOptions(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: const [
                    Icon(Icons.radio_rounded, color: Color(0xFF818CF8), size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Radio & Recommendations',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.radio_rounded, color: Color(0xFF818CF8)),
                title: const Text('Start Song Radio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text('Curates a continuous 50-track station for "${song.title}"',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  audioHandler.startSongRadio(song);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Starting radio for "${song.title}"...')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: Color(0xFF34D399)),
                title: const Text('Add 10 Similar Songs to Queue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Keeps current queue and appends similar tracks to Up Next',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final count = await audioHandler.addRadioMix(count: 10);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(count > 0 ? 'Added $count similar songs to queue!' : 'Queue updated with recommendations.'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SequenceState?>(
      stream: audioHandler.player.sequenceStateStream,
      initialData: audioHandler.player.sequenceState,
      builder: (context, seqSnapshot) {
        final currentTag = seqSnapshot.data?.currentSource?.tag;
        final Song? directSong = currentTag is Song ? currentTag : null;

        return ValueListenableBuilder<Song?>(
          valueListenable: audioHandler.currentSongNotifier,
          builder: (context, fallbackSong, _) {
            final song = directSong ?? fallbackSong;
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
          body: FluidMeshGradient(
            imageUrl: song.coverUrl,
            child: SafeArea(
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
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                              IconButton(
                                icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
                                tooltip: 'Equalizer',
                                onPressed: () => PlayerEqualizerSheet.show(context),
                              ),
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
                                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                                IconButton(
                                  icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8), size: 28),
                                  tooltip: 'Add to Playlist',
                                  onPressed: () => AddToPlaylistDialog.show(context, song),
                                ),
                                PlayerDownloadButton(song: song),
                              ],
                            ),

                            // Seek Bar & Timers
                            StreamBuilder<Duration>(
                              stream: audioHandler.throttledPositionStream,
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
                            const PlayerControls(),

                            // Bottom Auto Radio Bar
                            InkWell(
                              onTap: () => _showRadioAndMixOptions(context, song),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF131B2E),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
            ),
        );
      },
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
              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
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
    return ValueListenableBuilder<LyricsState>(
      valueListenable: audioHandler.lyricsStateNotifier,
      builder: (context, state, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: audioHandler.currentLyricsNotifier,
          builder: (context, lyrics, _) {
            if (state.status == LyricsStatus.loading && (lyrics == null || lyrics.trim().isEmpty)) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(color: Color(0xFF818CF8)),
                    SizedBox(height: 14),
                    Text(
                      'Finding synchronized lyrics...',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }

            if (state.status == LyricsStatus.error && (lyrics == null || lyrics.trim().isEmpty)) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_off_rounded, size: 36, color: Color(0xFFEF4444)),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Couldn't load lyrics",
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.error?.userMessage ?? 'Connection issue',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                        label: const Text('Retry', style: TextStyle(color: Colors.white, fontSize: 12)),
                        onPressed: () => audioHandler.reloadLyrics(),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (lyrics == null || lyrics.trim().isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lyrics_rounded, size: 42, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No lyrics found for this track',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }

            return SyncedLyricsEmbed(
              lyrics: lyrics,
              song: song,
            );
          },
        );
      },
    );
  }

  Widget _defaultCover() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset('assets/logo.png', width: 90, height: 90, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
