import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../domain/models/app_error.dart';
import '../../theme/app_theme.dart';

class SearchErrorView extends StatelessWidget {
  final AppError error;
  final VoidCallback onRetry;
  final VoidCallback onOpenDownloads;

  const SearchErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onOpenDownloads,
  });

  @override
  Widget build(BuildContext context) {
    final isOffline = error.category == AppErrorCategory.offline;
    final isServerWaking = error.category == AppErrorCategory.serverWaking;
    final isTimeout = error.category == AppErrorCategory.timeout;

    final IconData icon = isOffline
        ? Icons.wifi_off_rounded
        : (isServerWaking
            ? Icons.cloud_sync_rounded
            : (isTimeout ? Icons.timer_off_rounded : Icons.error_outline_rounded));

    final String title = isOffline
        ? "You're Offline"
        : (isServerWaking
            ? "Server Is Starting Up"
            : (isTimeout ? "Search Timed Out" : "Search Unavailable"));

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Icon(icon, size: 48, color: AppColors.electricCyan),
            ),
            const SizedBox(height: 18),
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
                    onPressed: onOpenDownloads,
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
