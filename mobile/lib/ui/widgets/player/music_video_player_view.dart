import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../../services/youtube_client.dart';
import '../../../services/app_logger.dart';

/// YouTube Music style embedded Music Video Player.
/// Seamlessly loads and displays the official music video for [song],
/// keeping video playback locked in sync with the high-fidelity audio stream.
class MusicVideoPlayerView extends StatefulWidget {
  final Song song;
  final VoidCallback onSwitchToCover;

  const MusicVideoPlayerView({
    Key? key,
    required this.song,
    required this.onSwitchToCover,
  }) : super(key: key);

  @override
  State<MusicVideoPlayerView> createState() => _MusicVideoPlayerViewState();
}

class _MusicVideoPlayerViewState extends State<MusicVideoPlayerView> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playSub;
  bool _showControls = false;
  Timer? _controlsDismissTimer;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant MusicVideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _disposeController();
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final videoId = await YouTubeClient.resolveVideoIdForSong(widget.song);
      if (videoId == null || !mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No official music video found for this song';
        });
        return;
      }

      final streamUrl = await YouTubeClient.getBestVideoStreamUrl(videoId);
      if (streamUrl == null || !mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Video stream could not be extracted';
        });
        return;
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: YouTubeClient.headersForUrl(streamUrl),
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Keep video muted so pristine 320kbps audio from audioHandler plays
      await controller.setVolume(0.0);
      await controller.setLooping(false);

      // Seek video to active player position
      final currentPos = audioHandler.player.position;
      await controller.seekTo(currentPos);

      if (audioHandler.player.playing) {
        await controller.play();
      }

      _controller = controller;

      // Listen to position to keep video synchronized with audio scrubber
      _posSub?.cancel();
      _posSub = audioHandler.throttledPositionStream.listen((pos) {
        if (_controller != null && _controller!.value.isInitialized) {
          final vidPos = _controller!.value.position;
          final driftMs = (vidPos.inMilliseconds - pos.inMilliseconds).abs();
          // If scrubber moved or drift exceeds 400ms, resync video
          if (driftMs > 400) {
            _controller!.seekTo(pos);
          }
        }
      });

      // Listen to audio player state changes (play/pause)
      _playSub?.cancel();
      _playSub = audioHandler.player.playingStream.listen((playing) {
        if (_controller != null && _controller!.value.isInitialized) {
          if (playing && !_controller!.value.isPlaying) {
            _controller!.play();
          } else if (!playing && _controller!.value.isPlaying) {
            _controller!.pause();
          }
        }
      });

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log('MusicVideoPlayerView', 'Video initialization error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading music video: $e';
        });
      }
    }
  }

  void _disposeController() {
    _posSub?.cancel();
    _posSub = null;
    _playSub?.cancel();
    _playSub = null;
    _controlsDismissTimer?.cancel();
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    _controlsDismissTimer?.cancel();
    if (_showControls) {
      _controlsDismissTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width - 48;
    // 16:9 video frame
    final cardHeight = cardWidth * (9 / 16);

    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video or placeholder/loading
            if (_controller != null && _controller!.value.isInitialized)
              GestureDetector(
                onTap: _toggleControls,
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                ),
              )
            else if (_isLoading)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Loading Official Music Video...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ?? 'Music video unavailable',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      icon: const Icon(Icons.album_rounded, size: 16, color: Colors.white),
                      label: const Text('Back to Cover', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: widget.onSwitchToCover,
                    ),
                  ],
                ),
              ),

            // Video overlay controls on tap
            if (_controller != null && _controller!.value.isInitialized && _showControls)
              GestureDetector(
                onTap: _toggleControls,
                child: Container(
                  color: Colors.black45,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 42,
                          icon: Icon(
                            audioHandler.player.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            if (audioHandler.player.playing) {
                              audioHandler.pause();
                            } else {
                              audioHandler.play();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Top indicator badge: "Official Video"
            if (_controller != null && _controller!.value.isInitialized)
              Positioned(
                top: 8,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.ondemand_video_rounded, color: Color(0xFFF43F5E), size: 12),
                      SizedBox(width: 4),
                      Text(
                        'MUSIC VIDEO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
