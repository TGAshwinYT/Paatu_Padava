import 'package:flutter/material.dart';
import '../../services/settings_manager.dart';
import '../../services/party_sync_coordinator.dart';
import '../widgets/mini_player.dart';
import '../widgets/party_mode_sheet.dart';

class PartySyncSettingsScreen extends StatelessWidget {
  const PartySyncSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Party Sync & Latency',
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
              _buildPartySessionCard(context),
              const SizedBox(height: 20),
              _buildHardwareLatencySection(context),
              const SizedBox(height: 20),
              _buildBluetoothDelaySection(context),
              const SizedBox(height: 20),
              _buildNtpDiagnosticsSection(),
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

  Widget _buildPartySessionCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.25),
            const Color(0xFF131B2E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.speaker_group_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Multi-Device Synchronized Audio',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    ValueListenableBuilder<PartyRole>(
                      valueListenable: PartySyncCoordinator.roleNotifier,
                      builder: (context, role, _) {
                        final text = role == PartyRole.none
                            ? 'Not in a session'
                            : (role == PartyRole.host
                                ? 'Active Session (Host: ${PartySyncCoordinator.partyCode})'
                                : 'Connected as Guest (${PartySyncCoordinator.partyCode})');
                        return Text(
                          text,
                          style: TextStyle(
                            color: role == PartyRole.none ? const Color(0xFF94A3B8) : const Color(0xFF34D399),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: () => PartyModeSheet.show(context),
                child: const Text('Open Session', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Play music together across multiple phones in the same room. Sub-millisecond NTP synchronization eliminates echo and delay.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareLatencySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('HARDWARE AUDIO LATENCY (-150ms to +150ms)', Icons.av_timer_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: SettingsManager.hardwareAudioLatencyMsNotifier,
            builder: (context, latencyMs, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Hardware Output Offset',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          latencyMs == 0 ? '0 ms (Standard)' : '${latencyMs > 0 ? "+$latencyMs" : latencyMs} ms',
                          style: const TextStyle(
                            color: Color(0xFF818CF8),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Compensates for hardware DAC and OS audio driver latency so all speakers sync in lockstep.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF6366F1),
                      inactiveTrackColor: const Color(0xFF1E293B),
                      thumbColor: Colors.white,
                      overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: latencyMs.toDouble(),
                      min: -150,
                      max: 150,
                      divisions: 60,
                      onChanged: (val) => SettingsManager.setHardwareAudioLatencyMs(val.toInt()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStepButton('-10ms', () => SettingsManager.setHardwareAudioLatencyMs(latencyMs - 10)),
                      const SizedBox(width: 8),
                      _buildStepButton('-2ms', () => SettingsManager.setHardwareAudioLatencyMs(latencyMs - 2)),
                      const SizedBox(width: 8),
                      _buildStepButton('Reset (0ms)', () => SettingsManager.setHardwareAudioLatencyMs(0)),
                      const SizedBox(width: 8),
                      _buildStepButton('+2ms', () => SettingsManager.setHardwareAudioLatencyMs(latencyMs + 2)),
                      const SizedBox(width: 8),
                      _buildStepButton('+10ms', () => SettingsManager.setHardwareAudioLatencyMs(latencyMs + 10)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothDelaySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('BLUETOOTH AUDIO BUFFER OFFSET', Icons.bluetooth_audio_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: SettingsManager.bluetoothDelayMsNotifier,
            builder: (context, delayMs, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Bluetooth Buffer Compensation',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          delayMs == 0 ? '0 ms' : '${delayMs > 0 ? "+$delayMs" : delayMs} ms',
                          style: const TextStyle(
                            color: Color(0xFF06B6D4),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Adjust for heavy Bluetooth SBC/AAC buffer delays (-500ms to +500ms).',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF06B6D4),
                      inactiveTrackColor: const Color(0xFF1E293B),
                      thumbColor: Colors.white,
                      overlayColor: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: delayMs.toDouble(),
                      min: -500,
                      max: 500,
                      divisions: 100,
                      onChanged: (val) => SettingsManager.setBluetoothDelayMs(val.toInt()),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStepButton(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildNtpDiagnosticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('LIVE NTP CLOCK DRIFT DIAGNOSTICS', Icons.radar_rounded),
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
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'High-Precision 4-Timestamp Handshake',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: PartySyncCoordinator.currentDriftMsNotifier,
                      builder: (context, drift, _) {
                        final Color color = drift.abs() < 15
                            ? const Color(0xFF10B981)
                            : (drift.abs() < 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
                        return _buildMetricBox(
                          title: 'Live Clock Drift',
                          value: '${drift > 0 ? "+$drift" : drift} ms',
                          status: drift.abs() < 15 ? 'Synchronized' : 'Compensating',
                          color: color,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: PartySyncCoordinator.measuredRttMsNotifier,
                      builder: (context, rtt, _) {
                        return _buildMetricBox(
                          title: 'Network RTT',
                          value: '$rtt ms',
                          status: rtt < 100 ? 'Low Ping' : 'High Ping',
                          color: const Color(0xFF06B6D4),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: PartySyncCoordinator.clockOffsetMsNotifier,
                      builder: (context, offset, _) {
                        return _buildMetricBox(
                          title: 'NTP Offset (Theta)',
                          value: '${offset > 0 ? "+$offset" : offset} ms',
                          status: 'Offset to Cloud Master',
                          color: const Color(0xFF818CF8),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: PartySyncCoordinator.peerCountNotifier,
                      builder: (context, peers, _) {
                        return _buildMetricBox(
                          title: 'Connected Peers',
                          value: '$peers',
                          status: peers > 1 ? 'Multi-Speaker' : 'Single Device',
                          color: const Color(0xFFA855F7),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: PartySyncCoordinator.syncStatusDescription,
                builder: (context, desc, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Status: $desc',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricBox({
    required String title,
    required String value,
    required String status,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(status, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 10)),
        ],
      ),
    );
  }
}
