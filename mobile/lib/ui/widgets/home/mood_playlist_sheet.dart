import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../logic/mood_playlist_generator.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../../services/playlist_manager.dart';
import '../../theme/app_theme.dart';

/// Modal bottom sheet to create dynamic discovery playlists from natural language mood prompts.
class MoodPlaylistSheet extends StatefulWidget {
  final String? initialPrompt;

  const MoodPlaylistSheet({super.key, this.initialPrompt});

  static Future<void> show(BuildContext context, {String? initialPrompt}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MoodPlaylistSheet(initialPrompt: initialPrompt),
    );
  }

  @override
  State<MoodPlaylistSheet> createState() => _MoodPlaylistSheetState();
}

class _MoodPlaylistSheetState extends State<MoodPlaylistSheet> {
  late final TextEditingController _controller;
  bool _isGenerating = false;
  MoodPlaylistResult? _result;
  List<Song> _tracks = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt ?? '');
    if (widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleGenerate(widget.initialPrompt!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleGenerate(String prompt) async {
    final clean = prompt.trim();
    if (clean.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    try {
      final res = await MoodPlaylistGenerator.generate(prompt: clean, targetCount: 20);
      if (!mounted) return;
      if (res.tracks.isEmpty) {
        setState(() {
          _isGenerating = false;
          _errorMessage = 'No matching tracks found for this mood. Try different keywords!';
        });
      } else {
        setState(() {
          _isGenerating = false;
          _result = res;
          _tracks = List<Song>.from(res.tracks);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = 'Failed to generate mood playlist: $e';
      });
    }
  }

  void _handlePlayNow() {
    if (_tracks.isEmpty) return;
    HapticFeedback.lightImpact();
    audioHandler.playSong(_tracks.first, queue: _tracks);
    Navigator.of(context).pop();
  }

  Future<void> _handleSavePlaylist() async {
    if (_result == null || _tracks.isEmpty) return;
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    final playlistTitle = _result!.title;

    try {
      await PlaylistManager.createPlaylist(playlistTitle, initialTracks: _tracks);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved "$playlistTitle" to your playlists!'),
          backgroundColor: AppColors.neonViolet,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to save playlist: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.surfaceBorderHighlight, width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Flexible(
            child: _result == null ? _buildInputView() : _buildResultView(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: AppColors.neonGradient, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Make a Mood Playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Type a mood, activity, or scene. Radio Engine traverses candidate graphs to synthesize a fresh discovery mix.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g., Rainy evening calm acoustic melodies...',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              prefixIcon: const Icon(Icons.bubble_chart_rounded, color: AppColors.cyanLight, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.neonViolet),
                onPressed: () => _handleGenerate(_controller.text),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.surfaceBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.neonViolet, width: 1.5)),
            ),
            onSubmitted: _handleGenerate,
          ),
          const SizedBox(height: 16),
          const Text('Popular Vibes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textWhite)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MoodPlaylistGenerator.quickMoodPresets.map((preset) {
              return ActionChip(
                backgroundColor: AppColors.surfaceElevated,
                side: const BorderSide(color: AppColors.surfaceBorder),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(preset['emoji']!, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Text(preset['title']!, style: const TextStyle(fontSize: 12, color: AppColors.textWhite)),
                  ],
                ),
                onPressed: () {
                  _controller.text = preset['prompt']!;
                  _handleGenerate(preset['prompt']!);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          if (_isGenerating)
            Center(
              child: Column(
                children: const [
                  CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.neonViolet),
                  SizedBox(height: 12),
                  Text('Synthesizing candidates & applying dispersion filters...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            )
          else if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _handleGenerate(_controller.text),
                icon: const Icon(Icons.bolt_rounded, size: 20),
                label: const Text('Generate Mix ✨', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonViolet,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    final res = _result!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Text(res.moodEmoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(res.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                    Text('${_tracks.length} tracks • Radio Engine Mix', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.textMuted),
                tooltip: 'Regenerate',
                onPressed: () => setState(() => _result = null),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _handlePlayNow,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Play Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonViolet,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _handleSavePlaylist,
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
                label: const Text('Save'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.surfaceBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: AppColors.surfaceBorder, height: 16),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: _tracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, idx) {
              final song = _tracks[idx];
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CachedNetworkImage(
                      imageUrl: song.coverUrl,
                      memCacheWidth: 96,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceElevated,
                        child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
                      ),
                    ),
                  ),
                ),
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  onPressed: () => setState(() => _tracks.removeAt(idx)),
                ),
                onTap: () {
                  audioHandler.playSong(song, queue: _tracks);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
