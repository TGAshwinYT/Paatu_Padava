import 'package:flutter/material.dart';
import '../../services/settings_manager.dart';
import '../widgets/mini_player.dart';

class HomeSettingsScreen extends StatelessWidget {
  const HomeSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Home Feed & Experience',
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
              _buildHeroBannerSection(),
              const SizedBox(height: 20),
              _buildTop10ChartSection(),
              const SizedBox(height: 20),
              _buildPrivacyAndFeelingSection(),
              const SizedBox(height: 20),
              _buildModulesSection(),
              const SizedBox(height: 20),
              _buildSandboxingInfoCard(),
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

  Widget _buildHeroBannerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('FLAGSHIP HERO SHOWCASE', Icons.view_carousel_rounded),
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
                'Top Banner Presentation',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose how the flagship hero showcase is curated at the top of your feed.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: SettingsManager.homeHeroBannerModeNotifier,
                builder: (context, currentMode, _) {
                  return Column(
                    children: [
                      _buildOptionTile(
                        title: 'Smart Adaptive (Recommended)',
                        subtitle: 'Blends current time-of-day greeting with editorial Top 50 hits',
                        icon: Icons.auto_awesome_rounded,
                        isSelected: currentMode == 'smart',
                        onTap: () => SettingsManager.setHomeHeroBannerMode('smart'),
                      ),
                      const SizedBox(height: 8),
                      _buildOptionTile(
                        title: 'Spotify Top 50 Chart',
                        subtitle: 'Always features the #1 official trending chart and top 50 tracks',
                        icon: Icons.local_fire_department_rounded,
                        isSelected: currentMode == 'flagship',
                        onTap: () => SettingsManager.setHomeHeroBannerMode('flagship'),
                      ),
                      const SizedBox(height: 8),
                      _buildOptionTile(
                        title: 'Time-of-Day Vibe',
                        subtitle: 'Switches automatically: Morning Acoustic, Afternoon Flow, Late Night Lofi',
                        icon: Icons.wb_sunny_rounded,
                        isSelected: currentMode == 'time_of_day',
                        onTap: () => SettingsManager.setHomeHeroBannerMode('time_of_day'),
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

  Widget _buildTop10ChartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('REGIONAL TOP 10 CHARTS', Icons.leaderboard_rounded),
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
                'Chart Track Layout',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select between Spotify-style ranked vertical numbering or Apple-style slider.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: SettingsManager.homeTop10ChartLayoutNotifier,
                builder: (context, currentLayout, _) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildLayoutCard(
                          title: 'Ranked List',
                          subtitle: '#1 to #10 with ▲/▼',
                          icon: Icons.format_list_numbered_rounded,
                          isSelected: currentLayout == 'vertical',
                          onTap: () => SettingsManager.setHomeTop10ChartLayout('vertical'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildLayoutCard(
                          title: '3D Card Slider',
                          subtitle: 'Horizontal scroll',
                          icon: Icons.view_column_rounded,
                          isSelected: currentLayout == 'horizontal',
                          onTap: () => SettingsManager.setHomeTop10ChartLayout('horizontal'),
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

  Widget _buildPrivacyAndFeelingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('PRIVACY & MOOD MEMORY', Icons.privacy_tip_rounded),
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
              ValueListenableBuilder<bool>(
                valueListenable: SettingsManager.homeRememberFeelingNotifier,
                builder: (context, remember, _) {
                  return Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF6366F1),
                      value: remember,
                      onChanged: (val) => SettingsManager.setHomeRememberFeeling(val),
                      title: const Text(
                        'Remember Last Mood / Feeling Filter',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        remember
                            ? 'App will preserve your active feeling filter across restarts.'
                            : 'Privacy friendly: Resets to "All" on app launch so your mood isn\'t tracked or locked.',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('CONTENT MODULES & GRIDS', Icons.dashboard_customize_rounded),
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
              ValueListenableBuilder<bool>(
                valueListenable: SettingsManager.homeShowQuickPicksNotifier,
                builder: (context, showQuickPicks, _) {
                  return Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF6366F1),
                      value: showQuickPicks,
                      onChanged: (val) => SettingsManager.setHomeShowQuickPicks(val),
                      title: const Text(
                        'YouTube Music Style Quick Picks',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Display 4-row column carousel for fast multi-track discovery.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ),
                  );
                },
              ),
              const Divider(color: Colors.white10, height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: SettingsManager.dynamicBackgroundNotifier,
                builder: (context, dynamicBg, _) {
                  return Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF6366F1),
                      value: dynamicBg,
                      onChanged: (val) => SettingsManager.setDynamicBackground(val),
                      title: const Text(
                        'Apple Music Ambient Mesh Glow',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Subtle dynamic background mesh that reacts to current album artwork.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSandboxingInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zero-Permission Storage Architecture',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Paatu Padava uses Android scoped internal app storage for all audio and cache. We never request storage permission, camera, microphone, contacts, or location tracking.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.15) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF64748B), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.15) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF64748B), size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
