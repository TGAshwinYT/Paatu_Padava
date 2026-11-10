import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/favorites_manager.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/fluid_mesh_gradient.dart';
import '../widgets/player/player_download_button.dart';
import '../widgets/player/player_equalizer_sheet.dart';
import '../widgets/player/player_controls.dart';
import '../widgets/player/player_scrubber.dart';
import '../widgets/player/player_gesture_detector.dart';
import 'lyrics_screen.dart';
import '../widgets/cover_art_image.dart';
import '../../services/artist_sanitizer.dart';
import '../../data/repositories/song_repository.dart';
import '../widgets/artist_picker_sheet.dart';
import '../../services/sleep_timer_service.dart';
import '../widgets/player/sleep_timer_sheet.dart';
import '../../services/device_connect_coordinator.dart';
import '../widgets/player/device_connect_sheet.dart';
import '../../services/playlist_manager.dart';
import 'playlist_screen.dart';
import 'album_screen.dart';
import 'remote_playlist_screen.dart';
import 'liked_songs_screen.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({Key? key}) : super(key: key);

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen>
    with SingleTickerProviderStateMixin {
  // Double-tap heart/unheart animation overlay
  late final AnimationController _heartAnimController;
  late final Animation<double> _heartScaleAnimation;
  late final Animation<double> _heartOpacityAnimation;
  bool _showHeartOverlay = false;
  bool _lastHeartWasLiked = true;
  Timer? _heartDismissTimer;

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _heartScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.3, end: 1.25)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.25, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_heartAnimController);

    _heartOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(_heartAnimController);
  }

  @override
  void dispose() {
    _heartDismissTimer?.cancel();
    _heartAnimController.dispose();
    super.dispose();
  }

  Future<void> _handleArtworkDoubleTap(Song song) async {
    HapticFeedback.lightImpact();
    final isLiked = await FavoritesManager.toggleFavorite(song);

    if (mounted) {
      _heartDismissTimer?.cancel();
      setState(() {
        _lastHeartWasLiked = isLiked;
        _showHeartOverlay = true;
      });
      _heartAnimController.forward(from: 0.0);

      _heartDismissTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _showHeartOverlay = false;
          });
        }
      });
    }
  }

  void _showSleepTimerSheet() {
    SleepTimerSheet.show(context);
  }

  void _navigateToCurrentContext(BuildContext context, PlaybackContext? ctx, Song song) {
    if (ctx == null) {
      if (song.album.isNotEmpty && !song.album.toLowerCase().contains('unknown')) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlbumScreen(
              albumId: '',
              albumTitle: song.album,
              imageUrl: song.coverUrl,
            ),
          ),
        );
      }
      return;
    }

    if (ctx.type == 'playlist') {
      final plList = PlaylistManager.playlistsNotifier.value;
      final found = plList.where((p) => p.id == ctx.id);
      if (found.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: ctx.id)),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RemotePlaylistScreen(
              playlistId: ctx.id,
              playlistTitle: ctx.title,
              imageUrl: ctx.coverUrl ?? song.coverUrl,
            ),
          ),
        );
      }
    } else if (ctx.type == 'album') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlbumScreen(
            albumId: ctx.id,
            albumTitle: ctx.title,
            imageUrl: ctx.coverUrl ?? song.coverUrl,
          ),
        ),
      );
    } else if (ctx.type == 'liked') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
      );
    } else if (ctx.type == 'mix') {
      Navigator.pop(context);
    }
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
            // Prioritize fallbackSong (currentSongNotifier) since it represents the actively selected
            // song immediately, avoiding stale artwork/source chip while player loads the new audio source.
            final song = fallbackSong ?? directSong;
            if (song == null) {
              return const Scaffold(
                backgroundColor: Color(0xFF0A0E1A),
                body: Center(
                  child: Text('No song playing', style: TextStyle(color: Colors.white70)),
                ),
              );
            }
            return PopScope(
              canPop: true,
              child: Scaffold(
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
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: ValueListenableBuilder<PlaybackContext?>(
                                valueListenable: audioHandler.currentContextNotifier,
                                builder: (context, playbackContext, _) {
                                  final typeName = playbackContext?.type.toUpperCase() ??
                                      (song.album.isNotEmpty && !song.album.toLowerCase().contains('unknown')
                                          ? 'ALBUM'
                                          : 'NOW PLAYING');
                                  final title = playbackContext?.title ??
                                      (song.album.isNotEmpty && !song.album.toLowerCase().contains('unknown')
                                          ? song.album
                                          : 'Paatu Padava');

                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _navigateToCurrentContext(context, playbackContext, song),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'PLAYING FROM $typeName',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.45),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                            const SizedBox(width: 3),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 13,
                                              color: Colors.white.withValues(alpha: 0.45),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ValueListenableBuilder<ConnectedDevice>(
                                valueListenable: DeviceConnectCoordinator.instance.currentDeviceNotifier,
                                builder: (context, device, _) {
                                  final isCasting = !device.isLocal;
                                  return IconButton(
                                    icon: Icon(
                                      isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
                                      color: isCasting ? const Color(0xFF10B981) : Colors.white70,
                                      size: 22,
                                    ),
                                    tooltip: isCasting ? 'Streaming on ${device.name}' : 'Connect to a Device',
                                    onPressed: () => DeviceConnectSheet.show(context),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 22),
                                tooltip: 'Equalizer',
                                onPressed: () => PlayerEqualizerSheet.show(context),
                              ),
                              ListenableBuilder(
                                listenable: SleepTimerService.instance,
                                builder: (context, _) {
                                  final timer = SleepTimerService.instance;
                                  final isActive = timer.isActive;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                                          color: isActive ? const Color(0xFF6366F1) : Colors.white70,
                                          size: 22,
                                        ),
                                        tooltip: 'Sleep Timer',
                                        onPressed: _showSleepTimerSheet,
                                      ),
                                      if (isActive)
                                        GestureDetector(
                                          onTap: _showSleepTimerSheet,
                                          child: Container(
                                            margin: const EdgeInsets.only(right: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              timer.formattedRemainingShort,
                                              style: const TextStyle(
                                                color: Color(0xFF818CF8),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                fontFeatures: [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 26),
                                tooltip: 'Playback Queue',
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
                            // Song / Lyrics Selector Pill
                            Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF131B2E),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Song / Cover mode
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.music_note_rounded,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Song',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Fullscreen Lyrics
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      LyricsScreen.open(context, song: song);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Text(
                                        'Lyrics',
                                        style: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Middle Content: Album Artwork with Double-Tap Heart Interaction
                            Flexible(
                              child: RepaintBoundary(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final maxAvailable = constraints.maxHeight;
                                    final screenWidth = MediaQuery.sizeOf(context).width;
                                    final targetSize = (screenWidth * 0.78).clamp(180.0, maxAvailable > 0 ? maxAvailable : 340.0);
                                    return SizedBox(
                                      height: targetSize,
                                      child: PlayerGestureDetector(
                                        onDoubleTap: () => _handleArtworkDoubleTap(song),
                                        child: _buildArtworkView(song, targetSize),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),

                            // Song Title, Artist, and Favorite Row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
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
                                      Builder(
                                        builder: (context) {
                                          final artists = ArtistSanitizer.extractAllGenuineArtists(song.artist);
                                          if (artists.isEmpty) {
                                            return const Text(
                                              'Unknown Artist',
                                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                                            );
                                          }
                                          return SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                for (int i = 0; i < artists.length; i++) ...[
                                                  GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: () {
                                                      final artist = artists[i];
                                                      final isPrimary = artist.toLowerCase() == song.primaryArtist.toLowerCase();
                                                      final norm = SongRepository.normalizeArtist(artist);
                                                      ArtistPickerSheet.navigateToArtist(
                                                        context,
                                                        artistName: artist,
                                                        artistId: isPrimary ? (song.artistId ?? '') : '',
                                                        imageUrl: SongRepository.verifiedArtistAvatars[norm] ?? '',
                                                      );
                                                    },
                                                    child: Text(
                                                      artists[i],
                                                      style: const TextStyle(
                                                        color: Color(0xFF94A3B8),
                                                        fontSize: 15,
                                                        decoration: TextDecoration.underline,
                                                        decorationColor: Color(0x3394A3B8),
                                                      ),
                                                    ),
                                                  ),
                                                  if (i < artists.length - 1)
                                                    const Text(
                                                      ', ',
                                                      style: TextStyle(
                                                        color: Color(0xFF64748B),
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                ],
                                                if (artists.length > 1) ...[
                                                  const SizedBox(width: 6),
                                                  GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: () => ArtistPickerSheet.show(context, song: song),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withValues(alpha: 0.08),
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: const Icon(
                                                        Icons.more_horiz_rounded,
                                                        color: Color(0xFF94A3B8),
                                                        size: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 6),
                                      // Discreet Audio Quality Micro-Pill below artist
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: song.source == 'offline'
                                                ? const Color(0xFF10B981).withValues(alpha: 0.35)
                                                : const Color(0xFF818CF8).withValues(alpha: 0.25),
                                          ),
                                        ),
                                        child: Text(
                                          song.source == 'offline'
                                              ? 'LOSSLESS'
                                              : (song.source == 'youtube'
                                                  ? 'YOUTUBE'
                                                  : (song.streamUrl?.contains('_160.') == true
                                                      ? '160 KBPS • AAC'
                                                      : (song.streamUrl?.contains('_96.') == true
                                                          ? '96 KBPS'
                                                          : '320 KBPS • HQ'))),
                                          style: TextStyle(
                                            color: song.source == 'offline'
                                                ? const Color(0xFF34D399)
                                                : const Color(0xFF818CF8),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                          ),
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
                              ],
                            ),

                            // Seek Bar & Timers (isolated scrubber with internal isDragging gate)
                            PlayerScrubber(song: song),

                            // Active Remote Casting Indicator Banner
                            ValueListenableBuilder<ConnectedDevice>(
                              valueListenable: DeviceConnectCoordinator.instance.currentDeviceNotifier,
                              builder: (context, device, _) {
                                if (device.isLocal) return const SizedBox.shrink();
                                return GestureDetector(
                                  onTap: () => DeviceConnectSheet.show(context),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.speaker_rounded, size: 14, color: Color(0xFF10B981)),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                          'Listening on ${device.name}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF10B981),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                            // Main Controls: Smart Shuffle, Prev, Play/Pause, Next, Repeat
                            const RepaintBoundary(
                              child: PlayerControls(),
                            ),

                            // Secondary Utility Actions: Add to Playlist and Download
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8), size: 26),
                                    tooltip: 'Add to Playlist',
                                    onPressed: () => AddToPlaylistDialog.show(context, song),
                                  ),
                                  const SizedBox(width: 32),
                                  PlayerDownloadButton(song: song),
                                ],
                              ),
                            ),

                            // Bottom Queue & Up Next Bar
                            ValueListenableBuilder<List<Song>>(
                              valueListenable: audioHandler.playlistNotifier,
                              builder: (context, playlist, _) {
                                return ValueListenableBuilder<int>(
                                  valueListenable: audioHandler.currentIndexNotifier,
                                  builder: (context, currentIndex, _) {
                                    final upcomingTracks = (currentIndex >= 0 && currentIndex + 1 < playlist.length)
                                        ? playlist.sublist(currentIndex + 1)
                                        : <Song>[];
                                    final nextSong = upcomingTracks.isNotEmpty ? upcomingTracks.first : null;
                                    final upcomingCount = upcomingTracks.length;

                                    return InkWell(
                                      onTap: () => QueueSheet.show(context),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context).size.width - 32,
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF131B2E),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.25),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.queue_music_rounded,
                                              size: 18,
                                              color: Color(0xFF818CF8),
                                            ),
                                            const SizedBox(width: 8),
                                            if (nextSong != null) ...[
                                              const Text(
                                                'Up Next: ',
                                                style: TextStyle(
                                                  color: Color(0xFF818CF8),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Flexible(
                                                child: Text(
                                                  '${nextSong.title} • ${nextSong.artist}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              if (upcomingCount > 1) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    '+${upcomingCount - 1}',
                                                    style: const TextStyle(
                                                      color: Color(0xFFA5B4FC),
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ] else ...[
                                              const Text(
                                                'Queue (Empty)',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(width: 6),
                                            const Icon(
                                              Icons.keyboard_arrow_up_rounded,
                                              size: 16,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
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
      },
    );
  }

  Widget _buildArtworkView(Song song, [double? size]) {
    final double artSize = size ?? (MediaQuery.sizeOf(context).width * 0.78).clamp(180.0, 340.0);
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _handleArtworkDoubleTap(song),
        child: Container(
          width: artSize,
          height: artSize,
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                (song.localFilePath != null && File(song.localFilePath!).existsSync())
                    ? Image.file(
                        File(song.localFilePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultCover(),
                      )
                    : CoverArtImage(
                        song: song,
                        borderRadius: BorderRadius.circular(28),
                        memCacheWidth: 800,
                        memCacheHeight: 800,
                        errorWidget: _defaultCover(),
                      ),
                if (_showHeartOverlay)
                  Center(
                    child: AnimatedBuilder(
                      animation: _heartAnimController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _heartOpacityAnimation.value.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: _heartScaleAnimation.value,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.45),
                              ),
                              child: Icon(
                                _lastHeartWasLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: _lastHeartWasLiked
                                    ? const Color(0xFFEC4899)
                                    : Colors.white,
                                size: 84,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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
