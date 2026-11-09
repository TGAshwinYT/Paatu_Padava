import 'package:flutter/material.dart';
import '../../../logic/queue/queue_tuner_mode.dart';
import '../../../services/player_handler.dart';
import '../../../services/settings_manager.dart';

/// Horizontal Tuner Chip bar allowing instant mood/vibe filtering on Up Next queue.
/// Inspired by YouTube Music's Up Next mood tuners and Spotify's smart blend.
class QueueTunerBar extends StatelessWidget {
  const QueueTunerBar({Key? key}) : super(key: key);

  void _showEngineBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 16),
                Row(
                  children: const [
                    Icon(Icons.settings_suggest_rounded, color: Color(0xFF6366F1), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Next Song Recommendation Engine',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose the primary algorithmic model that drives candidate songs for Autoplay and Smart Shuffle.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<NextTrackStrategyMode>(
                  valueListenable: SettingsManager.nextTrackStrategyNotifier,
                  builder: (context, activeStrategy, _) {
                    return Column(
                      children: [
                        _buildEngineTile(
                          context,
                          title: 'Spotify Context (Recommended)',
                          subtitle: 'Session anchoring (60/40), era proximity, and anti-repetition cooldown.',
                          icon: Icons.graphic_eq_rounded,
                          accentColor: const Color(0xFF1DB954),
                          isSelected: activeStrategy == NextTrackStrategyMode.spotifyStyle,
                          onTap: () {
                            SettingsManager.setNextTrackStrategy(NextTrackStrategyMode.spotifyStyle);
                            Navigator.pop(ctx);
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildEngineTile(
                          context,
                          title: 'YouTube Auto-Mix',
                          subtitle: 'Dynamic directed graph walking via YouTube Radio and official topic masters.',
                          icon: Icons.radio_rounded,
                          accentColor: const Color(0xFFFF0000),
                          isSelected: activeStrategy == NextTrackStrategyMode.ytMusicStyle,
                          onTap: () {
                            SettingsManager.setNextTrackStrategy(NextTrackStrategyMode.ytMusicStyle);
                            Navigator.pop(ctx);
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildEngineTile(
                          context,
                          title: 'Markov-Cosine AI (100% On-Device)',
                          subtitle: 'Laplace-smoothed transition learning + 5D audio feature vector cosine space.',
                          icon: Icons.auto_awesome_rounded,
                          accentColor: const Color(0xFFA855F7),
                          isSelected: activeStrategy == NextTrackStrategyMode.markovCosineRadio,
                          onTap: () {
                            SettingsManager.setNextTrackStrategy(NextTrackStrategyMode.markovCosineRadio);
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildEngineTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.12) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : Colors.white10,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? accentColor : const Color(0xFF94A3B8), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.transparent,
      child: Row(
        children: [
          // Scrollable Tuner Chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ValueListenableBuilder<QueueTunerMode>(
                valueListenable: audioHandler.queueTunerModeNotifier,
                builder: (context, activeMode, _) {
                  return Row(
                    children: QueueTunerMode.values.map((mode) {
                      final isSelected = activeMode == mode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () {
                            audioHandler.queueTunerController.setTunerMode(mode);
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF818CF8) : Colors.white10,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  mode.icon,
                                  size: 14,
                                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  mode.label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Option C Shortcut: Engine Customization Button
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF94A3B8), size: 19),
            tooltip: 'Next Song Engine Settings',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _showEngineBottomSheet(context),
          ),
        ],
      ),
    );
  }
}

