import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/party_sync_coordinator.dart';
import '../../services/settings_manager.dart';

class PartyModeSheet extends StatefulWidget {
  const PartyModeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const PartyModeSheet(),
    );
  }

  @override
  State<PartyModeSheet> createState() => _PartyModeSheetState();
}

class _PartyModeSheetState extends State<PartyModeSheet> {
  final TextEditingController _codeController = TextEditingController();
  bool _isJoining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleStartParty() async {
    final code = await PartySyncCoordinator.startParty();
    if (code == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start party session. Check internet connection.')),
      );
    }
  }

  Future<void> _handleJoinParty() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isJoining = true);
    final success = await PartySyncCoordinator.joinParty(code);
    setState(() => _isJoining = false);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to join party. Check the code and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF131B2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
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
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.speaker_group_rounded, color: Color(0xFF818CF8), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Listen Together (Party Mode)',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Sub-millisecond lockstep audio sync across phones',
                      style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Active Party Status or Action Cards
          ValueListenableBuilder<PartyRole>(
            valueListenable: PartySyncCoordinator.roleNotifier,
            builder: (context, role, _) {
              if (role == PartyRole.none) {
                return _buildInactiveView();
              } else {
                return _buildActiveSessionView(role);
              }
            },
          ),

          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 14),

          // Bluetooth Hardware Latency Slider
          _buildBluetoothOffsetSection(),
        ],
      ),
    );
  }

  Widget _buildInactiveView() {
    return Column(
      children: [
        // Host card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.wifi_tethering_rounded, color: Color(0xFF818CF8), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Host a Party',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'You control playback, queue, and seeking. Friends listen in lockstep.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Start Party as Host', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _handleStartParty,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Join card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.login_rounded, color: Color(0xFF34D399), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Join a Friend\'s Party',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white, letterSpacing: 2.0, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'e.g. SYNC-9K2M',
                        hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 1.0),
                        filled: true,
                        fillColor: const Color(0xFF131B2E),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onPressed: _isJoining ? null : _handleJoinParty,
                    child: _isJoining
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Join', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveSessionView(PartyRole role) {
    final code = PartySyncCoordinator.partyCode ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sensors_rounded, color: Color(0xFF34D399), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      role == PartyRole.host ? 'HOSTING SESSION' : 'CONNECTED JOINER',
                      style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.exit_to_app_rounded, size: 14),
                label: const Text('Leave', style: TextStyle(fontSize: 12)),
                onPressed: () async {
                  await PartySyncCoordinator.leaveParty();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Code display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                code,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3.0,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Party code copied to clipboard!')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Real-time telemetry: RTT, clock offset, drift
          ValueListenableBuilder<String>(
            valueListenable: PartySyncCoordinator.syncStatusDescription,
            builder: (context, statusDesc, _) {
              return ValueListenableBuilder<int>(
                valueListenable: PartySyncCoordinator.currentDriftMsNotifier,
                builder: (context, driftMs, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          statusDesc,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                        if (role == PartyRole.joiner)
                          Text(
                            'Drift: ${driftMs.abs()}ms',
                            style: TextStyle(
                              color: driftMs.abs() < 50 ? const Color(0xFF10B981) : Colors.amberAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothOffsetSection() {
    return ValueListenableBuilder<int>(
      valueListenable: SettingsManager.bluetoothDelayMsNotifier,
      builder: (context, delayMs, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.bluetooth_audio_rounded, color: Color(0xFF818CF8), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Bluetooth Output Delay',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  '${delayMs > 0 ? "+" : ""}${delayMs}ms',
                  style: TextStyle(
                    color: delayMs == 0 ? Colors.white70 : const Color(0xFF818CF8),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Compensates for wireless earphone hardware latency so your audio stays locked with speakers.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF6366F1),
                inactiveTrackColor: Colors.white12,
                thumbColor: const Color(0xFF818CF8),
                overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
              ),
              child: Slider(
                value: delayMs.toDouble(),
                min: -500,
                max: 500,
                divisions: 100,
                onChanged: (val) {
                  SettingsManager.setBluetoothDelayMs(val.round());
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPresetChip('0ms (Speaker)', 0, delayMs),
                _buildPresetChip('+120ms (SBC)', 120, delayMs),
                _buildPresetChip('+200ms (AAC/TWS)', 200, delayMs),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPresetChip(String label, int value, int current) {
    final isSelected = current == value;
    return InkWell(
      onTap: () => SettingsManager.setBluetoothDelayMs(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF818CF8) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
