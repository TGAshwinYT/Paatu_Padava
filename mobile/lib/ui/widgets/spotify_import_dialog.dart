import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/spotify_import_service.dart';
import '../../services/player_handler.dart';
import '../../services/playlist_manager.dart';

class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (ctx) => const SpotifyImportDialog(),
    );
  }

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  final TextEditingController _urlController = TextEditingController();

  // Preview & Fetch State
  bool _isLoadingPreview = false;
  String? _previewStatusText;
  SpotifyPlaylistMetadata? _previewMetadata;

  // Active Import & Progress State
  bool _isImporting = false;
  bool _isCancelled = false;
  int _currentTrackNum = 0;
  int _totalTracks = 0;
  double _progressFraction = 0.0;
  String _currentStatus = '';
  String _activeTrackTitle = '';
  String _activeTrackArtist = '';
  int _matchedCount = 0;
  int _skippedCount = 0;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      final text = data.text!.trim();
      setState(() {
        _urlController.text = text;
      });
      _handlePreview();
    }
  }

  Future<void> _handlePreview() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !url.contains('spotify.com')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Spotify link (open.spotify.com)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isLoadingPreview = true;
      _previewStatusText = 'Fetching playlist metadata from Spotify...';
    });

    try {
      final meta = await SpotifyImportService.fetchSpotifyMetadata(url);
      if (!mounted) return;

      setState(() {
        _isLoadingPreview = false;
        _previewStatusText = null;
        _previewMetadata = meta;
      });

      if (meta == null || meta.tracks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not fetch Spotify preview. You can still try direct import!'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPreview = false;
        _previewStatusText = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading playlist preview: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleImport({
    bool playImmediately = true,
    bool saveAsPlaylist = false,
    bool addToQueue = false,
  }) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // 1. Fetch metadata if not already available
    SpotifyPlaylistMetadata? meta = _previewMetadata;
    if (meta == null) {
      setState(() {
        _isLoadingPreview = true;
        _previewStatusText = 'Fetching full tracklist from Spotify...';
      });

      meta = await SpotifyImportService.fetchSpotifyMetadata(url);
      if (!mounted) return;

      setState(() {
        _isLoadingPreview = false;
        _previewStatusText = null;
        _previewMetadata = meta;
      });

      if (meta == null || meta.tracks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load Spotify playlist. Please check your URL and internet.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    // 2. Initialize in-dialog Progress View
    setState(() {
      _isImporting = true;
      _isCancelled = false;
      _currentTrackNum = 0;
      _totalTracks = meta!.tracks.length;
      _progressFraction = 0.0;
      _currentStatus = 'Matching tracks (0/${meta.tracks.length})...';
      _matchedCount = 0;
      _skippedCount = 0;
      _activeTrackTitle = meta.tracks.isNotEmpty ? meta.tracks.first.title : '';
      _activeTrackArtist = meta.tracks.isNotEmpty ? meta.tracks.first.artist : '';
    });

    // 3. Run Paginated Matching with live progress callbacks
    final result = await SpotifyImportService.importPlaylistWithProgress(
      metadata: meta,
      isCancelled: () => _isCancelled,
      onProgress: (current, total, progress, status, matched) {
        if (!mounted) return;
        setState(() {
          _currentTrackNum = current;
          _totalTracks = total;
          _progressFraction = progress;
          _currentStatus = 'Matching tracks ($current/$total)...';
          if (current <= meta!.tracks.length) {
            final t = meta.tracks[current - 1];
            _activeTrackTitle = t.title;
            _activeTrackArtist = t.artist;
          }
          if (matched != null) {
            _matchedCount++;
          } else if (status.contains('Skipped')) {
            _skippedCount++;
          }
        });
      },
    );

    if (!mounted || _isCancelled) return;

    // 4. Save to Local Hive Playlist Table named after the imported Spotify playlist
    if (saveAsPlaylist && result.importedSongs.isNotEmpty) {
      await PlaylistManager.createPlaylist(result.playlistTitle, initialTracks: result.importedSongs);
    }

    // 5. Handle Playback or Queueing
    if (playImmediately && result.importedSongs.isNotEmpty) {
      await audioHandler.playSong(result.importedSongs.first, queue: result.importedSongs);
    } else if (addToQueue && result.importedSongs.isNotEmpty) {
      for (final song in result.importedSongs) {
        audioHandler.addToQueue(song);
      }
    }

    // Capture context before closing modal bottom sheet
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();

    // 6. If any track failed to match, display summary dialog with skipped items
    if (result.hasSkipped) {
      _showImportSummaryDialog(
        rootContext,
        result,
        saveAsPlaylist: saveAsPlaylist,
        playedImmediately: playImmediately,
      );
    } else if (result.importedSongs.isNotEmpty) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text(
            saveAsPlaylist
                ? 'Saved all ${result.importedSongs.length} songs to "${result.playlistTitle}"!'
                : 'Imported and playing ${result.importedSongs.length} tracks!',
          ),
          backgroundColor: const Color(0xFF1DB954),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text('Could not match tracks on JioSaavn or YouTube.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Displays the completion summary dialog for skipped tracks
  static void _showImportSummaryDialog(
    BuildContext context,
    SpotifyImportResult result, {
    bool saveAsPlaylist = false,
    bool playedImmediately = false,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0x331DB954), width: 1.5),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        actionsPadding: const EdgeInsets.all(16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.playlist_add_check_rounded,
                color: Color(0xFF1DB954),
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Import Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prominent imported vs skipped count indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Imported ${result.importedSongs.length} of ${result.totalTracks} songs. ${result.skippedTracks.length} ${result.skippedTracks.length == 1 ? 'song' : 'songs'} skipped.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (saveAsPlaylist)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Saved ${result.importedSongs.length} tracks to local playlist "${result.playlistTitle}".',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            const Text(
              'Skipped Tracks (no confident match):',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: result.skippedTracks.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (ctx, i) {
                    final skipped = result.skippedTracks[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  skipped.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  skipped.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (!playedImmediately && result.importedSongs.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                audioHandler.playSong(result.importedSongs.first, queue: result.importedSongs);
              },
              icon: const Icon(Icons.play_arrow, color: Color(0xFF1DB954), size: 18),
              label: const Text(
                'Play Songs',
                style: TextStyle(color: Color(0xFF1DB954), fontWeight: FontWeight.bold),
              ),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: !_isImporting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isImporting) {
          setState(() {
            _isCancelled = true;
          });
          Navigator.of(context).pop();
        }
      },
      child: Container(
        margin: EdgeInsets.only(bottom: bottomInset),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: const BoxDecoration(
          color: Color(0xFF131B2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: Color(0x331DB954), width: 1.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
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
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1DB954).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.album,
                    color: Color(0xFF1DB954),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isImporting ? 'Importing Spotify Playlist' : 'Import from Spotify',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isImporting
                            ? '${_previewMetadata?.title ?? "Playlist"} ($_totalTracks tracks)'
                            : 'Paste any Spotify playlist, album, or track URL',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isImporting)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // When actively matching tracks: Show the live progress modal view
            if (_isImporting) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Percentage indicator and matching status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentStatus.isNotEmpty
                              ? _currentStatus
                              : 'Matching tracks ($_currentTrackNum/$_totalTracks)...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF1DB954).withOpacity(0.4)),
                          ),
                          child: Text(
                            '${(_progressFraction * 100).toInt()}%',
                            style: const TextStyle(
                              color: Color(0xFF1DB954),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Linear Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progressFraction > 0 ? _progressFraction : null,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Active candidate track display
                    if (_activeTrackTitle.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0E1A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF1DB954),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _activeTrackTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _activeTrackArtist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),

                    // Matched vs Skipped Counters
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Matched: $_matchedCount',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Skipped: $_skippedCount',
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Cancel import button
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _isCancelled = true;
                          });
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.stop_circle_outlined, color: Colors.white54, size: 18),
                        label: const Text('Cancel Import', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Input field (URL)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.link, color: Color(0xFF1DB954), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'https://open.spotify.com/playlist/...',
                          hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        onSubmitted: (_) => _handlePreview(),
                      ),
                    ),
                    TextButton(
                      onPressed: _pasteFromClipboard,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1DB954),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('Paste', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Loading Preview indicator
              if (_isLoadingPreview) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF1DB954)),
                      const SizedBox(height: 16),
                      Text(
                        _previewStatusText ?? 'Loading...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ] else if (_previewMetadata != null) ...[
                // Playlist Preview Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x331DB954)),
                  ),
                  child: Row(
                    children: [
                      if (_previewMetadata!.coverUrl != null && _previewMetadata!.coverUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _previewMetadata!.coverUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              color: Colors.white10,
                              child: const Icon(Icons.music_note, color: Colors.white38),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.music_note, color: Colors.white38),
                        ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _previewMetadata!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_previewMetadata!.totalTracks} tracks available',
                              style: const TextStyle(color: Color(0xFF1DB954), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Action Buttons with Preview
                ElevatedButton.icon(
                  onPressed: () => _handleImport(saveAsPlaylist: true, playImmediately: false),
                  icon: const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    'Save as Playlist',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _handleImport(addToQueue: true, playImmediately: false),
                        icon: const Icon(Icons.queue_music, size: 18),
                        label: const Text('Add to Queue'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleImport(playImmediately: true, saveAsPlaylist: true),
                        icon: const Icon(Icons.play_arrow, color: Colors.black, size: 20),
                        label: const Text(
                          'Play Now',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Default Action Buttons before preview
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _handlePreview,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Preview Tracks'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleImport(playImmediately: true, saveAsPlaylist: true),
                        icon: const Icon(Icons.play_arrow, color: Colors.black, size: 18),
                        label: const Text(
                          'Direct Import',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => _handleImport(saveAsPlaylist: true, playImmediately: false),
                  icon: const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    'Import & Save as Playlist',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
