import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../domain/models/lyrics_state.dart';
import '../widgets/lyrics_offset_pill.dart';
import '../widgets/lyrics/bgm_pulse_indicator.dart';
import '../widgets/lyrics/lyrics_playback_bar.dart';
import '../widgets/lyrics/wrong_lyrics_sheet.dart';
import '../widgets/lyrics/lyrics_top_bar.dart';
import '../widgets/lyrics/lyrics_empty_states.dart';

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
  StreamSubscription<bool>? _playingSub;
  int _lastPositionUpdateMs = 0;

  @override
  void initState() {
    super.initState();
    _manualOffsetMs = audioHandler.lyricsOffsetMsNotifier.value;
    _parseLyrics(audioHandler.currentLyricsNotifier.value);

    // Listen to reactive lyrics updates
    audioHandler.currentLyricsNotifier.addListener(_onLyricsChanged);
    audioHandler.lyricsStateNotifier.addListener(_onLyricsChanged);

    // Listen to manual offset changes from other components
    audioHandler.lyricsOffsetMsNotifier.addListener(_onOffsetNotifierChanged);

    // Subscribe to position stream with effective offset calculation
    _subscribePosition();
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _posSub?.cancel();
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    audioHandler.currentLyricsNotifier.removeListener(_onLyricsChanged);
    audioHandler.lyricsStateNotifier.removeListener(_onLyricsChanged);
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
    _posSub?.cancel();
    _lastPositionUpdateMs = 0;
    _posSub = audioHandler.throttledPositionStream.listen((currentPos) {
      if (!mounted || !_isLrc || _lines.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPositionUpdateMs < 500) return;
      _lastPositionUpdateMs = now;
      _updateActiveIndexForPosition(currentPos);
    });

    // Pause/resume position listener based on playback state to eliminate background battery drain
    _playingSub?.cancel();
    _playingSub = audioHandler.player.playingStream.listen((isPlaying) {
      if (!mounted) return;
      if (isPlaying) {
        if (_posSub?.isPaused == true) {
          _posSub?.resume();
        }
      } else {
        if (_posSub != null && !_posSub!.isPaused) {
          _posSub?.pause();
        }
      }
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
                  child: LyricsTopBar(
                    song: currentSong,
                    isLrc: _isLrc,
                    showOffsetPill: _showOffsetPill,
                    manualOffsetMs: _manualOffsetMs,
                    isFullscreen: _isFullscreen,
                    onToggleOffsetPill: () => setState(() => _showOffsetPill = !_showOffsetPill),
                    onOpenWrongLyricsPicker: () => WrongLyricsSheet.show(context, currentSong),
                    onToggleFullscreen: () => setState(() => _isFullscreen = !_isFullscreen),
                    onCollapse: () => Navigator.of(context).pop(),
                  ),
                ),

              // 4. Floating LyricsOffsetPill Stacked Above Bottom Playback Controls
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
                  child: LyricsPlaybackBar(song: currentSong),
                ),

              // 6. Floating Exit-Fullscreen Button
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
                            color: const Color(0xFF0F172A).withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
            color: const Color(0xFF060B14).withValues(alpha: 0.85),
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

  Widget _buildLyricsBody(Song? song) {
    final state = audioHandler.lyricsStateNotifier.value;
    final lyrics = audioHandler.currentLyricsNotifier.value;

    if (state.status == LyricsStatus.loading && (lyrics == null || lyrics.trim().isEmpty)) {
      return const LyricsLoadingView();
    }

    if (state.status == LyricsStatus.error && (lyrics == null || lyrics.trim().isEmpty)) {
      return LyricsErrorView(
        error: state.error,
        onRetry: () => audioHandler.reloadLyrics(),
        onSearch: () => WrongLyricsSheet.show(context, song),
      );
    }

    if (state.status == LyricsStatus.rejectedMismatch && (lyrics == null || lyrics.trim().isEmpty)) {
      return LyricsRejectedMismatchView(
        onSearch: () => WrongLyricsSheet.show(context, song),
      );
    }

    if (lyrics == null || lyrics.trim().isEmpty) {
      return LyricsNotFoundView(
        onSearch: () => WrongLyricsSheet.show(context, song),
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
                    ? BgmPulseIndicator(isActive: isActive)
                    : AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.35),
                          fontSize: isActive ? 24 : 17,
                          fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                          height: 1.45,
                          shadows: isActive
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF9333EA).withValues(alpha: 0.55),
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
}
