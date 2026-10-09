import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../services/player_handler.dart';
import '../../../services/api_client.dart';

class WrongLyricsSheet {
  static Future<void> show(BuildContext context, Song? song) async {
    final searchController = TextEditingController(text: song != null ? '${song.title} ${song.artist}' : '');
    try {
      List<Map<String, dynamic>> searchResults = [];
      bool isSearching = false;

      await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void performSearch() async {
              final q = searchController.text.trim();
              if (q.isEmpty) return;
              setSheetState(() => isSearching = true);
              final results = await ApiClient.searchLyricsCandidates(q);
              setSheetState(() {
                searchResults = results;
                isSearching = false;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Lyrics Search & Picker',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => performSearch(),
                      decoration: InputDecoration(
                        hintText: 'Search title or artist...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF818CF8)),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF818CF8)),
                          onPressed: performSearch,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isSearching)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF818CF8))),
                      )
                    else if (searchResults.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.manage_search_rounded, size: 48, color: Colors.white24),
                              const SizedBox(height: 10),
                              const Text('Search for synced LRC or plain lyrics', style: TextStyle(color: Colors.white54)),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.paste_rounded, size: 16),
                                label: const Text('Paste Custom Lyrics / LRC'),
                                onPressed: () {
                                  Navigator.pop(context);
                                  showPasteCustomLyricsDialog(context, song);
                                },
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: searchResults.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                          itemBuilder: (context, i) {
                            final item = searchResults[i];
                            final track = item['trackName'] ?? item['name'] ?? 'Unknown';
                            final artist = item['artistName'] ?? 'Unknown';
                            final album = item['albumName'] ?? '';
                            final synced = item['syncedLyrics']?.toString();
                            final plain = item['plainLyrics']?.toString();
                            final isSynced = synced != null && synced.trim().isNotEmpty;
                            final chosen = isSynced ? synced : plain;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              title: Text(
                                track,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Text(
                                '$artist • $album',
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSynced ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.white12,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isSynced ? 'Synced LRC' : 'Plain Text',
                                  style: TextStyle(
                                    color: isSynced ? const Color(0xFF34D399) : Colors.white60,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              onTap: () {
                                if (chosen != null && chosen.trim().isNotEmpty) {
                                  audioHandler.setCustomLyrics(chosen);
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Lyrics updated for track')),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    } finally {
      searchController.dispose();
    }
  }

  static Future<void> showPasteCustomLyricsDialog(BuildContext context, Song? song) async {
    final pasteController = TextEditingController();
    try {
      await showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            title: const Text('Paste Custom Lyrics', style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: pasteController,
              maxLines: 8,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Paste synced [mm:ss.xx] or plain lyrics here...',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                onPressed: () {
                  final txt = pasteController.text.trim();
                  if (txt.isNotEmpty) {
                    audioHandler.setCustomLyrics(txt);
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      );
    } finally {
      pasteController.dispose();
    }
  }
}
