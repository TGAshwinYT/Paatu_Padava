import 'package:flutter/material.dart';
import '../../services/sync_manager.dart';

/// Interactive Cloud Sync Status Indicator
/// Surfaces real-time library synchronization states (syncing, synced, offline, error)
/// to ensure silent sync failures are immediately visible to the user.
class SyncStatusIndicator extends StatelessWidget {
  final bool showLabel;

  const SyncStatusIndicator({super.key, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: SyncManager.syncStatusNotifier,
      builder: (context, status, _) {
        final (icon, color, tooltip, label) = switch (status) {
          SyncStatus.syncing => (
              Icons.sync_rounded,
              const Color(0xFF06B6D4), // Cyan
              'Syncing with cloud...',
              'Syncing...',
            ),
          SyncStatus.synced => (
              Icons.cloud_done_rounded,
              const Color(0xFF10B981), // Emerald Green
              'Cloud library up to date',
              'Synced',
            ),
          SyncStatus.offline => (
              Icons.cloud_off_rounded,
              const Color(0xFF9CA3AF), // Muted Grey
              'Offline — working locally',
              'Offline',
            ),
          SyncStatus.error => (
              Icons.sync_problem_rounded,
              const Color(0xFFEF4444), // Crimson Red
              'Cloud sync issue. Tap to retry.',
              'Sync Error',
            ),
          SyncStatus.idle => (
              Icons.cloud_queue_rounded,
              const Color(0xFF9CA3AF),
              'Cloud library ready',
              'Ready',
            ),
        };

        return Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    status == SyncStatus.syncing
                        ? 'Library is currently synchronizing...'
                        : 'Refreshing cloud sync...',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
              SyncManager.syncAll();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: showLabel ? 8 : 6,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: color.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status == SyncStatus.syncing)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  else
                    Icon(icon, size: 14, color: color),
                  if (showLabel) ...[
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
