import 'package:flutter/material.dart';
import '../../services/settings_manager.dart';
import '../../services/equalizer_service.dart';
import '../widgets/mini_player.dart';

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
          '5-Band Hardware Equalizer',
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
              _buildSectionHeader('5-BAND HARDWARE EQUALIZER', Icons.tune_rounded),
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
          // Presets chips
          ValueListenableBuilder<String>(
            valueListenable: SettingsManager.eqPresetNotifier,
            builder: (context, currentPreset, _) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPresetChip('Flat', 'flat', currentPreset),
                    _buildPresetChip('Bass Boost', 'bass_boost', currentPreset),
                    _buildPresetChip('Vocal', 'vocal', currentPreset),
                    _buildPresetChip('Rock', 'rock', currentPreset),
                    _buildPresetChip('Pop', 'pop', currentPreset),
                    _buildPresetChip('Classical', 'classical', currentPreset),
                    _buildPresetChip('Electronic', 'electronic', currentPreset),
                  ],
                ),
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
                        height: 140,
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
