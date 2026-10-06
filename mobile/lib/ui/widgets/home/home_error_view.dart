import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../domain/models/app_error.dart';
import '../../theme/app_theme.dart';
import '../../screens/library_screen.dart';

class HomeErrorView extends StatelessWidget {
  final AppError error;
  final VoidCallback onRetry;

  const HomeErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isOffline = error.category == AppErrorCategory.offline;
    final isServerWaking = error.category == AppErrorCategory.serverWaking;

    final IconData icon = isOffline
        ? Icons.wifi_off_rounded
        : (isServerWaking ? Icons.cloud_sync_rounded : Icons.cloud_off_rounded);

    final String title = isOffline
        ? "You're Offline"
        : (isServerWaking ? "Server Is Waking Up" : "Couldn't Load Music Feed");

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Icon(icon, size: 48, color: AppColors.electricCyan),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.userMessage,
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isOffline) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_done_rounded, size: 18, color: AppColors.electricCyan),
                    label: Text(
                      'Open Downloads',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.electricCyan),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LibraryScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                ],
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                  label: Text(
                    'Retry',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonViolet,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: onRetry,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
