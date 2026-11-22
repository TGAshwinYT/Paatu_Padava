import 'package:flutter/material.dart';
import '../../../services/blacklist_manager.dart';

/// Modal bottom sheet for viewing and unblocking blacklisted tracks & artists
class BlockedContentModal {
  static void show(BuildContext context) {
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
}
