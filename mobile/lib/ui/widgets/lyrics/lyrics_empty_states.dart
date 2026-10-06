import 'package:flutter/material.dart';
import '../../../domain/models/app_error.dart';

class LyricsLoadingView extends StatelessWidget {
  const LyricsLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(color: Color(0xFF818CF8)),
          SizedBox(height: 16),
          Text(
            'Finding synchronized lyrics...',
            style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class LyricsErrorView extends StatelessWidget {
  final AppError? error;
  final VoidCallback onRetry;
  final VoidCallback onSearch;

  const LyricsErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 44, color: Color(0xFFEF4444)),
            ),
            const SizedBox(height: 16),
            const Text(
              "Couldn't load lyrics",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              error?.userMessage ?? 'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                  label: const Text('Retry', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: onRetry,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF818CF8)),
                  label: const Text('Search Lyrics', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF818CF8)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: onSearch,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LyricsRejectedMismatchView extends StatelessWidget {
  final VoidCallback onSearch;

  const LyricsRejectedMismatchView({super.key, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded, size: 48, color: Color(0xFFF59E0B)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Lyrics rejected due to low confidence',
            style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'The matched track differed too much in title or duration.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF818CF8)),
            label: const Text('Find / Search Lyrics', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF818CF8)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: onSearch,
          ),
        ],
      ),
    );
  }
}

class LyricsNotFoundView extends StatelessWidget {
  final VoidCallback onSearch;

  const LyricsNotFoundView({super.key, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lyrics_rounded, size: 48, color: Colors.white38),
          ),
          const SizedBox(height: 16),
          const Text(
            'No lyrics found for this track',
            style: TextStyle(color: Colors.white60, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enjoy the pure acoustic vibes',
            style: TextStyle(color: Colors.white30, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF818CF8)),
            label: const Text('Find / Search Lyrics', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF818CF8)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: onSearch,
          ),
        ],
      ),
    );
  }
}
