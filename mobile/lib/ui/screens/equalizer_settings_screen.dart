import 'package:flutter/material.dart';
import '../../services/settings_manager.dart';
import '../../services/equalizer_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/player/equalizer_curve_canvas.dart';

class EqualizerSettingsScreen extends StatelessWidget {
  const EqualizerSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          '5-Band Hardware Equalizer & FX',
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
              _buildSectionHeader('AUDIO CROSSFADE', Icons.linear_scale_rounded),
              const SizedBox(height: 10),
              _buildCrossfadeCard(context),
              const SizedBox(height: 20),
              _buildSectionHeader('5-BAND HARDWARE EQUALIZER & DSP', Icons.tune_rounded),
              const SizedBox(height: 10),
              const EqualizerSettingsCard(),
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

  Widget _buildCrossfadeCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: SettingsManager.crossfadeDurationNotifier,
        builder: (context, seconds, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Track Transition Time',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      seconds == 0 ? 'Gapless (Off)' : '${seconds}s Crossfade',
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
                'Smoothly overlaps the trailing audio of the ending track with the next song.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF6366F1),
                  inactiveTrackColor: const Color(0xFF1E293B),
                  thumbColor: Colors.white,
                  overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: seconds.toDouble(),
                  min: 0,
                  max: 12,
                  divisions: 12,
                  onChanged: (val) => SettingsManager.setCrossfadeSeconds(val.toInt()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class EqualizerSettingsCard extends StatelessWidget {
  const EqualizerSettingsCard({super.key});

  Widget _buildPresetChip(String label, String presetKey, String currentPreset) {
    final isSelected = currentPreset == presetKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF6366F1),
        backgroundColor: const Color(0xFF1E293B),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (_) {
          SettingsManager.setEqPreset(presetKey);
          EqualizerService.applyCurrentBands();
        },
      ),
    );
  }

  Widget _buildCustomChip(BuildContext context, String name, String presetKey, String currentPreset) {
    final isSelected = currentPreset == presetKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        label: Text(name),
        selected: isSelected,
        selectedColor: const Color(0xFF06B6D4),
        backgroundColor: const Color(0xFF1E293B),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (_) {
          SettingsManager.applyCustomEqPreset(name);
          EqualizerService.applyCurrentBands();
        },
        onDeleted: () {
          SettingsManager.deleteCustomEqPreset(name);
        },
        deleteIconColor: Colors.white54,
      ),
    );
  }

  void _promptSavePreset(BuildContext context) {
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
            hintText: 'e.g. Warm Acoustic',
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
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bandLabels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dynamic Visual Frequency Response Curve Canvas
          ValueListenableBuilder<List<double>>(
            valueListenable: SettingsManager.eqBandsNotifier,
            builder: (context, bands, _) {
              return EqualizerCurveCanvas(
                bands: bands,
                height: 90,
              );
            },
          ),
          const SizedBox(height: 14),

          // Presets chips with custom preset support
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
                        _buildPresetChip('Flat', 'flat', currentPreset),
                        _buildPresetChip('Bass Boost', 'bass_boost', currentPreset),
                        _buildPresetChip('Bass & Treble', 'bass_treble', currentPreset),
                        _buildPresetChip('Vocal Booster', 'vocal_booster', currentPreset),
                        _buildPresetChip('Acoustic', 'acoustic', currentPreset),
                        _buildPresetChip('Electronic', 'electronic', currentPreset),
                        _buildPresetChip('Rock', 'rock', currentPreset),
                        _buildPresetChip('Pop', 'pop', currentPreset),
                        _buildPresetChip('Classical', 'classical', currentPreset),
                        _buildPresetChip('Hip Hop', 'hip_hop', currentPreset),
                        _buildPresetChip('Deep', 'deep', currentPreset),
                        ...customPresets.keys.map((name) {
                          return _buildCustomChip(context, name, 'custom_$name', currentPreset);
                        }),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF06B6D4)),
                            label: const Text('Save Preset'),
                            labelStyle: const TextStyle(color: Color(0xFF06B6D4), fontSize: 12),
                            backgroundColor: const Color(0xFF1E293B),
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
          const SizedBox(height: 16),

          // 5 Band Sliders
          ValueListenableBuilder<List<double>>(
            valueListenable: SettingsManager.eqBandsNotifier,
            builder: (context, bands, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(5, (index) {
                  final gain = (index < bands.length) ? bands[index] : 0.0;
                  return Column(
                    children: [
                      Text(
                        '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}dB',
                        style: const TextStyle(color: Color(0xFF818CF8), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(
                        height: 130,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF6366F1),
                              inactiveTrackColor: Colors.white12,
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              trackHeight: 3,
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
                      const SizedBox(height: 4),
                      Text(
                        bandLabels[index],
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      ),
                    ],
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 16),

          // Hardware DSP sliders: Bass Boost & 3D Spatial Virtualizer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: Column(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: SettingsManager.bassBoostNotifier,
                  builder: (context, bass, _) {
                    return Row(
                      children: [
                        const Icon(Icons.speaker_rounded, color: Color(0xFFF43F5E), size: 16),
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 76,
                          child: Text('Bass Boost', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
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
                const Divider(color: Colors.white10, height: 10),
                ValueListenableBuilder<double>(
                  valueListenable: SettingsManager.virtualizerNotifier,
                  builder: (context, virt, _) {
                    return Row(
                      children: [
                        const Icon(Icons.surround_sound_rounded, color: Color(0xFF8B5CF6), size: 16),
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 76,
                          child: Text('3D Spatial', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
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
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                EqualizerService.isBound
                    ? 'Native DSP: Active (Session #${EqualizerService.activeSessionId})'
                    : 'Native DSP: Connected',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              TextButton.icon(
                icon: const Icon(Icons.settings_voice_rounded, size: 16, color: Color(0xFF6366F1)),
                label: const Text('System Equalizer', style: TextStyle(color: Color(0xFF6366F1), fontSize: 12)),
                onPressed: () => EqualizerService.openSystemEqualizer(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
