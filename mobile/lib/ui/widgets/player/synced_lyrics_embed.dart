import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../models/song.dart';
import '../../../domain/models/lyrics_state.dart';
import '../../../services/player_handler.dart';
import '../../../services/lyrics_client.dart';
import '../../screens/lyrics_screen.dart';
import '../lyrics/karaoke_line_text.dart';
import '../lyrics/bgm_pulse_indicator.dart';

class SyncedLyricsEmbed extends StatefulWidget {
  final String lyrics;
  final Song song;

  const SyncedLyricsEmbed({
    Key? key,
    required this.lyrics,
    required this.song,
  }) : super(key: key);

  @override
  State<SyncedLyricsEmbed> createState() => _SyncedLyricsEmbedState();
}

class _SyncedLyricsEmbedState extends State<SyncedLyricsEmbed> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final List<LyricLine> _lines = [];
  final List<GlobalKey> _lineKeys = [];
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  int _activeIndex = -1;
  Duration _lastPosition = Duration.zero;
  bool _isUserScrolling = false;
  Timer? _userScrollResumeTimer;
  bool _isLrc = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _parseLyrics();
    _subscribePosition();
    audioHandler.lyricsOffsetMsNotifier.addListener(_onOffsetChanged);

    // Trigger immediate synchronized jump to the active playing line when mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateActiveIndexForPosition(audioHandler.player.position, immediate: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_posSub != null && !_posSub!.isPaused) {
        _posSub?.pause();
      }
    } else if (state == AppLifecycleState.resumed && audioHandler.player.playing) {
      if (_posSub?.isPaused == true) {
        _posSub?.resume();
      }
    }
  }

  void _onOffsetChanged() {
    if (mounted) {
      _updateActiveIndexForPosition(audioHandler.player.position, immediate: true);
    }
  }

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

  void _updateActiveIndexForPosition(Duration pos, {bool immediate = false}) {
    if (!_isLrc || _lines.isEmpty) return;

    _lastPosition = pos;
    final offsetMs = audioHandler.lyricsOffsetMsNotifier.value;
    final effectivePosition = pos + Duration(milliseconds: 180 + offsetMs);
    final idx = _findActiveLineIndex(effectivePosition);

    if (idx != _activeIndex || immediate) {
      if (mounted) {
        setState(() => _activeIndex = idx);
      } else {
        _activeIndex = idx;
      }
      _scrollToActive(idx, immediate: immediate);
    }
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _parseLyrics();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateActiveIndexForPosition(audioHandler.player.position, immediate: true);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playingSub?.cancel();
    _posSub?.cancel();
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    audioHandler.lyricsOffsetMsNotifier.removeListener(_onOffsetChanged);
    super.dispose();
  }

  void _parseLyrics() {
    _lines.clear();
    _lineKeys.clear();

    String effectiveLyrics = widget.lyrics;
    if (!LyricsClient.isLrc(effectiveLyrics)) {
      effectiveLyrics = LyricsClient.plainLyricsToAutoTimedLrc(effectiveLyrics, widget.song.duration);
    }

    final parsed = LyricsClient.parseLrc(effectiveLyrics, durationSeconds: widget.song.duration);
    _lines.addAll(parsed);
    _isLrc = _lines.isNotEmpty;

    for (int i = 0; i < _lines.length; i++) {
      _lineKeys.add(GlobalKey());
    }
  }

  void _subscribePosition() {
    _posSub?.cancel();
    _posSub = audioHandler.lyricsPositionStream.listen((pos) {
      if (!mounted) return;
      _updateActiveIndexForPosition(pos);
    });

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
          alignment: 0.45,
          duration: immediate ? Duration.zero : const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } else if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
        final viewportHeight = _scrollController.position.viewportDimension;
        final topPadding = viewportHeight * 0.22;
        const estimatedLineHeight = 48.0;
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
            duration: const Duration(milliseconds: 400),
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

  void _seekToLine(LyricLine line, int idx) {
    audioHandler.seek(line.timestamp);
    _isUserScrolling = false;
    _userScrollResumeTimer?.cancel();
    _scrollToActive(idx);
  }

  Widget _buildDualLyricsToggle() {
    return ValueListenableBuilder<DualLyrics?>(
      valueListenable: audioHandler.dualLyricsNotifier,
      builder: (context, dualLyrics, _) {
        if (dualLyrics == null || !dualLyrics.hasMultipleVariants) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<LyricsLanguage>(
          valueListenable: audioHandler.lyricsLanguageNotifier,
          builder: (context, activeLang, _) {
            final isEnglish = activeLang == LyricsLanguage.english;
            final label = isEnglish ? 'EN' : 'Default';
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: InkWell(
                onTap: () {
                  audioHandler.setLyricsLanguage(
                    isEnglish ? LyricsLanguage.defaultLang : LyricsLanguage.english,
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.translate_rounded, size: 12, color: Color(0xFF818CF8)),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
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

  Widget _buildFullscreenPill() {
    return InkWell(
      onTap: () => LyricsScreen.open(context, song: widget.song),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.45),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.fullscreen_rounded, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text(
              'FULLSCREEN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLrc) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => LyricsScreen.open(context, song: widget.song),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 36),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Center(
                    child: Text(
                      Song.sanitize(widget.lyrics),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        height: 2.1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDualLyricsToggle(),
                    _buildFullscreenPill(),
                  ],
                ),
              ),
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.touch_app_rounded, color: Colors.white60, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Tap anywhere for full screen',
                          style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
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
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.height * 0.22,
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
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: line.isBgm
                          ? BgmPulseIndicator(isActive: isActive)
                          : AnimatedScale(
                              scale: isActive ? 1.05 : 0.98,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutBack,
                              child: KaraokeLineText(
                                line: line,
                                position: _lastPosition,
                                isActive: isActive,
                                isKaraokeMode: false,
                                language: audioHandler.lyricsLanguageNotifier.value,
                                fontSize: isActive ? 20 : 15,
                                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                                baseColor: Colors.white.withValues(alpha: 0.35),
                                activeColor: Colors.white,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDualLyricsToggle(),
                _buildFullscreenPill(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
