import 'package:flutter/material.dart';
import '../../services/settings_manager.dart';
import '../widgets/mini_player.dart';

class AudioQualitySettingsScreen extends StatelessWidget {
  const AudioQualitySettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Audio Quality & Streaming',
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
              _buildStreamingQualitySection(),
              const SizedBox(height: 20),
              _buildVolumeNormalizationSection(),
              const SizedBox(height: 20),
              _buildAutoplaySection(),
              const SizedBox(height: 20),
              _buildCrossfadeSection(),
              const SizedBox(height: 20),
              _buildPersistentBackgroundPlaybackSection(),
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
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF818CF8),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStreamingQualitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('STREAMING QUALITY', Icons.graphic_eq_rounded),
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
              const Text(
                'Wi-Fi & Cellular Audio Bitrate',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Higher bitrates provide lossless dynamics and pristine high frequencies at the cost of higher data usage.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: SettingsManager.streamingQualityNotifier,
                builder: (context, currentQuality, _) {
                  return Column(
                    children: [
                      _buildQualityOption(
                        title: 'Auto (Adaptive)',
                        subtitle: 'Dynamically adapts bitrate to network speed to eliminate buffering (Recommended).',
                        badge: 'AUTO',
                        isSelected: currentQuality == 'auto',
                        onTap: () => SettingsManager.setStreamingQuality('auto'),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildQualityOption(
                        title: 'Data Saver (96 kbps)',
                        subtitle: 'Uses ~40 MB per hour. Best for slow or limited cellular networks.',
                        badge: '96k',
                        isSelected: currentQuality == '96kbps',
                        onTap: () => SettingsManager.setStreamingQuality('96kbps'),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildQualityOption(
                        title: 'Standard Quality (160 kbps)',
                        subtitle: 'Uses ~70 MB per hour. Balanced streaming performance.',
                        badge: '160k',
                        isSelected: currentQuality == '160kbps',
                        onTap: () => SettingsManager.setStreamingQuality('160kbps'),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildQualityOption(
                        title: 'High Fidelity (320 kbps)',
                        subtitle: 'Uses ~140 MB per hour. Pure studio acoustic clarity.',
                        badge: '320k',
                        isSelected: currentQuality == '320kbps',
                        onTap: () => SettingsManager.setStreamingQuality('320kbps'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQualityOption({
    required String title,
    required String subtitle,
    required String badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1), size: 20)
            else
              const Icon(Icons.radio_button_unchecked_rounded, color: Color(0xFF475569), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeNormalizationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('VOLUME NORMALIZATION', Icons.volume_up_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.volumeNormalizationNotifier,
            builder: (context, isEnabled, _) {
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.equalizer_rounded, color: Color(0xFF818CF8), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ReplayGain Loudness Match',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Normalizes audio output to standard -14 LUFS to eliminate jarring volume spikes between different tracks.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isEnabled,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (val) => SettingsManager.setVolumeNormalization(val),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAutoplaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('AUTOPLAY & CONTINUOUS RADIO', Icons.autorenew_rounded),
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
              ValueListenableBuilder<bool>(
                valueListenable: SettingsManager.autoplayNotifier,
                builder: (context, isAutoplay, _) {
                  return Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.playlist_play_rounded, color: Color(0xFF34D399), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Autoplay Similar Tracks',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Seamlessly queue recommended music when the active playlist completes.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isAutoplay,
                        activeColor: const Color(0xFF10B981),
                        onChanged: (val) => SettingsManager.setAutoplay(val),
                      ),
                    ],
                  );
                },
              ),
              const Divider(color: Colors.white10, height: 24),
              const Text(
                'Next Song Algorithmic Engine',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose how songs are automatically selected for infinite radio mode.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<NextTrackStrategyMode>(
                valueListenable: SettingsManager.nextTrackStrategyNotifier,
                builder: (context, strategy, _) {
                  return Column(
                    children: [
                      _buildStrategyCard(
                        title: 'Spotify Context',
                        subtitle: 'Adaptive anchor blend with short-term artist cooldown & candidate scoring',
                        icon: Icons.graphic_eq_rounded,
                        isSelected: strategy == NextTrackStrategyMode.spotifyStyle,
                        onTap: () => SettingsManager.setNextTrackStrategy(NextTrackStrategyMode.spotifyStyle),
                      ),
                      const SizedBox(height: 8),
                      _buildStrategyCard(
                        title: 'YouTube Auto-Mix',
                        subtitle: 'Graph traversal with official master tracks & rolling skip fatigue',
                        icon: Icons.radio_rounded,
                        isSelected: strategy == NextTrackStrategyMode.ytMusicStyle,
                        onTap: () => SettingsManager.setNextTrackStrategy(NextTrackStrategyMode.ytMusicStyle),
                      ),
                      const SizedBox(height: 8),
                      _buildStrategyCard(
                        title: 'Markov-Cosine AI',
                        subtitle: 'Multi-dimensional vector similarity with transition learning',
                        icon: Icons.auto_awesome_rounded,
                        isSelected: strategy == NextTrackStrategyMode.markovCosineRadio,
                        onTap: () => SettingsManager.setNextTrackStrategy(NextTrackStrategyMode.markovCosineRadio),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStrategyCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.15) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.05),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF94A3B8), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrossfadeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('AUDIO CROSSFADE', Icons.linear_scale_rounded),
        const SizedBox(height: 10),
        Container(
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
                  const Divider(color: Colors.white10, height: 24),
                  ValueListenableBuilder<bool>(
                    valueListenable: SettingsManager.beatMatchedTransitionsNotifier,
                    builder: (context, isBeatMatch, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.speed_rounded, color: Color(0xFFA78BFA), size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'DJ Automix (Beat-Matched)',
                                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Harmonically aligns tempo (±3%) and bar phrases for seamless transitions.',
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, height: 1.25),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: isBeatMatch,
                                activeColor: const Color(0xFF8B5CF6),
                                onChanged: (val) => SettingsManager.setBeatMatchedTransitions(val),
                              ),
                            ],
                          ),
                          if (isBeatMatch) ...[
                            const SizedBox(height: 12),
                            ValueListenableBuilder<int>(
                              valueListenable: SettingsManager.transitionPhraseBeatsNotifier,
                              builder: (context, beats, _) {
                                return Row(
                                  children: [4, 8, 16].map((b) {
                                    final isSelected = beats == b;
                                    final label = b == 4 ? '1 Bar (4b)' : (b == 8 ? '2 Bars (8b)' : '4 Bars (16b)');
                                    return Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 3),
                                        child: ChoiceChip(
                                          label: Center(
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          selected: isSelected,
                                          selectedColor: const Color(0xFF6366F1),
                                          backgroundColor: const Color(0xFF1E293B),
                                          showCheckmark: false,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            side: BorderSide(
                                              color: isSelected ? const Color(0xFF6366F1) : Colors.white10,
                                            ),
                                          ),
                                          onSelected: (_) => SettingsManager.setTransitionPhraseBeats(b),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPersistentBackgroundPlaybackSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('BACKGROUND RESILIENCE & APP CLOSURE', Icons.all_inclusive_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.persistentBackgroundPlaybackNotifier,
            builder: (context, isPersistent, _) {
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.phonelink_ring_rounded, color: Color(0xFF818CF8), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Keep Playing When App Is Closed',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Keep playing and advancing to next songs even when Paatu Padava is closed or cleared from Recent Apps (RAM). Tapping Pause will close the player completely.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isPersistent,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (val) => SettingsManager.setPersistentBackgroundPlayback(val),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
