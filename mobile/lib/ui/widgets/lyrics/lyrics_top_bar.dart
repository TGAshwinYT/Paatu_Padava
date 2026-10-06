import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/song.dart';

class LyricsTopBar extends StatelessWidget {
  final Song? song;
  final bool isLrc;
  final bool showOffsetPill;
  final int manualOffsetMs;
  final bool isFullscreen;
  final VoidCallback onToggleOffsetPill;
  final VoidCallback onOpenWrongLyricsPicker;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onCollapse;

  const LyricsTopBar({
    super.key,
    required this.song,
    required this.isLrc,
    required this.showOffsetPill,
    required this.manualOffsetMs,
    required this.isFullscreen,
    required this.onToggleOffsetPill,
    required this.onOpenWrongLyricsPicker,
    required this.onToggleFullscreen,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isOffsetActive = manualOffsetMs != 0;

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
            color: const Color(0xFF0A0E1A).withValues(alpha: 0.65),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                tooltip: 'Collapse Lyrics',
                onPressed: onCollapse,
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
              if (isLrc) ...[
                Tooltip(
                  message: showOffsetPill ? 'Hide Offset Pill' : 'Show Sync Offset Pill',
                  child: InkWell(
                    onTap: onToggleOffsetPill,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOffsetActive
                            ? const Color(0xFF9333EA).withValues(alpha: 0.25)
                            : (showOffsetPill ? Colors.white.withValues(alpha: 0.12) : Colors.transparent),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isOffsetActive
                              ? const Color(0xFF9333EA).withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.12),
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
                              manualOffsetMs > 0 ? '+${manualOffsetMs}ms' : '${manualOffsetMs}ms',
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

              // Wrong Lyrics Picker / Manual Search
              IconButton(
                icon: const Icon(
                  Icons.manage_search_rounded,
                  color: Colors.white70,
                  size: 24,
                ),
                tooltip: 'Wrong Lyrics? Search Alternatives',
                onPressed: onOpenWrongLyricsPicker,
              ),
              const SizedBox(width: 4),

              // Always-visible Fullscreen Toggle (⛶)
              IconButton(
                icon: Icon(
                  isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                tooltip: isFullscreen ? 'Exit Fullscreen' : 'Enter Fullscreen',
                onPressed: onToggleFullscreen,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
