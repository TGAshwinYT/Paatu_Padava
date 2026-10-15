import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/equalizer_service.dart';
import '../../../services/settings_manager.dart';
import 'equalizer_curve_canvas.dart';

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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.96),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.tune_rounded, color: Color(0xFF06B6D4), size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Hardware Equalizer & DSP FX',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF818CF8)),
                            label: const Text('System EQ', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              EqualizerService.openSystemEqualizer();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Real-time Visual Frequency Response Curve Canvas
                      ValueListenableBuilder<List<double>>(
                        valueListenable: SettingsManager.eqBandsNotifier,
                        builder: (context, bands, _) {
                          return EqualizerCurveCanvas(
                            bands: bands,
                            height: 84,
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // Preset selector row with custom preset chip & save button
                      ValueListenableBuilder<String>(
                        valueListenable: SettingsManager.eqPresetNotifier,
                        builder: (context, currentPreset, _) {
                          return ValueListenableBuilder<Map<String, List<double>>>(
                            valueListenable: SettingsManager.customEqPresetsNotifier,
                            builder: (context, customPresets, _) {
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildEqChip('Flat', 'flat', currentPreset),
                                    _buildEqChip('Bass Boost', 'bass_boost', currentPreset),
                                    _buildEqChip('Bass & Treble', 'bass_treble', currentPreset),
                                    _buildEqChip('Vocal Booster', 'vocal_booster', currentPreset),
                                    _buildEqChip('Acoustic', 'acoustic', currentPreset),
                                    _buildEqChip('Electronic', 'electronic', currentPreset),
                                    _buildEqChip('Rock', 'rock', currentPreset),
                                    _buildEqChip('Pop', 'pop', currentPreset),
                                    _buildEqChip('Classical', 'classical', currentPreset),
                                    _buildEqChip('Hip Hop', 'hip_hop', currentPreset),
                                    _buildEqChip('Deep', 'deep', currentPreset),
                                    ...customPresets.keys.map((name) {
                                      final key = 'custom_$name';
                                      return _buildCustomChip(context, name, key, currentPreset);
                                    }),
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ActionChip(
                                        avatar: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF06B6D4)),
                                        label: const Text('Save Preset'),
                                        labelStyle: const TextStyle(color: Color(0xFF06B6D4), fontSize: 12),
                                        backgroundColor: const Color(0xFF131B2E),
                                        side: BorderSide(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
                                        onPressed: () => _promptSavePreset(context),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // 5 Frequency Slider Sliders
                      ValueListenableBuilder<List<double>>(
                        valueListenable: SettingsManager.eqBandsNotifier,
                        builder: (context, bands, _) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
                                      height: 110,
                                      child: RotatedBox(
                                        quarterTurns: 3,
                                        child: SliderTheme(
                                          data: SliderThemeData(
                                            trackHeight: 3,
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                            activeTrackColor: const Color(0xFF06B6D4),
                                            inactiveTrackColor: Colors.white12,
                                            thumbColor: Colors.white,
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
                      const SizedBox(height: 14),

                      // Hardware DSP Effects: Bass Boost & Spatial Virtualizer Sliders
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131B2E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Column(
                          children: [
                            // Bass Boost
                            ValueListenableBuilder<double>(
                              valueListenable: SettingsManager.bassBoostNotifier,
                              builder: (context, bass, _) {
                                return Row(
                                  children: [
                                    const Icon(Icons.speaker_rounded, color: Color(0xFFF43F5E), size: 18),
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      width: 80,
                                      child: Text(
                                        'Bass Boost',
                                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 3,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                          activeTrackColor: const Color(0xFFF43F5E),
                                          inactiveTrackColor: Colors.white12,
                                          thumbColor: Colors.white,
                                        ),
                                        child: Slider(
                                          value: bass,
                                          min: 0.0,
                                          max: 1.0,
                                          onChanged: (v) => EqualizerService.setBassBoost(v),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 36,
                                      child: Text(
                                        '${(bass * 100).round()}%',
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const Divider(color: Colors.white10, height: 12),
                            // 3D Spatial Virtualizer / Surround simulation
                            ValueListenableBuilder<double>(
                              valueListenable: SettingsManager.virtualizerNotifier,
                              builder: (context, virt, _) {
                                return Row(
                                  children: [
                                    const Icon(Icons.surround_sound_rounded, color: Color(0xFF8B5CF6), size: 18),
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      width: 80,
                                      child: Text(
                                        '3D Spatial',
                                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 3,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                          activeTrackColor: const Color(0xFF8B5CF6),
                                          inactiveTrackColor: Colors.white12,
                                          thumbColor: Colors.white,
                                        ),
                                        child: Slider(
                                          value: virt,
                                          min: 0.0,
                                          max: 1.0,
                                          onChanged: (v) => EqualizerService.setVirtualizer(v),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 36,
                                      child: Text(
                                        '${(virt * 100).round()}%',
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
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
        selectedColor: const Color(0xFF6366F1),
        backgroundColor: const Color(0xFF131B2E),
        side: BorderSide(
          color: isSelected ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.08),
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

  static Widget _buildCustomChip(BuildContext context, String name, String presetKey, String currentPreset) {
    final isSelected = currentPreset == presetKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        label: Text(name),
        selected: isSelected,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        selectedColor: const Color(0xFF06B6D4),
        backgroundColor: const Color(0xFF131B2E),
        side: BorderSide(
          color: isSelected ? const Color(0xFF06B6D4) : Colors.white.withValues(alpha: 0.08),
        ),
        onSelected: (selected) {
          if (selected) {
            SettingsManager.applyCustomEqPreset(name);
            EqualizerService.applyCurrentBands();
          }
        },
        onDeleted: () {
          SettingsManager.deleteCustomEqPreset(name);
        },
        deleteIconColor: Colors.white54,
      ),
    );
  }

  static void _promptSavePreset(BuildContext context) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Save Custom Preset', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. My Bass Boost',
            hintStyle: TextStyle(color: Colors.white38),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF06B6D4))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF06B6D4)),
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                SettingsManager.saveCustomEqPreset(name, SettingsManager.eqBands);
                HapticFeedback.lightImpact();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
