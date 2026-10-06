import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../services/download_manager.dart';

class PlayerDownloadButton extends StatelessWidget {
  final Song song;
  const PlayerDownloadButton({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: DownloadManager.activeDownloads,
      builder: (context, activeDownloads, _) {
        final isDownloading = activeDownloads.containsKey(song.id);
        final progress = activeDownloads[song.id] ?? 0.0;
        final isDownloaded = DownloadManager.isDownloaded(song.id);

        if (isDownloaded) {
          return const IconButton(
            icon: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
            onPressed: null,
          );
        }

        if (isDownloading) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                color: const Color(0xFF6366F1),
                strokeWidth: 3,
              ),
            ),
          );
        }

        return IconButton(
          icon: const Icon(Icons.download_for_offline_outlined, color: Colors.white70, size: 28),
          onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading "${song.title}" for offline playback...'),
                duration: const Duration(seconds: 2),
              ),
            );
            await DownloadManager.downloadSong(song);
          },
        );
      },
    );
  }
}
