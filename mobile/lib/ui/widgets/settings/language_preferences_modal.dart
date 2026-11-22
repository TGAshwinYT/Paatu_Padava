import 'package:flutter/material.dart';
import '../../../services/settings_manager.dart';

/// Modal bottom sheet for configuring music languages and lyrics display modes
class LanguagePreferencesModal {
  static const List<String> allLanguages = [
    'Tamil',
    'English',
    'Hindi',
    'Telugu',
    'Malayalam',
    'Kannada',
    'Punjabi',
    'Marathi',
    'Bengali',
    'Gujarati',
    'Bhojpuri',
    'Urdu',
    'Haryanvi',
    'Rajasthani',
    'Odia',
    'Assamese',
    'Spanish',
    'Korean',
  ];

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Music Languages',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
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
                        'Select your preferred music languages for smart recommendations and search boosting:',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allLanguages.map((lang) {
                          final isSelected = currentLangs.any((l) => l.trim().toLowerCase() == lang.trim().toLowerCase());
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
                              final updated = currentLangs.map((l) => l.trim()).toList();
                              if (selected) {
                                if (!updated.any((l) => l.toLowerCase() == lang.toLowerCase())) {
                                  updated.add(lang);
                                }
                              } else {
                                if (updated.length > 1) {
                                  updated.removeWhere((l) => l.toLowerCase() == lang.toLowerCase());
                                }
                              }
                              final normalized = updated
                                  .map((l) => l.isEmpty ? l : (l[0].toUpperCase() + l.substring(1).toLowerCase()))
                                  .toSet()
                                  .toList();
                              SettingsManager.setPreferredLanguages(normalized);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 8),
                      const Text(
                        'Default Lyrics Display Mode:',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<String>(
                        valueListenable: SettingsManager.lyricsPreferredLanguageNotifier,
                        builder: (context, preferredLang, _) {
                          final isEnglish = preferredLang == 'english';
                          return Row(
                            children: [
                              ChoiceChip(
                                label: const Text('Default / Native Script'),
                                selected: !isEnglish,
                                selectedColor: const Color(0xFF6366F1),
                                backgroundColor: const Color(0xFF1E293B),
                                labelStyle: TextStyle(
                                  color: !isEnglish ? Colors.white : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: !isEnglish ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (val) {
                                  if (val) SettingsManager.setLyricsPreferredLanguage('default');
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Romanized English'),
                                selected: isEnglish,
                                selectedColor: const Color(0xFF6366F1),
                                backgroundColor: const Color(0xFF1E293B),
                                labelStyle: TextStyle(
                                  color: isEnglish ? Colors.white : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: isEnglish ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (val) {
                                  if (val) SettingsManager.setLyricsPreferredLanguage('english');
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
