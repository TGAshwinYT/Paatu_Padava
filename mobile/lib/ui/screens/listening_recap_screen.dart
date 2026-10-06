import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/recap_service.dart';
import '../widgets/recap/recap_minutes_slide.dart';
import '../widgets/recap/recap_top_songs_slide.dart';
import '../widgets/recap/recap_top_artists_slide.dart';
import '../widgets/recap/recap_persona_slide.dart';
import '../widgets/recap/recap_share_card_slide.dart';
import '../widgets/recap/recap_states.dart';

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
    _progressController.stop();
  }

  void _resumeProgress() {
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
            return const RecapLoadingState();
          }

          final recap = snapshot.data;
          if (recap == null || recap.isEmpty) {
            return const RecapEmptyState();
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
                    RecapMinutesSlide(recap: recap),
                    RecapTopSongsSlide(recap: recap),
                    RecapTopArtistsSlide(recap: recap),
                    RecapPersonaSlide(recap: recap),
                    RecapShareCardSlide(recap: recap),
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
                                  color: Colors.white.withValues(alpha: 0.2),
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
                                                    color: Colors.white.withValues(alpha: 0.8),
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
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
}
