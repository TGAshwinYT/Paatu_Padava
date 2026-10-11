import 'package:flutter/material.dart';
import '../../services/settings_manager.dart';
import '../../services/download_manager.dart';
import '../widgets/mini_player.dart';

class DownloadsSettingsScreen extends StatefulWidget {
  const DownloadsSettingsScreen({Key? key}) : super(key: key);

  @override
  State<DownloadsSettingsScreen> createState() => _DownloadsSettingsScreenState();
}

class _DownloadsSettingsScreenState extends State<DownloadsSettingsScreen> {
  bool _isDeleting = false;

  Future<void> _handleDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete All Downloads?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This will permanently remove all downloaded tracks from your local device storage. You will need an active internet connection to stream them again.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isDeleting = true);
      await DownloadManager.deleteAllDownloads();
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All downloaded tracks have been removed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Downloads & Offline',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _buildDownloadQualitySection(),
              const SizedBox(height: 20),
              _buildNetworkRulesSection(),
              const SizedBox(height: 20),
              _buildStorageLocationSection(),
              const SizedBox(height: 20),
              _buildDangerZoneSection(),
            ],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF818CF8),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadQualitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('OFFLINE AUDIO QUALITY', Icons.download_done_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Download Audio Quality',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Saved tracks are cached at this bitrate. Higher bitrates consume more device disk storage.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: SettingsManager.downloadQualityNotifier,
                builder: (context, currentQuality, _) {
                  return Column(
                    children: [
                      _buildQualityOption(
                        title: 'Data Saver (96 kbps)',
                        subtitle: 'Approx. 2.5 MB per track. Fits thousands of tracks on limited storage.',
                        badge: '96k',
                        isSelected: currentQuality == '96kbps',
                        onTap: () => SettingsManager.setDownloadQuality('96kbps'),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildQualityOption(
                        title: 'Standard (160 kbps)',
                        subtitle: 'Approx. 4.5 MB per track. Excellent fidelity for headphones and earbuds.',
                        badge: '160k',
                        isSelected: currentQuality == '160kbps',
                        onTap: () => SettingsManager.setDownloadQuality('160kbps'),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildQualityOption(
                        title: 'Extreme Fidelity (320 kbps)',
                        subtitle: 'Approx. 9.0 MB per track. Studio mastering with full dynamic depth.',
                        badge: '320k',
                        isSelected: currentQuality == '320kbps',
                        onTap: () => SettingsManager.setDownloadQuality('320kbps'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQualityOption({
    required String title,
    required String subtitle,
    required String badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1), size: 20)
            else
              const Icon(Icons.radio_button_unchecked_rounded, color: Color(0xFF475569), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkRulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('NETWORK USAGE', Icons.wifi_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.downloadWifiOnlyNotifier,
            builder: (context, wifiOnly, _) {
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.wifi_lock_rounded, color: Color(0xFF06B6D4), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Download via Wi-Fi Only',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Pause background song downloads when connected to mobile cellular data to conserve your plan.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: wifiOnly,
                    activeColor: const Color(0xFF06B6D4),
                    onChanged: (val) => SettingsManager.setDownloadWifiOnly(val),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStorageLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('STORAGE DESTINATION', Icons.sd_card_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Download Storage Path',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select whether downloaded tracks are kept on internal device storage or an external SD card.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: SettingsManager.downloadPathNotifier,
                builder: (context, currentPath, _) {
                  return Column(
                    children: [
                      _buildPathTile(
                        title: 'Internal Device Storage',
                        subtitle: 'Primary fast storage (/storage/emulated/0/Music/PaatuPadava)',
                        icon: Icons.phone_android_rounded,
                        isSelected: currentPath == 'Internal Storage',
                        onTap: () => SettingsManager.setDownloadPath('Internal Storage'),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildPathTile(
                        title: 'SD Card / External Storage',
                        subtitle: 'Removable micro-SD media (/storage/sdcard1/PaatuPadava)',
                        icon: Icons.sd_storage_rounded,
                        isSelected: currentPath == 'SD Card',
                        onTap: () => SettingsManager.setDownloadPath('SD Card'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPathTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF64748B), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1), size: 20)
            else
              const Icon(Icons.radio_button_unchecked_rounded, color: Color(0xFF475569), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZoneSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('MANAGE DOWNLOADED MEDIA', Icons.delete_sweep_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clear All Downloads',
                      style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Permanently delete all locally stored tracks to free up phone storage.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                  foregroundColor: Colors.redAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: _isDeleting ? null : _handleDeleteAll,
                child: _isDeleting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                    : const Text('Clear All', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
