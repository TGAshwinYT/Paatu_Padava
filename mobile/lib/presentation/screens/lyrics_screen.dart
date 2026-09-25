import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../widgets/lyrics_offset_pill.dart';

class _LrcLine {
  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;
  final bool isBgm;

  const _LrcLine({
    required this.timestamp,
    this.endTimestamp,
    required this.text,
    this.isBgm = false,
  });
}

/// Full-screen BloomeeTunes-style synchronized lyrics page with real-time
/// floating offset synchronization pill and glassmorphic bottom controls.
class LyricsScreen extends StatefulWidget {
  final Song? initialSong;

  const LyricsScreen({super.key, this.initialSong});

  static Future<void> open(BuildContext context, {Song? song}) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => LyricsScreen(initialSong: song),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<_LrcLine> _lines = [];
  final List<GlobalKey> _lineKeys = [];

  StreamSubscription<Duration>? _posSub;
  Timer? _userScrollResumeTimer;

  int _activeIndex = -1;
  bool _isUserScrolling = false;
  bool _isLrc = false;
  bool _showOffsetPill = true;
  bool _isFullscreen = false;
  int _manualOffsetMs = 0;

  @override
  void initState() {
    super.initState();
    _manualOffsetMs = audioHandler.lyricsOffsetMsNotifier.value;
    _parseLyrics(audioHandler.currentLyricsNotifier.value);

    // Listen to reactive lyrics updates
    audioHandler.currentLyricsNotifier.addListener(_onLyricsChanged);

    // Listen to manual offset changes from other components
    audioHandler.lyricsOffsetMsNotifier.addListener(_onOffsetNotifierChanged);

    // Subscribe to position stream with effective offset calculation
    _subscribePosition();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    audioHandler.currentLyricsNotifier.removeListener(_onLyricsChanged);
    audioHandler.lyricsOffsetMsNotifier.removeListener(_onOffsetNotifierChanged);
    super.dispose();
  }

  void _onLyricsChanged() {
    if (mounted) {
      setState(() {
        _parseLyrics(audioHandler.currentLyricsNotifier.value);
      });
    }
  }

  void _onOffsetNotifierChanged() {
    final newOffset = audioHandler.lyricsOffsetMsNotifier.value;
    if (newOffset != _manualOffsetMs && mounted) {
      setState(() {
        _manualOffsetMs = newOffset;
      });
      _updateActiveIndexForPosition(audioHandler.player.position);
    }
  }

  void _parseLyrics(String? rawLyrics) {
    _lines.clear();
    _lineKeys.clear();

    if (rawLyrics == null || rawLyrics.trim().isEmpty) {
      _isLrc = false;
      return;
    }

    final timestampRegex = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
    final rawLines = rawLyrics.split('\n');
    _isLrc = rawLines.any((l) => timestampRegex.hasMatch(l.trim()));

    if (!_isLrc) return;

    final List<_LrcLine> parsed = [];

    for (final line in rawLines) {
      final matches = timestampRegex.allMatches(line);
      if (matches.isNotEmpty) {
        final text = Song.sanitize(line.replaceAll(timestampRegex, '').trim());
        if (text.isEmpty) continue;

        for (final m in matches) {
          final min = int.tryParse(m.group(1)!) ?? 0;
          final sec = double.tryParse(m.group(2)!) ?? 0.0;
          final ts = Duration(milliseconds: ((min * 60 + sec) * 1000).toInt());
          parsed.add(_LrcLine(timestamp: ts, text: text, isBgm: false));
        }
      }
    }

    parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Bloomee BGM / Instrumental pauses (>6s gaps)
    if (parsed.isNotEmpty) {
      // Intro instrumental pause > 6s
      if (parsed.first.timestamp > const Duration(seconds: 6)) {
        _lines.add(_LrcLine(
          timestamp: Duration.zero,
          endTimestamp: parsed.first.timestamp,
          text: '• • • ♪',
          isBgm: true,
        ));
      }

      for (int i = 0; i < parsed.length; i++) {
        _lines.add(parsed[i]);

        if (i < parsed.length - 1) {
          final current = parsed[i];
          final next = parsed[i + 1];
          final gap = next.timestamp - current.timestamp;

          if (gap > const Duration(seconds: 6)) {
            final vocalMs = math.min(2500, (gap.inMilliseconds ~/ 3));
            final bgmStart = current.timestamp + Duration(milliseconds: vocalMs);
            _lines.add(_LrcLine(
              timestamp: bgmStart,
              endTimestamp: next.timestamp,
              text: '• • • ♪',
              isBgm: true,
            ));
          }
        }
      }
    }

    for (int i = 0; i < _lines.length; i++) {
      _lineKeys.add(GlobalKey());
    }

    _updateActiveIndexForPosition(audioHandler.player.position);
  }

  void _subscribePosition() {
    _posSub = audioHandler.player.positionStream.listen((currentPos) {
      if (!mounted || !_isLrc || _lines.isEmpty) return;
      _updateActiveIndexForPosition(currentPos);
    });
  }

  /// Calculates the active lyric index using the exact formula:
  /// effectivePosition = currentPosition + Duration(milliseconds: manualOffsetMs)
  void _updateActiveIndexForPosition(Duration currentPosition) {
    if (!_isLrc || _lines.isEmpty) return;

    final effectivePosition = currentPosition + Duration(milliseconds: _manualOffsetMs);
    int idx = _lines.lastIndexWhere((l) => l.timestamp <= effectivePosition);
    if (idx == -1) idx = 0;

    if (idx != _activeIndex) {
      setState(() => _activeIndex = idx);
      _scrollToActive(idx);
    }
  }

  /// Smoothly center-scrolls the active lyric line using Scrollable / ScrollController
  void _scrollToActive(int idx) {
    if (_isUserScrolling) return;
    if (idx < 0 || idx >= _lineKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keyContext = _lineKeys[idx].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.5, // Centers active line directly in the viewport
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _onUserScroll() {
    _isUserScrolling = true;
    _userScrollResumeTimer?.cancel();
    _userScrollResumeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isUserScrolling = false);
        _scrollToActive(_activeIndex);
      }
    });
  }

  /// Seeking on line tap applies: target = line.timestamp - Duration(milliseconds: manualOffsetMs)
  void _seekToLine(_LrcLine line, int idx) {
    final targetSeek = line.timestamp - Duration(milliseconds: _manualOffsetMs);
    final clampedSeek = targetSeek < Duration.zero ? Duration.zero : targetSeek;

    audioHandler.seek(clampedSeek);
    _isUserScrolling = false;
    _scrollToActive(idx);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, song, _) {
        final currentSong = song ?? widget.initialSong;

        return Scaffold(
          backgroundColor: const Color(0xFF060B14),
          body: Stack(
            children: [
              // 1. Dynamic Blurred Artwork Background
              Positioned.fill(
                child: _buildArtworkBackground(currentSong),
              ),

              // 2. Main Synced Lyrics List View
              Positioned.fill(
                child: _buildLyricsBody(currentSong),
              ),

              // 3. Top Navigation & Action Header (Hidden in Fullscreen)
              if (!_isFullscreen)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(currentSong),
                ),

              // 4. Floating LyricsOffsetPill Stacked Above Bottom Playback Controls
              // ONLY visible when the track has synced LRC and NOT in fullscreen mode
              if (_isLrc && !_isFullscreen)
                Positioned(
                  bottom: 125,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    offset: _showOffsetPill ? Offset.zero : const Offset(0, 1.4),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: _showOffsetPill ? 1.0 : 0.0,
                      child: Center(
                        child: LyricsOffsetPill(
                          offsetMs: _manualOffsetMs,
                          onOffsetChanged: (newMs) {
                            setState(() {
                              _manualOffsetMs = newMs;
                            });
                            audioHandler.lyricsOffsetMsNotifier.value = newMs;
                            _updateActiveIndexForPosition(audioHandler.player.position);
                          },
                          onClose: () {
                            setState(() {
                              _showOffsetPill = false;
                            });
                          },
                          onReset: () {
                            setState(() {
                              _manualOffsetMs = 0;
                            });
                            audioHandler.lyricsOffsetMsNotifier.value = 0;
                            _updateActiveIndexForPosition(audioHandler.player.position);
                          },
                        ),
                      ),
                    ),
                  ),
                ),

              // 5. Glassmorphic Bottom Playback Controls (Hidden in Fullscreen)
              if (!_isFullscreen)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomPlaybackBar(currentSong),
                ),

              // 6. Floating Exit-Fullscreen Button (Only when _isFullscreen is true)
              if (_isFullscreen)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 16,
                  child: SafeArea(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _isFullscreen = false),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withOpacity(0.7),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.15)),
                          ),
                          child: const Icon(
                            Icons.fullscreen_exit_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtworkBackground(Song? song) {
    if (song == null) {
      return Container(color: const Color(0xFF060B14));
    }

    final hasLocal = song.isDownloaded && song.localFilePath != null && File(song.localFilePath!).existsSync();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasLocal)
          Image.file(File(song.localFilePath!), fit: BoxFit.cover)
        else if (song.coverUrl.isNotEmpty)
          CachedNetworkImage(imageUrl: song.coverUrl, fit: BoxFit.cover)
        else
          Container(color: const Color(0xFF1E293B)),

        // Glassmorphic deep blur filter
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(
            color: const Color(0xFF060B14).withOpacity(0.85),
          ),
        ),

        // Gradient vignette for optimal text readability
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC060B14),
                Color(0x99060B14),
                Color(0xF0060B14),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(Song? song) {
    final mediaQuery = MediaQuery.of(context);
    final isOffsetActive = _manualOffsetMs != 0;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.only(
            top: mediaQuery.padding.top + 8,
            bottom: 12,
            left: 12,
            right: 12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A).withOpacity(0.65),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                tooltip: 'Collapse Lyrics',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song?.title ?? 'Lyrics',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song?.artist ?? 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Button to reopen or toggle the Floating LyricsOffsetPill (ONLY for synced LRC)
              if (_isLrc) ...[
                Tooltip(
                  message: _showOffsetPill ? 'Hide Offset Pill' : 'Show Sync Offset Pill',
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showOffsetPill = !_showOffsetPill;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOffsetActive
                            ? const Color(0xFF9333EA).withOpacity(0.25)
                            : (_showOffsetPill ? Colors.white.withOpacity(0.12) : Colors.transparent),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isOffsetActive
                              ? const Color(0xFF9333EA).withOpacity(0.5)
                              : Colors.white.withOpacity(0.12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: isOffsetActive ? const Color(0xFF06B6D4) : Colors.white70,
                          ),
                          if (isOffsetActive) ...[
                            const SizedBox(width: 4),
                            Text(
                              _manualOffsetMs > 0 ? '+${_manualOffsetMs}ms' : '${_manualOffsetMs}ms',
                              style: const TextStyle(
                                color: Color(0xFF06B6D4),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],

              // Always-visible Fullscreen Toggle (⛶)
              IconButton(
                icon: Icon(
                  _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                tooltip: _isFullscreen ? 'Exit Fullscreen' : 'Enter Fullscreen',
                onPressed: () {
                  setState(() {
                    _isFullscreen = !_isFullscreen;
                  });
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsBody(Song? song) {
    final lyrics = audioHandler.currentLyricsNotifier.value;

    if (lyrics == null || lyrics.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lyrics_rounded, size: 48, color: Colors.white38),
            ),
            const SizedBox(height: 16),
            const Text(
              'No lyrics found for this track',
              style: TextStyle(color: Colors.white60, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enjoy the pure acoustic vibes',
              style: TextStyle(color: Colors.white30, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (!_isLrc) {
      // Plain text unsynced lyrics (e.g. 'Hukum')
      return NotificationListener<ScrollNotification>(
        onNotification: (_) => false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            28,
            _isFullscreen ? (MediaQuery.of(context).padding.top + 40) : (MediaQuery.of(context).size.height * 0.14),
            28,
            _isFullscreen ? 60 : (MediaQuery.of(context).size.height * 0.22),
          ),
          child: Column(
            children: [
              Text(
                Song.sanitize(lyrics),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 2.1,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.25,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Synced LRC View with Center-Scrolling
    final screenHeight = MediaQuery.of(context).size.height;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          _onUserScroll();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: screenHeight * 0.38,
          bottom: screenHeight * 0.44,
          left: 24,
          right: 24,
        ),
        itemCount: _lines.length,
        itemBuilder: (context, idx) {
          final line = _lines[idx];
          final isActive = idx == _activeIndex;

          return Center(
            key: _lineKeys[idx],
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _seekToLine(line, idx),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: line.isBgm
                    ? _BgmPulseIndicator(isActive: isActive)
                    : AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white.withOpacity(0.35),
                          fontSize: isActive ? 24 : 17,
                          fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                          height: 1.45,
                          shadows: isActive
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF9333EA).withOpacity(0.55),
                                    blurRadius: 20,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        textAlign: TextAlign.center,
                        child: Text(line.text),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomPlaybackBar(Song? song) {
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
            color: const Color(0xFF0F172A).withOpacity(0.85),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mini Seek Progress Bar
              StreamBuilder<Duration>(
                stream: audioHandler.player.positionStream,
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
                                color: const Color(0xFF9333EA).withOpacity(0.4),
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

class _BgmPulseIndicator extends StatefulWidget {
  final bool isActive;
  const _BgmPulseIndicator({required this.isActive});

  @override
  State<_BgmPulseIndicator> createState() => _BgmPulseIndicatorState();
}

class _BgmPulseIndicatorState extends State<_BgmPulseIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final scale = widget.isActive ? (0.85 + _anim.value * 0.25) : 0.8;
        return Opacity(
          opacity: widget.isActive ? (0.6 + _anim.value * 0.4) : 0.25,
          child: Transform.scale(
            scale: scale,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(),
                const SizedBox(width: 6),
                _dot(),
                const SizedBox(width: 6),
                _dot(),
                const SizedBox(width: 8),
                Icon(
                  Icons.music_note_rounded,
                  size: 18,
                  color: widget.isActive ? const Color(0xFF06B6D4) : Colors.white38,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dot() {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.isActive ? const Color(0xFF06B6D4) : Colors.white38,
      ),
    );
  }
}
