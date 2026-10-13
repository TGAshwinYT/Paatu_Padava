import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/settings_manager.dart';
import '../../domain/models/lyrics_state.dart';
import '../widgets/lyrics_offset_pill.dart';
import '../widgets/lyrics/bgm_pulse_indicator.dart';
import '../widgets/lyrics/lyrics_playback_bar.dart';
import '../widgets/lyrics/wrong_lyrics_sheet.dart';
import '../widgets/lyrics/lyrics_top_bar.dart';
import '../widgets/lyrics/lyrics_empty_states.dart';
import '../widgets/fluid_mesh_gradient.dart';

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

    // Parse standard LRC header offset (e.g. [offset:+500] or [offset:-200]) in milliseconds
    final offsetRegex = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
    int headerOffsetMs = 0;
    for (final line in rawLines) {
      final m = offsetRegex.firstMatch(line.trim());
      if (m != null) {
        headerOffsetMs = int.tryParse(m.group(1)!) ?? 0;
        break;
      }
    }

    final List<_LrcLine> parsed = [];

    for (final line in rawLines) {
      final matches = timestampRegex.allMatches(line);
      if (matches.isNotEmpty) {
        final text = Song.sanitize(line.replaceAll(timestampRegex, '').trim());
        if (text.isEmpty) continue;

        for (final m in matches) {
          final min = int.tryParse(m.group(1)!) ?? 0;
          final sec = double.tryParse(m.group(2)!) ?? 0.0;
          final rawMs = ((min * 60 + sec) * 1000).toInt();
          final effectiveMs = math.max(0, rawMs + headerOffsetMs);
          parsed.add(_LrcLine(timestamp: Duration(milliseconds: effectiveMs), text: text, isBgm: false));
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
    _posSub = audioHandler.lyricsPositionStream.listen((currentPos) {
      if (!mounted || !_isLrc || _lines.isEmpty) return;
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

  /// Evaluates active lines using binary search against adjusted timestamps
  /// to eliminate progressive drift and O(N) evaluation stalls.
  int _findActiveLineIndex(Duration effectivePosition) {
    if (_lines.isEmpty) return 0;
    final effectiveMs = effectivePosition.inMilliseconds;
    int low = 0;
    int high = _lines.length - 1;
    int idx = 0;

    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_lines[mid].timestamp.inMilliseconds <= effectiveMs) {
        idx = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return idx;
  }

  /// Calculates the active lyric index using binary search:
  /// effectivePosition = currentPosition + Duration(milliseconds: manualOffsetMs)
  void _updateActiveIndexForPosition(Duration currentPosition) {
    if (!_isLrc || _lines.isEmpty) return;

    final effectivePosition = currentPosition + Duration(milliseconds: _manualOffsetMs);
    final idx = _findActiveLineIndex(effectivePosition);

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
          alignment: 0.45, // Centers active line smoothly at 45% eye-level
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _onUserScrollStart() {
    _isUserScrolling = true;
    _userScrollResumeTimer?.cancel();
  }

  void _onUserScrollEnd() {
    _userScrollResumeTimer?.cancel();
    _userScrollResumeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _isUserScrolling = false);
        _scrollToActive(_activeIndex);
      }
    });
  }

  /// Seeking on line tap applies: target = line.timestamp - Duration(milliseconds: manualOffsetMs)
  void _seekToLine(_LrcLine line, int idx) {
    HapticFeedback.lightImpact();
    final targetSeek = line.timestamp - Duration(milliseconds: _manualOffsetMs);
    final clampedSeek = targetSeek < Duration.zero ? Duration.zero : targetSeek;

    audioHandler.seek(clampedSeek);
    _isUserScrolling = false;
    _scrollToActive(idx);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: ValueListenableBuilder<Song?>(
        valueListenable: audioHandler.currentSongNotifier,
        builder: (context, song, _) {
          final currentSong = song ?? widget.initialSong;

          return Scaffold(
            extendBodyBehindAppBar: true,
            extendBody: true,
            backgroundColor: const Color(0xFF060B14),
            body: Stack(
              children: [
                // 1. Dynamic Blurred Fluid Mesh Artwork Background
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
      ),
    );
  }

  Widget _buildArtworkBackground(Song? song) {
    if (song == null) {
      return Container(color: const Color(0xFF060B14));
    }

    final isDynamic = SettingsManager.isDynamicBackgroundEnabled;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Apple Music Full-Screen Fluid Mesh Gradient
        FluidMeshGradient(
          imageUrl: song.coverUrl,
          blurSigma: 70.0,
          opacity: 0.70,
          animate: isDynamic,
        ),

        // 2. Translucent dark wash for contrast
        Container(
          color: const Color(0xFF060B14).withValues(alpha: 0.50),
        ),

        // 3. Apple Music vertical gradient vignette ensuring crystal-clear text readability
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xDD060B14),
                Color(0x33060B14),
                Color(0xEE060B14),
              ],
              stops: [0.0, 0.40, 1.0],
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
      // Plain text unsynced lyrics: clean, beautifully spaced typography across full screen
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          28,
          _isFullscreen ? (MediaQuery.of(context).padding.top + 40) : (MediaQuery.of(context).padding.top + 80),
          28,
          _isFullscreen ? 60 : (MediaQuery.of(context).size.height * 0.22),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              Song.sanitize(lyrics),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                height: 2.2,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.35,
              ),
            ),
          ),
        ),
      );
    }

    // Synced LRC View with Center-Scrolling at eye-level (0.45)
    final screenHeight = MediaQuery.of(context).size.height;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification && notification.dragDetails != null) {
          _onUserScrollStart();
        } else if (notification is UserScrollNotification && notification.direction != ScrollDirection.idle) {
          _onUserScrollStart();
        } else if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
          _onUserScrollStart();
        } else if (notification is ScrollEndNotification) {
          _onUserScrollEnd();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: screenHeight * 0.38,
          bottom: screenHeight * 0.48,
          left: 28,
          right: 28,
        ),
        itemCount: _lines.length,
        itemBuilder: (context, idx) {
          final line = _lines[idx];
          final isActive = idx == _activeIndex;
          final int distance = (idx - _activeIndex).abs();

          // Apple Music high-contrast typography & optical depth falloff
          final double opacity = isActive
              ? 1.0
              : (_activeIndex == -1
                  ? 0.50
                  : (distance == 1
                      ? 0.38
                      : (distance == 2
                          ? 0.25
                          : 0.16)));

          final double fontSize = isActive ? 28.0 : 21.0;
          final FontWeight fontWeight = isActive ? FontWeight.w800 : FontWeight.w700;

          return Align(
            alignment: Alignment.centerLeft,
            key: _lineKeys[idx],
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _seekToLine(line, idx),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                child: line.isBgm
                    ? BgmPulseIndicator(isActive: isActive)
                    : AnimatedScale(
                        scale: isActive ? 1.04 : 1.0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.centerLeft,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: opacity),
                            fontSize: fontSize,
                            fontWeight: fontWeight,
                            height: 1.35,
                            letterSpacing: -0.2,
                            shadows: isActive
                                ? [
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.25),
                                      blurRadius: 18,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          textAlign: TextAlign.left,
                          child: Text(line.text),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
