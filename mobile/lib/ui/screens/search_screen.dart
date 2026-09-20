import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../services/saavn_client.dart';
import '../../services/youtube_client.dart';
import '../../services/player_handler.dart';
import '../../services/download_manager.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  String _searchSource = 'saavn'; // 'saavn' or 'youtube'
  List<Song> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  final List<String> _quickSuggestions = [
    'Anirudh Ravichander',
    'A.R. Rahman',
    'Harris Jayaraj',
    'Yuvan Shankar Raja',
    'Sid Sriram',
    'Ilayaraja',
    'Leo Songs',
    'Vikram Songs',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    List<Song> searchResults = [];
    if (_searchSource == 'saavn') {
      searchResults = await SaavnClient.search(clean, limit: 25);
    } else {
      searchResults = await YouTubeClient.search(clean, limit: 20);
    }

    if (mounted) {
      setState(() {
        _results = searchResults;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  onSubmitted: _executeSearch,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6366F1), size: 24),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),

            // Source Selector Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  _sourceTab(
                    label: '⚡ JioSaavn (320kbps HD)',
                    sourceKey: 'saavn',
                    icon: Icons.hd_rounded,
                  ),
                  const SizedBox(width: 8),
                  _sourceTab(
                    label: '▶ YouTube',
                    sourceKey: 'youtube',
                    icon: Icons.smart_display_rounded,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Search Results or Suggestions
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceTab({required String label, required String sourceKey, required IconData icon}) {
    final isSelected = _searchSource == sourceKey;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (_searchSource != sourceKey) {
            setState(() => _searchSource = sourceKey);
            if (_searchController.text.isNotEmpty) {
              _executeSearch(_searchController.text);
            }
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
      );
    }

    if (!_hasSearched) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Popular Searches',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: _quickSuggestions.map((tag) {
              return ActionChip(
                backgroundColor: const Color(0xFF1E293B),
                label: Text(tag, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
                onPressed: () {
                  _searchController.text = tag;
                  _executeSearch(tag);
                },
              );
            }).toList(),
          ),
        ],
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 50, color: Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(
              'No results for "${_searchController.text}"',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try switching between JioSaavn and YouTube tabs',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final song = _results[index];
        return _SearchResultTile(
          song: song,
          onTap: () => audioHandler.playSong(song, queue: _results),
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _SearchResultTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: audioHandler.currentSongNotifier,
      builder: (context, currentSong, _) {
        final isPlaying = currentSong?.id == song.id;

        return ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: song.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: song.coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF1E293B),
                            child: const Icon(Icons.music_note_rounded, color: Colors.white24),
                          ),
                        )
                      : Container(color: const Color(0xFF1E293B)),
                ),
              ),
              if (isPlaying)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.equalizer_rounded, color: Color(0xFF6366F1), size: 24),
                ),
            ],
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying ? const Color(0xFF6366F1) : Colors.white,
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: song.source == 'youtube'
                      ? Colors.redAccent.withOpacity(0.2)
                      : const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  song.source == 'youtube' ? 'YT' : '320K',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: song.source == 'youtube' ? Colors.redAccent : const Color(0xFF10B981),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          trailing: _SearchDownloadButton(song: song),
        );
      },
    );
  }
}

class _SearchDownloadButton extends StatelessWidget {
  final Song song;
  const _SearchDownloadButton({required this.song});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: DownloadManager.activeDownloads,
      builder: (context, activeDownloads, _) {
        final isDownloaded = DownloadManager.isDownloaded(song.id);
        final isDownloading = activeDownloads.containsKey(song.id);
        final progress = activeDownloads[song.id] ?? 0.0;

        if (isDownloaded) {
          return const IconButton(
            icon: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
            onPressed: null,
          );
        }

        if (isDownloading) {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                color: const Color(0xFF6366F1),
                strokeWidth: 2,
              ),
            ),
          );
        }

        return IconButton(
          icon: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF64748B), size: 22),
          onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading "${song.title}"...'),
                duration: const Duration(seconds: 1),
              ),
            );
            await DownloadManager.downloadSong(song);
          },
        );
      },
    );
  }
}
