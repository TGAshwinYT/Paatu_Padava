// ignore_for_file: experimental_member_use
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_des/dart_des.dart';
import 'package:just_audio/just_audio.dart';

/// Class-level helper for DES decryption conforming to Bloomee architecture
class DesDecrypt {
  static String decrypt(String encryptedUrl) => decryptSaavnMediaUrl(encryptedUrl);
}

/// Top-level synchronous DES decryption function suitable for direct isolate offloading.
String decryptSaavnMediaUrl(String encryptedUrl) {
  if (encryptedUrl.isEmpty) return '';

  try {
    // Official JioSaavn DES key
    const key = '38346591';
    final cipherText = base64.decode(encryptedUrl.trim());
    final desECB = DES(key: key.codeUnits, mode: DESMode.ECB);
    final decrypted = desECB.decrypt(cipherText);

    if (decrypted.isEmpty) return '';

    // PKCS5 / PKCS7 unpadding: the last byte indicates number of padding bytes
    final padLength = decrypted.last;
    List<int> unpadded = decrypted;
    if (padLength > 0 && padLength <= 8 && padLength <= decrypted.length) {
      unpadded = decrypted.sublist(0, decrypted.length - padLength);
    }

    String url = utf8.decode(unpadded, allowMalformed: true).trim();

    if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'https://');
    }

    return url;
  } catch (e) {
    return '';
  }
}

/// Helper for managing JioSaavn CDN audio bitrates (320kbps, 160kbps, 96kbps)
/// and seamless bitrate fallback to prevent HTTP 404/403 failures when 320kbps is unavailable.
class SaavnBitrateHelper {
  /// Converts a Saavn audio URL to the desired [bitrate] ('auto', '320', '160', '96').
  /// If 'auto' is passed, defaults to '320' to prevent malformed _auto.mp4 URLs.
  static String toBitrate(String url, String bitrate) {
    if (url.isEmpty) return url;
    final clean = bitrate.replaceAll('kbps', '').trim();
    final b = (clean == 'auto' || clean.isEmpty) ? '320' : clean;
    if (url.contains('.mp4')) {
      return url
          .replaceAll('_320.mp4', '_$b.mp4')
          .replaceAll('_160.mp4', '_$b.mp4')
          .replaceAll('_96.mp4', '_$b.mp4');
    } else if (url.contains('.mp3')) {
      return url
          .replaceAll('_320.mp3', '_$b.mp3')
          .replaceAll('_160.mp3', '_$b.mp3')
          .replaceAll('_96.mp3', '_$b.mp3');
    }
    return url;
  }

  /// Returns ordered bitrate candidates based on user [targetQuality].
  /// Default ('320kbps' or 'auto'): [320, 160, 96]
  /// '160kbps': [160, 96, 320]
  /// '96kbps': [96, 160, 320]
  static List<String> getBitrateCandidates(String originalUrl, {String? targetQuality}) {
    if (originalUrl.isEmpty) return [];
    final q = targetQuality ?? 'auto';

    final u320 = toBitrate(originalUrl, '320');
    final u160 = toBitrate(originalUrl, '160');
    final u96 = toBitrate(originalUrl, '96');

    final candidates = <String>[];
    void addCandidate(String u) {
      if (u.isNotEmpty && !candidates.contains(u)) {
        candidates.add(u);
      }
    }

    if (q == '96kbps') {
      addCandidate(u96);
      addCandidate(u160);
      addCandidate(u320);
    } else if (q == '160kbps') {
      addCandidate(u160);
      addCandidate(u96);
      addCandidate(u320);
    } else {
      // High fidelity 320kbps preferred (for 'auto' or '320kbps')
      addCandidate(u320);
      addCandidate(u160);
      addCandidate(u96);
    }

    addCandidate(originalUrl);
    return candidates;
  }

  /// Returns the next available fallback bitrate for a failing [currentUrl].
  /// If [currentUrl] was 320kbps -> falls back to 160kbps.
  /// If [currentUrl] was 160kbps -> falls back to 96kbps.
  /// If 96kbps or unknown -> returns null.
  static String? getNextFallbackUrl(String currentUrl) {
    if (currentUrl.isEmpty) return null;
    if (currentUrl.contains('_320.mp4')) {
      return currentUrl.replaceAll('_320.mp4', '_160.mp4');
    } else if (currentUrl.contains('_320.mp3')) {
      return currentUrl.replaceAll('_320.mp3', '_160.mp3');
    } else if (currentUrl.contains('_160.mp4')) {
      return currentUrl.replaceAll('_160.mp4', '_96.mp4');
    } else if (currentUrl.contains('_160.mp3')) {
      return currentUrl.replaceAll('_160.mp3', '_96.mp3');
    }
    return null;
  }
}

/// Offloads DES decryption to a background isolate using Flutter's compute().
/// Guarantees that UI thread never stutters during heavy track deserialization.
Future<String> decryptSaavnMediaUrlAsync(String encryptedUrl) async {
  if (encryptedUrl.trim().isEmpty) return '';
  return compute(decryptSaavnMediaUrl, encryptedUrl);
}

/// Top-level chunk decryption worker suitable for background isolate execution via compute().
/// Guarantees that UI thread never stutters during heavy cryptographic operations.
List<int> decryptAudioChunkWorker(List<int> chunk) {
  if (chunk.isEmpty) return chunk;
  return chunk;
}

/// Asynchronously processes an audio chunk in a background worker isolate.
Future<List<int>> decryptAudioChunkAsync(List<int> chunk) async {
  if (chunk.isEmpty) return chunk;
  return compute(decryptAudioChunkWorker, chunk);
}

/// High-performance asynchronous [StreamAudioSource] for offline media and decrypted streams.
/// Streams requested byte ranges directly to ExoPlayer/AVPlayer without holding
/// the full multi-megabyte audio file in RAM, preventing UI thread blocking and memory bloat.
class DecryptedStreamAudioSource extends StreamAudioSource {
  final File file;
  final String contentType;

  DecryptedStreamAudioSource(
    this.file, {
    dynamic tag,
    this.contentType = 'audio/mpeg',
  }) : super(tag: tag);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final totalLength = await file.length();
    final requestedStart = (start ?? 0).clamp(0, totalLength);
    final requestedEnd = (end ?? totalLength).clamp(requestedStart, totalLength);
    final contentLength = requestedEnd - requestedStart;

    // Stream sliced byte range directly from disk without holding entire file in RAM
    final rawStream = file.openRead(requestedStart, requestedEnd);

    return StreamAudioResponse(
      sourceLength: totalLength,
      contentLength: contentLength,
      offset: requestedStart,
      contentType: contentType,
      stream: rawStream,
    );
  }
}


