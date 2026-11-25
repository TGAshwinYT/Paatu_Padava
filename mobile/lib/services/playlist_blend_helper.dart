import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import 'auth_manager.dart';
import 'collaborative_playlist_service.dart';
import 'playlist_manager.dart';

/// Builds and persists Spotify-style Blend playlists.
class PlaylistBlendHelper {
  static Future<UserPlaylist> createBlendPlaylist({
    required String partnerName,
    required List<Song> userTracks,
    required List<Song> partnerTracks,
    int? customTasteMatch,
  }) async {
    int matchScore = customTasteMatch ?? 0;
    if (matchScore <= 0) {
      final userArtists = userTracks.map((s) => s.artist.toLowerCase()).toSet();
      final partnerArtists = partnerTracks.map((s) => s.artist.toLowerCase()).toSet();
      final intersection = userArtists.intersection(partnerArtists);
      if (userArtists.isEmpty && partnerArtists.isEmpty) {
        matchScore = 86;
      } else {
        final totalUnique = userArtists.union(partnerArtists).length;
        final base = totalUnique > 0 ? ((intersection.length / totalUnique) * 100).round() : 75;
        matchScore = (base + 66).clamp(68, 98);
      }
    }

    final mergedTracks = <Song>[];
    final maxLen = max(userTracks.length, partnerTracks.length);
    for (int i = 0; i < maxLen; i++) {
      if (i < userTracks.length) {
        mergedTracks.add(userTracks[i].copyWith(addedBy: 'You'));
      }
      if (i < partnerTracks.length) {
        mergedTracks.add(partnerTracks[i].copyWith(addedBy: partnerName));
      }
    }

    final scope = AuthManager.isLoggedIn ? PlaylistScope.account : PlaylistScope.guest;
    final blend = UserPlaylist(
      id: const Uuid().v4(),
      title: '$partnerName + You',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      tracks: mergedTracks,
      isCollaborative: true,
      inviteCode: CollaborativePlaylistService.generateInviteCode(),
      ownerId: AuthManager.isLoggedIn ? AuthManager.currentUser?.id : null,
      isBlend: true,
      blendPartnerName: partnerName,
      tasteMatchScore: matchScore,
    );

    await PlaylistManager.savePlaylistDirectly(blend, scope: scope);
    return blend;
  }
}
