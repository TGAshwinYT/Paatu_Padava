import 'dart:convert';
import 'package:dart_des/dart_des.dart';

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

    return url;
  } catch (e) {
    return '';
  }
}
