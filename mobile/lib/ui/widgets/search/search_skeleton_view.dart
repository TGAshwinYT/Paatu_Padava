import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Shimmering skeleton view displayed during search query processing.
/// Replaces full-screen spinners to prevent layout shifts and flash-to-black.
class SearchSkeletonView extends StatefulWidget {
  const SearchSkeletonView({super.key});

  @override
  State<SearchSkeletonView> createState() => _SearchSkeletonViewState();
}

class _SearchSkeletonViewState extends State<SearchSkeletonView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildBox({required double width, required double height, double borderRadius = 6}) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, _) {
        final color = Color.lerp(
          AppColors.surfaceDark,
          AppColors.surfaceElevated,
          _pulseAnimation.value,
        );
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Top Hero Card Skeleton
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, _) {
            final color = Color.lerp(
              AppColors.surfaceDark,
              AppColors.surfaceElevated,
              _pulseAnimation.value,
            );
            return Container(
              height: 110,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: AppColors.bgDark.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildBox(width: 140, height: 16),
                        const SizedBox(height: 10),
                        _buildBox(width: 90, height: 12),
                        const SizedBox(height: 8),
                        _buildBox(width: 60, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        _buildBox(width: 120, height: 14),
        const SizedBox(height: 14),
        // 5 Song Row Skeletons
        for (int i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _buildBox(width: 52, height: 52, borderRadius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBox(width: i.isEven ? 160 : 130, height: 14),
                      const SizedBox(height: 8),
                      _buildBox(width: i.isEven ? 90 : 110, height: 12),
                    ],
                  ),
                ),
                _buildBox(width: 24, height: 24, borderRadius: 12),
              ],
            ),
          ),
      ],
    );
  }
}
