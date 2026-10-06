import 'package:flutter/material.dart';
import '../../../services/settings_manager.dart';

class LanguageSettingsCard extends StatelessWidget {
  static const List<String> allLanguages = [
    'Tamil',
    'Hindi',
    'Telugu',
    'Malayalam',
    'Kannada',
    'English',
    'Punjabi',
    'Bengali',
  ];

  const LanguageSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ValueListenableBuilder<List<String>>(
        valueListenable: SettingsManager.languagesNotifier,
        builder: (context, currentLangs, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select your preferred music languages for smart recommendations:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allLanguages.map((lang) {
                  final isSelected = currentLangs.contains(lang);
                  return FilterChip(
                    label: Text(lang),
                    selected: isSelected,
                    selectedColor: const Color(0xFF6366F1),
                    backgroundColor: const Color(0xFF1E293B),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onSelected: (selected) {
                      final updated = List<String>.from(currentLangs);
                      if (selected) {
                        if (!updated.contains(lang)) updated.add(lang);
                      } else {
                        if (updated.length > 1) updated.remove(lang);
                      }
                      SettingsManager.setPreferredLanguages(updated);
                    },
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}
