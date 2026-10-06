import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/recap_service.dart';

class RecapTopArtistsSlide extends StatelessWidget {
  final ListeningRecap recap;

  const RecapTopArtistsSlide({super.key, required this.recap});

  Widget _artistAvatarPlaceholder(String name) {
    return Container(
      color: const Color(0xFF334155),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
    );
  }

  Widget _buildPodiumColumn({
    required int rank,
    required ArtistPlayStat artist,
    required double height,
    required Color badgeColor,
    bool isCenter = false,
  }) {
    final avatarSize = isCenter ? 72.0 : 58.0;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCenter)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 28),
            ),
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: badgeColor, width: isCenter ? 2.5 : 1.5),
              boxShadow: isCenter
                  ? [
                      BoxShadow(
                        color: badgeColor.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: ClipOval(
              child: artist.representativeCoverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: artist.representativeCoverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _artistAvatarPlaceholder(artist.artistName),
                    )
                  : _artistAvatarPlaceholder(artist.artistName),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            artist.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: isCenter ? 14 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${artist.playCount} plays',
            style: GoogleFonts.outfit(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  badgeColor.withValues(alpha: 0.35),
                  badgeColor.withValues(alpha: 0.08),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: isCenter ? 28 : 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final artists = recap.topArtists;
    final top1 = artists.isNotEmpty ? artists[0] : null;
    final top2 = artists.length > 1 ? artists[1] : null;
    final top3 = artists.length > 2 ? artists[2] : null;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF0F172A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 48),
            Text(
              'Your Musical Pantheon',
              style: GoogleFonts.outfit(
                color: const Color(0xFF818CF8),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Top Artists',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 36),

            // Podium Display (#2 Left, #1 Center, #3 Right)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (top2 != null)
                  _buildPodiumColumn(
                    rank: 2,
                    artist: top2,
                    height: 120,
                    badgeColor: const Color(0xFF94A3B8),
                  ),
                const SizedBox(width: 12),
                if (top1 != null)
                  _buildPodiumColumn(
                    rank: 1,
                    artist: top1,
                    height: 160,
                    badgeColor: const Color(0xFFFBBF24),
                    isCenter: true,
                  ),
                const SizedBox(width: 12),
                if (top3 != null)
                  _buildPodiumColumn(
                    rank: 3,
                    artist: top3,
                    height: 95,
                    badgeColor: const Color(0xFFB45309),
                  ),
              ],
            ),

            const SizedBox(height: 32),

            // Remaining Top 4 & 5
            if (artists.length > 3)
              Expanded(
                child: ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: artists.length - 3,
                  itemBuilder: (context, idx) {
                    final artist = artists[idx + 3];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '#${idx + 4}',
                            style: GoogleFonts.outfit(color: Colors.white38, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              artist.artistName,
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${artist.playCount} plays',
                            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
