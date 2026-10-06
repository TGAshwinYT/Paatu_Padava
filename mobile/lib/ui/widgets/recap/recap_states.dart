import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RecapLoadingState extends StatelessWidget {
  const RecapLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
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
}

class RecapEmptyState extends StatelessWidget {
  const RecapEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
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
}
