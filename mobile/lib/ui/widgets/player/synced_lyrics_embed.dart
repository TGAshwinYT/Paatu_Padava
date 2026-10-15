import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../models/song.dart';
import '../../../domain/models/lyrics_state.dart';
import '../../../services/player_handler.dart';
import '../../../services/lyrics_client.dart';
import '../../screens/lyrics_screen.dart';

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

class _SyncedLyricsEmbedState extends State<SyncedLyricsEmbed> {
  final ScrollController _scrollController = ScrollController();
  final List<LyricLine> _lines = [];
  final List<GlobalKey> _lineKeys = [];
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  int _activeIndex = -1;
  bool _isUserScrolling = false;
  Timer? _userScrollResumeTimer;
  bool _isLrc = false;

  @override
  void initState() {
    super.initState();
    _parseLyrics();
    _subscribePosition();
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

  @override
  void didUpdateWidget(covariant SyncedLyricsEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _parseLyrics();
      final effectivePosition = audioHandler.player.position + const Duration(milliseconds: 180);
      final idx = _findActiveLineIndex(effectivePosition);
      if (idx != _activeIndex) {
        setState(() => _activeIndex = idx);
        _scrollToActive(idx);
      }
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _posSub?.cancel();
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _parseLyrics() {
    _lines.clear();
    _lineKeys.clear();

    String effectiveLyrics = widget.lyrics;
    if (!LyricsClient.isLrc(effectiveLyrics)) {
      effectiveLyrics = LyricsClient.plainLyricsToAutoTimedLrc(effectiveLyrics, widget.song.duration);
    }

    final parsed = LyricsClient.parseLrc(effectiveLyrics);
    _lines.addAll(parsed);
    _isLrc = _lines.isNotEmpty;

    for (int i = 0; i < _lines.length; i++) {
      _lineKeys.add(GlobalKey());
    }
  }

  void _subscribePosition() {
    _posSub?.cancel();
    _posSub = audioHandler.lyricsPositionStream.listen((pos) {
      if (!mounted || !_isLrc || _lines.isEmpty) return;

      final effectivePosition = pos + const Duration(milliseconds: 180);
      final idx = _findActiveLineIndex(effectivePosition);

      if (idx != _activeIndex) {
        setState(() => _activeIndex = idx);
        _scrollToActive(idx);
      }
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

  void _scrollToActive(int idx) {
    if (_isUserScrolling) return;
    if (idx < 0 || idx >= _lineKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keyContext = _lineKeys[idx].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.45,
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
                    onTap: () {
                      audioHandler.seek(line.timestamp);
                      _isUserScrolling = false;
                      _scrollToActive(idx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: line.isBgm
                          ? _BgmPulseIndicator(isActive: isActive)
                          : AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.35),
                                fontSize: isActive ? 20 : 15,
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                height: 1.45,
                                shadows: isActive
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF1DB954).withValues(alpha: 0.45),
                                          blurRadius: 14,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              textAlign: TextAlign.center,
                              child: Text(
                                (audioHandler.lyricsLanguageNotifier.value == LyricsLanguage.english &&
                                        line.romanizedText != null &&
                                        line.romanizedText!.isNotEmpty)
                                    ? line.romanizedText!
                                    : line.text,
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

class _BgmPulseIndicator extends StatefulWidget {
  final bool isActive;
  const _BgmPulseIndicator({Key? key, required this.isActive}) : super(key: key);

  @override
  State<_BgmPulseIndicator> createState() => _BgmPulseIndicatorState();
}

class _BgmPulseIndicatorState extends State<_BgmPulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            '• • • ♪',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 16,
              letterSpacing: 4,
            ),
          ),
        ],
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final val = _controller.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1DB954).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDot(0, val),
              const SizedBox(width: 6),
              _buildDot(1, val),
              const SizedBox(width: 6),
              _buildDot(2, val),
              const SizedBox(width: 10),
              Transform.scale(
                scale: 1.0 + (0.15 * math.sin(val * 2 * math.pi)),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Color(0xFF1DB954),
                  size: 20,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDot(int index, double animValue) {
    final phase = (animValue - (index * 0.2)) % 1.0;
    final scale = 0.75 + 0.45 * (math.sin(phase * 2 * math.pi).abs());
    final opacity = 0.35 + 0.65 * (math.sin(phase * 2 * math.pi).abs());

    return Opacity(
      opacity: opacity.clamp(0.2, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF1DB954),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x991DB954),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
