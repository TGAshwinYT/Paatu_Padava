import 'package:flutter/material.dart';
import '../../../logic/queue/queue_tuner_mode.dart';
import '../../../services/player_handler.dart';
import '../../../services/settings_manager.dart';
import '../../theme/app_theme.dart';

/// Horizontal Tuner Chip bar allowing instant mood/vibe filtering + Same-Language
/// lock on the Up Next queue.
class QueueTunerBar extends StatelessWidget {
  const QueueTunerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.transparent,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: ValueListenableBuilder<QueueTunerMode>(
          valueListenable: audioHandler.queueTunerModeNotifier,
          builder: (context, activeMode, _) {
            return Row(
              children: [
                ...QueueTunerMode.values.map((mode) {
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
                          color: isSelected ? AppColors.neonViolet : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? AppColors.neonViolet : Colors.white10,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              mode.icon,
                              size: 14,
                              color: isSelected ? AppColors.textWhite : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              mode.label,
                              style: textTheme.labelMedium?.copyWith(
                                color: isSelected ? AppColors.textWhite : AppColors.textSecondary,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                ValueListenableBuilder<bool>(
                  valueListenable: SettingsManager.sameLanguageLockNotifier,
                  builder: (context, locked, _) {
                    return InkWell(
                      onTap: () async {
                        await SettingsManager.setSameLanguageLock(!locked);
                        if (isAudioHandlerInitialized) {
                          audioHandler.queueTunerController.setTunerMode(
                            activeMode,
                            forceRefresh: true,
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: locked ? AppColors.neonViolet : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: locked ? AppColors.neonViolet : Colors.white10,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.translate_rounded,
                              size: 14,
                              color: locked ? AppColors.textWhite : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Same Language',
                              style: textTheme.labelMedium?.copyWith(
                                color: locked ? AppColors.textWhite : AppColors.textSecondary,
                                fontWeight: locked ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
