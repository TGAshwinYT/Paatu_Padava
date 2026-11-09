import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../../logic/home_feed_provider.dart';

/// Top category filter pills matching Spotify & Apple Music standards:
/// Filters between All, Playlists, Made For You, and Moods with 1 tap.
class HomeCategoryPills extends StatelessWidget {
  const HomeCategoryPills({super.key});

  static const List<Map<String, String>> _categories = [
    {'id': 'all', 'label': 'All'},
    {'id': 'playlists', 'label': 'Playlists'},
    {'id': 'for_you', 'label': 'Made For You'},
    {'id': 'moods', 'label': 'Moods & Stations'},
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HomeFeedProvider.instance,
      builder: (context, _) {
        final currentFilter = HomeFeedProvider.instance.homeFilter;

        return SizedBox(
          height: 38,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final catId = cat['id']!;
              final isSelected = currentFilter == catId;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  HomeFeedProvider.instance.setHomeFilter(catId);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.neonViolet : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.neonViolet
                          : AppColors.surfaceBorder,
                      width: 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.neonViolet.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      cat['label']!,
                      style: GoogleFonts.outfit(
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
