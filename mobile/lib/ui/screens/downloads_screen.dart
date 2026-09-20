import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/download_manager.dart';
import '../../services/player_handler.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<Song> _downloadedSongs = [];
  String _totalSize = '0 MB';

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  void _loadDownloads() {
    setState(() {
      _downloadedSongs = DownloadManager.getDownloadedSongs();
      _totalSize = DownloadManager.getFormattedTotalSize();
    });
  }

  Future<void> _confirmDelete(Song song) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Download?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${song.title}" from offline storage?',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await DownloadManager.deleteSong(song.id);
      _loadDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${song.title}" from downloads'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF6366F1),
          backgroundColor: const Color(0xFF1E293B),
          onRefresh: () async => _loadDownloads(),
          child: CustomScrollView(
            slivers: [
              // Screen Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Offline Library',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Zero data • 100% Offline Playback',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.download_done_rounded, color: Color(0xFF10B981), size: 24),
                      ),
                    ],
                  ),
                ),
              ),

              // Storage & Quick Play Banner Card
              if (_downloadedSongs.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.storage_rounded, size: 16, color: Color(0xFF6366F1)),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_downloadedSongs.length} Songs Saved',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Storage: $_totalSize on device',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              if (_downloadedSongs.isNotEmpty) {
                                audioHandler.playSong(_downloadedSongs.first, queue: _downloadedSongs);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Downloaded Songs List or Empty State
              if (_downloadedSongs.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.06)),
                            ),
                            child: const Icon(
                              Icons.cloud_download_outlined,
                              size: 48,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'No Offline Songs Yet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Download songs from Home or Search to listen anywhere without internet connection!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = _downloadedSongs[index];
                      return _DownloadedSongTile(
                        song: song,
                        onTap: () => audioHandler.playSong(song, queue: _downloadedSongs),
                        onDelete: () => _confirmDelete(song),
                      );
                    },
                    childCount: _downloadedSongs.length,
                  ),
                ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadedSongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DownloadedSongTile({
    required this.song,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;

        return Dismissible(
          key: Key('offline_${song.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Colors.redAccent.withOpacity(0.8),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
          ),
          onDismissed: (_) => onDelete(),
          child: ListTile(
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: (song.localFilePath != null && File(song.localFilePath!).existsSync())
                        ? Image.file(
                            File(song.localFilePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultCover(),
                          )
                        : (song.coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: song.coverUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                                errorWidget: (_, __, ___) => _defaultCover(),
                              )
                            : _defaultCover()),
                  ),
                ),
                if (isPlaying)
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.equalizer_rounded, color: Color(0xFF6366F1), size: 24),
                  ),
              ],
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isPlaying ? const Color(0xFF6366F1) : Colors.white,
                fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
            subtitle: Row(
              children: [
                const Icon(Icons.offline_pin_rounded, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF1E293B),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.play_arrow_rounded, color: Color(0xFF6366F1)),
                          title: const Text('Play Offline', style: TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            onTap();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          title: const Text('Delete from Device', style: TextStyle(color: Colors.redAccent)),
                          onTap: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _defaultCover() {
    return Container(
      color: const Color(0xFF1E293B),
      child: const Icon(Icons.music_note_rounded, color: Color(0xFF6366F1), size: 24),
    );
  }
}
