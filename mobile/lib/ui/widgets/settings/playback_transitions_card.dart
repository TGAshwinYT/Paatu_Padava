import 'package:flutter/material.dart';
import '../../../services/settings_manager.dart';
import '../../theme/app_theme.dart';

class PlaybackTransitionsCard extends StatelessWidget {
  const PlaybackTransitionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.blur_on_rounded, color: AppColors.neonViolet, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'PLAYBACK TRANSITIONS & BACKGROUND',
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
              _buildCrossfadeRow(context, textTheme),
              const Divider(color: Colors.white10, height: 24),
              _buildBeatMatchSection(context, textTheme),
              const Divider(color: Colors.white10, height: 24),
              _buildBackgroundPlaybackRow(context, textTheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCrossfadeRow(BuildContext context, TextTheme textTheme) {
    return ValueListenableBuilder<int>(
      valueListenable: SettingsManager.crossfadeDurationNotifier,
      builder: (context, seconds, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Crossfade Duration',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(color: AppColors.textWhite, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  seconds == 0 ? 'Off' : '${seconds}s',
                  style: textTheme.labelMedium?.copyWith(color: AppColors.neonViolet, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Slider(
              value: seconds.toDouble(),
              min: 0,
              max: 12,
              divisions: 12,
              activeColor: AppColors.neonViolet,
              onChanged: (v) => SettingsManager.setCrossfadeSeconds(v.round()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBeatMatchSection(BuildContext context, TextTheme textTheme) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.beatMatchedTransitionsNotifier,
      builder: (context, isBeatMatch, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DJ Automix (Beat-Matched)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(color: AppColors.textWhite, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Harmonically aligns tempo (±3%) and bar phrases for seamless transitions.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isBeatMatch,
                  activeColor: AppColors.neonViolet,
                  onChanged: (val) => SettingsManager.setBeatMatchedTransitions(val),
                ),
              ],
            ),
            if (isBeatMatch) ...[
              const SizedBox(height: 10),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelSmall?.copyWith(
                                  color: isSelected ? AppColors.textWhite : AppColors.textSecondary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: AppColors.neonViolet,
                            backgroundColor: AppColors.surfaceDarkElevated,
                            showCheckmark: false,
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
    );
  }

  Widget _buildBackgroundPlaybackRow(BuildContext context, TextTheme textTheme) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.persistentBackgroundPlaybackNotifier,
      builder: (context, isPersistent, _) {
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Keep Playing When App Is Closed',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(color: AppColors.textWhite, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Keep playing even when cleared from Recent Apps. Tap Pause to close.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: isPersistent,
              activeColor: AppColors.neonViolet,
              onChanged: (val) => SettingsManager.setPersistentBackgroundPlayback(val),
            ),
          ],
        );
      },
    );
  }
}
