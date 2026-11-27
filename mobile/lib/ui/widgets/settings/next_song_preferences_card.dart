import 'package:flutter/material.dart';
import '../../../logic/queue/queue_tuner_mode.dart';
import '../../../services/player_handler.dart';
import '../../../services/settings_manager.dart';
import '../../theme/app_theme.dart';

class NextSongPreferencesCard extends StatelessWidget {
  const NextSongPreferencesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: AppColors.neonViolet, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'NEXT SONG & LANGUAGE ENGINE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.neonViolet,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSameLanguageRow(textTheme),
              const Divider(color: Colors.white10, height: 24),
              _buildTunerModeSelector(textTheme),
              const Divider(color: Colors.white10, height: 24),
              _buildStrategySelector(textTheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSameLanguageRow(TextTheme textTheme) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.sameLanguageLockNotifier,
      builder: (context, locked, _) {
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Same-Language Lock',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      color: AppColors.textWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Keep autoplay & radio in the current song\'s language (e.g. English → English).',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: locked,
              activeColor: AppColors.neonViolet,
              onChanged: (val) => SettingsManager.setSameLanguageLock(val),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTunerModeSelector(TextTheme textTheme) {
    return ValueListenableBuilder<String>(
      valueListenable: SettingsManager.preferredTunerModeNotifier,
      builder: (context, activeName, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Next Song Mode',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.textWhite,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: QueueTunerMode.values.map((m) {
                final isSelected = m.name == activeName;
                return ChoiceChip(
                  label: Text(
                    m.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: isSelected ? AppColors.textWhite : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.neonViolet,
                  backgroundColor: AppColors.surfaceElevated,
                  showCheckmark: false,
                  onSelected: (_) {
                    SettingsManager.setPreferredTunerMode(m.name);
                    if (isAudioHandlerInitialized) {
                      audioHandler.queueTunerController.setTunerMode(m, forceRefresh: true);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStrategySelector(TextTheme textTheme) {
    return ValueListenableBuilder<NextTrackStrategyMode>(
      valueListenable: SettingsManager.nextTrackStrategyNotifier,
      builder: (context, current, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Matching Engine',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.textWhite,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: NextTrackStrategyMode.values.map((s) {
                final isSelected = s == current;
                final label = switch (s) {
                  NextTrackStrategyMode.unifiedSmartRadio => 'Unified Smart Radio',
                  NextTrackStrategyMode.spotifyStyle => 'Spotify Style',
                  NextTrackStrategyMode.ytMusicStyle => 'YT Music Style',
                  NextTrackStrategyMode.markovCosineRadio => 'Markov-Cosine',
                };
                return ChoiceChip(
                  label: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: isSelected ? AppColors.textWhite : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.neonViolet,
                  backgroundColor: AppColors.surfaceElevated,
                  showCheckmark: false,
                  onSelected: (_) => SettingsManager.setNextTrackStrategy(s),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}
