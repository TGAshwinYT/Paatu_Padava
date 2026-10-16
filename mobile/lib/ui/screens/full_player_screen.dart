import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
import '../../services/artist_sanitizer.dart';
import '../../data/repositories/song_repository.dart';
import '../widgets/artist_picker_sheet.dart';
import '../../services/sleep_timer_service.dart';
import '../widgets/player/sleep_timer_sheet.dart';
import '../../services/device_connect_coordinator.dart';
import '../widgets/player/device_connect_sheet.dart';

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
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'PLAYING FROM',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.45),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    song.album.isNotEmpty ? song.album : 'Paatu Padava',
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
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Text(
                                            'Lyrics',
                                            style: TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Icon(
                                            Icons.open_in_full_rounded,
                                            size: 11,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Middle Content: Album Artwork with Double-Tap Heart Interaction
                            RepaintBoundary(
                              child: SizedBox(
                                height: MediaQuery.of(context).size.width * 0.82,
                                child: PlayerGestureDetector(
                                  onDoubleTap: () => _handleArtworkDoubleTap(song),
                                  child: _buildArtworkView(song),
                                ),
                              ),
                            ),

                            // Song Title, Artist, and Favorite Row
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              song.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF131B2E),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: song.source == 'offline'
                                                    ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                                    : const Color(0xFF6366F1).withValues(alpha: 0.3),
                                              ),
                                            ),
                                            child: Text(
                                              song.source == 'offline'
                                                  ? 'LOSSLESS'
                                                  : (song.source == 'youtube'
                                                      ? 'YOUTUBE'
                                                      : (song.streamUrl?.contains('_160.') == true
                                                          ? '160 KBPS'
                                                          : (song.streamUrl?.contains('_96.') == true
                                                              ? '96 KBPS'
                                                              : '320 KBPS'))),
                                              style: TextStyle(
                                                color: song.source == 'offline'
                                                    ? const Color(0xFF34D399)
                                                    : const Color(0xFF818CF8),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ),
                                        ],
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
                                        Text(
                                          'Listening on ${device.name}',
                                          style: const TextStyle(
                                            color: Color(0xFF10B981),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
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
                                            const SizedBox(width: 8),
                                            Container(
                                              height: 12,
                                              width: 1,
                                              color: Colors.white.withValues(alpha: 0.15),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(
                                                Icons.radio_rounded,
                                                size: 16,
                                                color: Color(0xFF6366F1),
                                              ),
                                              tooltip: 'Radio & Recommendations',
                                              onPressed: () => _showRadioAndMixOptions(context, song),
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

  Widget _buildArtworkView(Song song) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _handleArtworkDoubleTap(song),
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                (song.localFilePath != null && File(song.localFilePath!).existsSync())
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
