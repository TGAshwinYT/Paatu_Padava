import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

String decryptSaavnMediaUrl(String encryptedUrl) {
  if (encryptedUrl.isEmpty) return '';

  try {
    final keyBytes = utf8.encode("38346536");
    final cipherText = base64.decode(encryptedUrl.trim());

    final cipher = ECBBlockCipher(DESEngine());
    cipher.init(false, KeyParameter(Uint8List.fromList(keyBytes)));

    final decrypted = Uint8List(cipherText.length);
    for (var offset = 0; offset < cipherText.length; offset += 8) {
      cipher.processBlock(cipherText, offset, decrypted, offset);
    }

    // PKCS5 / PKCS7 Unpadding
    if (decrypted.isEmpty) return '';
    final padLength = decrypted.last;
    if (padLength > 0 && padLength <= 8 && padLength <= decrypted.length) {
      final unpadded = decrypted.sublist(0, decrypted.length - padLength);
      return utf8.decode(unpadded).replaceAll('.mp4', '.mp3').replaceAll('_96.mp3', '_320.mp3');
    }

    return utf8.decode(decrypted).replaceAll('.mp4', '.mp3').replaceAll('_96.mp3', '_320.mp3');
  } catch (e) {
    return '';
  }
}
