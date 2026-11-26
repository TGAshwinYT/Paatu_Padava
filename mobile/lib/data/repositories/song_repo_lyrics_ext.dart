part of 'song_repository.dart';

Future<LyricsState> _getLyricsImpl({
  required String trackId,
  required String title,
  required String artist,
  String? album,
  int durationSeconds = 0,
}) {
  return LyricsClient.instance.fetchLyrics(
    trackId: trackId,
    title: title,
    artist: artist,
    album: album,
    durationSeconds: durationSeconds,
  );
}

Future<LyricsState> _getLyricsForSongImpl(Song song) {
  int duration = song.duration;
  if (duration <= 0) {
    final currentMediaItem = audioHandler.mediaItem.value;
    if (currentMediaItem?.id == song.id) {
      duration = audioHandler.player.duration?.inSeconds ?? 0;
    }
  }
  return SongRepository.getLyrics(
    trackId: song.id,
    title: song.title,
    artist: song.artist,
    album: song.album,
    durationSeconds: duration,
  );
}

Future<List<Map<String, dynamic>>> _searchLyricsCandidatesImpl(String query) =>
    ApiClient.searchLyricsCandidates(query);

bool _isLanguageMismatchImpl(Song song, String targetLanguage) {
  final rawTarget = targetLanguage.toLowerCase().trim();
  if (rawTarget.isEmpty) return false;

  // Devanagari script family: authentic match for Hindi, Marathi, Bhojpuri, Sanskrit, etc.
  if (rawTarget == 'devanagari') {
    if (song.language != null && song.language!.isNotEmpty) {
      final sLang = song.language!.toLowerCase().trim();
      if (SongRepository._devanagariLanguages.contains(sLang) || sLang == 'devanagari') {
        return false;
      }
      return true;
    }
    final combined = '${song.title} ${song.artist} ${song.album}'.toLowerCase();
    if (RegExp(r'[\u0B80-\u0BFF\u0C00-\u0C7F\u0D00-\u0D7F\u0C80-\u0CFF]').hasMatch(combined)) {
      return true;
    }
    return false;
  }

  final target = rawTarget;

  // 1. Explicit metadata language check from Saavn/API
  if (song.language != null && song.language!.isNotEmpty) {
    final sLang = song.language!.toLowerCase().trim();
    final normSongLang = sLang == 'devanagari' ? 'hindi' : sLang;
    if (normSongLang != target) {
      if (target == 'english' && sLang == 'english') return false;
      return true;
    }
  }

  // 2. Text and script analysis on title, artist, and album
  final combined = '${song.title} ${song.artist} ${song.album}'.toLowerCase();

  if (target == 'tamil') {
    if (RegExp(r'[\u0900-\u097F\u0C00-\u0C7F\u0D00-\u0D7F\u0C80-\u0CFF]').hasMatch(combined)) {
      return true;
    }
    final titleAndArtist = '${song.title} ${song.artist}'.toLowerCase();
    if (RegExp(r'\b(hindi|bollywood|bhojpuri|punjabi|telugu|malayalam|kannada)\b').hasMatch(titleAndArtist)) {
      if (!titleAndArtist.contains('tamil')) {
        return true;
      }
    }
    if (!ArtistSanitizer.isGenuineArtist(song.artist)) {
      return true;
    }
    if (song.language == 'english' || song.language == 'hindi') {
      return true;
    }
  } else if (target == 'telugu') {
    if (RegExp(r'[\u0900-\u097F\u0B80-\u0BFF\u0D00-\u0D7F\u0C80-\u0CFF]').hasMatch(combined)) {
      return true;
    }
    if (RegExp(r'\b(hindi|bollywood|tamil|malayalam|kannada|punjabi)\b').hasMatch(combined) && !combined.contains('telugu')) {
      return true;
    }
  } else if (target == 'malayalam') {
    if (RegExp(r'[\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF]').hasMatch(combined)) {
      return true;
    }
    if (RegExp(r'\b(hindi|bollywood|tamil|telugu|kannada|punjabi)\b').hasMatch(combined) && !combined.contains('malayalam')) {
      return true;
    }
  } else if (target == 'hindi') {
    if (RegExp(r'[\u0B80-\u0BFF\u0C00-\u0C7F\u0D00-\u0D7F\u0C80-\u0CFF]').hasMatch(combined)) {
      return true;
    }
    if (RegExp(r'\b(tamil|telugu|malayalam|kannada)\b').hasMatch(combined) && !combined.contains('hindi')) {
      return true;
    }
  } else if (target == 'kannada') {
    if (RegExp(r'[\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0D00-\u0D7F]').hasMatch(combined)) {
      return true;
    }
    if (RegExp(r'\b(hindi|bollywood|tamil|telugu|malayalam|punjabi)\b').hasMatch(combined) && !combined.contains('kannada')) {
      return true;
    }
  }

  return false;
}
