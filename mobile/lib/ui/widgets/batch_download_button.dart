import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/download_manager.dart';

class BatchDownloadButton extends StatelessWidget {
  final List<Song> songs;
  final String label;
  final bool isCompact;

  const BatchDownloadButton({
    Key? key,
    required this.songs,
    this.label = 'Download All',
    this.isCompact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return ValueListenableBuilder<List<Song>>(
      valueListenable: DownloadManager.downloadedSongsNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<Map<String, double>>(
          valueListenable: DownloadManager.activeDownloads,
          builder: (context, activeDownloads, __) {
            final allDownloaded = DownloadManager.areAllDownloaded(songs);
            final isAnyDownloading = DownloadManager.isAnyDownloading(songs);
            final progress = DownloadManager.getBatchDownloadProgress(songs);
            final downloadedCount = DownloadManager.getDownloadedCount(songs);

            if (allDownloaded) {
              if (isCompact) {
                return IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
                  tooltip: 'All songs downloaded',
                  onPressed: () => _showDownloadedOptions(context),
                );
              }
              return OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF10B981)),
                label: const Text('Downloaded', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _showDownloadedOptions(context),
              );
            }

            if (isAnyDownloading) {
              final percent = (progress * 100).toInt();
              if (isCompact) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        value: progress > 0 ? progress : null,
                        strokeWidth: 2.5,
                        color: const Color(0xFF6366F1),
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                      tooltip: 'Cancel downloads',
                      onPressed: () => DownloadManager.cancelBatch(songs),
                    ),
                  ],
                );
              }
              return OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
                ),
                icon: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 2,
                    color: const Color(0xFF818CF8),
                    backgroundColor: Colors.white10,
                  ),
                ),
                label: Text(
                  '$percent% ($downloadedCount/${songs.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                onPressed: () => _showCancelOptions(context),
              );
            }

            // Normal state: not all downloaded
            final remaining = songs.length - downloadedCount;
            final displayLabel = downloadedCount > 0 ? 'Download ($remaining)' : label;

            if (isCompact) {
              return IconButton(
                icon: const Icon(Icons.download_for_offline_outlined, color: Colors.white70, size: 24),
                tooltip: displayLabel,
                onPressed: () => DownloadManager.downloadBatch(songs),
              );
            }

            return OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.download_for_offline_outlined, size: 18, color: Colors.white),
              label: Text(displayLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => DownloadManager.downloadBatch(songs),
            );
          },
        );
      },
    );
  }

  void _showDownloadedOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'All ${songs.length} Tracks Downloaded',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'These tracks are available for full offline playback without internet.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  title: const Text('Delete from Offline Storage', style: TextStyle(color: Colors.redAccent)),
                  contentPadding: EdgeInsets.zero,
                  onTap: () async {
                    Navigator.pop(ctx);
                    for (final s in songs) {
                      await DownloadManager.deleteSong(s.id);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Removed ${songs.length} songs from offline storage')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCancelOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Download in Progress',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Would you like to cancel the remaining downloads in this queue?',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.stop_circle_outlined, color: Colors.orangeAccent),
                  title: const Text('Cancel Remaining Downloads', style: TextStyle(color: Colors.orangeAccent)),
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.pop(ctx);
                    DownloadManager.cancelBatch(songs);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Downloads cancelled')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
