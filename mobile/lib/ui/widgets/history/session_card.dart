import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../domain/models/listening_session.dart';
import '../../../services/player_handler.dart';
import '../../theme/app_theme.dart';
import '../../screens/listening_session_screen.dart';
import 'session_collage_cover.dart';

/// Renders a Spotify-style Album / Playlist card for a continuous listening session.
class SessionCard extends StatelessWidget {
  final ListeningSession session;
  final bool isHorizontalCard;

  const SessionCard({
    super.key,
    required this.session,
    this.isHorizontalCard = true,
  });

  void _openSession(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListeningSessionScreen(session: session),
      ),
    );
  }

  void _playSession() {
    if (session.songs.isNotEmpty) {
      audioHandler.playSong(session.songs.first, queue: session.songs);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isHorizontalCard) {
      // Horizontal Carousel Card
      return Container(
        width: 150,
        margin: const EdgeInsets.only(right: 14),
        child: InkWell(
          onTap: () => _openSession(context),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Stack with Play Badge
              Stack(
                children: [
                  SessionCollageCover(
                    coverUrls: session.coverUrls,
                    size: 150,
                    borderRadius: 16,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _playSession,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.neonViolet,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Session Title
              Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              // Subtitle
              Text(
                '${session.formattedDate} • ${session.trackCount} tracks',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Grid / List Card in Sessions Tab
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: InkWell(
        onTap: () => _openSession(context),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SessionCollageCover(
                coverUrls: session.coverUrls,
                size: 72,
                borderRadius: 14,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session.formattedDate} at ${session.formattedStartTime}',
                      style: GoogleFonts.outfit(
                        color: AppColors.electricCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.trackCount} songs • ${session.formattedDuration}',
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _playSession,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppColors.neonViolet,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                ),
                tooltip: 'Play Session',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
