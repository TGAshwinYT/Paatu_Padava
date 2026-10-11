import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/auth_manager.dart';
import '../../services/cache_manager.dart';
import '../../services/supabase_service.dart';
import '../../services/party_sync_coordinator.dart';
import '../../services/settings_manager.dart';
import '../widgets/mini_player.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/settings/language_settings_card.dart';
import '../widgets/settings/battery_settings_card.dart';
import '../widgets/settings/diagnostics_settings_card.dart';
import 'audio_quality_settings_screen.dart';
import 'downloads_settings_screen.dart';
import 'storage_settings_screen.dart';
import 'appearance_settings_screen.dart';
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
      backgroundColor: const Color(0xFF0A0E1A),
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
                ValueListenableBuilder<String>(
                  valueListenable: SettingsManager.streamingQualityNotifier,
                  builder: (context, quality, _) {
                    final isNorm = SettingsManager.isVolumeNormalizationEnabled;
                    return _buildNavigationTile(
                      icon: Icons.graphic_eq_rounded,
                      iconColor: const Color(0xFF6366F1),
                      title: 'Audio Quality & Streaming',
                      subtitle: '$quality • Loudness Normalization ${isNorm ? "On" : "Off"}',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AudioQualitySettingsScreen()),
                        );
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
                          MaterialPageRoute(builder: (_) => const AudioQualitySettingsScreen()),
                        );
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
                ValueListenableBuilder<String>(
                  valueListenable: SettingsManager.downloadQualityNotifier,
                  builder: (context, quality, _) {
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
                ValueListenableBuilder<String>(
                  valueListenable: SettingsManager.themeModeNotifier,
                  builder: (context, theme, _) {
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
                        setState(() {});
                      },
                    );
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                _buildNavigationTile(
                  icon: Icons.language_rounded,
                  iconColor: const Color(0xFF38BDF8),
                  title: 'Music Languages',
                  subtitle: SettingsManager.preferredLanguages.join(', '),
                  onTap: () => _showLanguageModal(context),
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

  void _showLanguageModal(BuildContext context) {
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
            const LanguageSettingsCard(),
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
            const BatterySettingsCard(),
          ],
        ),
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
            const DiagnosticsSettingsCard(),
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
