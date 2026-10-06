import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../services/equalizer_service.dart';
import '../../../services/settings_manager.dart';

class PlayerEqualizerSheet {
  static void show(BuildContext context) {
    final bandLabels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.tune_rounded, color: Color(0xFF9333EA), size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Equalizer & Sound FX',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF06B6D4)),
                          label: const Text('System EQ', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            EqualizerService.openSystemEqualizer();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: SettingsManager.eqPresetNotifier,
                      builder: (context, currentPreset, _) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildEqChip('Flat', 'flat', currentPreset),
                              _buildEqChip('Bass Boost', 'bass_boost', currentPreset),
                              _buildEqChip('Vocal', 'vocal', currentPreset),
                              _buildEqChip('Rock', 'rock', currentPreset),
                              _buildEqChip('Pop', 'pop', currentPreset),
                              _buildEqChip('Classical', 'classical', currentPreset),
                              _buildEqChip('Electronic', 'electronic', currentPreset),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<List<double>>(
                      valueListenable: SettingsManager.eqBandsNotifier,
                      builder: (context, bands, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(bandLabels.length, (index) {
                              final gain = (index < bands.length) ? bands[index] : 0.0;
                              return Column(
                                children: [
                                  Text(
                                    '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)} dB',
                                    style: TextStyle(
                                      color: gain.abs() > 0.1 ? const Color(0xFF06B6D4) : const Color(0xFF64748B),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 120,
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 3,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                          activeTrackColor: const Color(0xFF9333EA),
                                          inactiveTrackColor: Colors.white12,
                                          thumbColor: const Color(0xFF06B6D4),
                                          overlayColor: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                                        ),
                                        child: Slider(
                                          value: gain,
                                          min: -10.0,
                                          max: 10.0,
                                          onChanged: (val) {
                                            SettingsManager.setEqBand(index, val);
                                            EqualizerService.setBandLevel(index, val);
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    bandLabels[index],
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                  ),
                                ],
                              );
                            }),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildEqChip(String label, String presetKey, String currentPreset) {
    final isSelected = currentPreset == presetKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        selectedColor: const Color(0xFF9333EA),
        backgroundColor: const Color(0xFF131B2E),
        side: BorderSide(
          color: isSelected ? const Color(0xFF9333EA) : Colors.white.withValues(alpha: 0.08),
        ),
        onSelected: (selected) {
          if (selected) {
            SettingsManager.setEqPreset(presetKey);
            EqualizerService.setPreset(presetKey);
          }
        },
      ),
    );
  }
}
