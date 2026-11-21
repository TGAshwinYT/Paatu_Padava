import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/song.dart';
import '../../../services/download_manager.dart';
import '../cover_art_image.dart';

/// Spotify & Bloomee grade animated download button with:
/// 1. Dynamic circular progress ring during active downloads.
/// 2. Joyful spring-scale completion pop (0.8 -> 1.25 -> 1.0) when finished.
/// 3. Interactive options sheet when tapped while downloaded (Remove download, audio info).
class PlayerDownloadButton extends StatefulWidget {
  final Song song;
  final double size;
  final Color? iconColor;
  final Color? downloadedColor;

  const PlayerDownloadButton({
    super.key,
    required this.song,
    this.size = 28.0,
    this.iconColor,
    this.downloadedColor,
  });

  @override
  State<PlayerDownloadButton> createState() => _PlayerDownloadButtonState();
}

class _PlayerDownloadButtonState extends State<PlayerDownloadButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController;
  late final Animation<double> _popAnimation;
  bool _wasDownloading = false;

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _popAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.8, end: 1.28)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.28, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 40,
      ),
    ]).animate(_popController);
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  void _showDownloadedOptions(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: CoverArtImage(
                          song: widget.song,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 13),
                          SizedBox(width: 4),
                          Text(
                            'Downloaded',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                  title: const Text(
                    'Remove Download',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Delete offline copy from device storage',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    HapticFeedback.lightImpact();
                    await DownloadManager.deleteSong(widget.song.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Removed "${widget.song.title}" from downloads'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: DownloadManager.downloadedSongsNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<Map<String, double>>(
          valueListenable: DownloadManager.activeDownloads,
          builder: (context, activeDownloads, _) {
            final isDownloading = activeDownloads.containsKey(widget.song.id);
            final progress = activeDownloads[widget.song.id] ?? 0.0;
            final isDownloaded = DownloadManager.isDownloaded(widget.song.id);

            // Trigger spring scale pop when download completes
            if (_wasDownloading && !isDownloading && isDownloaded) {
              _popController.forward(from: 0.0);
            }
            _wasDownloading = isDownloading;

            if (isDownloaded) {
              return ScaleTransition(
                scale: _popAnimation,
                child: IconButton(
                  iconSize: widget.size,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: widget.size + 12,
                    height: widget.size + 12,
                  ),
                  icon: Icon(
                    Icons.check_circle_rounded,
                    color: widget.downloadedColor ?? const Color(0xFF10B981),
                    size: widget.size,
                  ),
                  tooltip: 'Downloaded (Tap for options)',
                  onPressed: () => _showDownloadedOptions(context),
                ),
              );
            }

            if (isDownloading) {
              return Tooltip(
                message: 'Downloading ${(progress * 100).toInt()}%',
                child: SizedBox(
                  width: widget.size + 12,
                  height: widget.size + 12,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: widget.size,
                          height: widget.size,
                          child: CircularProgressIndicator(
                            value: progress > 0 ? progress : null,
                            color: const Color(0xFF6366F1),
                            backgroundColor: Colors.white12,
                            strokeWidth: 2.5,
                          ),
                        ),
                        Icon(
                          Icons.arrow_downward_rounded,
                          size: widget.size * 0.45,
                          color: const Color(0xFF818CF8),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final isQueued = DownloadManager.isQueuedOrDownloading(widget.song.id);
            if (isQueued) {
              return SizedBox(
                width: widget.size + 12,
                height: widget.size + 12,
                child: Center(
                  child: Icon(
                    Icons.hourglass_empty_rounded,
                    color: const Color(0xFF818CF8),
                    size: widget.size * 0.75,
                  ),
                ),
              );
            }

            return IconButton(
              iconSize: widget.size,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: widget.size + 12,
                height: widget.size + 12,
              ),
              icon: Icon(
                Icons.download_for_offline_outlined,
                color: widget.iconColor ?? Colors.white70,
                size: widget.size,
              ),
              tooltip: 'Download offline',
              onPressed: () async {
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Downloading "${widget.song.title}" for offline playback...'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                await DownloadManager.downloadSong(widget.song);
              },
            );
          },
        );
      },
    );
  }
}
