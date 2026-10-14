import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
  bool _isSdCardAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkSdCardAvailability();
  }

  Future<void> _checkSdCardAvailability() async {
    try {
      final extDirs = await getExternalStorageDirectories();
      final hasSd = extDirs != null && extDirs.length > 1;
      final sdPathExists = Directory('/storage/sdcard1').existsSync() || Directory('/storage/external_SD').existsSync();
      if (mounted) {
        setState(() {
          _isSdCardAvailable = hasSd || sdPathExists;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSdCardAvailable = false;
        });
      }
    }
  }

  Future<void> _handleSdCardTap() async {
    SettingsManager.setDownloadPath('SD Card');
    if (!_isSdCardAvailable && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SD Card selected. Please ensure storage permissions are granted when media is inserted.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleCustomPathDialog(String currentPath) async {
    final controller = TextEditingController(
      text: (currentPath != 'Internal Storage' && currentPath != 'SD Card')
          ? currentPath
          : '/storage/emulated/0/Music/PaatuPadava',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.folder_rounded, color: Color(0xFF6366F1), size: 24),
            SizedBox(width: 8),
            Text(
              'Set Storage Destination',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the destination directory path where offline music will be saved:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                hintText: '/storage/emulated/0/Music/PaatuPadava',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, 'DEFAULT');
            },
            child: const Text('Use Default', style: TextStyle(color: Color(0xFF818CF8))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final val = controller.text.trim();
              Navigator.pop(ctx, val.isNotEmpty ? val : 'DEFAULT');
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == 'DEFAULT') {
      SettingsManager.setDownloadPath('Internal Storage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restored default internal storage location')),
        );
      }
    } else if (result != null && result.isNotEmpty) {
      SettingsManager.setDownloadPath(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download storage path set to "$result"')),
        );
      }
    }
  }

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  final isInternal = currentPath == 'Internal Storage';
                  final isSd = currentPath == 'SD Card';
                  final isCustom = !isInternal && !isSd;

                  return Column(
                    children: [
                      _buildPathTile(
                        title: 'Internal Device Storage',
                        subtitle: 'Primary fast storage (/storage/emulated/0/Music/PaatuPadava)',
                        icon: Icons.phone_android_rounded,
                        isSelected: isInternal,
                        onTap: () => SettingsManager.setDownloadPath('Internal Storage'),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      Opacity(
                        opacity: _isSdCardAvailable ? 1.0 : 0.45,
                        child: _buildPathTile(
                          title: 'SD Card / External Storage',
                          subtitle: _isSdCardAvailable
                              ? 'Removable micro-SD media (/storage/sdcard1/PaatuPadava)'
                              : 'Removable micro-SD media (Not Detected — Tap to check permissions)',
                          icon: Icons.sd_storage_rounded,
                          isSelected: isSd,
                          onTap: _handleSdCardTap,
                        ),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildPathTile(
                        title: 'Custom Folder / Browse...',
                        subtitle: isCustom ? currentPath : 'Select custom folder or restore default storage path',
                        icon: Icons.folder_open_rounded,
                        isSelected: isCustom,
                        onTap: () => _handleCustomPathDialog(currentPath),
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
