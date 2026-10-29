import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/models/listening_session.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/favorites_manager.dart';
import '../../services/history_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/mini_player.dart';
import '../widgets/history/session_collage_cover.dart';

class ListeningSessionScreen extends StatefulWidget {
  final ListeningSession session;

  const ListeningSessionScreen({
    super.key,
    required this.session,
  });

  @override
  State<ListeningSessionScreen> createState() => _ListeningSessionScreenState();
}

class _ListeningSessionScreenState extends State<ListeningSessionScreen> {
  late ListeningSession _session;
  bool _isSavingPlaylist = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
  }

  void _playAll({bool shuffle = false}) {
    if (_session.songs.isEmpty) return;
    final playlist = List<Song>.from(_session.songs);
    if (shuffle) {
      playlist.shuffle();
    }
    audioHandler.playSong(playlist.first, queue: playlist);
  }

  void _playTrackAt(int index) {
    if (index >= 0 && index < _session.songs.length) {
      audioHandler.playSong(_session.songs[index], queue: _session.songs);
    }
  }

  Future<void> _saveAsPlaylist() async {
    final titleController = TextEditingController(text: _session.title);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorderHighlight),
        ),
        title: const Text(
          'Save Session as Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save this continuous playback session to your playlists library:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Playlist Name',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AppColors.surfaceDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonViolet,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save Playlist'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSavingPlaylist = true);
      try {
        final playlist = await HistoryManager.saveSessionAsPlaylist(
          _session,
          customTitle: titleController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved "${playlist.title}" with ${_session.trackCount} songs'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save playlist: $e'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSavingPlaylist = false);
        }
      }
    }
  }

  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: song.coverUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          memCacheWidth: 150,
                          memCacheHeight: 150,
                          errorWidget: (_, __, ___) => const Icon(Icons.music_note),
                        )
                      : const Icon(Icons.music_note),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const Divider(color: AppColors.surfaceBorder),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded, color: Color(0xFF6366F1)),
                title: const Text('Play Next', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  audioHandler.insertNext(song);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Playing "${song.title}" next')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded, color: Colors.white70),
                title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  audioHandler.addToQueue(song);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added "${song.title}" to queue')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: AppColors.neonViolet),
                title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  AddToPlaylistDialog.show(context, song);
                },
              ),
              ValueListenableBuilder<List<Song>>(
                valueListenable: FavoritesManager.favoritesNotifier,
                builder: (context, _, __) {
                  final isFav = FavoritesManager.isFavorite(song.id);
                  return ListTile(
                    leading: Icon(
                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFav ? const Color(0xFFEC4899) : Colors.white70,
                    ),
                    title: Text(
                      isFav ? 'Remove from Liked Songs' : 'Save to Liked Songs',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      FavoritesManager.toggleFavorite(song);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _session.songs;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Dynamic App Bar
              SliverAppBar(
                expandedHeight: 330,
                pinned: true,
                backgroundColor: AppColors.bgDark,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: _isSavingPlaylist
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_rounded, color: Colors.white),
                    tooltip: 'Save as Playlist',
                    onPressed: _isSavingPlaylist ? null : _saveAsPlaylist,
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF4F46E5).withValues(alpha: 0.35),
                          const Color(0xFF0F172A),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 12),
                          // 2x2 Collage Cover
                          Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: SessionCollageCover(
                              coverUrls: _session.coverUrls,
                              size: 150,
                              borderRadius: 18,
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Session Title
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Subtitle Metadata
                          Text(
                            _session.subtitle,
                            style: GoogleFonts.outfit(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Action Buttons Row (Play All, Shuffle, Save as Playlist)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(
                    children: [
                      // Play All button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _playAll(),
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                          label: Text(
                            'Play Session',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.neonViolet,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Shuffle Button
                      IconButton(
                        onPressed: () => _playAll(shuffle: true),
                        icon: const Icon(Icons.shuffle_rounded, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceElevated,
                          padding: const EdgeInsets.all(13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        tooltip: 'Shuffle Play',
                      ),
                      const SizedBox(width: 10),
                      // Save to Playlist
                      IconButton(
                        onPressed: _isSavingPlaylist ? null : _saveAsPlaylist,
                        icon: const Icon(Icons.bookmark_add_outlined, color: AppColors.electricCyan),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceElevated,
                          padding: const EdgeInsets.all(13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        tooltip: 'Save to Playlists',
                      ),
                    ],
                  ),
                ),
              ),

              // Track Count Section Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CONTINUOUS TRACKS (${songs.length})',
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        _session.formattedDuration,
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Tracks List
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = songs[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: song.coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: song.coverUrl,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 150,
                                    memCacheHeight: 150,
                                    errorWidget: (_, __, ___) => Container(
                                      width: 46,
                                      height: 46,
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(Icons.music_note, color: Colors.white38),
                                    ),
                                  )
                                : Container(
                                    width: 46,
                                    height: 46,
                                    color: AppColors.surfaceElevated,
                                    child: const Icon(Icons.music_note, color: Colors.white38),
                                  ),
                          ),
                        ],
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          if (song.source == 'saavn')
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.neonViolet.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '320K',
                                style: TextStyle(
                                  color: AppColors.neonViolet,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (song.source == 'youtube')
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.electricCyan.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YT',
                                style: TextStyle(
                                  color: AppColors.electricCyan,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (song.duration > 0)
                            Text(
                              '${song.duration ~/ 60}:${(song.duration % 60).toString().padLeft(2, '0')}',
                              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          IconButton(
                            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 20),
                            onPressed: () => _showSongOptions(context, song),
                          ),
                        ],
                      ),
                      onTap: () => _playTrackAt(index),
                    );
                  },
                  childCount: songs.length,
                ),
              ),

              // Bottom padding for MiniPlayer
              const SliverToBoxAdapter(
                child: SizedBox(height: 110),
              ),
            ],
          ),

          // Persistent MiniPlayer
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
