import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../domain/models/lyrics_state.dart';
import '../../../services/lyrics_client.dart';

/// Renders a lyric line with word-by-word sweeping glowing highlight when active in Karaoke mode,
/// and smooth high-contrast typography in standard mode.
class KaraokeLineText extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final displayText = (language == LyricsLanguage.english &&
            line.romanizedText != null &&
            line.romanizedText!.isNotEmpty)
        ? line.romanizedText!
        : line.text;

    // Inactive lines or non-karaoke mode render clean static text with optical depth
    if (!isActive || !isKaraokeMode || line.words.isEmpty) {
      return Text(
        displayText,
        textAlign: TextAlign.left,
        style: TextStyle(
          color: isActive ? activeColor : baseColor,
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
      );
    }

    // Active Line under Karaoke Mode: Word-by-word fluid sweep!
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6.0,
      runSpacing: 4.0,
      children: line.words.map((word) {
        final wordText = (language == LyricsLanguage.english &&
                word.romanizedText != null &&
                word.romanizedText!.isNotEmpty)
            ? word.romanizedText!
            : word.text;

        final progress = word.progressAt(position);
        final isCompleted = progress >= 1.0;

        // Future unvoiced word
        if (progress <= 0.0) {
          return Text(
            wordText,
            style: TextStyle(
              color: baseColor,
              fontSize: fontSize,
              fontWeight: fontWeight,
              height: 1.35,
              letterSpacing: -0.2,
            ),
          );
        }

        // Fully sung word
        if (isCompleted) {
          return Text(
            wordText,
            style: TextStyle(
              color: activeColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1.35,
              letterSpacing: -0.2,
              shadows: [
                BoxShadow(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          );
        }

        // Active singing word: ShaderMask horizontal liquid sweep + scale aura
        return Transform.scale(
          scale: 1.05,
          alignment: Alignment.centerLeft,
          child: ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0.0, progress, math.min(1.0, progress + 0.06), 1.0],
                colors: [
                  const Color(0xFF06B6D4), // Cyan active singing fill
                  const Color(0xFF06B6D4),
                  baseColor,
                  baseColor,
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcIn,
            child: Text(
              wordText,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                height: 1.35,
                letterSpacing: -0.2,
                shadows: [
                  BoxShadow(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.60),
                    blurRadius: 18,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
