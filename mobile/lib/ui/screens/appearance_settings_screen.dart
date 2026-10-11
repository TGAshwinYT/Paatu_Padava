import 'package:flutter/material.dart';
import '../../services/settings_manager.dart';
import '../widgets/mini_player.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Appearance & Display',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _buildThemeSection(),
              const SizedBox(height: 20),
              _buildDynamicBackgroundSection(),
              const SizedBox(height: 20),
              _buildIndicRomanizationSection(),
              const SizedBox(height: 20),
              _buildKeepAwakeSection(),
              const SizedBox(height: 20),
              _buildLyricsLanguageSection(),
            ],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF818CF8),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('APPLICATION THEME', Icons.palette_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Color Palette & Contrast',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select your preferred UI background style for low-light listening.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: SettingsManager.themeModeNotifier,
                builder: (context, currentTheme, _) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildThemeCard(
                          title: 'AMOLED Black',
                          subtitle: '#000000 true black for battery efficiency',
                          color: Colors.black,
                          borderColor: const Color(0xFF334155),
                          isSelected: currentTheme == 'amoled',
                          onTap: () => SettingsManager.setThemeMode('amoled'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildThemeCard(
                          title: 'Dark Indigo',
                          subtitle: '#0A0E1A deep midnight slate contrast',
                          color: const Color(0xFF0F172A),
                          borderColor: const Color(0xFF6366F1),
                          isSelected: currentTheme == 'dark_indigo',
                          onTap: () => SettingsManager.setThemeMode('dark_indigo'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemeCard({
    required String title,
    required String subtitle,
    required Color color,
    required Color borderColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1), size: 18),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicBackgroundSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('FLUID MESH GRADIENT', Icons.animation_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.dynamicBackgroundNotifier,
            builder: (context, isDynamic, _) {
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.blur_on_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dynamic Fluid Mesh Gradient',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Floods the player background and full-screen lyrics with animated, flowing ambient colors sampled from album art.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isDynamic,
                    activeColor: const Color(0xFFEC4899),
                    onChanged: (val) => SettingsManager.setDynamicBackground(val),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIndicRomanizationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('INDIC SCRIPT TRANSLITERATION', Icons.translate_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.indicRomanizationNotifier,
            builder: (context, romanize, _) {
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.spellcheck_rounded, color: Color(0xFF34D399), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Romanize Indic Lyrics',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Automatically converts Tamil, Hindi, Telugu, and Malayalam lyrics into English Latin phonetics for easy karaoke singing.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: romanize,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => SettingsManager.setIndicRomanization(val),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKeepAwakeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('DISPLAY AWAKE TIMEOUT', Icons.screen_lock_portrait_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.keepScreenAwakeNotifier,
            builder: (context, keepAwake, _) {
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFF59E0B), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Keep Screen Awake',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Prevents device screen from turning off or locking while viewing the Fullscreen Lyrics or Player view.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: keepAwake,
                    activeColor: const Color(0xFFF59E0B),
                    onChanged: (val) => SettingsManager.setKeepScreenAwake(val),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsLanguageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('DEFAULT LYRICS SCRIPT', Icons.lyrics_rounded),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Preferred Lyrics Presentation',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose whether dual-variant songs display native regional scripts or transliterated Latin by default.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: SettingsManager.lyricsPreferredLanguageNotifier,
                builder: (context, lang, _) {
                  return Row(
                    children: [
                      _buildScriptChip(
                        label: 'Native Script',
                        keyName: 'default',
                        current: lang,
                        onTap: () => SettingsManager.setLyricsPreferredLanguage('default'),
                      ),
                      const SizedBox(width: 8),
                      _buildScriptChip(
                        label: 'Romanized English',
                        keyName: 'english',
                        current: lang,
                        onTap: () => SettingsManager.setLyricsPreferredLanguage('english'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScriptChip({
    required String label,
    required String keyName,
    required String current,
    required VoidCallback onTap,
  }) {
    final isSelected = current == keyName;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.2) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.05),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF818CF8) : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
