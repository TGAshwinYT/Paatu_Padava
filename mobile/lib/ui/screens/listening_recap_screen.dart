import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/player_handler.dart';
import '../../services/recap_service.dart';

/// Full-screen animated story experience for Paatu Recap (Music Wrapped).
/// Features 5 high-impact visual slides with story progress bars, touch navigation,
/// podium visualizers, and shareable persona summary card.
class ListeningRecapScreen extends StatefulWidget {
  const ListeningRecapScreen({Key? key}) : super(key: key);

  @override
  State<ListeningRecapScreen> createState() => _ListeningRecapScreenState();
}

class _ListeningRecapScreenState extends State<ListeningRecapScreen> with TickerProviderStateMixin {
  late Future<ListeningRecap> _recapFuture;
  late PageController _pageController;
  late AnimationController _progressController;

  int _currentIndex = 0;
  static const int _totalSlides = 5;
  static const Duration _slideDuration = Duration(seconds: 7);
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _recapFuture = ListeningRecapService.generateRecap();
    _pageController = PageController();
    _progressController = AnimationController(vsync: this, duration: _slideDuration);

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextSlide();
      }
    });

    _progressController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _nextSlide() {
    if (_currentIndex < _totalSlides - 1) {
      setState(() {
        _currentIndex++;
      });
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
      _progressController.reset();
      _progressController.forward();
    } else {
      _progressController.stop();
    }
  }

  void _prevSlide() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
      _progressController.reset();
      _progressController.forward();
    } else {
      _progressController.reset();
      _progressController.forward();
    }
  }

  void _pauseProgress() {
    setState(() => _isPaused = true);
    _progressController.stop();
  }

  void _resumeProgress() {
    setState(() => _isPaused = false);
    _progressController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070913),
      body: FutureBuilder<ListeningRecap>(
        future: _recapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }

          final recap = snapshot.data;
          if (recap == null || recap.isEmpty) {
            return _buildEmptyState();
          }

          return GestureDetector(
            onLongPressStart: (_) => _pauseProgress(),
            onLongPressEnd: (_) => _resumeProgress(),
            child: Stack(
              children: [
                // Slide Content PageView
                PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildMinutesSlide(recap),
                    _buildTopSongsSlide(recap),
                    _buildTopArtistsSlide(recap),
                    _buildPersonaSlide(recap),
                    _buildShareCardSlide(recap),
                  ],
                ),

                // Touch Target Overlay for Tap Left / Tap Right Navigation
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _prevSlide,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _nextSlide,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),

                // Top Progress Indicators & Close Action
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: List.generate(_totalSlides, (index) {
                            return Expanded(
                              child: Container(
                                height: 3.5,
                                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    if (index < _currentIndex) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      );
                                    } else if (index == _currentIndex) {
                                      return AnimatedBuilder(
                                        animation: _progressController,
                                        builder: (context, child) {
                                          return FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: _progressController.value,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(4),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.white.withOpacity(0.8),
                                                    blurRadius: 4,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    }
                                    return const SizedBox();
                                  },
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.auto_awesome, color: Color(0xFFFBBF24), size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'PAATU RECAP',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 24),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SLIDE 1: TOTAL MINUTES LISTENED
  // ---------------------------------------------------------------------------
  Widget _buildMinutesSlide(ListeningRecap recap) {
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
                color: const Color(0xFF8B5CF6).withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFA78BFA).withOpacity(0.4), width: 1.5),
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
                        color: const Color(0xFFEC4899).withOpacity(0.6),
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
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
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

  // ---------------------------------------------------------------------------
  // SLIDE 2: TOP SONGS COUNTDOWN
  // ---------------------------------------------------------------------------
  Widget _buildTopSongsSlide(ListeningRecap recap) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF022C22), Color(0xFF042F2E)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 48),
            Text(
              'Your Soundtrack',
              style: GoogleFonts.outfit(
                color: const Color(0xFF34D399),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Top Songs on Repeat',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recap.topSongs.length,
                itemBuilder: (context, index) {
                  final stat = recap.topSongs[index];
                  final isLeader = index == 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isLeader ? const Color(0xFF059669).withOpacity(0.2) : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isLeader ? const Color(0xFF10B981).withOpacity(0.4) : Colors.white.withOpacity(0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '#${index + 1}',
                          style: GoogleFonts.outfit(
                            color: isLeader ? const Color(0xFF34D399) : Colors.white38,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: stat.song.coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: stat.song.coverUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _coverPlaceholder(),
                                )
                              : _coverPlaceholder(),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stat.song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                stat.song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${stat.playCount} plays',
                              style: GoogleFonts.outfit(
                                color: isLeader ? const Color(0xFF34D399) : Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${stat.totalMinutes} min',
                              style: GoogleFonts.outfit(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
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

  // ---------------------------------------------------------------------------
  // SLIDE 3: TOP ARTISTS PODIUM
  // ---------------------------------------------------------------------------
  Widget _buildTopArtistsSlide(ListeningRecap recap) {
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
                        color: Colors.white.withOpacity(0.04),
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
                        color: badgeColor.withOpacity(0.4),
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
                  badgeColor.withOpacity(0.35),
                  badgeColor.withOpacity(0.08),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border.all(color: badgeColor.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.9),
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

  // ---------------------------------------------------------------------------
  // SLIDE 4: LISTENING PERSONA & PEAK CLOCK
  // ---------------------------------------------------------------------------
  Widget _buildPersonaSlide(ListeningRecap recap) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4C0519), Color(0xFF881337), Color(0xFF0F172A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFB7185).withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFB7185).withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, color: Color(0xFFFB7185), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'PEAK HOUR • ${recap.peakHourFormatted}',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFF43F5E), Color(0xFF881337)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF43F5E).withOpacity(0.5),
                    blurRadius: 36,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Icon(Icons.psychology_alt_rounded, color: Colors.white, size: 64),
            ),
            const SizedBox(height: 32),
            Text(
              'Your Musical Persona',
              style: GoogleFonts.outfit(
                color: const Color(0xFFFDA4AF),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              recap.listenerPersona,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              recap.personaSubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: const Color(0xFFFB7185),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Text(
                '“${recap.personaQuote}”',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SLIDE 5: RECAP SUMMARY & SHARE CARD
  // ---------------------------------------------------------------------------
  Widget _buildShareCardSlide(ListeningRecap recap) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF030712), Color(0xFF111827), Color(0xFF0F172A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Expanded(
              child: Center(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxThemeData(maxWidth: 360),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1B4B), Color(0xFF172554), Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withOpacity(0.25),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Paatu Paadava',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'RECAP',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFFA5B4FC),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'MY 2026 IN MUSIC',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF818CF8),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        recap.listenerPersona,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: Colors.white.withOpacity(0.1), height: 1),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MINUTES LISTENED',
                                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${recap.totalMinutes}',
                                  style: GoogleFonts.outfit(color: const Color(0xFF38BDF8), fontSize: 24, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TOP ARTIST',
                                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  recap.topArtists.isNotEmpty ? recap.topArtists.first.artistName : 'Various',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(color: const Color(0xFFF472B6), fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOP TRACK',
                            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            recap.topSongs.isNotEmpty ? recap.topSongs.first.song.title : 'None',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            recap.topSongs.isNotEmpty ? recap.topSongs.first.song.artist : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 6,
                    shadowColor: const Color(0xFF6366F1).withOpacity(0.5),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 20),
                  label: Text(
                    'Copy Recap Summary',
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    final topTrack = recap.topSongs.isNotEmpty ? recap.topSongs.first.song.title : 'None';
                    final topArtist = recap.topArtists.isNotEmpty ? recap.topArtists.first.artistName : 'Various';
                    final text = '🎵 My Paatu Paadava Recap:\n'
                        '⏱️ ${recap.totalMinutes} minutes listened\n'
                        '👑 Persona: ${recap.listenerPersona}\n'
                        '🌟 Top Artist: $topArtist\n'
                        '🔥 Top Track: $topTrack\n'
                        '#PaatuPaadava #MusicRecap';

                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Recap summary copied to clipboard! Share it with friends.'),
                        backgroundColor: Color(0xFF6366F1),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY & LOADING STATES
  // ---------------------------------------------------------------------------
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF8B5CF6)),
          const SizedBox(height: 20),
          Text(
            'Analyzing your sound journey...',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Color(0xFF818CF8), size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Story Begins Now',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Listen to a few songs to generate your personal listening stats, top artists, and music persona.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white60, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Explore Music',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      color: const Color(0xFF1E293B),
      child: const Icon(Icons.music_note, color: Colors.white30, size: 24),
    );
  }

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
}
