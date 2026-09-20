import 'dart:convert';
import 'package:dart_des/dart_des.dart';

String decryptSaavnMediaUrl(String encryptedUrl) {
  if (encryptedUrl.isEmpty) return '';

  try {
    const key = '38346536';
    final cipherText = base64.decode(encryptedUrl.trim());
    final desECB = DES(key: key.codeUnits, mode: DESMode.ECB);
    final decrypted = desECB.decrypt(cipherText);

    if (decrypted.isEmpty) return '';

    // PKCS5 / PKCS7 unpadding: the last byte indicates the number of padding bytes
    final padLength = decrypted.last;
    List<int> unpadded = decrypted;
    if (padLength > 0 && padLength <= 8 && padLength <= decrypted.length) {
      unpadded = decrypted.sublist(0, decrypted.length - padLength);
    }

    return utf8.decode(unpadded).replaceAll('.mp4', '.mp3').replaceAll('_96.mp3', '_320.mp3');
  } catch (e) {
    return '';
  }
}
