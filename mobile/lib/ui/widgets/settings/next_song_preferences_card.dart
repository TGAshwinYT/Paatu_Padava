import 'package:flutter/material.dart';
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
            const Icon(Icons.autorenew_rounded, color: AppColors.neonViolet, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AUTOPLAY & CONTINUOUS RADIO',
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
          child: ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.autoplayNotifier,
            builder: (context, isAutoplay, _) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Autoplay Similar Tracks',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            color: AppColors.textWhite,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Automatically queue similar songs when your playlist or search track ends.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isAutoplay,
                    activeColor: AppColors.neonViolet,
                    onChanged: (val) => SettingsManager.setAutoplay(val),
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
