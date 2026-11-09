import 'package:flutter/material.dart';
import '../../../logic/queue/queue_tuner_mode.dart';
import '../../../services/player_handler.dart';

/// Horizontal Tuner Chip bar allowing instant mood/vibe filtering on Up Next queue.
/// Inspired by YouTube Music's Up Next mood tuners and Spotify's smart blend.
class QueueTunerBar extends StatelessWidget {
  const QueueTunerBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
    );
  }
}
