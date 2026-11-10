import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../data/repositories/song_repository.dart';
import '../../services/settings_manager.dart';
import '../../services/spotify_import_service.dart';
import '../widgets/mini_player.dart';
import '../theme/app_theme.dart';
import '../widgets/common/song_tile.dart';
import '../../logic/stream_resolver.dart';

class ArtistScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final String imageUrl;

  const ArtistScreen({
    Key? key,
    required this.artistId,
    required this.artistName,
    required this.imageUrl,
  }) : super(key: key);

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  List<Song> _songs = [];
  List<Song> _filteredSongs = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _resolvedImageUrl = '';

  @override
  void initState() {
    super.initState();
    final norm = SongRepository.normalizeArtist(widget.artistName);
    if (SongRepository.verifiedArtistAvatars.containsKey(norm)) {
      _resolvedImageUrl = SongRepository.verifiedArtistAvatars[norm]!;
    } else if (widget.imageUrl.isNotEmpty) {
      _resolvedImageUrl = widget.imageUrl;
    }
    _loadArtistSongs();
    _fetchRealArtistImage();
  }

  Future<void> _fetchRealArtistImage() async {
    final norm = SongRepository.normalizeArtist(widget.artistName);
    if (SongRepository.verifiedArtistAvatars.containsKey(norm)) {
      if (mounted && _resolvedImageUrl != SongRepository.verifiedArtistAvatars[norm]!) {
        setState(() => _resolvedImageUrl = SongRepository.verifiedArtistAvatars[norm]!);
      }
      return;
    }

    // Try Spotify Web API for genuine high-res artist profile image
    try {
      final spotifyImg = await SpotifyImportService.getArtistProfileImage(widget.artistName);
      if (spotifyImg != null && spotifyImg.isNotEmpty && mounted) {
        setState(() => _resolvedImageUrl = spotifyImg);
        return;
      }
    } catch (_) {}

    final repoImg = await SongRepository.resolveArtistAvatar(widget.artistName);
    if (repoImg != null && repoImg.isNotEmpty && mounted) {
      setState(() => _resolvedImageUrl = repoImg);
      return;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadArtistSongs() async {
    setState(() => _isLoading = true);

    try {
      final discography = await SongRepository.getArtistDiscography(
        artistId: widget.artistId,
        artistName: widget.artistName,
      );

      final discImg = discography['image']?.toString() ?? '';
      if (_resolvedImageUrl.isEmpty && discImg.isNotEmpty && mounted) {
        setState(() => _resolvedImageUrl = discImg);
      }

      var uniqueSongs = (discography['songs'] as List<Song>?) ?? <Song>[];

      // Prioritize songs in user's preferred language to avoid cross-language contamination
      final effectivePrefLangs = SettingsManager.preferredLanguages.map((l) => l.toLowerCase()).toList();
      final hasPreferredSongs = effectivePrefLangs.isNotEmpty &&
          uniqueSongs.any((s) => effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(s, l)));

      // If the artist has tracks in the user's preferred languages (e.g. A.R. Rahman with Tamil & Hindi tracks),
      // boost those preferred language tracks first while keeping the rest playable below.
      // If the artist does NOT produce tracks in the user's preferred language (e.g. Ed Sheeran, Taylor Swift),
      // leave the discography in its natural popularity/hit order without arbitrary penalties.
      if (hasPreferredSongs) {
        uniqueSongs.sort((a, b) {
          final aIsMismatch = !effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(a, l));
          final bIsMismatch = !effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(b, l));
          if (!aIsMismatch && bIsMismatch) return -1;
          if (aIsMismatch && !bIsMismatch) return 1;
          return 0;
        });
      }

      if (mounted) {
        setState(() {
          _songs = uniqueSongs;
          _filteredSongs = uniqueSongs;
          _isLoading = false;
        });
        if (uniqueSongs.isNotEmpty) {
          DefaultStreamResolver.prewarmSongs(uniqueSongs, limit: 3);
        }
        return;
      }
    } catch (e) {
      debugPrint('[ArtistScreen] Error loading artist discography: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    final clean = query.trim().toLowerCase();
    setState(() {
      if (clean.isEmpty) {
        _filteredSongs = _songs;
      } else {
        _filteredSongs = _songs.where((s) {
          return s.title.toLowerCase().contains(clean) ||
              s.album.toLowerCase().contains(clean);
        }).toList();
      }
    });
  }

  Widget _buildSectionHeader(String title, IconData icon, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF818CF8), size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(
              subtitle,
              style: GoogleFonts.outfit(
                color: const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
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
                expandedHeight: 270.0,
                pinned: true,
                backgroundColor: const Color(0xFF0F172A),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16, right: 20),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      if (SongRepository.isArtistVerified(widget.artistName)) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF38BDF8),
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      _resolvedImageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _resolvedImageUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 600,
                              memCacheHeight: 600,
                              errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                            )
                          : Container(color: const Color(0xFF1E293B)),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFF0A0E1A).withValues(alpha: 0.7),
                              const Color(0xFF0A0E1A),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      // Top gradient for back button visibility
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 90,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons & Discography Status Row
              if (!_isLoading && _songs.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Catalog Count Badge
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '${_songs.length} Tracks Available',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF818CF8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Search toggle icon button
                            IconButton(
                              icon: Icon(
                                _isSearching ? Icons.close_rounded : Icons.search_rounded,
                                color: Colors.white70,
                                size: 22,
                              ),
                              tooltip: 'Filter songs',
                              onPressed: () {
                                setState(() {
                                  _isSearching = !_isSearching;
                                  if (!_isSearching) {
                                    _searchController.clear();
                                    _filteredSongs = _songs;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Search Input if toggled
                        if (_isSearching) ...[
                          Container(
                            height: 42,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131B2E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Filter in ${_songs.length} songs...',
                                hintStyle: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 13),
                                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],

                        // Play All & Shuffle Buttons
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 4,
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 22),
                              label: Text(
                                'Play All',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              onPressed: () {
                                if (_filteredSongs.isNotEmpty) {
                                  audioHandler.playSong(_filteredSongs.first, queue: _filteredSongs);
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: const Icon(Icons.shuffle_rounded, size: 18, color: Color(0xFF818CF8)),
                              label: Text(
                                'Shuffle',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              onPressed: () {
                                if (_filteredSongs.isNotEmpty) {
                                  final shuffled = List<Song>.from(_filteredSongs)..shuffle();
                                  audioHandler.playSong(shuffled.first, queue: shuffled);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // Loading State
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                  ),
                )
              else if (_songs.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.music_off_rounded, color: Color(0xFF64748B), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'No tracks found for this artist',
                          style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isSearching || _songs.length <= 5)
                // Filtered or Small Discography View
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return SongTile(
                        song: _filteredSongs[index],
                        queue: _filteredSongs,
                        index: index,
                        playbackContext: PlaybackContext(
                          id: widget.artistId,
                          title: widget.artistName,
                          type: 'artist',
                        ),
                      );
                    },
                    childCount: _filteredSongs.length,
                  ),
                )
              else ...[
                // Spotify-Style Sections: Popular Tracks & Discography
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Popular', Icons.trending_up_rounded, subtitle: 'Top 5 Tracks'),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return SongTile(
                        song: _songs[index],
                        queue: _songs,
                        index: index,
                        showRank: true,
                        playbackContext: PlaybackContext(
                          id: widget.artistId,
                          title: widget.artistName,
                          type: 'artist',
                        ),
                      );
                    },
                    childCount: _songs.length >= 5 ? 5 : _songs.length,
                  ),
                ),

                if (_songs.length > 5) ...[
                  SliverToBoxAdapter(
                    child: _buildSectionHeader(
                      'Discography & Releases',
                      Icons.album_rounded,
                      subtitle: '(${_songs.length} Tracks)',
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final songIndex = index + 5;
                        return SongTile(
                          song: _songs[songIndex],
                          queue: _songs,
                          index: songIndex,
                          playbackContext: PlaybackContext(
                            id: widget.artistId,
                            title: widget.artistName,
                            type: 'artist',
                          ),
                        );
                      },
                      childCount: _songs.length - 5,
                    ),
                  ),
                ],
              ],

              // Safe bottom padding for MiniPlayer
              SliverToBoxAdapter(
                child: SizedBox(height: AppDimensions.bottomClearance(context, hasBottomNav: false)),
              ),
            ],
          ),

          // Docked MiniPlayer above bottom navigation
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
