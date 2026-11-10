import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/models/history_entry.dart';
import '../../models/song.dart';
import '../../services/favorites_manager.dart';
import '../../services/download_manager.dart';
import '../../services/playlist_manager.dart';
import '../../services/history_manager.dart';
import '../../services/player_handler.dart';
import '../../services/auth_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/sync_status_indicator.dart';
import '../widgets/account_bar_button.dart';
import '../widgets/common/song_tile.dart';
import '../widgets/library/create_blend_sheet.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'listening_recap_screen.dart';

/// Flagship single-surface Library Screen for Paatu Padava.
/// Replaces the old launcher bento boxes with a fluid Spotify/Apple Music-grade
/// library surface with sticky filter chips, pinned Liked Songs hero card,
/// and instant 1-tap playback.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  // Active Filter: 'all', 'playlists', 'liked', 'downloads', 'history'
  String _activeFilter = 'all';

  final List<Map<String, String>> _filterOptions = const [
    {'id': 'all', 'label': 'All'},
    {'id': 'playlists', 'label': 'Playlists'},
    {'id': 'liked', 'label': 'Liked'},
    {'id': 'downloads', 'label': 'Downloaded'},
    {'id': 'history', 'label': 'History'},
  ];

  void _showAddActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: AppColors.neonViolet, size: 26),
                title: Text('Create New Playlist', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Build a custom track collection', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreatePlaylistDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFEC4899), size: 24),
                title: Text('Create Shared Blend', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Merge music tastes with a friend', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  CreateBlendSheet.show(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.album_rounded, color: Color(0xFF1DB954), size: 24),
                title: Text('Import Spotify Playlist', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Sync any Spotify playlist with 320kbps Lossless audio', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  SpotifyImportDialog.show(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('New Playlist', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Give your playlist a name',
            hintStyle: GoogleFonts.outfit(color: Colors.white38),
            filled: true,
            fillColor: AppColors.bgDark,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.surfaceBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.neonViolet, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonViolet,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final title = textController.text.trim();
              if (title.isNotEmpty) {
                Navigator.pop(dialogCtx);
                final playlist = await PlaylistManager.createPlaylist(title);
                if (mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: playlist.id)));
                }
              }
            },
            child: Text('Create', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(UserPlaylist playlist) {
    if (playlist.isBlend) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFEC4899)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
      );
    }
    if (playlist.coverUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: playlist.coverUrl,
        fit: BoxFit.cover,
        memCacheWidth: 150,
        memCacheHeight: 150,
        errorWidget: (_, __, ___) => _buildFallbackCover(),
      );
    }
    return _buildFallbackCover();
  }

  Widget _buildFallbackCover() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF312E81), Color(0xFF1E1B4B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: const Icon(Icons.queue_music_rounded, color: Colors.white54, size: 22),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top App Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your Library',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.electricCyan, size: 26),
                      tooltip: 'Create or Import',
                      onPressed: _showAddActionSheet,
                    ),
                    const SyncStatusIndicator(),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
                      tooltip: 'Settings',
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    ),
                    const AccountBarButton(),
                  ],
                ),
              ),
            ),

            // Persistent Guest Mode Notification Pill
            SliverToBoxAdapter(
              child: ValueListenableBuilder<AuthUser?>(
                valueListenable: AuthManager.authNotifier,
                builder: (context, user, _) {
                  if (user == null || user.isGuest) {
                    return Container(
                      margin: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.neonViolet.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: AppColors.neonViolet, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Guest Mode: Stored locally. Sign in to sync across devices.',
                              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                          TextButton(
                            onPressed: () => AuthDialog.show(context),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.neonViolet,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('Sign In', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),

            // Category Filter Chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _filterOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = _filterOptions[index];
                    final isSelected = _activeFilter == item['id'];
                    return FilterChip(
                      selected: isSelected,
                      label: Text(
                        item['label']!,
                        style: GoogleFonts.outfit(
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 12.5,
                        ),
                      ),
                      backgroundColor: AppColors.surfaceElevated,
                      selectedColor: AppColors.neonViolet,
                      side: BorderSide(
                        color: isSelected ? AppColors.neonViolet : AppColors.surfaceBorder,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      onSelected: (_) => setState(() => _activeFilter = item['id']!),
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // View Content Switcher
            ..._buildFilterContent(context),

            // Bottom clearance for persistent MiniPlayer & BottomNavigationBar
            SliverToBoxAdapter(
              child: SizedBox(height: AppDimensions.bottomClearance(context, hasBottomNav: true)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFilterContent(BuildContext context) {
    if (_activeFilter == 'liked') {
      return _buildLikedSongsSliver();
    } else if (_activeFilter == 'downloads') {
      return _buildDownloadsSliver();
    } else if (_activeFilter == 'history') {
      return _buildHistorySliver();
    } else if (_activeFilter == 'playlists') {
      return _buildPlaylistsSliver();
    } else {
      return _buildAllUnifiedSliver(context);
    }
  }

  List<Widget> _buildAllUnifiedSliver(BuildContext context) {
    return [
      // 1. Pinned Liked Songs Hero Card
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: ValueListenableBuilder<List<Song>>(
            valueListenable: FavoritesManager.favoritesNotifier,
            builder: (context, favs, _) {
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() => _activeFilter = 'liked'),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Liked Songs',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${favs.length} ${favs.length == 1 ? "track" : "tracks"} • Auto-synced',
                              style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (favs.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 36),
                          onPressed: () => audioHandler.playSong(
                            favs.first,
                            queue: favs,
                            context: const PlaybackContext(id: 'liked', title: 'Liked Songs', type: 'liked'),
                          ),
                        )
                      else
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 14),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),

      // 2. Paatu Recap 2026 Banner
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListeningRecapScreen())),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF3B0764), Color(0xFF1E1B4B)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFFC084FC), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Paatu Recap 2026', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                        Text('Your top music persona & tracks', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFC084FC), size: 13),
                ],
              ),
            ),
          ),
        ),
      ),

      // 3. Playlists Shelf Header
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Your Playlists',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _activeFilter = 'playlists'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.electricCyan,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('See All', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ),

      // 4. Top Playlists
      ValueListenableBuilder<List<UserPlaylist>>(
        valueListenable: PlaylistManager.playlistsNotifier,
        builder: (context, playlists, _) {
          if (playlists.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('No playlists created yet. Tap + above to create one!', style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 12.5)),
              ),
            );
          }
          final displayPlaylists = playlists.take(5).toList();
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildPlaylistTile(displayPlaylists[index]),
              childCount: displayPlaylists.length,
            ),
          );
        },
      ),
    ];
  }

  Widget _buildPlaylistTile(UserPlaylist playlist) {
    final trackCount = playlist.tracks.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: playlist.id))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 48, height: 48, child: _buildCover(playlist)),
        ),
        title: Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Row(
          children: [
            if (playlist.isBlend) ...[
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFEC4899), size: 12),
              const SizedBox(width: 4),
              Text('Blend • ', style: GoogleFonts.outfit(color: const Color(0xFFEC4899), fontSize: 11, fontWeight: FontWeight.bold)),
            ] else if (playlist.isCollaborative) ...[
              const Icon(Icons.group_rounded, color: Color(0xFF34D399), size: 12),
              const SizedBox(width: 4),
              Text('Shared • ', style: GoogleFonts.outfit(color: const Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold)),
            ],
            Text('$trackCount ${trackCount == 1 ? "track" : "tracks"}', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trackCount > 0)
              IconButton(
                icon: const Icon(Icons.play_circle_filled_rounded, color: AppColors.neonViolet, size: 26),
                onPressed: () => audioHandler.playSong(
                  playlist.tracks.first,
                  queue: playlist.tracks,
                  context: PlaybackContext(id: playlist.id, title: playlist.title, type: 'playlist'),
                ),
              ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPlaylistsSliver() {
    return [
      ValueListenableBuilder<List<UserPlaylist>>(
        valueListenable: PlaylistManager.playlistsNotifier,
        builder: (context, playlists, _) {
          if (playlists.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.queue_music_rounded, color: Color(0xFF64748B), size: 48),
                    const SizedBox(height: 12),
                    Text('No Playlists Found', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonViolet, foregroundColor: Colors.white),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Create Playlist', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      onPressed: _showCreatePlaylistDialog,
                    ),
                  ],
                ),
              ),
            );
          }
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildPlaylistTile(playlists[index]),
              childCount: playlists.length,
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _buildLikedSongsSliver() {
    return [
      ValueListenableBuilder<List<Song>>(
        valueListenable: FavoritesManager.favoritesNotifier,
        builder: (context, favs, _) {
          if (favs.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_border_rounded, color: Color(0xFF64748B), size: 48),
                    const SizedBox(height: 12),
                    Text('No Liked Songs Yet', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Heart songs while listening to build your favorites', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = favs[index];
                return SongTile(
                  song: song,
                  queue: favs,
                  index: index,
                  showRank: false,
                  playbackContext: const PlaybackContext(id: 'liked', title: 'Liked Songs', type: 'liked'),
                );
              },
              childCount: favs.length,
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _buildDownloadsSliver() {
    return [
      ValueListenableBuilder<List<Song>>(
        valueListenable: DownloadManager.downloadedSongsNotifier,
        builder: (context, downloads, _) {
          if (downloads.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download_done_rounded, color: Color(0xFF64748B), size: 48),
                    const SizedBox(height: 12),
                    Text('No Offline Songs', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Download songs to listen anywhere without internet', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = downloads[index];
                return SongTile(
                  song: song,
                  queue: downloads,
                  index: index,
                  showRank: false,
                  playbackContext: const PlaybackContext(id: 'offline', title: 'Downloaded Music', type: 'downloads'),
                );
              },
              childCount: downloads.length,
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _buildHistorySliver() {
    return [
      ValueListenableBuilder<List<HistoryEntry>>(
        valueListenable: HistoryManager.historyEntriesNotifier,
        builder: (context, history, _) {
          if (history.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history_rounded, color: Color(0xFF64748B), size: 48),
                    const SizedBox(height: 12),
                    Text('No Listening History', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Tracks you play will show up here', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          final songs = history.map((e) => e.track.toSong()).toList();
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = songs[index];
                return SongTile(
                  song: song,
                  queue: songs,
                  index: index,
                  showRank: false,
                  playbackContext: const PlaybackContext(id: 'history', title: 'History', type: 'history'),
                );
              },
              childCount: songs.length,
            ),
          );
        },
      ),
    ];
  }
}
