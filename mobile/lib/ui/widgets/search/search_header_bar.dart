import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class SearchHeaderBar extends StatelessWidget {
  final bool isSearchActive;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onEnterActiveSearch;
  final VoidCallback onExitActiveSearch;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const SearchHeaderBar({
    super.key,
    required this.isSearchActive,
    required this.controller,
    required this.focusNode,
    required this.onEnterActiveSearch,
    required this.onExitActiveSearch,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSearchActive && controller.text.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Text(
              'Search',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: GestureDetector(
              onTap: onEnterActiveSearch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search_rounded, color: AppColors.neonViolet, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'What do you want to play?',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDark.withValues(alpha: 0.85),
        border: const Border(
          bottom: BorderSide(color: AppColors.surfaceBorder, width: 0.5),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                  tooltip: 'Back to Search',
                  onPressed: onExitActiveSearch,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surfaceBorderHighlight),
                    ),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      textInputAction: TextInputAction.search,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search songs, artists, albums...',
                        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.neonViolet, size: 22),
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, _) {
                            if (value.text.isEmpty) return const SizedBox.shrink();
                            return IconButton(
                              icon: const Icon(Icons.cancel_rounded, color: Colors.white70, size: 20),
                              tooltip: 'Clear search',
                              onPressed: () {
                                controller.clear();
                                onChanged('');
                              },
                            );
                          },
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
