import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../services/settings_manager.dart';

/// Left/Right Stereo Earbud Balance control card.
/// Attenuates the louder channel (0 dB down to -30 dB) so users with uneven
/// earbuds can raise master volume without ear fatigue or digital clipping.
class StereoBalanceCard extends StatelessWidget {
  const StereoBalanceCard({super.key});

  static String formatBalanceLabel(double balance) {
    if (balance.abs() < 0.02) return 'Balanced (Center)';
    final db = (balance.abs() * 30.0).toStringAsFixed(1);
    return balance < 0
        ? 'Left favored • Right -$db dB'
        : 'Right favored • Left -$db dB';
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: SettingsManager.stereoBalanceNotifier,
        builder: (context, balance, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Earbud L / R Balance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (balance.abs() >= 0.02)
                    TextButton(
                      onPressed: () => SettingsManager.setStereoBalance(0.0),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          color: Color(0xFF818CF8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isAndroid
                    ? formatBalanceLabel(balance)
                    : 'Hardware L/R balance is available on Android 9+ devices.',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'L',
                    style: TextStyle(
                      color: Color(0xFF06B6D4),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF6366F1),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: const Color(0xFF06B6D4),
                        overlayColor: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: balance.clamp(-1.0, 1.0),
                        min: -1.0,
                        max: 1.0,
                        divisions: 40,
                        onChanged: isAndroid
                            ? (val) {
                                final snapped = val.abs() < 0.04 ? 0.0 : val;
                                SettingsManager.setStereoBalance(snapped);
                              }
                            : null,
                      ),
                    ),
                  ),
                  const Text(
                    'R',
                    style: TextStyle(
                      color: Color(0xFF06B6D4),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const Text(
                'Lowers the louder earbud so you can turn up volume comfortably.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          );
        },
      ),
    );
  }
}
