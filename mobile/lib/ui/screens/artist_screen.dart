import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/youtube_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';
import '../../data/repositories/song_repository.dart';
import '../../services/settings_manager.dart';
import '../../services/spotify_import_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/search/search_song_options_sheet.dart';
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

    // Fallback: JioSaavn genuine music artist search
    try {
      final saavnArtists = await SaavnClient.searchArtists(widget.artistName, limit: 3);
      for (final a in saavnArtists) {
        final img = a['image']?.toString();
        if (img != null && img.isNotEmpty && !img.contains('default') && mounted) {
          setState(() => _resolvedImageUrl = img);
          return;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadArtistSongs() async {
    setState(() => _isLoading = true);
    final List<Song> gathered = [];

    try {
      final futures = <Future<List<Song>>>[];

      // 1. Dedicated artist page details (if artistId is available)
      if (widget.artistId.trim().isNotEmpty) {
        futures.add(
          SaavnClient.getArtistDetails(widget.artistId.trim())
              .then((d) => (d?['songs'] as List<Song>?) ?? <Song>[])
              .catchError((_) => <Song>[]),
        );
      }

      // 2. JioSaavn Top Hits search
      futures.add(
        SaavnClient.search('${widget.artistName} Hit Songs', limit: 40)
            .catchError((_) => <Song>[]),
      );

      // 3. JioSaavn Complete Catalog search
      futures.add(
        SaavnClient.search(widget.artistName, limit: 40)
            .catchError((_) => <Song>[]),
      );

      // 4. YouTube Music Tracks fallback/supplement
      futures.add(
        YouTubeClient.search('${widget.artistName} Songs', limit: 25)
            .catchError((_) => <Song>[]),
      );

      final results = await Future.wait(futures);
      for (final list in results) {
        gathered.addAll(list);
      }
    } catch (e) {
      debugPrint('[ArtistScreen] Error loading artist discography: $e');
    }

    // Strict deduplication across multiple sources
    var uniqueSongs = SongRepository.deduplicateSongs(gathered);

    // Fallback if needed
    if (uniqueSongs.isEmpty) {
      try {
        final fallback = await SaavnClient.search(widget.artistName, limit: 30);
        uniqueSongs = SongRepository.deduplicateSongs(fallback);
      } catch (_) {}
    }

    // Prioritize songs in user's preferred language to avoid cross-language contamination
    final prefLang = SettingsManager.preferredLanguages.isNotEmpty
        ? SettingsManager.preferredLanguages.first.toLowerCase()
        : 'tamil';
    uniqueSongs.sort((a, b) {
      final aIsMismatch = SongRepository.isLanguageMismatch(a, prefLang);
      final bIsMismatch = SongRepository.isLanguageMismatch(b, prefLang);
      if (!aIsMismatch && bIsMismatch) return -1;
      if (aIsMismatch && !bIsMismatch) return 1;
      return 0;
    });

    if (mounted) {
      setState(() {
        _songs = uniqueSongs;
        _filteredSongs = uniqueSongs;
        _isLoading = false;
      });
      if (uniqueSongs.isNotEmpty) {
        DefaultStreamResolver.prewarmSongs(uniqueSongs, limit: 3);
      }
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

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildSongTile(Song song, {int? rank}) {
    final formattedDuration = _formatDuration(song.duration);

    return ListTile(
      onTap: () => audioHandler.playSong(song, queue: _filteredSongs),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rank != null) ...[
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: rank <= 3 ? const Color(0xFF818CF8) : const Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: CachedNetworkImage(
                imageUrl: song.coverUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF1E293B),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white30, size: 20),
                ),
              ),
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
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Row(
        children: [
          if (song.source == 'youtube') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'YT',
                style: TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          Expanded(
            child: Text(
              song.album.isNotEmpty ? song.album : widget.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: const Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ),
          if (formattedDuration.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              formattedDuration,
              style: GoogleFonts.outfit(
                color: const Color(0xFF64748B),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF64748B), size: 20),
            tooltip: 'Download Offline',
            onPressed: () => DownloadManager.downloadSong(song),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B), size: 20),
            tooltip: 'Options',
            onPressed: () => SearchSongOptionsSheet.show(context, song),
          ),
        ],
      ),
    );
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
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified_rounded,
                        color: Color(0xFF38BDF8),
                        size: 16,
                      ),
                    ],
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      _resolvedImageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _resolvedImageUrl,
                              fit: BoxFit.cover,
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
                      return _buildSongTile(_filteredSongs[index]);
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
                      return _buildSongTile(_songs[index], rank: index + 1);
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
                        return _buildSongTile(_songs[songIndex]);
                      },
                      childCount: _songs.length - 5,
                    ),
                  ),
                ],
              ],

              // Safe bottom padding for MiniPlayer
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
