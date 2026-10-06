import 'package:flutter/material.dart';
import '../../../services/settings_manager.dart';

class AudioQualitySettingsCard extends StatelessWidget {
  const AudioQualitySettingsCard({super.key});

  Widget _buildQualityRadioTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      activeColor: const Color(0xFF6366F1),
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.volumeNormalizationNotifier,
            builder: (context, isEnabled, _) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                activeColor: const Color(0xFF6366F1),
                title: const Text(
                  'Loudness Normalization (ReplayGain)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Standardizes loudness (-14 LUFS) between YouTube & 320k master streams to prevent volume jumps',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                value: isEnabled,
                onChanged: (val) => SettingsManager.setVolumeNormalization(val),
              );
            },
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.autoplayNotifier,
            builder: (context, isAutoplay, _) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                activeColor: const Color(0xFF6366F1),
                title: const Text(
                  'Autoplay Similar Songs',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Keep on listening to similar songs endlessly when your queue or album ends (Spotify & YouTube Music style)',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                value: isAutoplay,
                onChanged: (val) => SettingsManager.setAutoplay(val),
              );
            },
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          ValueListenableBuilder<int>(
            valueListenable: SettingsManager.crossfadeDurationNotifier,
            builder: (context, crossfadeSec, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Crossfade Transitions',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        Text(
                          crossfadeSec == 0 ? 'Off (Gapless)' : '${crossfadeSec}s',
                          style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Smoothly blends and fades volume between consecutive songs',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF6366F1),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: crossfadeSec.toDouble(),
                        min: 0.0,
                        max: 12.0,
                        divisions: 12,
                        onChanged: (val) => SettingsManager.setCrossfadeSeconds(val.round()),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          ValueListenableBuilder<NextTrackStrategyMode>(
            valueListenable: SettingsManager.nextTrackStrategyNotifier,
            builder: (context, strategyMode, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'Next-Song Recommendation Algorithm',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  _buildQualityRadioTile(
                    title: 'Spotify Style (Cohesive Clusters)',
                    subtitle: 'Curates closely related acoustic clusters, similar tempo, and collaborative seeds',
                    value: NextTrackStrategyMode.spotifyStyle.name,
                    groupValue: strategyMode.name,
                    onChanged: (val) {
                      if (val != null) {
                        SettingsManager.setNextTrackStrategy(NextTrackStrategyMode.spotifyStyle);
                      }
                    },
                  ),
                  _buildQualityRadioTile(
                    title: 'YouTube Music Style (Eclectic Radio)',
                    subtitle: 'Deeper discovery, algorithmic radio seeds, and genre-adjacent track exploration',
                    value: NextTrackStrategyMode.ytMusicStyle.name,
                    groupValue: strategyMode.name,
                    onChanged: (val) {
                      if (val != null) {
                        SettingsManager.setNextTrackStrategy(NextTrackStrategyMode.ytMusicStyle);
                      }
                    },
                  ),
                ],
              );
            },
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          ValueListenableBuilder<String>(
            valueListenable: SettingsManager.streamingQualityNotifier,
            builder: (context, streamingQuality, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'Streaming Bitrate Quality',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  _buildQualityRadioTile(
                    title: 'Lossless 320 kbps',
                    subtitle: 'Studio fidelity audio streaming (Recommended)',
                    value: '320kbps',
                    groupValue: streamingQuality,
                    onChanged: (val) => SettingsManager.setStreamingQuality(val!),
                  ),
                  _buildQualityRadioTile(
                    title: 'High 160 kbps',
                    subtitle: 'Balanced clarity and moderate data consumption',
                    value: '160kbps',
                    groupValue: streamingQuality,
                    onChanged: (val) => SettingsManager.setStreamingQuality(val!),
                  ),
                  _buildQualityRadioTile(
                    title: 'Normal 96 kbps',
                    subtitle: 'Data saving mode for weak mobile networks',
                    value: '96kbps',
                    groupValue: streamingQuality,
                    onChanged: (val) => SettingsManager.setStreamingQuality(val!),
                  ),
                ],
              );
            },
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          ValueListenableBuilder<String>(
            valueListenable: SettingsManager.downloadQualityNotifier,
            builder: (context, downloadQuality, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Download Quality', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        SizedBox(height: 2),
                        Text('Target bitrate for offline downloads', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      ],
                    ),
                    DropdownButton<String>(
                      value: downloadQuality,
                      dropdownColor: const Color(0xFF1E293B),
                      underline: const SizedBox(),
                      style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: '320kbps', child: Text('320 kbps')),
                        DropdownMenuItem(value: '160kbps', child: Text('160 kbps')),
                        DropdownMenuItem(value: '96kbps', child: Text('96 kbps')),
                      ],
                      onChanged: (val) {
                        if (val != null) SettingsManager.setDownloadQuality(val);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
