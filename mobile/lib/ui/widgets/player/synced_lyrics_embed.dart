import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../domain/models/lyrics_state.dart';
import '../../../services/player_handler.dart';
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
  final List<_LrcLine> _lines = [];
  final List<GlobalKey> _lineKeys = [];
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  int _lastPositionUpdateMs = 0;
  int _activeIndex = -1;
  bool _isUserScrolling = false;
  Timer? _userScrollResumeTimer;
  bool _isLrc = false;

  @override
  void initState() {
    super.initState();
    _parseLyrics();
    _subscribePosition();
    audioHandler.lyricsOffsetMsNotifier.addListener(_onOffsetChanged);
  }

  void _onOffsetChanged() {
    if (mounted && _isLrc && _lines.isNotEmpty) {
      final pos = audioHandler.player.position;
      final manualOffsetMs = audioHandler.lyricsOffsetMsNotifier.value;
      final effectivePosition = pos + Duration(milliseconds: manualOffsetMs);
      int idx = _lines.lastIndexWhere((l) => l.timestamp <= effectivePosition);
      if (idx == -1) idx = 0;
      if (idx != _activeIndex) {
        setState(() => _activeIndex = idx);
        _scrollToActive(idx);
      }
    }
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _parseLyrics();
      _onOffsetChanged();
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    audioHandler.lyricsOffsetMsNotifier.removeListener(_onOffsetChanged);
    _posSub?.cancel();
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _parseLyrics() {
    _lines.clear();
    _lineKeys.clear();

    final lrcRegex = RegExp(r'^\[(\d+):(\d+(?:\.\d+)?)\](.*)');
    final rawLines = widget.lyrics.split('\n');
    _isLrc = rawLines.any((l) => lrcRegex.hasMatch(l.trim()));

    if (!_isLrc) return;

    final List<_LrcLine> parsed = [];
    for (final line in rawLines) {
      final match = lrcRegex.firstMatch(line.trim());
      if (match != null) {
        final min = int.tryParse(match.group(1)!) ?? 0;
        final sec = double.tryParse(match.group(2)!) ?? 0.0;
        final rawText = match.group(3)?.trim() ?? '';
        final text = Song.sanitize(rawText);
        if (text.isNotEmpty) {
          parsed.add(_LrcLine(
            timestamp: Duration(milliseconds: ((min * 60 + sec) * 1000).toInt()),
            text: text,
            isBgm: false,
          ));
        }
      }
    }

    parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Detect BGM / Instrumental pauses > 6 seconds
    if (parsed.isNotEmpty) {
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
  }

  void _subscribePosition() {
    _posSub?.cancel();
    _lastPositionUpdateMs = 0;
    _posSub = audioHandler.throttledPositionStream.listen((pos) {
      if (!mounted || !_isLrc || _lines.isEmpty) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPositionUpdateMs < 500) return;
      _lastPositionUpdateMs = now;

      final manualOffsetMs = audioHandler.lyricsOffsetMsNotifier.value;
      final effectivePosition = pos + Duration(milliseconds: manualOffsetMs);
      int idx = _lines.lastIndexWhere((l) => l.timestamp <= effectivePosition);
      if (idx == -1) idx = 0;

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
          alignment: 0.5,
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

  @override
  Widget build(BuildContext context) {
    if (!_isLrc) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: SingleChildScrollView(
          child: Text(
            Song.sanitize(widget.lyrics),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.9,
              fontWeight: FontWeight.w500,
            ),
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
              if (notification is UserScrollNotification) {
                _onUserScroll();
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
                      final manualOffsetMs = audioHandler.lyricsOffsetMsNotifier.value;
                      final targetSeek = line.timestamp - Duration(milliseconds: manualOffsetMs);
                      audioHandler.seek(targetSeek < Duration.zero ? Duration.zero : targetSeek);
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
                              child: Text(line.text),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<DualLyrics?>(
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
                          padding: const EdgeInsets.only(right: 4.0),
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
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white70, size: 24),
                  tooltip: 'Expand Bloomee Lyrics Page',
                  onPressed: () => LyricsScreen.open(context, song: widget.song),
                ),
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

class _LrcLine {
  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;
  final bool isBgm;

  _LrcLine({
    required this.timestamp,
    this.endTimestamp,
    required this.text,
    this.isBgm = false,
  });
}
