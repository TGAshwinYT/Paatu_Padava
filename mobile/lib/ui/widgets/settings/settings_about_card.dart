import 'package:flutter/material.dart';
import '../../../services/supabase_service.dart';

/// About Paatu Padava Card displaying version, build info, and cloud sync status
class SettingsAboutCard extends StatelessWidget {
  final String appVersion;
  final String gitCommit;
  final String buildTime;

  const SettingsAboutCard({
    Key? key,
    required this.appVersion,
    this.gitCommit = '',
    this.buildTime = '',
  }) : super(key: key);

  String get _buildDetailsText {
    final commit = gitCommit.trim();
    final time = buildTime.trim();
    if (commit.isNotEmpty && time.isNotEmpty) {
      return '$appVersion • Git: $commit • $time';
    } else if (commit.isNotEmpty) {
      return '$appVersion • Git: $commit';
    } else if (time.isNotEmpty) {
      return '$appVersion • Build: $time';
    }
    return '$appVersion • Local Dev';
  }

  @override
  Widget build(BuildContext context) {
    final isConfigured = SupabaseService.isConfigured;
    final isInitialized = SupabaseService.isInitialized;
    final isHealthy = isConfigured && isInitialized;

    String pillText;
    if (!isConfigured) {
      pillText = 'Cloud Sync: Unavailable';
    } else if (!isInitialized) {
      pillText = 'Cloud Sync: Offline (Unable to reach sync service)';
    } else {
      final url = SupabaseService.supabaseUrl;
      final isProd = url.contains('bdolimatfkyqibiedlqp');
      pillText = 'Cloud Sync: Active (${isProd ? 'Production' : 'Connected'})';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.music_note_rounded, color: Color(0xFF6366F1), size: 24),
              SizedBox(width: 10),
              Text(
                'Paatu Padava Mobile',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_buildDetailsText\nComplete Web App Parity • Smart AI Shuffle • Lossless Audio Streaming & Offline Downloads.',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isHealthy ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isHealthy ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFEF4444).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHealthy ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  size: 14,
                  color: isHealthy ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    pillText,
                    style: TextStyle(
                      color: isHealthy ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
