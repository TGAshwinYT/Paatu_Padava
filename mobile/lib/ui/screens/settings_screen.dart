import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide CacheManager;
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/settings_manager.dart';
import '../../services/auth_manager.dart';
import '../../services/equalizer_service.dart';
import '../../services/cache_manager.dart';
import '../../services/supabase_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/auth_dialog.dart';
import 'storage_settings_screen.dart';
import 'listening_recap_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _cacheSizeStr = 'Calculating...';
  bool _isClearing = false;
  String _appVersion = 'Version 2.0.0 (Release)';

  static const String _gitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: '');
  static const String _buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: '');

  final List<String> _allLanguages = [
    'Tamil',
    'Hindi',
    'Telugu',
    'Malayalam',
    'Kannada',
    'English',
    'Punjabi',
    'Bengali',
  ];

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
          _appVersion = 'Version 2.0.0 (Release)';
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

  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    try {
      await DefaultCacheManager().emptyCache();
      await CacheManager.clearAllCache();
      await _calculateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
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
          'Settings & Audio',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              // User Account Header
              _buildAccountCard(),
              const SizedBox(height: 20),

              // Audio Quality Section
              _buildSectionHeader('AUDIO QUALITY & STREAMING', Icons.graphic_eq_rounded),
              const SizedBox(height: 10),
              _buildAudioQualityCard(),
              const SizedBox(height: 20),

              // Equalizer Section
              _buildSectionHeader('5-BAND EQUALIZER', Icons.tune_rounded),
              const SizedBox(height: 10),
              _buildEqualizerCard(),
              const SizedBox(height: 20),

              // Languages Section
              _buildSectionHeader('MUSIC PREFERENCES', Icons.language_rounded),
              const SizedBox(height: 10),
              _buildLanguagesCard(),
              const SizedBox(height: 20),

              // Storage & Cache Section
              _buildSectionHeader('STORAGE & CACHE', Icons.storage_rounded),
              const SizedBox(height: 10),
              _buildStorageCard(),
              const SizedBox(height: 20),

              // Listening Recap & Wrapped Section
              _buildSectionHeader('YOUR STATS & WRAPPED', Icons.auto_awesome),
              const SizedBox(height: 10),
              _buildRecapCard(),
              const SizedBox(height: 20),

              // About Section
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

  Widget _buildAccountCard() {
    final isLoggedIn = AuthManager.isLoggedIn;
    final user = AuthManager.user;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF6366F1),
            child: Text(
              isLoggedIn && user != null ? user.username.substring(0, 1).toUpperCase() : 'G',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoggedIn && user != null ? user.username : 'Guest Session',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  isLoggedIn && user != null ? user.email : 'Local offline mode active',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
              ],
            ),
          ),
          if (isLoggedIn)
            TextButton(
              onPressed: () async {
                await AuthManager.logout();
                if (mounted) setState(() {});
              },
              child: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
            )
          else
            TextButton(
              onPressed: () async {
                await AuthDialog.show(context);
                if (mounted) setState(() {});
              },
              child: const Text(
                'Sign In',
                style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioQualityCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.volumeNormalizationNotifier,
            builder: (context, isEnabled, _) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                activeColor: const Color(0xFF6366F1),
                title: const Text(
                  'Loudness Normalization (ReplayGain)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Standardizes loudness (-14 LUFS) between YouTube & 320k master streams to prevent volume jumps',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                value: isEnabled,
                onChanged: (val) => SettingsManager.setVolumeNormalization(val),
              );
            },
          ),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
          ValueListenableBuilder<int>(
            valueListenable: SettingsManager.crossfadeDurationNotifier,
            builder: (context, crossfadeSec, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Crossfade Transitions',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        Text(
                          crossfadeSec == 0 ? 'Off (Gapless)' : '${crossfadeSec}s',
                          style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Smoothly blends and fades volume between consecutive songs',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF6366F1),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: crossfadeSec.toDouble(),
                        min: 0.0,
                        max: 12.0,
                        divisions: 12,
                        onChanged: (val) => SettingsManager.setCrossfadeSeconds(val.round()),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
          ValueListenableBuilder<String>(
            valueListenable: SettingsManager.streamingQualityNotifier,
            builder: (context, streamingQuality, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'Streaming Bitrate Quality',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  _buildQualityRadioTile(
                    title: 'Lossless 320 kbps',
                    subtitle: 'Studio fidelity audio streaming (Recommended)',
                    value: '320kbps',
                    groupValue: streamingQuality,
                    onChanged: (val) => SettingsManager.setStreamingQuality(val!),
                  ),
                  _buildQualityRadioTile(
                    title: 'High 160 kbps',
                    subtitle: 'Balanced clarity and moderate data consumption',
                    value: '160kbps',
                    groupValue: streamingQuality,
                    onChanged: (val) => SettingsManager.setStreamingQuality(val!),
                  ),
                  _buildQualityRadioTile(
                    title: 'Normal 96 kbps',
                    subtitle: 'Data saving mode for weak mobile networks',
                    value: '96kbps',
                    groupValue: streamingQuality,
                    onChanged: (val) => SettingsManager.setStreamingQuality(val!),
                  ),
                ],
              );
            },
          ),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
          ValueListenableBuilder<String>(
            valueListenable: SettingsManager.downloadQualityNotifier,
            builder: (context, downloadQuality, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Download Quality', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        SizedBox(height: 2),
                        Text('Target bitrate for offline downloads', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      ],
                    ),
                    DropdownButton<String>(
                      value: downloadQuality,
                      dropdownColor: const Color(0xFF1E293B),
                      underline: const SizedBox(),
                      style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: '320kbps', child: Text('320 kbps')),
                        DropdownMenuItem(value: '160kbps', child: Text('160 kbps')),
                        DropdownMenuItem(value: '96kbps', child: Text('96 kbps')),
                      ],
                      onChanged: (val) {
                        if (val != null) SettingsManager.setDownloadQuality(val);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQualityRadioTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      activeColor: const Color(0xFF6366F1),
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
    );
  }

  Widget _buildEqualizerCard() {
    final bandLabels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Presets chips
          ValueListenableBuilder<String>(
            valueListenable: SettingsManager.eqPresetNotifier,
            builder: (context, currentPreset, _) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPresetChip('Flat', 'flat', currentPreset),
                    _buildPresetChip('Bass Boost', 'bass_boost', currentPreset),
                    _buildPresetChip('Vocal', 'vocal', currentPreset),
                    _buildPresetChip('Rock', 'rock', currentPreset),
                    _buildPresetChip('Pop', 'pop', currentPreset),
                    _buildPresetChip('Classical', 'classical', currentPreset),
                    _buildPresetChip('Electronic', 'electronic', currentPreset),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // 5 Band Sliders
          ValueListenableBuilder<List<double>>(
            valueListenable: SettingsManager.eqBandsNotifier,
            builder: (context, bands, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(5, (index) {
                  final gain = (index < bands.length) ? bands[index] : 0.0;
                  return Column(
                    children: [
                      Text(
                        '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}dB',
                        style: const TextStyle(color: Color(0xFF818CF8), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(
                        height: 140,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF6366F1),
                              inactiveTrackColor: Colors.white12,
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: gain,
                              min: -10.0,
                              max: 10.0,
                              onChanged: (val) {
                                SettingsManager.setEqBand(index, val);
                                EqualizerService.setBandLevel(index, val);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bandLabels[index],
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      ),
                    ],
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                EqualizerService.isBound
                    ? 'Native DSP: Active (Session #${EqualizerService.activeSessionId})'
                    : 'Native DSP: Connected',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              TextButton.icon(
                icon: const Icon(Icons.settings_voice_rounded, size: 16, color: Color(0xFF6366F1)),
                label: const Text('System Equalizer', style: TextStyle(color: Color(0xFF6366F1), fontSize: 12)),
                onPressed: () => EqualizerService.openSystemEqualizer(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String presetKey, String currentPreset) {
    final isSelected = currentPreset == presetKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF6366F1),
        backgroundColor: const Color(0xFF1E293B),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (_) {
          SettingsManager.setEqPreset(presetKey);
          EqualizerService.applyCurrentBands();
        },
      ),
    );
  }

  Widget _buildLanguagesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
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
                children: _allLanguages.map((lang) {
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

  Widget _buildStorageCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StorageSettingsScreen()),
            );
            _calculateCacheSize();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.storage_rounded, color: Color(0xFF818CF8), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Storage & Offline Downloads',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Temporary cache: $_cacheSizeStr • Tap to manage space',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  Widget _buildRecapCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6366F1).withOpacity(0.18),
            const Color(0xFFEC4899).withOpacity(0.12),
            const Color(0xFF131B2E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF818CF8).withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ListeningRecapScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paatu Recap & Music Wrapped',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Relive your top songs, artists & listening persona in story mode',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFA5B4FC), size: 16),
              ],
            ),
          ),
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
      pillText = 'Cloud Sync: Offline (Secrets not baked into this APK)';
    } else if (!isInitialized) {
      final err = SupabaseService.initError;
      pillText = (err != null && err.isNotEmpty)
          ? 'Cloud Sync: Offline (Failed to start: $err)'
          : 'Cloud Sync: Offline (Supabase failed to start)';
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
        border: Border.all(color: Colors.white.withOpacity(0.06)),
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
              color: isHealthy ? const Color(0xFF10B981).withOpacity(0.12) : const Color(0xFFEF4444).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isHealthy ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFFEF4444).withOpacity(0.3),
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
