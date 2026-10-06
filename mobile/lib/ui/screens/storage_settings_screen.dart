import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/cache_manager.dart';
import '../../services/download_manager.dart';
import '../../services/settings_manager.dart';
import '../widgets/mini_player.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({Key? key}) : super(key: key);

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  StorageBreakdown? _breakdown;
  bool _isLoading = true;
  bool _isCleaning = false;

  @override
  void initState() {
    super.initState();
    _refreshStorage();
  }

  Future<void> _refreshStorage() async {
    setState(() => _isLoading = true);
    final breakdown = await CacheManager.getDetailedBreakdown();
    if (mounted) {
      setState(() {
        _breakdown = breakdown;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearImages() async {
    setState(() => _isCleaning = true);
    await CacheManager.clearImageCache();
    await _refreshStorage();
    if (mounted) {
      setState(() => _isCleaning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image cache cleared successfully')),
      );
    }
  }

  Future<void> _clearTempCache() async {
    setState(() => _isCleaning = true);
    await CacheManager.clearAllCache();
    await _refreshStorage();
    if (mounted) {
      setState(() => _isCleaning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Temporary audio & network cache cleared')),
      );
    }
  }

  Future<void> _deleteAllDownloads() async {
    final songsCount = _breakdown?.offlineSongCount ?? 0;
    final sizeStr = _breakdown?.offlineAudioFormatted ?? '0 MB';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete All Downloads?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently remove $songsCount downloaded tracks ($sizeStr) from your device storage. You will need an active internet connection to play them again.',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isCleaning = true);
      await DownloadManager.deleteAllDownloads();
      await _refreshStorage();
      if (mounted) {
        setState(() => _isCleaning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All downloaded tracks have been deleted')),
        );
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
        title: const Text(
          'Storage & Downloads',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh Storage Breakdown',
            onPressed: _isLoading || _isCleaning ? null : _refreshStorage,
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  children: [
                    _buildOverviewCard(),
                    const SizedBox(height: 24),
                    _buildQualityCard(),
                    const SizedBox(height: 24),
                    _buildCacheLimitCard(),
                    const SizedBox(height: 24),
                    _buildActionsCard(),
                    const SizedBox(height: 24),
                    _buildDownloadsExplorer(),
                    const SizedBox(height: 120),
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

  // ================= Storage Meter Overview ================= //

  Widget _buildOverviewCard() {
    final b = _breakdown;
    if (b == null) return const SizedBox.shrink();

    final total = b.totalAppBytes > 0 ? b.totalAppBytes.toDouble() : 1.0;
    final offlineRatio = (b.offlineAudioBytes / total).clamp(0.0, 1.0);
    final tempRatio = (b.tempCacheBytes / total).clamp(0.0, 1.0);
    final imageRatio = (b.imageCacheBytes / total).clamp(0.0, 1.0);
    final hiveRatio = (b.hiveDatabaseBytes / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total App Storage',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
              ),
              Text(
                b.totalAppFormatted,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Multi-Segmented Storage Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  if (offlineRatio > 0)
                    Expanded(
                      flex: (offlineRatio * 1000).toInt().clamp(1, 1000),
                      child: Container(color: const Color(0xFF6366F1)), // Indigo (Offline Audio)
                    ),
                  if (imageRatio > 0)
                    Expanded(
                      flex: (imageRatio * 1000).toInt().clamp(1, 1000),
                      child: Container(color: const Color(0xFF06B6D4)), // Cyan (Images)
                    ),
                  if (tempRatio > 0)
                    Expanded(
                      flex: (tempRatio * 1000).toInt().clamp(1, 1000),
                      child: Container(color: const Color(0xFFF59E0B)), // Amber (Temp Cache)
                    ),
                  if (hiveRatio > 0)
                    Expanded(
                      flex: (hiveRatio * 1000).toInt().clamp(1, 1000),
                      child: Container(color: const Color(0xFFA855F7)), // Purple (Database)
                    ),
                  if (b.totalAppBytes == 0)
                    Expanded(
                      child: Container(color: const Color(0xFF334155)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Legend Items
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _buildLegendItem(const Color(0xFF6366F1), 'Offline Music', b.offlineAudioFormatted),
              _buildLegendItem(const Color(0xFF06B6D4), 'Image Cache', b.imageCacheFormatted),
              _buildLegendItem(const Color(0xFFF59E0B), 'Stream Cache', b.tempCacheFormatted),
              _buildLegendItem(const Color(0xFFA855F7), 'Local Database', b.hiveDatabaseFormatted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, String size) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        Text(
          size,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ================= Quality Selector ================= //

  Widget _buildQualityCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.high_quality_rounded, color: Color(0xFF818CF8), size: 20),
              SizedBox(width: 8),
              Text(
                'Download Audio Quality',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Higher quality audio uses more disk space per song.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildQualityChip('96kbps', 'Saver (~2.5 MB)'),
              const SizedBox(width: 8),
              _buildQualityChip('160kbps', 'Standard (~4.5 MB)'),
              const SizedBox(width: 8),
              _buildQualityChip('320kbps', 'Extreme (~9.0 MB)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQualityChip(String quality, String subtitle) {
    final isSelected = SettingsManager.downloadQuality == quality;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          await SettingsManager.setDownloadQuality(quality);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.2) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.05),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                quality,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF818CF8) : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= Cache Limit Settings ================= //

  Widget _buildCacheLimitCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.storage_rounded, color: Color(0xFF10B981), size: 20),
              SizedBox(width: 8),
              Text(
                'Maximum Cache Size (LRU Limit)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Automatically purges least recently listened streaming cache when this limit is exceeded.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<int>(
            valueListenable: SettingsManager.maxCacheSizeMbNotifier,
            builder: (context, limitMb, _) {
              return Row(
                children: [
                  _buildLimitChip(250, '250 MB', limitMb),
                  const SizedBox(width: 8),
                  _buildLimitChip(500, '500 MB', limitMb),
                  const SizedBox(width: 8),
                  _buildLimitChip(1000, '1.0 GB', limitMb),
                  const SizedBox(width: 8),
                  _buildLimitChip(2000, '2.0 GB', limitMb),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLimitChip(int mb, String label, int currentLimit) {
    final isSelected = currentLimit == mb;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          await SettingsManager.setMaxCacheSizeMb(mb);
          await CacheManager.autoEvictOldCache();
          await _refreshStorage();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.05),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF34D399) : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================= Cache Actions ================= //

  Widget _buildActionsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Text(
              'Storage Cleaners',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined, color: Color(0xFF06B6D4)),
            title: const Text('Clear Image Cache', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: Text(
              'Frees ${_breakdown?.imageCacheFormatted ?? "0 MB"} of artwork cache',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isCleaning ? null : _clearImages,
              child: const Text('Clear'),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            leading: const Icon(Icons.cleaning_services_rounded, color: Color(0xFFF59E0B)),
            title: const Text('Clear Temporary Stream Cache', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: Text(
              'Frees ${_breakdown?.tempCacheFormatted ?? "0 MB"} of stream chunks',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isCleaning ? null : _clearTempCache,
              child: const Text('Clear'),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            title: const Text('Delete All Downloads', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Deletes ${_breakdown?.offlineSongCount ?? 0} downloaded songs (${_breakdown?.offlineAudioFormatted ?? "0 MB"})',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                foregroundColor: Colors.redAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isCleaning || (_breakdown?.offlineSongCount ?? 0) == 0 ? null : _deleteAllDownloads,
              child: const Text('Delete All'),
            ),
          ),
        ],
      ),
    );
  }

  // ================= Downloads Explorer ================= //

  Widget _buildDownloadsExplorer() {
    return ValueListenableBuilder<List<Song>>(
      valueListenable: DownloadManager.downloadedSongsNotifier,
      builder: (context, downloadedSongs, _) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Downloaded Tracks (${downloadedSongs.length})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      _breakdown?.offlineAudioFormatted ?? '',
                      style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (downloadedSongs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  child: Center(
                    child: Column(
                      children: const [
                        Icon(Icons.download_done_rounded, color: Color(0xFF64748B), size: 40),
                        SizedBox(height: 12),
                        Text(
                          'No offline tracks downloaded yet',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap "Download All" on albums or playlists for instant offline listening.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: downloadedSongs.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final song = downloadedSongs[index];
                    final sizeStr = DownloadManager.getSongFileSizeString(song.id);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: song.coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: song.coverUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 44,
                                  height: 44,
                                  color: const Color(0xFF1E293B),
                                  child: const Icon(Icons.music_note, color: Colors.white54, size: 20),
                                ),
                              )
                            : Container(
                                width: 44,
                                height: 44,
                                color: const Color(0xFF1E293B),
                                child: const Icon(Icons.music_note, color: Colors.white54, size: 20),
                              ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${song.artist} • $sizeStr',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                        tooltip: 'Delete track',
                        onPressed: () async {
                          await DownloadManager.deleteSong(song.id);
                          await _refreshStorage();
                        },
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
