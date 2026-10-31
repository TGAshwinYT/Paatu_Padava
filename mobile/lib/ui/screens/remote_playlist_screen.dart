import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/song.dart';
import '../../services/playlist_manager.dart';
import '../../services/player_handler.dart';
import '../../logic/stream_resolver.dart';
import '../../data/repositories/song_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/batch_download_button.dart';
import '../widgets/swipeable_song_tile.dart';

class RemotePlaylistScreen extends StatefulWidget {
  final String playlistId;
  final String playlistTitle;
  final String imageUrl;
  final String? subtitle;
  final String source; // 'saavn', 'youtube', 'auto_album'

  const RemotePlaylistScreen({
    super.key,
    required this.playlistId,
    required this.playlistTitle,
    required this.imageUrl,
    this.subtitle,
    this.source = 'saavn',
  });

  @override
  State<RemotePlaylistScreen> createState() => _RemotePlaylistScreenState();
}

class _RemotePlaylistScreenState extends State<RemotePlaylistScreen> {
  List<Song> _songs = [];
  bool _isLoading = true;
  bool _isSavedToLibrary = false;
  late String _currentImageUrl;

  @override
  void initState() {
    super.initState();
    _currentImageUrl = widget.imageUrl;
    _loadPlaylistTracks();
  }

  Future<void> _loadPlaylistTracks() async {
    setState(() => _isLoading = true);

    try {
      final res = await SongRepository.getRemotePlaylistTracks(
        playlistId: widget.playlistId,
        playlistTitle: widget.playlistTitle,
        source: widget.source,
      );

      final img = res['image']?.toString() ?? '';
      if (img.isNotEmpty) _currentImageUrl = img;
      final songs = res['songs'] as List<Song>? ?? <Song>[];

      if (mounted) {
        setState(() {
          _songs = songs;
          _isLoading = false;
        });
        if (songs.isNotEmpty) {
          DefaultStreamResolver.prewarmSongs(songs, limit: 3);
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveToLibrary() async {
    if (_songs.isEmpty || _isSavedToLibrary) return;
    try {
      final name = widget.playlistTitle.trim().isNotEmpty
          ? widget.playlistTitle.trim()
          : 'Saved Playlist';
      await PlaylistManager.createPlaylist(name, initialTracks: _songs);
      if (mounted) {
        setState(() => _isSavedToLibrary = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "$name" to your playlists'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save playlist: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_songs.isEmpty) return;
    final queue = List<Song>.from(_songs);
    if (shuffle) {
      queue.shuffle();
    }
    audioHandler.playSong(queue.first, queue: queue);
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
                actions: [
                  if (_songs.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _isSavedToLibrary ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                        color: _isSavedToLibrary ? AppColors.electricCyan : Colors.white,
                      ),
                      tooltip: _isSavedToLibrary ? 'Saved to Library' : 'Save to Library',
                      onPressed: _saveToLibrary,
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    widget.playlistTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: _currentImageUrl.isNotEmpty ? _currentImageUrl : widget.imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        memCacheHeight: 600,
                        errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFF0A0E1A).withValues(alpha: 0.85),
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

              // Action Buttons Row
              if (!_isLoading && _songs.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.neonViolet,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: Text(
                              'Play All',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _playAll(shuffle: false),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF334155)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.shuffle_rounded, size: 18),
                            label: Text(
                              'Shuffle',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                            ),
                            onPressed: () => _playAll(shuffle: true),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _isSavedToLibrary ? AppColors.electricCyan : Colors.white70,
                              side: BorderSide(
                                color: _isSavedToLibrary ? AppColors.electricCyan : const Color(0xFF334155),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: Icon(
                              _isSavedToLibrary ? Icons.check_circle_rounded : Icons.add_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _isSavedToLibrary ? 'Saved' : 'Save',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                            ),
                            onPressed: _saveToLibrary,
                          ),
                          const SizedBox(width: 10),
                          BatchDownloadButton(songs: _songs),
                        ],
                      ),
                    ),
                  ),
                ),

              // Playlist Subtitle & Track Count
              if (!_isLoading && _songs.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Text(
                      '${_songs.length} Tracks • ${(widget.subtitle ?? (widget.source == "youtube" ? "YouTube Music" : "JioSaavn")).replaceAll(RegExp(r'^\d+\s*Tracks\s*•\s*', caseSensitive: false), '')}',
                      style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                ),

              // Songs List
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: AppColors.neonViolet)),
                )
              else if (_songs.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No tracks available for this playlist',
                      style: GoogleFonts.outfit(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _songs[index];
                        return SwipeableSongTile(
                          song: song,
                          queue: _songs,
                          index: index,
                        );
                      },
                      childCount: _songs.length,
                    ),
                  ),
                ),
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
