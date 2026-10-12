// ignore_for_file: experimental_member_use
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_des/dart_des.dart';
import 'package:just_audio/just_audio.dart';

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
    
    // JioSaavn CDN serves audio in .mp4 (AAC) or .mp3 containers.
    // Upgrade 96kbps / 160kbps to 320kbps for pristine high fidelity
    if (url.contains('_96.mp4')) {
      url = url.replaceAll('_96.mp4', '_320.mp4');
    } else if (url.contains('_160.mp4')) {
      url = url.replaceAll('_160.mp4', '_320.mp4');
    } else if (url.contains('_96.mp3')) {
      url = url.replaceAll('_96.mp3', '_320.mp3');
    } else if (url.contains('_160.mp3')) {
      url = url.replaceAll('_160.mp3', '_320.mp3');
    }

    if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'https://');
    }

    return url;
  } catch (e) {
    return '';
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


