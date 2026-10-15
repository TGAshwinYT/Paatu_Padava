import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/device_connect_coordinator.dart';
import '../../../services/player_handler.dart';
import '../party_mode_sheet.dart';

/// Spotify Connect & Apple AirPlay Device Picker Sheet.
/// Allows instant switching between phone speaker, smart TVs, UPnP/DLNA/AirPlay speakers,
/// and WebSocket Party Sync sessions.
class DeviceConnectSheet extends StatefulWidget {
  const DeviceConnectSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DeviceConnectSheet(),
    );
  }

  @override
  State<DeviceConnectSheet> createState() => _DeviceConnectSheetState();
}

class _DeviceConnectSheetState extends State<DeviceConnectSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _scanAnimController;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    DeviceConnectCoordinator.instance.scanForDevices();
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    super.dispose();
  }

  IconData _iconForDevice(DeviceType type) {
    switch (type) {
      case DeviceType.tv:
        return Icons.tv_rounded;
      case DeviceType.speaker:
        return Icons.speaker_rounded;
      case DeviceType.computer:
        return Icons.laptop_chromebook_rounded;
      case DeviceType.partyGroup:
        return Icons.groups_rounded;
      case DeviceType.phone:
        return Icons.phone_android_rounded;
    }
  }

  Color _badgeColorForProtocol(ConnectionProtocol protocol) {
    switch (protocol) {
      case ConnectionProtocol.googleCast:
        return const Color(0xFF3B82F6);
      case ConnectionProtocol.airPlay:
        return const Color(0xFFA855F7);
      case ConnectionProtocol.dlna:
        return const Color(0xFFF59E0B);
      case ConnectionProtocol.webSocket:
        return const Color(0xFF10B981);
      case ConnectionProtocol.local:
        return const Color(0xFF6366F1);
    }
  }

  String _labelForProtocol(ConnectionProtocol protocol) {
    switch (protocol) {
      case ConnectionProtocol.googleCast:
        return 'Google Cast';
      case ConnectionProtocol.airPlay:
        return 'AirPlay / UPnP';
      case ConnectionProtocol.dlna:
        return 'DLNA';
      case ConnectionProtocol.webSocket:
        return 'Connect';
      case ConnectionProtocol.local:
        return 'Local';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top drag bar
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.devices_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connect to a Device',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Spotify Connect & AirPlay Continuity',
                            style: GoogleFonts.outfit(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: DeviceConnectCoordinator.instance.isScanningNotifier,
                    builder: (context, isScanning, _) {
                      return IconButton(
                        icon: isScanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                              )
                            : const Icon(Icons.refresh_rounded, color: Colors.white70),
                        tooltip: 'Scan for devices',
                        onPressed: isScanning
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                DeviceConnectCoordinator.instance.scanForDevices();
                              },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Current Active Device Card
              ValueListenableBuilder<ConnectedDevice>(
                valueListenable: DeviceConnectCoordinator.instance.currentDeviceNotifier,
                builder: (context, currentDevice, _) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: currentDevice.isLocal
                            ? const Color(0xFF6366F1).withValues(alpha: 0.3)
                            : const Color(0xFF10B981).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (currentDevice.isLocal ? const Color(0xFF6366F1) : const Color(0xFF10B981))
                              .withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: (currentDevice.isLocal ? const Color(0xFF6366F1) : const Color(0xFF10B981))
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _iconForDevice(currentDevice.type),
                                color: currentDevice.isLocal ? const Color(0xFF818CF8) : const Color(0xFF10B981),
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'CURRENT AUDIO OUTPUT',
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFF10B981),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentDevice.name,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    currentDevice.isLocal
                                        ? "Playing through this phone's speakers"
                                        : "${currentDevice.status} • High Fidelity Lossless",
                                    style: GoogleFonts.outfit(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!currentDevice.isLocal)
                              TextButton(
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  DeviceConnectCoordinator.instance.disconnect();
                                },
                                child: Text(
                                  'This Phone',
                                  style: GoogleFonts.outfit(
                                    color: const Color(0xFF818CF8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Volume Slider for active target
                        Row(
                          children: [
                            Icon(
                              Icons.volume_down_rounded,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                  activeTrackColor: currentDevice.isLocal
                                      ? const Color(0xFF6366F1)
                                      : const Color(0xFF10B981),
                                  thumbColor: Colors.white,
                                  inactiveTrackColor: Colors.white12,
                                ),
                                child: Slider(
                                  value: currentDevice.isLocal
                                      ? (isAudioHandlerInitialized ? audioHandler.userVolume : 1.0)
                                      : currentDevice.volume,
                                  onChanged: (v) {
                                    DeviceConnectCoordinator.instance.setVolume(v);
                                  },
                                ),
                              ),
                            ),
                            Icon(
                              Icons.volume_up_rounded,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              Text(
                'AVAILABLE DEVICES ON NETWORK',
                style: GoogleFonts.outfit(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),

              // Available Device List
              ValueListenableBuilder<List<ConnectedDevice>>(
                valueListenable: DeviceConnectCoordinator.instance.discoveredDevicesNotifier,
                builder: (context, devices, _) {
                  final activeId = DeviceConnectCoordinator.instance.currentDevice.id;

                  return Column(
                    children: devices.map((dev) {
                      final isSelected = dev.id == activeId;
                      final badgeColor = _badgeColorForProtocol(dev.protocol);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isSelected
                              ? const Color(0xFF1E293B)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: isSelected
                                ? null
                                : () async {
                                    HapticFeedback.mediumImpact();
                                    await DeviceConnectCoordinator.instance.switchToDevice(dev);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Switched playback to ${dev.name}'),
                                          backgroundColor: const Color(0xFF10B981),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    _iconForDevice(dev.type),
                                    color: isSelected ? const Color(0xFF10B981) : Colors.white70,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dev.name,
                                          style: GoogleFonts.outfit(
                                            color: isSelected ? const Color(0xFF10B981) : Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          dev.status,
                                          style: GoogleFonts.outfit(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      _labelForProtocol(dev.protocol),
                                      style: GoogleFonts.outfit(
                                        color: badgeColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Listen Together / Party Mode Action Bar
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  PartyModeSheet.show(context);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6366F1).withValues(alpha: 0.2),
                        const Color(0xFF131B2E),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF6366F1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.group_rounded, color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Party Mode (Sync Multiple Phones)',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Listen in real-time with friends anywhere',
                              style: GoogleFonts.outfit(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
