import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/song.dart';
import '../../services/collaborative_playlist_service.dart';
import '../../services/player_handler.dart';
import '../../services/playlist_manager.dart';
import '../widgets/mini_player.dart';
import '../widgets/batch_download_button.dart';
import '../widgets/swipeable_song_tile.dart';

class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  final String? playlistTitle;

  const PlaylistScreen({
    Key? key,
    required this.playlistId,
    this.playlistTitle,
  }) : super(key: key);

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  RealtimeChannel? _collabChannel;
  bool _isCollabConnected = false;

  @override
  void initState() {
    super.initState();
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    final playlist = PlaylistManager.getPlaylist(widget.playlistId);
    if (playlist != null && playlist.isCollaborative) {
      _collabChannel = CollaborativePlaylistService.subscribeToPlaylist(
        playlistId: widget.playlistId,
        onTracksUpdated: (updatedTracks) {
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Playlist updated by a collaborator'),
                duration: Duration(seconds: 2),
                backgroundColor: Color(0xFF10B981),
              ),
            );
          }
        },
        onConnectionStatusChanged: (isConnected) {
          if (mounted) {
            setState(() {
              _isCollabConnected = isConnected;
            });
          }
        },
      );
    }
  }

  @override
  void dispose() {
    CollaborativePlaylistService.unsubscribe(_collabChannel);
    super.dispose();
  }

  void _showCollaborationSheet(BuildContext context, UserPlaylist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isCollab = playlist.isCollaborative;
            final code = playlist.inviteCode ?? '';

            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.group_rounded, color: Color(0xFF818CF8), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isCollab ? 'Collaborative Playlist' : 'Enable Collaboration',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isCollab
                                  ? 'Friends can add and remove tracks in real time'
                                  : 'Share this playlist so friends can edit together',
                              style: GoogleFonts.outfit(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (isCollab) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        playlist.isOwner ? 'Role: Creator (Host)' : 'Role: Collaborator (Editor)',
                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'INVITE CODE',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF818CF8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0E1A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            code,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3.0,
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invite code copied to clipboard!')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (playlist.isOwner)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        icon: const Icon(Icons.group_off_rounded, size: 20),
                        label: const Text('Disable Collaboration'),
                        onPressed: () async {
                          final updated = await CollaborativePlaylistService.disableCollaboration(playlist.id);
                          if (updated != null) {
                            CollaborativePlaylistService.unsubscribe(_collabChannel);
                            _collabChannel = null;
                            if (mounted) setState(() {});
                            Navigator.pop(bottomCtx);
                          }
                        },
                      )
                    else
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amberAccent,
                          side: const BorderSide(color: Colors.amberAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        label: const Text('Leave Playlist'),
                        onPressed: () async {
                          Navigator.pop(bottomCtx);
                          _confirmDelete(context, playlist);
                        },
                      ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                        label: Text(
                          'Generate Invite Code',
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          final updated = await CollaborativePlaylistService.enableCollaboration(playlist.id);
                          if (updated != null) {
                            _setupRealtimeSubscription();
                            if (mounted) setState(() {});
                            Navigator.pop(bottomCtx);
                            _showCollaborationSheet(context, updated);
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, UserPlaylist playlist) {
    final isOwner = playlist.isOwner;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        title: Text(isOwner ? 'Delete Playlist?' : 'Leave Playlist?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isOwner
              ? 'Are you sure you want to delete "${playlist.title}"? This cannot be undone.'
              : 'Are you sure you want to leave "${playlist.title}"? It will be removed from your library but remain active for other collaborators.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (isOwner) {
                PlaylistManager.deletePlaylist(playlist.id);
              } else {
                PlaylistManager.deletePlaylistDirectly(playlist.id);
              }
              Navigator.pop(dialogCtx);
              Navigator.pop(context);
            },
            child: Text(isOwner ? 'Delete' : 'Leave', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      color: const Color(0xFF1E293B),
      child: const Center(
        child: Icon(Icons.playlist_play_rounded, size: 80, color: Color(0xFF6366F1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<UserPlaylist>>(
      valueListenable: PlaylistManager.playlistsNotifier,
      builder: (context, playlists, child) {
        UserPlaylist? playlist;
        try {
          playlist = playlists.firstWhere((p) => p.id == widget.playlistId);
        } catch (_) {
          playlist = PlaylistManager.getPlaylist(widget.playlistId);
        }

        if (playlist == null) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A0E1A),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0F172A),
              title: const Text('Playlist', style: TextStyle(color: Colors.white)),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: const Center(
              child: Text('Playlist not found or deleted', style: TextStyle(color: Colors.white70)),
            ),
          );
        }

        final tracks = playlist.tracks;
        final hasCover = playlist.coverUrl.isNotEmpty;
        final isCollab = playlist.isCollaborative;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0E1A),
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 260.0,
                    pinned: true,
                    backgroundColor: const Color(0xFF0F172A),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(
                          isCollab ? Icons.group_rounded : Icons.group_add_outlined,
                          color: isCollab ? const Color(0xFF34D399) : Colors.white70,
                        ),
                        tooltip: isCollab ? 'Collaboration Active' : 'Invite Collaborators',
                        onPressed: () => _showCollaborationSheet(context, playlist!),
                      ),
                      IconButton(
                        icon: Icon(
                          playlist.isOwner ? Icons.delete_outline_rounded : Icons.logout_rounded,
                          color: Colors.redAccent,
                        ),
                        tooltip: playlist.isOwner ? 'Delete Playlist' : 'Leave Playlist',
                        onPressed: () => _confirmDelete(context, playlist!),
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        playlist.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (hasCover)
                            CachedNetworkImage(
                              imageUrl: playlist.coverUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _buildPlaceholderCover(),
                            )
                          else
                            _buildPlaceholderCover(),
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

                  // Header Info & Controls
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${tracks.length} ${tracks.length == 1 ? "track" : "tracks"}',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (isCollab) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (_isCollabConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: (_isCollabConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withOpacity(0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isCollabConnected ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                                        color: _isCollabConnected ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isCollabConnected
                                            ? 'LIVE COLLAB • ${playlist.inviteCode ?? ""}'
                                            : 'RECONNECTING • ${playlist.inviteCode ?? ""}',
                                        style: GoogleFonts.outfit(
                                          color: _isCollabConnected ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (tracks.isNotEmpty)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
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
                                    label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () => audioHandler.playSong(tracks.first, queue: tracks),
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
                                      final shuffled = List<Song>.from(tracks)..shuffle();
                                      audioHandler.playSong(shuffled.first, queue: shuffled);
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  BatchDownloadButton(songs: tracks, label: 'Download All'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Track list
                  if (tracks.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'This playlist is empty.\nSearch songs and use "Add to Playlist".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.5),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = tracks[index];
                          return SwipeableSongTile(
                            song: song,
                            queue: tracks,
                            index: index,
                            onRemove: () {
                              PlaylistManager.removeSongFromPlaylist(widget.playlistId, song.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Removed "${song.title}" from playlist'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            removeTooltip: 'Remove',
                          );
                        },
                        childCount: tracks.length,
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
      },
    );
  }
}
