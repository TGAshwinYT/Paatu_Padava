import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/song.dart';
import '../../services/api_client.dart';
import '../../services/player_handler.dart';

class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const SpotifyImportDialog(),
    );
  }

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  String? _statusText;
  Map<String, dynamic>? _previewData;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _urlController.text = data.text!.trim();
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
      _isLoading = true;
      _statusText = 'Fetching playlist metadata from Spotify...';
    });

    final preview = await ApiClient.previewSpotifyPlaylist(url);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _statusText = null;
      _previewData = preview;
    });

    if (preview == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not fetch Spotify preview. You can still try direct import!'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }

  Future<void> _handleImport({bool playImmediately = true}) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusText = 'Matching 320kbps audio streams from JioSaavn & YouTube...';
    });

    final songs = await ApiClient.importSpotifyPlaylist(url);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _statusText = null;
    });

    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to import tracks. Check your internet connection or URL.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.pop(context);

    if (playImmediately) {
      await audioHandler.playSong(songs.first, queue: songs);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported and playing ${songs.length} tracks from Spotify!'),
          backgroundColor: const Color(0xFF1DB954),
        ),
      );
    } else {
      for (final song in songs) {
        audioHandler.addToQueue(song);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${songs.length} Spotify tracks to Queue!'),
          backgroundColor: const Color(0xFF1DB954),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import from Spotify',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Paste any Spotify playlist, album, or track URL',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // URL Input field
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

          // Loading Indicator or Preview Details
          if (_isLoading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Color(0xFF1DB954)),
                  const SizedBox(height: 16),
                  Text(
                    _statusText ?? 'Loading...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ] else if (_previewData != null) ...[
            // Preview Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x331DB954)),
              ),
              child: Row(
                children: [
                  if (_previewData!['thumbnail'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        _previewData!['thumbnail'].toString(),
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
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _previewData!['title']?.toString() ?? 'Spotify Playlist',
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
                          '${_previewData!['track_count'] ?? _previewData!['tracks']?.length ?? 0} tracks available',
                          style: const TextStyle(color: Color(0xFF1DB954), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleImport(playImmediately: false),
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
                    onPressed: () => _handleImport(playImmediately: true),
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
                    onPressed: () => _handleImport(playImmediately: true),
                    icon: const Icon(Icons.download, color: Colors.black, size: 18),
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
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
