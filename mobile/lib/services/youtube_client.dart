import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';

class YouTubeClient {
  static final YoutubeExplode _yt = YoutubeExplode();

  static Future<List<Song>> search(String query, {int limit = 15}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final searchResults = await _yt.search.search(clean);
      final List<Song> songs = [];

      for (final video in searchResults.take(limit)) {
        songs.add(Song(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          album: 'YouTube',
          coverUrl: video.thumbnails.highResUrl,
          duration: video.duration?.inSeconds ?? 0,
          source: 'youtube',
        ));
      }
      return songs;
    } catch (e) {
      return [];
    }
  }

  static Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) return null;

      // Select highest quality audio stream
      final bestAudio = audioStreams.withHighestBitrate();
      return bestAudio.url.toString();
    } catch (e) {
      return null;
    }
  }

  static void dispose() {
    _yt.close();
  }
}
