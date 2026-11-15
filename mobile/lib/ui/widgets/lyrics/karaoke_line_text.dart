import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../domain/models/lyrics_state.dart';
import '../../../services/lyrics_client.dart';

/// Renders a lyric line with smooth GPU-accelerated word-by-word sweeping highlight
/// when active in Karaoke mode, without allocating per-word ShaderMask widgets or heavy shadows.
/// Smoothly interpolates highlight progress between 200ms audio position emissions using a Ticker.
class KaraokeLineText extends StatefulWidget {
  final LyricLine line;
  final Duration position;
  final bool isActive;
  final bool isKaraokeMode;
  final LyricsLanguage language;
  final double fontSize;
  final FontWeight fontWeight;
  final Color baseColor;
  final Color activeColor;

  const KaraokeLineText({
    super.key,
    required this.line,
    required this.position,
    required this.isActive,
    required this.isKaraokeMode,
    required this.language,
    required this.fontSize,
    required this.fontWeight,
    required this.baseColor,
    required this.activeColor,
  });

  @override
  State<KaraokeLineText> createState() => _KaraokeLineTextState();
}

class _KaraokeLineTextState extends State<KaraokeLineText> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _lastAudioPosition = Duration.zero;
  int _lastPositionReceivedEpochMs = 0;
  double _smoothProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _lastAudioPosition = widget.position;
    _lastPositionReceivedEpochMs = DateTime.now().millisecondsSinceEpoch;
    _updateProgress(widget.position);
    _initTickerIfNeeded();
  }

  @override
  void didUpdateWidget(KaraokeLineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _lastAudioPosition = widget.position;
      _lastPositionReceivedEpochMs = DateTime.now().millisecondsSinceEpoch;
    }

    if (widget.isActive && widget.isKaraokeMode && widget.line.words.isNotEmpty) {
      _initTickerIfNeeded();
    } else {
      _stopTicker();
    }
  }

  void _initTickerIfNeeded() {
    if (widget.isActive && widget.isKaraokeMode && widget.line.words.isNotEmpty) {
      if (_ticker == null) {
        _ticker = createTicker(_onTick);
        _ticker!.start();
      } else if (!_ticker!.isActive) {
        _ticker!.start();
      }
    }
  }

  void _stopTicker() {
    if (_ticker != null && _ticker!.isActive) {
      _ticker!.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || !widget.isActive || !widget.isKaraokeMode) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedSinceAudioTick = nowMs - _lastPositionReceivedEpochMs;
    // Interpolate smoothly up to 300ms between audio stream packets
    final interpolatedMs = _lastAudioPosition.inMilliseconds + elapsedSinceAudioTick.clamp(0, 300);
    final interpolatedPos = Duration(milliseconds: interpolatedMs);

    final newProgress = _calculateLineProgress(interpolatedPos);
    if ((newProgress - _smoothProgress).abs() > 0.002) {
      setState(() {
        _smoothProgress = newProgress;
      });
    }
  }

  double _calculateLineProgress(Duration currentPos) {
    if (widget.line.words.isEmpty) return 0.0;

    final firstStart = widget.line.words.first.start;
    final lastEnd = widget.line.words.last.end;
    final totalDurationMs = (lastEnd - firstStart).inMilliseconds;
    if (totalDurationMs <= 0) return 0.0;

    final currentElapsedMs = (currentPos - firstStart).inMilliseconds;
    return (currentElapsedMs / totalDurationMs).clamp(0.0, 1.0);
  }

  void _updateProgress(Duration pos) {
    _smoothProgress = _calculateLineProgress(pos);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayText = (widget.language == LyricsLanguage.english &&
            widget.line.romanizedText != null &&
            widget.line.romanizedText!.isNotEmpty)
        ? widget.line.romanizedText!
        : widget.line.text;

    final baseTextStyle = TextStyle(
      color: widget.isActive ? widget.activeColor : widget.baseColor,
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
      height: 1.35,
      letterSpacing: -0.2,
      shadows: widget.isActive
          ? [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.20),
                blurRadius: 10,
                offset: const Offset(0, 1),
              ),
            ]
          : null,
    );

    // Inactive lines or non-karaoke mode render clean static text with optical depth
    if (!widget.isActive || !widget.isKaraokeMode || widget.line.words.isEmpty) {
      return Text(
        displayText,
        textAlign: TextAlign.left,
        style: baseTextStyle,
      );
    }

    // Active line in Karaoke mode: GPU clip-sweep with zero per-word ShaderMask passes
    final activeTextStyle = baseTextStyle.copyWith(
      color: const Color(0xFF06B6D4), // Cyan active singing fill
      fontWeight: FontWeight.w900,
      shadows: [
        BoxShadow(
          color: const Color(0xFF06B6D4).withValues(alpha: 0.40),
          blurRadius: 8,
          offset: const Offset(0, 1),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, widget.fontSize * 1.5),
          painter: _KaraokeSweepPainter(
            text: displayText,
            baseStyle: baseTextStyle,
            activeStyle: activeTextStyle,
            progress: _smoothProgress,
            maxWidth: constraints.maxWidth,
          ),
          child: Text(
            displayText,
            textAlign: TextAlign.left,
            style: baseTextStyle.copyWith(color: Colors.transparent),
          ),
        );
      },
    );
  }
}

class _KaraokeSweepPainter extends CustomPainter {
  final String text;
  final TextStyle baseStyle;
  final TextStyle activeStyle;
  final double progress;
  final double maxWidth;

  _KaraokeSweepPainter({
    required this.text,
    required this.baseStyle,
    required this.activeStyle,
    required this.progress,
    required this.maxWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final basePainter = TextPainter(
      text: TextSpan(text: text, style: baseStyle),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: maxWidth > 0 ? maxWidth : size.width);

    // 1. Draw full unvoiced base text
    basePainter.paint(canvas, Offset.zero);

    if (progress <= 0.0) return;

    // 2. Draw active singing highlight with a single clipped canvas pass
    final activePainter = TextPainter(
      text: TextSpan(text: text, style: activeStyle),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: maxWidth > 0 ? maxWidth : size.width);

    final highlightWidth = basePainter.width * progress;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, highlightWidth, basePainter.height));
    activePainter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KaraokeSweepPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.text != text ||
        oldDelegate.baseStyle != baseStyle ||
        oldDelegate.activeStyle != activeStyle;
  }
}
