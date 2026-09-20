import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../widgets/mini_player.dart';

class AlbumScreen extends StatefulWidget {
  final String albumId;
  final String albumTitle;
  final String imageUrl;

  const AlbumScreen({
    Key? key,
    required this.albumId,
    required this.albumTitle,
    required this.imageUrl,
  }) : super(key: key);

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<Song> _songs = [];
  bool _isLoading = true;
  String _artist = '';

  @override
  void initState() {
    super.initState();
    _loadAlbumDetails();
  }

  Future<void> _loadAlbumDetails() async {
    setState(() => _isLoading = true);
    final details = await SaavnClient.getAlbumDetails(widget.albumId);
    List<Song> songs = [];
    String artist = '';

    if (details != null) {
      if (details['songs'] is List<Song>) {
        songs = details['songs'] as List<Song>;
      }
      artist = details['artist']?.toString() ?? '';
    }

    // Fallback search if album details endpoint is empty
    if (songs.isEmpty) {
      songs = await SaavnClient.search('${widget.albumTitle} songs', limit: 20);
    }

    if (mounted) {
      setState(() {
        _songs = songs;
        _artist = artist;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280.0,
                pinned: true,
                backgroundColor: const Color(0xFF0F172A),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    widget.albumTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: widget.imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFF0A0E1A).withOpacity(0.85),
                              const Color(0xFF0A0E1A),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              if (!_isLoading && _songs.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: const Text('Play Album', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => audioHandler.playSong(_songs.first, queue: _songs),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withOpacity(0.15)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: const Text('Shuffle'),
                          onPressed: () {
                            final shuffled = List<Song>.from(_songs)..shuffle();
                            audioHandler.playSong(shuffled.first, queue: shuffled);
                          },
                        ),
                      ],
                    ),
                  ),
                ),

              // Songs List
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                  ),
                )
              else if (_songs.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text('No tracks found in this album', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = _songs[index];
                      return ListTile(
                        onTap: () => audioHandler.playSong(song, queue: _songs),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                        leading: SizedBox(
                          width: 28,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF64748B), size: 22),
                          onPressed: () => DownloadManager.downloadSong(song),
                        ),
                      );
                    },
                    childCount: _songs.length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),

          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
    );
  }
}
