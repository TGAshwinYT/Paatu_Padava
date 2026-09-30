import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'saavn_client.dart';
import 'settings_manager.dart';
import 'youtube_client.dart';

class DownloadManager {
  static const String boxName = 'offline_songs';
  static const int maxConcurrentDownloads = 2;

  static final Dio _dio = Dio();
  static final ValueNotifier<Map<String, double>> activeDownloads = ValueNotifier({});
  static final ValueNotifier<List<Song>> downloadedSongsNotifier = ValueNotifier<List<Song>>([]);
  static final ValueNotifier<int> queueLengthNotifier = ValueNotifier<int>(0);

  // Managed Concurrency Queue
  static final List<Song> _downloadQueue = [];
  static final Set<String> _activeDownloadSongIds = {};
  static final Map<String, CancelToken> _cancelTokens = {};

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
    downloadedSongsNotifier.value = getDownloadedSongs();
  }

  static Box get _box => Hive.box(boxName);

  static bool isDownloaded(String songId) {
    if (!Hive.isBoxOpen(boxName)) return false;
    return _box.containsKey(songId);
  }

  static bool isQueuedOrDownloading(String songId) {
    return _activeDownloadSongIds.contains(songId) || _downloadQueue.any((s) => s.id == songId);
  }

  static List<Song> getDownloadedSongs() {
    if (!Hive.isBoxOpen(boxName)) return [];
    final List<Song> songs = [];
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data != null && data is Map) {
        final song = Song.fromMap(data);
        // Verify local file exists on disk
        if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
          songs.add(song);
        }
      }
    }
    songs.sort((a, b) => (b.downloadedAt ?? 0).compareTo(a.downloadedAt ?? 0));
    return songs;
  }

  // ================= Concurrency Controlled Batch Operations ================= //

  /// Checks if all songs in a given collection are downloaded
  static bool areAllDownloaded(List<Song> songs) {
    if (songs.isEmpty) return false;
    return songs.every((s) => isDownloaded(s.id));
  }

  /// Counts how many songs in the list are downloaded
  static int getDownloadedCount(List<Song> songs) {
    return songs.where((s) => isDownloaded(s.id)).length;
  }

  /// Calculates aggregate batch progress (0.0 to 1.0)
  static double getBatchDownloadProgress(List<Song> songs) {
    if (songs.isEmpty) return 0.0;
    if (areAllDownloaded(songs)) return 1.0;

    double totalContribution = 0.0;
    final active = activeDownloads.value;

    for (final song in songs) {
      if (isDownloaded(song.id)) {
        totalContribution += 1.0;
      } else if (active.containsKey(song.id)) {
        totalContribution += active[song.id] ?? 0.0;
      }
    }

    return (totalContribution / songs.length).clamp(0.0, 1.0);
  }

  /// Returns true if any song in the given collection is currently downloading or in queue
  static bool isAnyDownloading(List<Song> songs) {
    return songs.any((s) => isQueuedOrDownloading(s.id));
  }

  /// Adds a list of songs to the managed download queue (batch download)
  static Future<void> downloadBatch(List<Song> songs) async {
    for (final song in songs) {
      if (!isDownloaded(song.id) && !isQueuedOrDownloading(song.id)) {
        _downloadQueue.add(song);
      }
    }
    queueLengthNotifier.value = _downloadQueue.length;
    _processQueue();
  }

  /// Cancels an active or queued download for a single song
  static void cancelDownload(String songId) {
    _downloadQueue.removeWhere((s) => s.id == songId);
    queueLengthNotifier.value = _downloadQueue.length;

    final token = _cancelTokens.remove(songId);
    if (token != null && !token.isCancelled) {
      token.cancel('Download cancelled by user');
    }

    _activeDownloadSongIds.remove(songId);

    final updated = Map<String, double>.from(activeDownloads.value);
    updated.remove(songId);
    activeDownloads.value = updated;

    _processQueue();
  }

  /// Cancels all active and queued downloads in a batch
  static void cancelBatch(List<Song> songs) {
    for (final song in songs) {
      cancelDownload(song.id);
    }
  }

  /// Internal queue processor enforcing maxConcurrentDownloads
  static void _processQueue() {
    while (_activeDownloadSongIds.length < maxConcurrentDownloads && _downloadQueue.isNotEmpty) {
      final nextSong = _downloadQueue.removeAt(0);
      queueLengthNotifier.value = _downloadQueue.length;
      _activeDownloadSongIds.add(nextSong.id);

      _executeSingleDownload(nextSong).whenComplete(() {
        _activeDownloadSongIds.remove(nextSong.id);
        _cancelTokens.remove(nextSong.id);
        _processQueue(); // Automatically trigger next waiting song
      });
    }
  }

  /// Direct single-song download entrypoint (adds to queue or downloads immediately)
  static Future<bool> downloadSong(Song song, {Function(double progress)? onProgress}) async {
    if (isDownloaded(song.id)) return true;
    if (isQueuedOrDownloading(song.id)) return true;

    _downloadQueue.add(song);
    queueLengthNotifier.value = _downloadQueue.length;
    _processQueue();
    return true;
  }

  /// Low-level worker that executes the download with CancelToken and bitrate scaling
  static Future<bool> _executeSingleDownload(Song song, {Function(double progress)? onProgress}) async {
    if (isDownloaded(song.id)) return true;

    final cancelToken = CancelToken();
    _cancelTokens[song.id] = cancelToken;

    try {
      // 1. Resolve Audio URL if not already present
      String? audioUrl = song.streamUrl;
      if (audioUrl == null || audioUrl.isEmpty) {
        if (song.source == 'youtube') {
          audioUrl = await YouTubeClient.getAudioStreamUrl(song.id);
        } else {
          final matches = await SaavnClient.search('${song.title} ${song.artist}', limit: 1);
          if (matches.isNotEmpty) {
            audioUrl = matches.first.streamUrl;
          }
        }
      }

      if (audioUrl == null || audioUrl.isEmpty) return false;
      if (cancelToken.isCancelled) return false;

      // Quality bitrate adjustments for JioSaavn download
      if (audioUrl.contains('jiosaavn') || audioUrl.contains('.mp4')) {
        final q = SettingsManager.downloadQuality;
        if (q == '96kbps') {
          audioUrl = audioUrl.replaceAll('_320.mp4', '_96.mp4').replaceAll('_160.mp4', '_96.mp4');
        } else if (q == '160kbps') {
          audioUrl = audioUrl.replaceAll('_320.mp4', '_160.mp4').replaceAll('_96.mp4', '_160.mp4');
        } else {
          audioUrl = audioUrl.replaceAll('_96.mp4', '_320.mp4').replaceAll('_160.mp4', '_320.mp4');
        }
      }

      // 2. Prepare Storage Directory
      final dir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${dir.path}/offline_audio');
      if (!audioDir.existsSync()) {
        audioDir.createSync(recursive: true);
      }

      final safeName = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final filePath = '${audioDir.path}/$safeName.mp3';

      // 3. Track active progress
      activeDownloads.value = {
        ...activeDownloads.value,
        song.id: 0.0,
      };

      await _dio.download(
        audioUrl,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && !cancelToken.isCancelled) {
            final p = received / total;
            activeDownloads.value = {
              ...activeDownloads.value,
              song.id: p,
            };
            onProgress?.call(p);
          }
        },
      );

      if (cancelToken.isCancelled) {
        // Clean up partial file if cancelled
        final partial = File(filePath);
        if (partial.existsSync()) partial.deleteSync();
        return false;
      }

      // 4. Save metadata to Hive
      final downloadedSong = song.copyWith(
        isDownloaded: true,
        localFilePath: filePath,
        downloadedAt: DateTime.now().millisecondsSinceEpoch,
        source: 'offline',
      );

      await _box.put(song.id, downloadedSong.toMap());
      downloadedSongsNotifier.value = getDownloadedSongs();

      // Clean up progress
      final updated = Map<String, double>.from(activeDownloads.value);
      updated.remove(song.id);
      activeDownloads.value = updated;

      return true;
    } catch (e) {
      final updated = Map<String, double>.from(activeDownloads.value);
      updated.remove(song.id);
      activeDownloads.value = updated;
      return false;
    }
  }

  // ================= Storage Inspection & Deletion ================= //

  static Future<void> deleteSong(String songId) async {
    cancelDownload(songId);

    if (Hive.isBoxOpen(boxName)) {
      final data = _box.get(songId);
      if (data != null && data is Map) {
        final path = data['localFilePath']?.toString();
        if (path != null) {
          final file = File(path);
          if (file.existsSync()) {
            file.deleteSync();
          }
        }
      }
      await _box.delete(songId);
    }

    downloadedSongsNotifier.value = getDownloadedSongs();
  }

  /// Deletes all downloaded songs and clears the storage box
  static Future<void> deleteAllDownloads() async {
    // Cancel all in-flight downloads
    for (final id in List<String>.from(_activeDownloadSongIds)) {
      cancelDownload(id);
    }
    _downloadQueue.clear();
    queueLengthNotifier.value = 0;

    // Delete all files in offline_audio directory
    try {
      final dir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${dir.path}/offline_audio');
      if (audioDir.existsSync()) {
        final files = audioDir.listSync();
        for (final file in files) {
          if (file is File) {
            try {
              file.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    if (Hive.isBoxOpen(boxName)) {
      await _box.clear();
    }

    downloadedSongsNotifier.value = [];
  }

  /// Returns file size in bytes for a specific song
  static int getSongFileSizeBytes(String songId) {
    if (!Hive.isBoxOpen(boxName)) return 0;
    final data = _box.get(songId);
    if (data != null && data is Map) {
      final path = data['localFilePath']?.toString();
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) {
          return file.lengthSync();
        }
      }
    }
    return 0;
  }

  /// Returns formatted file size for a specific song
  static String getSongFileSizeString(String songId) {
    final bytes = getSongFileSizeBytes(songId);
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Returns total size of all offline files in bytes
  static int getTotalOfflineSizeBytes() {
    int totalBytes = 0;
    for (final song in getDownloadedSongs()) {
      if (song.localFilePath != null) {
        final f = File(song.localFilePath!);
        if (f.existsSync()) {
          totalBytes += f.lengthSync();
        }
      }
    }
    return totalBytes;
  }

  static String getFormattedTotalSize() {
    final totalBytes = getTotalOfflineSizeBytes();
    final mb = totalBytes / (1024 * 1024);
    if (mb > 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}
