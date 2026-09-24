import 'dart:ui';
import 'package:flutter/material.dart';

/// BloomeeTunes-style glassmorphic frosted pill for real-time lyrics offset synchronization.
class LyricsOffsetPill extends StatelessWidget {
  /// The current manual offset in milliseconds.
  final int offsetMs;

  /// Callback triggered when the offset value is adjusted (e.g. +50ms, -50ms).
  final ValueChanged<int> onOffsetChanged;

  /// Callback triggered when the close button (✕) is pressed.
  final VoidCallback onClose;

  /// Optional callback to reset offset. Defaults to calling [onOffsetChanged] with 0.
  final VoidCallback? onReset;

  const LyricsOffsetPill({
    super.key,
    required this.offsetMs,
    required this.onOffsetChanged,
    required this.onClose,
    this.onReset,
  });

  String get _formattedOffset {
    if (offsetMs > 0) return '+$offsetMs ms';
    if (offsetMs < 0) return '$offsetMs ms';
    return '0 ms';
  }

  @override
  Widget build(BuildContext context) {
    final isOffsetActive = offsetMs != 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.78),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isOffsetActive
                  ? const Color(0xFF1DB954).withOpacity(0.35)
                  : Colors.white.withOpacity(0.12),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
              if (isOffsetActive)
                BoxShadow(
                  color: const Color(0xFF1DB954).withOpacity(0.25),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Minus (-) button: decrements offset by 50ms
              _buildActionButton(
                icon: Icons.remove_rounded,
                tooltip: '-50ms',
                onTap: () => onOffsetChanged(offsetMs - 50),
              ),

              const SizedBox(width: 4),

              // Center display: Current offset in ms + "TAP TO RESET" subtitle
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (onReset != null) {
                      onReset!();
                    } else {
                      onOffsetChanged(0);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            color: isOffsetActive ? const Color(0xFF1DB954) : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                          child: Text(_formattedOffset),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'TAP TO RESET',
                          style: TextStyle(
                            color: isOffsetActive
                                ? const Color(0xFF1DB954).withOpacity(0.85)
                                : Colors.white38,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // Plus (+) button: increments offset by 50ms
              _buildActionButton(
                icon: Icons.add_rounded,
                tooltip: '+50ms',
                onTap: () => onOffsetChanged(offsetMs + 50),
              ),

              const SizedBox(width: 6),

              // Glass divider
              Container(
                width: 1,
                height: 22,
                color: Colors.white.withOpacity(0.12),
              ),

              const SizedBox(width: 6),

              // Right close button (✕): dismisses the pill
              _buildActionButton(
                icon: Icons.close_rounded,
                tooltip: 'Dismiss Offset Pill',
                onTap: onClose,
                iconSize: 18,
                padding: 6,
                backgroundColor: Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double iconSize = 20,
    double padding = 8,
    Color? backgroundColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor ?? Colors.white.withOpacity(0.08),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}
