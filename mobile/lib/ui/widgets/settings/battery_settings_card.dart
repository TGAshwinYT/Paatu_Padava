import 'package:flutter/material.dart';
import '../../../services/battery_optimization_service.dart';

class BatterySettingsCard extends StatefulWidget {
  const BatterySettingsCard({super.key});

  @override
  State<BatterySettingsCard> createState() => _BatterySettingsCardState();
}

class _BatterySettingsCardState extends State<BatterySettingsCard> {
  String _deviceManufacturer = '';
  bool _isIgnoringBattery = true;
  bool _isAggressiveOEM = false;

  @override
  void initState() {
    super.initState();
    _checkBatteryOptimization();
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      final mfg = await BatteryOptimizationService.getDeviceManufacturer();
      final isIgnoring = await BatteryOptimizationService.isIgnoringBatteryOptimizations();
      final isAggressive = await BatteryOptimizationService.isAggressiveBatteryOEM();
      if (mounted) {
        setState(() {
          _deviceManufacturer = mfg;
          _isIgnoringBattery = isIgnoring;
          _isAggressiveOEM = isAggressive;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isRestricted = !_isIgnoringBattery;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (_isAggressiveOEM && isRestricted)
              ? Colors.amberAccent.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isRestricted ? Colors.amberAccent.withValues(alpha: 0.12) : const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isRestricted ? Icons.battery_alert_rounded : Icons.battery_charging_full_rounded,
                  color: isRestricted ? Colors.amberAccent : const Color(0xFF10B981),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _deviceManufacturer.isNotEmpty
                          ? '$_deviceManufacturer Battery Status'
                          : 'Battery Optimization',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isRestricted ? 'Optimized (Background playback may be stopped)' : 'Unrestricted (Continuous playback active)',
                      style: TextStyle(
                        color: isRestricted ? Colors.amberAccent : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: isRestricted ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isAggressiveOEM && isRestricted) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.amberAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_deviceManufacturer.isNotEmpty ? _deviceManufacturer : "The device"} restricts background apps by default. Tap below to set Battery to "Unrestricted" so music keeps playing when locked.',
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await BatteryOptimizationService.openBatteryOptimizationSettings();
                await Future.delayed(const Duration(seconds: 1));
                await _checkBatteryOptimization();
              },
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Manage Battery Optimization'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF818CF8),
                side: const BorderSide(color: Color(0xFF6366F1), width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
