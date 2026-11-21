import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../services/device_connect_coordinator.dart';
import '../../../services/settings_manager.dart';
import '../../../services/sleep_timer_service.dart';
import '../../theme/app_theme.dart';
import '../add_to_playlist_dialog.dart';
import '../cover_art_image.dart';
import 'device_connect_sheet.dart';
import 'player_download_button.dart';
import 'player_equalizer_sheet.dart';
import 'sleep_timer_sheet.dart';

/// Consolidated Bloomee-style utilities sheet for FullPlayerScreen.
/// Houses Equalizer, Sleep Timer, Device Connect, Playlist and Download actions
/// in a clean, uncluttered bottom sheet.
class PlayerUtilitiesSheet extends StatelessWidget {
  final Song song;

  const PlayerUtilitiesSheet({super.key, required this.song});

  static void show(BuildContext context, {required Song song}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PlayerUtilitiesSheet(song: song),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header: Mini track info preview
            Row(
              children: [
                CoverArtImage(
                  song: song,
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                PlayerDownloadButton(song: song),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),

            // 1. Equalizer Action
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded, color: Color(0xFF818CF8), size: 22),
              ),
              title: const Text(
                'Equalizer',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Audio presets, bass boost & surround',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
              onTap: () {
                Navigator.pop(context);
                PlayerEqualizerSheet.show(context);
              },
            ),

            // 2. Sleep Timer Action
            ListenableBuilder(
              listenable: SleepTimerService.instance,
              builder: (context, _) {
                final timer = SleepTimerService.instance;
                final isActive = timer.isActive;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isActive ? const Color(0xFF8B5CF6) : Colors.white10).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                      color: isActive ? const Color(0xFFA78BFA) : Colors.white70,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    'Sleep Timer',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    isActive ? 'Active (${timer.formattedRemainingShort} left)' : 'Stop playback after duration',
                    style: TextStyle(
                      color: isActive ? const Color(0xFFA78BFA) : AppColors.textMuted,
                      fontSize: 11.5,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                  onTap: () {
                    Navigator.pop(context);
                    SleepTimerSheet.show(context);
                  },
                );
              },
            ),

            // 3. Connect to a Device / Cast
            ValueListenableBuilder<ConnectedDevice>(
              valueListenable: DeviceConnectCoordinator.instance.currentDeviceNotifier,
              builder: (context, device, _) {
                final isCasting = !device.isLocal;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isCasting ? const Color(0xFF10B981) : Colors.white10).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
                      color: isCasting ? const Color(0xFF34D399) : Colors.white70,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    'Connect to a Device',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    isCasting ? 'Streaming on ${device.name}' : 'Play on Google Cast, smart TV, or speakers',
                    style: TextStyle(
                      color: isCasting ? const Color(0xFF34D399) : AppColors.textMuted,
                      fontSize: 11.5,
                      fontWeight: isCasting ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                  onTap: () {
                    Navigator.pop(context);
                    DeviceConnectSheet.show(context);
                  },
                );
              },
            ),

            // 4. Add to Playlist
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.playlist_add_rounded, color: Color(0xFFF472B6), size: 22),
              ),
              title: const Text(
                'Add to Playlist',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Add track to custom or local playlist',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
              onTap: () {
                Navigator.pop(context);
                AddToPlaylistDialog.show(context, song);
              },
            ),

            // 5. Streaming Audio Quality Selector
            ValueListenableBuilder<String>(
              valueListenable: SettingsManager.streamingQualityNotifier,
              builder: (context, quality, _) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.high_quality_rounded, color: Color(0xFFFBBF24), size: 22),
                  ),
                  title: const Text(
                    'Streaming Quality',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Bitrate: $quality',
                    style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      quality,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  onTap: () => _showQualityPicker(context),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQualityPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final options = [
          {'title': '320kbps (Very High)', 'value': '320kbps', 'desc': 'Studio quality, crisp highs'},
          {'title': '160kbps (High)', 'value': '160kbps', 'desc': 'Standard quality, balanced data'},
          {'title': '96kbps (Data Saver)', 'value': '96kbps', 'desc': 'Fast buffering on weak networks'},
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Select Streaming Quality',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...options.map((opt) {
                  final isSelected = SettingsManager.streamingQuality == opt['value'];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: isSelected ? const Color(0xFFFBBF24) : Colors.white38,
                    ),
                    title: Text(
                      opt['title']!,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      opt['desc']!,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                    onTap: () {
                      SettingsManager.setStreamingQuality(opt['value']!);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
