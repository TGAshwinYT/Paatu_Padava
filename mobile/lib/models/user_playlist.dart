import 'package:uuid/uuid.dart';
import '../models/song.dart';
import '../services/supabase_service.dart';

class UserPlaylist {
  String id;
  String title;
  final int createdAt;
  List<Song> tracks;
  bool isCollaborative;
  String? inviteCode;
  String? ownerId;
  bool isBlend;
  String? blendPartnerName;
  int? tasteMatchScore;

  UserPlaylist({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.tracks,
    this.isCollaborative = false,
    this.inviteCode,
    this.ownerId,
    this.isBlend = false,
    this.blendPartnerName,
    this.tasteMatchScore,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'created_at': createdAt,
    'tracks': tracks.map((t) => t.toMap()).toList(),
    'is_collaborative': isCollaborative,
    'invite_code': inviteCode,
    'owner_id': ownerId,
    'is_blend': isBlend,
    'blend_partner_name': blendPartnerName,
    'taste_match_score': tasteMatchScore,
  };

  factory UserPlaylist.fromMap(Map<dynamic, dynamic> map) {
    final rawTracks = map['tracks'] as List<dynamic>? ?? [];
    return UserPlaylist(
      id: map['id']?.toString() ?? const Uuid().v4(),
      title: map['title']?.toString() ?? 'Untitled Playlist',
      createdAt: int.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
      tracks: rawTracks.map((t) => Song.fromMap(t as Map<dynamic, dynamic>)).toList(),
      isCollaborative: map['is_collaborative'] == true,
      inviteCode: map['invite_code']?.toString(),
      ownerId: map['owner_id']?.toString(),
      isBlend: map['is_blend'] == true,
      blendPartnerName: map['blend_partner_name']?.toString(),
      tasteMatchScore: (map['taste_match_score'] as num?)?.toInt(),
    );
  }

  UserPlaylist copyWith({
    String? id,
    String? title,
    int? createdAt,
    List<Song>? tracks,
    bool? isCollaborative,
    String? inviteCode,
    String? ownerId,
    bool? isBlend,
    String? blendPartnerName,
    int? tasteMatchScore,
  }) {
    return UserPlaylist(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      tracks: tracks ?? this.tracks,
      isCollaborative: isCollaborative ?? this.isCollaborative,
      inviteCode: inviteCode ?? this.inviteCode,
      ownerId: ownerId ?? this.ownerId,
      isBlend: isBlend ?? this.isBlend,
      blendPartnerName: blendPartnerName ?? this.blendPartnerName,
      tasteMatchScore: tasteMatchScore ?? this.tasteMatchScore,
    );
  }

  /// Whether current logged-in user owns this playlist
  bool get isOwner {
    final supaId = SupabaseService.currentUser?.id;
    if (ownerId == null || supaId == null) return true;
    return ownerId == supaId;
  }

  String get coverUrl => tracks.isNotEmpty ? tracks.first.coverUrl : '';
}
