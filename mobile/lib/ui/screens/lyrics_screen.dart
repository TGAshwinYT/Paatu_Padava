import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/settings_manager.dart';
import '../../domain/models/lyrics_state.dart';
import '../../services/lyrics_client.dart';
import '../widgets/lyrics/bgm_pulse_indicator.dart';
import '../widgets/lyrics/karaoke_line_text.dart';
import '../widgets/lyrics/karaoke_vocal_slider.dart';
import '../widgets/lyrics/studio_karaoke_pill.dart';
import '../widgets/lyrics/lyrics_playback_bar.dart';
import '../widgets/lyrics/wrong_lyrics_sheet.dart';
import '../widgets/lyrics/lyrics_top_bar.dart';
import '../widgets/lyrics/lyrics_empty_states.dart';
import '../widgets/fluid_mesh_gradient.dart';

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
  final List<LyricLine> _lines = [];
  final List<GlobalKey> _lineKeys = [];

  StreamSubscription<Duration>? _posSub;
  Timer? _userScrollResumeTimer;

  int _activeIndex = -1;
  bool _isUserScrolling = false;
  bool _isLrc = false;
  bool _isFullscreen = false;
  bool _showSyncAdjuster = false;
  Duration _currentAudioPosition = Duration.zero;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _parseLyrics(audioHandler.currentLyricsNotifier.value);

    // Listen to reactive lyrics updates
    audioHandler.currentLyricsNotifier.addListener(_onLyricsChanged);
    audioHandler.lyricsStateNotifier.addListener(_onLyricsChanged);
    audioHandler.lyricsOffsetMsNotifier.addListener(_onOffsetChanged);
    audioHandler.isKaraokeModeNotifier.addListener(_onKaraokeChanged);

    // Subscribe to position stream with effective offset calculation
    _subscribePosition();

    // Ensure immediate synchronized jump to the active playing line when opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateActiveIndexForPosition(audioHandler.player.position, immediate: true);
    });
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _posSub?.cancel();
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    audioHandler.currentLyricsNotifier.removeListener(_onLyricsChanged);
    audioHandler.lyricsStateNotifier.removeListener(_onLyricsChanged);
    audioHandler.lyricsOffsetMsNotifier.removeListener(_onOffsetChanged);
    audioHandler.isKaraokeModeNotifier.removeListener(_onKaraokeChanged);
    super.dispose();
  }

  void _onKaraokeChanged() {
    if (mounted) setState(() {});
  }

  void _onOffsetChanged() {
    if (mounted) {
      _updateActiveIndexForPosition(audioHandler.player.position, immediate: true);
    }
  }

  void _onLyricsChanged() {
    if (mounted) {
      setState(() {
        _parseLyrics(audioHandler.currentLyricsNotifier.value);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateActiveIndexForPosition(audioHandler.player.position, immediate: true);
      });
    }
  }

  void _parseLyrics(String? rawLyrics) {
    _lines.clear();
    _lineKeys.clear();

    if (rawLyrics == null || rawLyrics.trim().isEmpty) {
      _isLrc = false;
      return;
    }

    final curSong = widget.initialSong ?? audioHandler.currentSong;
    final durSec = audioHandler.player.duration?.inSeconds ?? (curSong?.duration ?? 180);

    String effectiveLyrics = rawLyrics;
    if (!LyricsClient.isLrc(effectiveLyrics)) {
      effectiveLyrics = LyricsClient.plainLyricsToAutoTimedLrc(effectiveLyrics, durSec);
    }

    final parsed = LyricsClient.parseLrc(effectiveLyrics, durationSeconds: durSec);
    _lines.addAll(parsed);
    _isLrc = _lines.isNotEmpty;

    for (int i = 0; i < _lines.length; i++) {
      _lineKeys.add(GlobalKey());
    }

    if (_lines.isNotEmpty) {
      final offsetMs = audioHandler.lyricsOffsetMsNotifier.value;
      final effectivePosition = audioHandler.player.position + Duration(milliseconds: 180 + offsetMs);
      _activeIndex = _findActiveLineIndex(effectivePosition);
    }
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
  /// exact LRC timestamp + 180ms vocal-lead lookahead + user timing offset to eliminate lag.
  void _updateActiveIndexForPosition(Duration currentPosition, {bool immediate = false}) {
    if (!_isLrc || _lines.isEmpty) return;

    _currentAudioPosition = currentPosition;
    final offsetMs = audioHandler.lyricsOffsetMsNotifier.value;
    final effectivePosition = currentPosition + Duration(milliseconds: 180 + offsetMs);
    final idx = _findActiveLineIndex(effectivePosition);

    if (idx != _activeIndex || immediate) {
      _activeIndex = idx;
      if (mounted) {
        setState(() {});
      }
      _scrollToActive(idx, immediate: immediate);
    } else if (audioHandler.isKaraokeModeNotifier.value && mounted) {
      setState(() {});
    }
  }

  /// Two-phase center-scrolling for active lyric line:
  /// 1. If key is already mounted, Scrollable.ensureVisible centers at 45% eye-level.
  /// 2. If item is off-screen (unrendered in lazy ListView), jump/animate to estimated
  ///    offset to mount it, then refine with exact ensureVisible on the following frame.
  void _scrollToActive(int idx, {bool immediate = false}) {
    if (_isUserScrolling && !immediate) return;
    if (idx < 0 || idx >= _lineKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keyContext = _lineKeys[idx].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.45, // Centers active line smoothly at 45% eye-level
          duration: immediate ? Duration.zero : const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      } else if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
        final viewportHeight = _scrollController.position.viewportDimension;
        final topPadding = viewportHeight * 0.38;
        const estimatedLineHeight = 58.0;
        final estimatedOffset = (topPadding + (idx * estimatedLineHeight)) - (viewportHeight * 0.45);
        final maxExtent = _scrollController.position.maxScrollExtent;
        final targetOffset = maxExtent > 0
            ? estimatedOffset.clamp(0.0, maxExtent)
            : math.max(0.0, estimatedOffset);

        if (immediate) {
          _scrollController.jumpTo(targetOffset);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final mountedContext = _lineKeys[idx].currentContext;
            if (mountedContext != null && mountedContext.mounted) {
              Scrollable.ensureVisible(
                mountedContext,
                alignment: 0.45,
                duration: Duration.zero,
              );
            }
          });
        } else {
          _scrollController
              .animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          )
              .then((_) {
            if (!mounted) return;
            final mountedContext = _lineKeys[idx].currentContext;
            if (mountedContext != null && mountedContext.mounted) {
              Scrollable.ensureVisible(
                mountedContext,
                alignment: 0.45,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }
      }
    });
  }

  void _onUserScrollStart() {
    _isUserScrolling = true;
    _userScrollResumeTimer?.cancel();
  }

  void _onUserScrollEnd() {
    if (!_isUserScrolling) return;
    _userScrollResumeTimer?.cancel();
    _userScrollResumeTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _isUserScrolling = false);
        _scrollToActive(_activeIndex);
      }
    });
  }

  /// Seeking on line tap applies exact line timestamp
  void _seekToLine(LyricLine line, int idx) {
    HapticFeedback.lightImpact();
    final clampedSeek = line.timestamp < Duration.zero ? Duration.zero : line.timestamp;

    audioHandler.seek(clampedSeek);
    _isUserScrolling = false;
    _userScrollResumeTimer?.cancel();
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
              fit: StackFit.expand,
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
                      isFullscreen: _isFullscreen,
                      isSyncAdjusterOpen: _showSyncAdjuster,
                      onOpenWrongLyricsPicker: () => WrongLyricsSheet.show(context, currentSong),
                      onToggleFullscreen: () => setState(() => _isFullscreen = !_isFullscreen),
                      onToggleSyncAdjuster: () => setState(() => _showSyncAdjuster = !_showSyncAdjuster),
                      onCollapse: () => Navigator.of(context).pop(),
                    ),
                  ),

                // 3.5. Studio Karaoke Available Notification Pill
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 20,
                  child: const StudioKaraokePill(),
                ),

                // 3.6. Vertical Apple Music Sing Vocal Attenuation Capsule Slider
                Positioned(
                  bottom: _isFullscreen ? 36 : 124,
                  right: 14,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: audioHandler.isKaraokeModeNotifier,
                    builder: (context, isKaraoke, _) {
                      if (!isKaraoke) return const SizedBox.shrink();
                      return const KaraokeVocalSlider();
                    },
                  ),
                ),

                // 4. Floating Live Sync Timing Adjuster Pill
                if (_showSyncAdjuster && _isLrc)
                  Positioned(
                    bottom: _isFullscreen ? 28 : 116,
                    left: 16,
                    right: 16,
                    child: _buildSyncAdjusterPill(context),
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
          right: audioHandler.isKaraokeModeNotifier.value ? 72 : 28,
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
                    : ValueListenableBuilder<bool>(
                        valueListenable: audioHandler.isKaraokeModeNotifier,
                        builder: (context, isKaraoke, _) {
                          return ValueListenableBuilder<LyricsLanguage>(
                            valueListenable: audioHandler.lyricsLanguageNotifier,
                            builder: (context, lang, _) {
                              return KaraokeLineText(
                                line: line,
                                position: _currentAudioPosition,
                                isActive: isActive,
                                isKaraokeMode: isKaraoke,
                                language: lang,
                                fontSize: fontSize,
                                fontWeight: fontWeight,
                                baseColor: Colors.white.withValues(alpha: opacity),
                                activeColor: Colors.white,
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSyncAdjusterPill(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: audioHandler.lyricsOffsetMsNotifier,
            builder: (context, offsetMs, _) {
              final seconds = offsetMs / 1000.0;
              final offsetLabel = offsetMs == 0
                  ? '±0.0s'
                  : '${offsetMs > 0 ? "+" : ""}${seconds.toStringAsFixed(1)}s';

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _syncStepButton(
                    label: '-0.5s',
                    onTap: () => audioHandler.adjustLyricsOffset(-500),
                  ),
                  const SizedBox(width: 4),
                  _syncStepButton(
                    label: '-0.1s',
                    onTap: () => audioHandler.adjustLyricsOffset(-100),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: offsetMs != 0 ? () => audioHandler.resetLyricsOffset() : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                        decoration: BoxDecoration(
                          color: offsetMs != 0
                              ? const Color(0xFF06B6D4).withValues(alpha: 0.20)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: offsetMs != 0
                                ? const Color(0xFF06B6D4).withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          offsetMs != 0 ? 'Sync: $offsetLabel (Tap Reset)' : 'Sync: ±0.0s',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: offsetMs != 0 ? const Color(0xFF06B6D4) : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _syncStepButton(
                    label: '+0.1s',
                    onTap: () => audioHandler.adjustLyricsOffset(100),
                  ),
                  const SizedBox(width: 4),
                  _syncStepButton(
                    label: '+0.5s',
                    onTap: () => audioHandler.adjustLyricsOffset(500),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    tooltip: 'Close Adjuster',
                    onPressed: () => setState(() => _showSyncAdjuster = false),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _syncStepButton({required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
