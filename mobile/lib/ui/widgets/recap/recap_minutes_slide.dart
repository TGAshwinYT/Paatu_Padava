import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/recap_service.dart';

class RecapMinutesSlide extends StatelessWidget {
  final ListeningRecap recap;

  const RecapMinutesSlide({super.key, required this.recap});

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3B0764), Color(0xFF1E1B4B), Color(0xFF030712)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.4), width: 1.5),
              ),
              child: const Icon(Icons.timer_outlined, color: Color(0xFFA78BFA), size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              'You lived in\nthe sound.',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w900,
                height: 1.15,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${recap.totalMinutes}',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFF472B6),
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2.0,
                    shadows: [
                      Shadow(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.6),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'minutes',
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  _buildStatItem('Total Plays', '${recap.totalPlays}'),
                  Container(height: 32, width: 1, color: Colors.white12),
                  _buildStatItem('Unique Songs', '${recap.uniqueTracksCount}'),
                  Container(height: 32, width: 1, color: Colors.white12),
                  _buildStatItem('Artists', '${recap.uniqueArtistsCount}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
