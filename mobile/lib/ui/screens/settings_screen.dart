import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/auth_manager.dart';
import '../../services/cache_manager.dart';
import '../../services/supabase_service.dart';
import '../../services/party_sync_coordinator.dart';
import '../../services/settings_manager.dart';
import '../../services/battery_optimization_service.dart';
import '../../services/blacklist_manager.dart';
import '../../models/song.dart';
import '../../services/app_logger.dart';
import '../widgets/mini_player.dart';
import '../widgets/auth_dialog.dart';
import 'audio_quality_settings_screen.dart';
import 'equalizer_settings_screen.dart';
import 'downloads_settings_screen.dart';
import 'storage_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'home_settings_screen.dart';
import 'party_sync_settings_screen.dart';
import 'listening_recap_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _cacheSizeStr = 'Calculating...';
  String _appVersion = 'Version 2.1.0 (Release)';

  static const String _gitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: '');
  static const String _buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: '');

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _calculateCacheSize();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'Version ${info.version} (Build ${info.buildNumber})';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersion = 'Version 2.1.0 (Release)';
        });
      }
    }
  }

  Future<void> _calculateCacheSize() async {
    try {
      final sizeStr = await CacheManager.getCacheSizeString();
      if (mounted) {
        setState(() {
          _cacheSizeStr = sizeStr;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cacheSizeStr = '0.0 MB';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              // User Account Header Card
              _buildAccountCard(),
              const SizedBox(height: 24),

              // AUDIO & PLAYBACK
              _buildSectionHeader('AUDIO & PLAYBACK', Icons.headphones_rounded),
              const SizedBox(height: 10),
              _buildHubContainer([
                AnimatedBuilder(
                  animation: Listenable.merge([
                    SettingsManager.streamingQualityNotifier,
                    SettingsManager.volumeNormalizationNotifier,
                  ]),
                  builder: (context, _) {
                    final quality = SettingsManager.streamingQuality;
                    final qualityLabel = quality == 'auto' ? 'Auto (Adaptive)' : quality;
                    final isNorm = SettingsManager.isVolumeNormalizationEnabled;
                    return _buildNavigationTile(
                      icon: Icons.graphic_eq_rounded,
                      iconColor: const Color(0xFF6366F1),
                      title: 'Audio Quality & Streaming',
                      subtitle: '$qualityLabel • Loudness Normalization ${isNorm ? "On" : "Off"}',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AudioQualitySettingsScreen()),
                        );
                        if (!mounted) return;
                        setState(() {});
                      },
                    );
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                ValueListenableBuilder<String>(
                  valueListenable: SettingsManager.eqPresetNotifier,
                  builder: (context, preset, _) {
                    return _buildNavigationTile(
                      icon: Icons.tune_rounded,
                      iconColor: const Color(0xFFA855F7),
                      title: '5-Band Hardware Equalizer',
                      subtitle: 'Preset: ${preset.toUpperCase()} • Frequency acoustic tuning',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const EqualizerSettingsScreen()),
                        );
                        if (!mounted) return;
                        setState(() {});
                      },
                    );
                  },
                ),
              ]),
              const SizedBox(height: 24),

              // DOWNLOADS & STORAGE
              _buildSectionHeader('DOWNLOADS & STORAGE', Icons.download_for_offline_rounded),
              const SizedBox(height: 10),
              _buildHubContainer([
                AnimatedBuilder(
                  animation: Listenable.merge([
                    SettingsManager.downloadQualityNotifier,
                    SettingsManager.downloadWifiOnlyNotifier,
                    SettingsManager.downloadPathNotifier,
                  ]),
                  builder: (context, _) {
                    final quality = SettingsManager.downloadQuality;
                    final wifiOnly = SettingsManager.isDownloadWifiOnlyEnabled;
                    return _buildNavigationTile(
                      icon: Icons.download_done_rounded,
                      iconColor: const Color(0xFF10B981),
                      title: 'Downloads & Network Rules',
                      subtitle: '$quality • ${wifiOnly ? "Wi-Fi Only" : "Wi-Fi & Cellular"} • Storage Path',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DownloadsSettingsScreen()),
                        );
                        _calculateCacheSize();
                      },
                    );
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                _buildNavigationTile(
                  icon: Icons.storage_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  title: 'Storage & Cache Management',
                  subtitle: '$_cacheSizeStr temporary cache • Disk allocation & cleaners',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StorageSettingsScreen()),
                    );
                    _calculateCacheSize();
                  },
                ),
              ]),
              const SizedBox(height: 24),

              // DISPLAY & PREFERENCES
              _buildSectionHeader('DISPLAY & PREFERENCES', Icons.palette_rounded),
              const SizedBox(height: 10),
              _buildHubContainer([
                AnimatedBuilder(
                  animation: Listenable.merge([
                    SettingsManager.homeHeroBannerModeNotifier,
                    SettingsManager.homeTop10ChartLayoutNotifier,
                    SettingsManager.homeRememberFeelingNotifier,
                  ]),
                  builder: (context, _) {
                    final heroMode = SettingsManager.homeHeroBannerMode;
                    final chartLayout = SettingsManager.homeTop10ChartLayout;
                    final heroText = heroMode == 'smart' ? 'Adaptive' : (heroMode == 'flagship' ? 'Top 50' : 'Time-of-Day');
                    final chartText = chartLayout == 'vertical' ? 'Ranked #1-#10' : '3D Slider';
                    return _buildNavigationTile(
                      icon: Icons.dashboard_customize_rounded,
                      iconColor: const Color(0xFF8B5CF6),
                      title: 'Home Feed & Experience',
                      subtitle: '$heroText Hero • $chartText • Privacy Mood Guard',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HomeSettingsScreen()),
                        );
                        if (!mounted) return;
                        setState(() {});
                      },
                    );
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    SettingsManager.themeModeNotifier,
                    SettingsManager.dynamicBackgroundNotifier,
                    SettingsManager.indicRomanizationNotifier,
                  ]),
                  builder: (context, _) {
                    final theme = SettingsManager.themeMode;
                    final romanize = SettingsManager.isIndicRomanizationEnabled;
                    final dynamicBg = SettingsManager.isDynamicBackgroundEnabled;
                    return _buildNavigationTile(
                      icon: Icons.brush_rounded,
                      iconColor: const Color(0xFFEC4899),
                      title: 'Appearance & Display',
                      subtitle: '${theme == "amoled" ? "AMOLED" : "Dark Slate"} • ${dynamicBg ? "Fluid Mesh" : "Static"} • Romanization ${romanize ? "On" : "Off"}',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()),
                        );
                        if (!mounted) return;
                        setState(() {});
                      },
                    );
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                ValueListenableBuilder<List<String>>(
                  valueListenable: SettingsManager.languagesNotifier,
                  builder: (context, _, __) {
                    return _buildNavigationTile(
                      icon: Icons.language_rounded,
                      iconColor: const Color(0xFF38BDF8),
                      title: 'Music Languages',
                      subtitle: SettingsManager.preferredLanguages.join(', '),
                      onTap: () => _showLanguageModal(context),
                    );
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                ValueListenableBuilder<bool>(
                  valueListenable: BlacklistManager.isEnabledNotifier,
                  builder: (context, enabled, _) {
                    return ValueListenableBuilder<List<Song>>(
                      valueListenable: BlacklistManager.blacklistedSongsNotifier,
                      builder: (context, songs, _) {
                        return ValueListenableBuilder<List<String>>(
                          valueListenable: BlacklistManager.blacklistedArtistsNotifier,
                          builder: (context, artists, _) {
                            final songCount = songs.length;
                            final artistCount = artists.length;
                            return _buildNavigationTile(
                              icon: Icons.block_rounded,
                              iconColor: Colors.redAccent,
                              title: "Don't Play This (Content Blocklist)",
                              subtitle: enabled
                                  ? 'Active (Default) • $songCount songs & $artistCount artists blocked'
                                  : 'Disabled • Blocked songs may play',
                              onTap: () => _showBlockedContentModal(context),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ]),
              const SizedBox(height: 24),

              // SOCIAL & PARTY
              _buildSectionHeader('SOCIAL & PARTY SYNC', Icons.speaker_group_rounded),
              const SizedBox(height: 10),
              _buildHubContainer([
                ValueListenableBuilder<int>(
                  valueListenable: SettingsManager.hardwareAudioLatencyMsNotifier,
                  builder: (context, latency, _) {
                    final role = PartySyncCoordinator.role;
                    final statusStr = role == PartyRole.none ? 'Idle' : 'Active';
                    return _buildNavigationTile(
                      icon: Icons.sync_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      title: 'Multi-Phone Party Sync & Latency',
                      subtitle: 'Lockstep ($statusStr) • Latency: ${latency}ms • Live NTP Diagnostics',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PartySyncSettingsScreen()),
                        );
                        if (!mounted) return;
                        setState(() {});
                      },
                    );
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                _buildNavigationTile(
                  icon: Icons.auto_awesome,
                  iconColor: const Color(0xFFA855F7),
                  title: 'Paatu Recap & Music Wrapped',
                  subtitle: 'Relive your top songs, artists & listening persona',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ListeningRecapScreen()),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 24),

              // SYSTEM & DIAGNOSTICS
              _buildSectionHeader('SYSTEM & DIAGNOSTICS', Icons.settings_suggest_rounded),
              const SizedBox(height: 10),
              _buildHubContainer([
                _buildNavigationTile(
                  icon: Icons.battery_charging_full_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Battery & Background Playback',
                  subtitle: 'WakeLock guardrails & unthrottled position listener',
                  onTap: () => _showBatteryModal(context),
                ),
                const Divider(color: Colors.white10, height: 1),
                _buildNavigationTile(
                  icon: Icons.bug_report_rounded,
                  iconColor: const Color(0xFF94A3B8),
                  title: 'Diagnostics & Telemetry Logs',
                  subtitle: 'Crash dumps, stream health, and runtime isolate metrics',
                  onTap: () => _showDiagnosticsModal(context),
                ),
              ]),
              const SizedBox(height: 24),

              // ABOUT & CLOUD SYNC
              _buildSectionHeader('ABOUT', Icons.info_outline_rounded),
              const SizedBox(height: 10),
              _buildAboutCard(),
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
        Icon(icon, color: const Color(0xFF6366F1), size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF818CF8),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildHubContainer(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildNavigationTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthManager.authNotifier,
      builder: (context, user, _) {
        final isLoggedIn = user != null && !user.isGuest;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  isLoggedIn && user.username.isNotEmpty ? user.username.substring(0, 1).toUpperCase() : 'G',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoggedIn ? user.username : 'Guest Session',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLoggedIn ? user.email : 'Local offline mode active',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (isLoggedIn)
                TextButton(
                  onPressed: () async {
                    await AuthManager.logout();
                  },
                  child: const Text('Sign Out', style: TextStyle(color: Color(0xFFEF4444))),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => AuthDialog.show(context),
                  child: const Text('Sign In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showBlockedContentModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final isEnabled = BlacklistManager.isEnabled;
            final songs = BlacklistManager.blacklistedSongsNotifier.value;
            final artists = BlacklistManager.blacklistedArtistsNotifier.value;

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (ctx, scrollCtrl) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Don't Play This (Blocklist)",
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Switch(
                            value: isEnabled,
                            activeColor: const Color(0xFF6366F1),
                            onChanged: (val) async {
                              await BlacklistManager.setEnabled(val);
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        "Blocked tracks and artists are filtered out of autoplay, radio, home recommendations, and queues.",
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 24),
                    Expanded(
                      child: (songs.isEmpty && artists.isEmpty)
                          ? const Center(
                              child: Text(
                                "No blocked songs or artists.\nTap \"Don't play this\" on any song to hide it.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                              ),
                            )
                          : ListView(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: [
                                if (artists.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      "BLOCKED ARTISTS",
                                      style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  ...artists.map((artist) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: ListTile(
                                      leading: const Icon(Icons.person_off_rounded, color: Colors.redAccent, size: 20),
                                      title: Text(artist, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                      trailing: TextButton(
                                        onPressed: () async {
                                          await BlacklistManager.unblacklistArtist(artist);
                                          setModalState(() {});
                                        },
                                        child: const Text('Unblock', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
                                      ),
                                    ),
                                  )),
                                  const SizedBox(height: 12),
                                ],
                                if (songs.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      "BLOCKED SONGS",
                                      style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  ...songs.map((s) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: ListTile(
                                      leading: const Icon(Icons.music_off_rounded, color: Colors.redAccent, size: 20),
                                      title: Text(s.title, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: Text(s.artist, style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1),
                                      trailing: TextButton(
                                        onPressed: () async {
                                          await BlacklistManager.unblacklistSong(s.id);
                                          setModalState(() {});
                                        },
                                        child: const Text('Unblock', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
                                      ),
                                    ),
                                  )),
                                ],
                              ],
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showLanguageModal(BuildContext context) {
    const allLanguages = [
      'Tamil',
      'Hindi',
      'Telugu',
      'Malayalam',
      'Kannada',
      'English',
      'Punjabi',
      'Bengali',
    ];

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

  void _showBatteryModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return FutureBuilder<Map<String, dynamic>>(
            future: Future.wait([
              BatteryOptimizationService.getDeviceManufacturer(),
              BatteryOptimizationService.isIgnoringBatteryOptimizations(),
              BatteryOptimizationService.isAggressiveBatteryOEM(),
            ]).then((res) => {
              'mfg': res[0] as String,
              'isIgnoring': res[1] as bool,
              'isAggressive': res[2] as bool,
            }),
            builder: (context, snapshot) {
              final mfg = snapshot.data?['mfg'] as String? ?? '';
              final isIgnoring = snapshot.data?['isIgnoring'] as bool? ?? true;
              final isAggressive = snapshot.data?['isAggressive'] as bool? ?? false;
              final isRestricted = !isIgnoring;

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Battery & Background Playback',
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
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (isAggressive && isRestricted)
                              ? Colors.amberAccent.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isRestricted
                                      ? Colors.amberAccent.withValues(alpha: 0.12)
                                      : const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isRestricted ? Icons.battery_alert_rounded : Icons.battery_charging_full_rounded,
                                  color: isRestricted ? Colors.amberAccent : const Color(0xFF10B981),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mfg.isNotEmpty ? '$mfg Battery Status' : 'Battery Optimization',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isRestricted
                                          ? 'Optimized (Background playback may be stopped)'
                                          : 'Unrestricted (Continuous playback active)',
                                      style: TextStyle(
                                        color: isRestricted ? Colors.amberAccent : const Color(0xFF94A3B8),
                                        fontSize: 12,
                                        fontWeight: isRestricted ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (isAggressive && isRestricted) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline_rounded, color: Colors.amberAccent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${mfg.isNotEmpty ? mfg : "The device"} restricts background apps by default. Tap below to set Battery to "Unrestricted" so music keeps playing when locked.',
                                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await BatteryOptimizationService.openBatteryOptimizationSettings();
                                await Future.delayed(const Duration(seconds: 1));
                                setModalState(() {});
                              },
                              icon: const Icon(Icons.settings_outlined, size: 16),
                              label: const Text('Manage Battery Optimization'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF818CF8),
                                side: const BorderSide(color: Color(0xFF6366F1), width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 28),
                          ValueListenableBuilder<bool>(
                            valueListenable: SettingsManager.persistentBackgroundPlaybackNotifier,
                            builder: (context, isPersistent, _) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: const [
                                        Text(
                                          'Keep Playing When App Is Closed',
                                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(height: 3),
                                        Text(
                                          'Continue playing and queuing next songs when clearing from Recent Apps (RAM). Tapping Pause will close the app completely.',
                                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.3),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isPersistent,
                                    activeColor: const Color(0xFF10B981),
                                    onChanged: (val) {
                                      SettingsManager.setPersistentBackgroundPlayback(val);
                                      setModalState(() {});
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showDiagnosticsModal(BuildContext context) {
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
                  'Diagnostics & Crash Logs',
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
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.bug_report_rounded, color: Color(0xFF818CF8), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'App & Playback Event Trace',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Diagnostic logs for track transitions, preload, and crashes',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final logText = await AppLogger.getLogContent();
                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.terminal_rounded, color: Color(0xFF818CF8), size: 20),
                                    SizedBox(width: 8),
                                    Text('Diagnostics & Crash Logs',
                                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  height: 380,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0A0E1A),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                    ),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        logText,
                                        style: const TextStyle(
                                          color: Color(0xFFCBD5E1),
                                          fontFamily: 'monospace',
                                          fontSize: 10.5,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: logText));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Logs copied to clipboard.'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF818CF8)),
                                    label: const Text('Copy All', style: TextStyle(color: Color(0xFF818CF8))),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close', style: TextStyle(color: Colors.white70)),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(Icons.article_outlined, size: 16),
                          label: const Text('View Logs'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await AppLogger.clearLog();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Diagnostic logs cleared.'),
                                backgroundColor: Color(0xFF1E293B),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Clear'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _buildDetailsText {
    final commit = _gitCommit.trim();
    final time = _buildTime.trim();
    if (commit.isNotEmpty && time.isNotEmpty) {
      return '$_appVersion • Git: $commit • $time';
    } else if (commit.isNotEmpty) {
      return '$_appVersion • Git: $commit';
    } else if (time.isNotEmpty) {
      return '$_appVersion • Build: $time';
    }
    return '$_appVersion • Local Dev';
  }

  Widget _buildAboutCard() {
    final isConfigured = SupabaseService.isConfigured;
    final isInitialized = SupabaseService.isInitialized;
    final isHealthy = isConfigured && isInitialized;

    String pillText;
    if (!isConfigured) {
      pillText = 'Cloud Sync: Unavailable';
    } else if (!isInitialized) {
      pillText = 'Cloud Sync: Offline (Unable to reach sync service)';
    } else {
      final url = SupabaseService.supabaseUrl;
      final isProd = url.contains('bdolimatfkyqibiedlqp');
      pillText = 'Cloud Sync: Active (${isProd ? 'Production' : 'Connected'})';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.music_note_rounded, color: Color(0xFF6366F1), size: 24),
              SizedBox(width: 10),
              Text(
                'Paatu Padava Mobile',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_buildDetailsText\nComplete Web App Parity • Smart AI Shuffle • Lossless Audio Streaming & Offline Downloads.',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isHealthy ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isHealthy ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFEF4444).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHealthy ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  size: 14,
                  color: isHealthy ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    pillText,
                    style: TextStyle(
                      color: isHealthy ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
