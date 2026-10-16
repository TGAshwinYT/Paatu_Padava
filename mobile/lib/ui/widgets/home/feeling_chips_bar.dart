import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../../logic/home_feed_provider.dart';

class FeelingChipItem {
  final String id;
  final String label;
  final String emoji;

  const FeelingChipItem({
    required this.id,
    required this.label,
    required this.emoji,
  });
}

class FeelingChipsBar extends StatelessWidget {
  const FeelingChipsBar({Key? key}) : super(key: key);

  static const List<FeelingChipItem> chips = [
    FeelingChipItem(id: 'all', label: 'All', emoji: '✨'),
    FeelingChipItem(id: 'chill', label: 'Chill & Soul', emoji: '🌙'),
    FeelingChipItem(id: 'romance', label: 'Romance', emoji: '❤️'),
    FeelingChipItem(id: 'kuthu', label: 'High Energy', emoji: '⚡'),
    FeelingChipItem(id: 'focus', label: 'Focus & Lofi', emoji: '🎧'),
    FeelingChipItem(id: 'nostalgia', label: '90s Nostalgia', emoji: '📻'),
    FeelingChipItem(id: 'night', label: 'Late Night', emoji: '🌃'),
  ];

  @override
  Widget build(BuildContext context) {
    final activeFeeling = HomeFeedProvider.instance.state.activeFeeling;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = chips[index];
          final isSelected = activeFeeling == item.id;

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              HomeFeedProvider.instance.setActiveFeeling(item.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [AppColors.neonViolet, AppColors.electricCyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : const Color(0xFF131B2E),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.neonViolet.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.emoji,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: GoogleFonts.outfit(
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
