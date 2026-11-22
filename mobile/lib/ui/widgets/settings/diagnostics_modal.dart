import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/app_logger.dart';

/// Modal bottom sheet for viewing and clearing app runtime logs and diagnostics
class DiagnosticsModal {
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Diagnostics & Crash Logs',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.bug_report_rounded, color: Color(0xFF818CF8), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'App & Playback Event Trace',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Diagnostic logs for track transitions, preload, and crashes',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final logText = await AppLogger.getLogContent();
                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.terminal_rounded, color: Color(0xFF818CF8), size: 20),
                                    SizedBox(width: 8),
                                    Text('Diagnostics & Crash Logs',
                                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  height: 380,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0A0E1A),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                    ),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        logText,
                                        style: const TextStyle(
                                          color: Color(0xFFCBD5E1),
                                          fontFamily: 'monospace',
                                          fontSize: 10.5,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: logText));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Logs copied to clipboard.'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF818CF8)),
                                    label: const Text('Copy All', style: TextStyle(color: Color(0xFF818CF8))),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close', style: TextStyle(color: Colors.white70)),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(Icons.article_outlined, size: 16),
                          label: const Text('View Logs'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await AppLogger.clearLog();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Diagnostic logs cleared.'),
                                backgroundColor: Color(0xFF1E293B),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Clear'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
