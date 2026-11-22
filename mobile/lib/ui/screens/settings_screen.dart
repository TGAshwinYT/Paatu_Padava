import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/cache_manager.dart';
import '../../services/party_sync_coordinator.dart';
import '../../services/settings_manager.dart';
import '../../services/blacklist_manager.dart';
import '../../models/song.dart';
import '../widgets/mini_player.dart';
import 'audio_quality_settings_screen.dart';
import 'equalizer_settings_screen.dart';
import 'downloads_settings_screen.dart';
import 'storage_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'home_settings_screen.dart';
import 'party_sync_settings_screen.dart';
import 'listening_recap_screen.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/settings/settings_account_card.dart';
import '../widgets/settings/blocked_content_modal.dart';
import '../widgets/settings/language_preferences_modal.dart';
import '../widgets/settings/battery_optimization_modal.dart';
import '../widgets/settings/diagnostics_modal.dart';
import '../widgets/settings/settings_about_card.dart';

/// Modular, performant SettingsScreen.
/// Broken into scoped, const-friendly sub-widgets to eliminate full-screen rebuilds on setting mutations.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ValueNotifier<String> _cacheSizeNotifier = ValueNotifier<String>('Calculating...');
  String _appVersion = 'Version 2.1.0 (Release)';

  static const String _gitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: '');
  static const String _buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: '');

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _calculateCacheSize();
  }

  @override
  void dispose() {
    _cacheSizeNotifier.dispose();
    super.dispose();
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
      _cacheSizeNotifier.value = sizeStr;
    } catch (_) {
      _cacheSizeNotifier.value = '0.0 MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 340;
    final horizontalPad = isCompact ? 10.0 : 16.0;

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
            padding: EdgeInsets.fromLTRB(horizontalPad, 16, horizontalPad, 120),
            children: [
              // User Account Header Card
              const SettingsAccountCard(),
              const SizedBox(height: 24),

              // AUDIO & PLAYBACK
              const SettingsSectionHeader(title: 'AUDIO & PLAYBACK', icon: Icons.headphones_rounded),
              const SizedBox(height: 10),
              SettingsHubContainer(
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      SettingsManager.streamingQualityNotifier,
                      SettingsManager.volumeNormalizationNotifier,
                    ]),
                    builder: (context, _) {
                      final quality = SettingsManager.streamingQuality;
                      final qualityLabel = quality == 'auto' ? 'Auto (Adaptive)' : quality;
                      final isNorm = SettingsManager.isVolumeNormalizationEnabled;
                      return SettingsNavigationTile(
                        icon: Icons.graphic_eq_rounded,
                        iconColor: const Color(0xFF6366F1),
                        title: 'Audio Quality & Streaming',
                        subtitle: '$qualityLabel • Loudness Normalization ${isNorm ? "On" : "Off"}',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AudioQualitySettingsScreen()),
                          );
                        },
                      );
                    },
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  ValueListenableBuilder<String>(
                    valueListenable: SettingsManager.eqPresetNotifier,
                    builder: (context, preset, _) {
                      return SettingsNavigationTile(
                        icon: Icons.tune_rounded,
                        iconColor: const Color(0xFFA855F7),
                        title: '5-Band Hardware Equalizer',
                        subtitle: 'Preset: ${preset.toUpperCase()} • Frequency acoustic tuning',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const EqualizerSettingsScreen()),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // DOWNLOADS & STORAGE
              const SettingsSectionHeader(title: 'DOWNLOADS & STORAGE', icon: Icons.download_for_offline_rounded),
              const SizedBox(height: 10),
              SettingsHubContainer(
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      SettingsManager.downloadQualityNotifier,
                      SettingsManager.downloadWifiOnlyNotifier,
                      SettingsManager.downloadPathNotifier,
                    ]),
                    builder: (context, _) {
                      final quality = SettingsManager.downloadQuality;
                      final wifiOnly = SettingsManager.isDownloadWifiOnlyEnabled;
                      return SettingsNavigationTile(
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
                  ValueListenableBuilder<String>(
                    valueListenable: _cacheSizeNotifier,
                    builder: (context, cacheSizeStr, _) {
                      return SettingsNavigationTile(
                        icon: Icons.storage_rounded,
                        iconColor: const Color(0xFF06B6D4),
                        title: 'Storage & Cache Management',
                        subtitle: '$cacheSizeStr temporary cache • Disk allocation & cleaners',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const StorageSettingsScreen()),
                          );
                          _calculateCacheSize();
                        },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // DISPLAY & PREFERENCES
              const SettingsSectionHeader(title: 'DISPLAY & PREFERENCES', icon: Icons.palette_rounded),
              const SizedBox(height: 10),
              SettingsHubContainer(
                children: [
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
                      return SettingsNavigationTile(
                        icon: Icons.dashboard_customize_rounded,
                        iconColor: const Color(0xFF8B5CF6),
                        title: 'Home Feed & Experience',
                        subtitle: '$heroText Hero • $chartText • Privacy Mood Guard',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HomeSettingsScreen()),
                          );
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
                      return SettingsNavigationTile(
                        icon: Icons.brush_rounded,
                        iconColor: const Color(0xFFEC4899),
                        title: 'Appearance & Display',
                        subtitle: '${theme == "amoled" ? "AMOLED" : "Dark Slate"} • ${dynamicBg ? "Fluid Mesh" : "Static"} • Romanization ${romanize ? "On" : "Off"}',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()),
                          );
                        },
                      );
                    },
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  ValueListenableBuilder<List<String>>(
                    valueListenable: SettingsManager.languagesNotifier,
                    builder: (context, _, __) {
                      return SettingsNavigationTile(
                        icon: Icons.language_rounded,
                        iconColor: const Color(0xFF38BDF8),
                        title: 'Music Languages',
                        subtitle: SettingsManager.preferredLanguages.join(', '),
                        onTap: () => LanguagePreferencesModal.show(context),
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
                              return SettingsNavigationTile(
                                icon: Icons.block_rounded,
                                iconColor: Colors.redAccent,
                                title: "Don't Play This (Content Blocklist)",
                                subtitle: enabled
                                    ? 'Active (Default) • $songCount songs & $artistCount artists blocked'
                                    : 'Disabled • Blocked songs may play',
                                onTap: () => BlockedContentModal.show(context),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // SOCIAL & PARTY
              const SettingsSectionHeader(title: 'SOCIAL & PARTY SYNC', icon: Icons.speaker_group_rounded),
              const SizedBox(height: 10),
              SettingsHubContainer(
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: SettingsManager.hardwareAudioLatencyMsNotifier,
                    builder: (context, latency, _) {
                      final role = PartySyncCoordinator.role;
                      final statusStr = role == PartyRole.none ? 'Idle' : 'Active';
                      return SettingsNavigationTile(
                        icon: Icons.sync_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        title: 'Multi-Phone Party Sync & Latency',
                        subtitle: 'Lockstep ($statusStr) • Latency: ${latency}ms • Live NTP Diagnostics',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PartySyncSettingsScreen()),
                          );
                        },
                      );
                    },
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  SettingsNavigationTile(
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
                ],
              ),
              const SizedBox(height: 24),

              // SYSTEM & DIAGNOSTICS
              const SettingsSectionHeader(title: 'SYSTEM & DIAGNOSTICS', icon: Icons.settings_suggest_rounded),
              const SizedBox(height: 10),
              SettingsHubContainer(
                children: [
                  SettingsNavigationTile(
                    icon: Icons.battery_charging_full_rounded,
                    iconColor: const Color(0xFF10B981),
                    title: 'Battery & Background Playback',
                    subtitle: 'WakeLock guardrails & unthrottled position listener',
                    onTap: () => BatteryOptimizationModal.show(context),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  SettingsNavigationTile(
                    icon: Icons.bug_report_rounded,
                    iconColor: const Color(0xFF94A3B8),
                    title: 'Diagnostics & Telemetry Logs',
                    subtitle: 'Crash dumps, stream health, and runtime isolate metrics',
                    onTap: () => DiagnosticsModal.show(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ABOUT & CLOUD SYNC
              const SettingsSectionHeader(title: 'ABOUT', icon: Icons.info_outline_rounded),
              const SizedBox(height: 10),
              SettingsAboutCard(
                appVersion: _appVersion,
                gitCommit: _gitCommit,
                buildTime: _buildTime,
              ),
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
}
