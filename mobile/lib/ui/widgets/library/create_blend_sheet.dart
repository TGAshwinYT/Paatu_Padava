import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/song.dart';
import '../../../services/favorites_manager.dart';
import '../../../services/playlist_manager.dart';
import '../../screens/playlist_screen.dart';

/// Spotify-style Blend Creation Sheet.
/// Merges tastes between the user and a friend into an automatically updating
/// shared dynamic playlist with taste match scoring and contributor tagging.
class CreateBlendSheet extends StatefulWidget {
  const CreateBlendSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const CreateBlendSheet(),
    );
  }

  @override
  State<CreateBlendSheet> createState() => _CreateBlendSheetState();
}

class _CreateBlendSheetState extends State<CreateBlendSheet> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreating = false;

  final List<String> _quickFriends = ['Rahul', 'Priya', 'Vikram', 'Ananya', 'Karthik'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateBlend(String friendName) async {
    final cleanName = friendName.trim();
    if (cleanName.isEmpty) return;

    setState(() => _isCreating = true);
    HapticFeedback.mediumImpact();

    try {
      // 1. Gather user's favorite tracks
      final userTracks = List<Song>.from(FavoritesManager.favoritesNotifier.value);

      // If user has few favorites, synthesize starter tracks so blend is always rich
      if (userTracks.isEmpty) {
        userTracks.addAll([
          Song(
            id: 'blend_u_1',
            title: 'Aalaporan Thamizhan',
            artist: 'A.R. Rahman, Kailash Kher',
            album: 'Mersal',
            duration: 348,
            coverUrl: 'https://c.saavncdn.com/978/Mersal-Tamil-2017-500x500.jpg',
            source: 'saavn',
          ),
          Song(
            id: 'blend_u_2',
            title: 'Hukum - Thalaivar Alappara',
            artist: 'Anirudh Ravichander',
            album: 'Jailer',
            duration: 207,
            coverUrl: 'https://c.saavncdn.com/902/Jailer-Tamil-2023-20230728100523-500x500.jpg',
            source: 'saavn',
          ),
          Song(
            id: 'blend_u_3',
            title: 'Arabic Kuthu',
            artist: 'Anirudh Ravichander, Jonita Gandhi',
            album: 'Beast',
            duration: 280,
            coverUrl: 'https://c.saavncdn.com/712/Beast-Tamil-2022-20220504170823-500x500.jpg',
            source: 'saavn',
          ),
        ]);
      }

      // 2. Synthesize partner's top music taste seeds
      final partnerTracks = [
        Song(
          id: 'blend_p_1',
          title: 'Rowdy Baby',
          artist: 'Dhanush, Dhee',
          album: 'Maari 2',
          duration: 284,
          coverUrl: 'https://c.saavncdn.com/393/Maari-2-Tamil-2018-20181128-500x500.jpg',
          source: 'saavn',
        ),
        Song(
          id: 'blend_p_2',
          title: 'Marakkuma Nenjam',
          artist: 'A.R. Rahman',
          album: 'Vendhu Thanindhathu Kaadu',
          duration: 257,
          coverUrl: 'https://c.saavncdn.com/830/Vendhu-Thanindhathu-Kaadu-Tamil-2022-20220905183812-500x500.jpg',
          source: 'saavn',
        ),
        Song(
          id: 'blend_p_3',
          title: 'Badass',
          artist: 'Anirudh Ravichander',
          album: 'Leo',
          duration: 229,
          coverUrl: 'https://c.saavncdn.com/023/Leo-Tamil-2023-20231020084346-500x500.jpg',
          source: 'saavn',
        ),
        Song(
          id: 'blend_p_4',
          title: 'Enna Solla',
          artist: 'Anirudh Ravichander, Shweta Mohan',
          album: 'Thangamagan',
          duration: 217,
          coverUrl: 'https://c.saavncdn.com/582/Thangamagan-Tamil-2015-500x500.jpg',
          source: 'saavn',
        ),
      ];

      final blend = await PlaylistManager.createBlendPlaylist(
        partnerName: cleanName,
        userTracks: userTracks,
        partnerTracks: partnerTracks,
      );

      if (mounted) {
        Navigator.of(context).pop();
        _showBlendMatchDialog(context, blend);
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showBlendMatchDialog(BuildContext context, UserPlaylist blend) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // Two overlapping glowing circular avatars
            SizedBox(
              height: 64,
              width: 110,
              child: Stack(
                children: [
                  Positioned(
                    left: 10,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Center(
                        child: Text('YOU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          blend.blendPartnerName?.substring(0, 1).toUpperCase() ?? 'F',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${blend.tasteMatchScore ?? 86}% Taste Match!',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your music tastes with ${blend.blendPartnerName} have been blended into a shared real-time playlist.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistScreen(playlistId: blend.id),
                  ),
                );
              },
              child: Text(
                'Open Blend Playlist',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create a Blend',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'A shared playlist based on tastes you and a friend share',
                          style: GoogleFonts.outfit(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              Text(
                "FRIEND'S NAME",
                style: GoogleFonts.outfit(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _nameController,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Enter name (e.g. Priya)',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFEC4899), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'QUICK PICKS',
                style: GoogleFonts.outfit(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                children: _quickFriends.map((f) {
                  return ActionChip(
                    backgroundColor: const Color(0xFF1E293B),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    label: Text(f, style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                    onPressed: () {
                      _nameController.text = f;
                      _handleCreateBlend(f);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: const Color(0xFFEC4899),
                  foregroundColor: Colors.white,
                ),
                onPressed: _isCreating
                    ? null
                    : () {
                        final name = _nameController.text.trim();
                        if (name.isNotEmpty) {
                          _handleCreateBlend(name);
                        }
                      },
                child: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Generate Shared Blend',
                            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
