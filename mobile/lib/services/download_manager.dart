import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';

class DownloadManager {
  static const String boxName = 'offline_songs';
  static final Dio _dio = Dio();
  static final ValueNotifier<Map<String, double>> activeDownloads = ValueNotifier({});

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(boxName);
  }

  static Box get _box => Hive.box(boxName);

  static bool isDownloaded(String songId) {
    return _box.containsKey(songId);
  }

  static List<Song> getDownloadedSongs() {
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

  static Future<bool> downloadSong(Song song, {Function(double progress)? onProgress}) async {
    if (isDownloaded(song.id)) return true;

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
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final p = received / total;
            activeDownloads.value = {
              ...activeDownloads.value,
              song.id: p,
            };
            onProgress?.call(p);
          }
        },
      );

      // 4. Save metadata to Hive
      final downloadedSong = song.copyWith(
        isDownloaded: true,
        localFilePath: filePath,
        downloadedAt: DateTime.now().millisecondsSinceEpoch,
        source: 'offline',
      );

      await _box.put(song.id, downloadedSong.toMap());

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

  static Future<void> deleteSong(String songId) async {
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

  static String getFormattedTotalSize() {
    double totalBytes = 0;
    for (final song in getDownloadedSongs()) {
      if (song.localFilePath != null) {
        final f = File(song.localFilePath!);
        if (f.existsSync()) {
          totalBytes += f.lengthSync();
        }
      }
    }
    final mb = totalBytes / (1024 * 1024);
    if (mb > 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}
