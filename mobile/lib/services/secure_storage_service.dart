import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_logger.dart';

/// Encrypted key-value storage wrapper backed by Android Keystore / EncryptedSharedPreferences
/// and iOS Keychain, with an in-memory fallback for headless unit tests.
class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static final Map<String, String> _fallbackStore = {};

  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return _fallbackStore[key];
    } on PlatformException {
      return _fallbackStore[key];
    } catch (_) {
      return _fallbackStore[key];
    }
  }

  static Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on MissingPluginException {
      _fallbackStore[key] = value;
    } on PlatformException {
      _fallbackStore[key] = value;
    } catch (_) {
      _fallbackStore[key] = value;
    }
  }

  static Future<void> delete(String key) async {
    _fallbackStore.remove(key);
    try {
      await _storage.delete(key: key);
    } on MissingPluginException catch (e) {
      AppLogger.debug('SecureStorageService', 'MissingPluginException on delete($key): $e');
    } on PlatformException catch (e) {
      AppLogger.debug('SecureStorageService', 'PlatformException on delete($key): $e');
    } catch (e) {
      AppLogger.debug('SecureStorageService', 'Fallback delete($key) notice: $e');
    }
  }

  static Future<bool> containsKey(String key) async {
    final val = await read(key);
    return val != null;
  }

  @visibleForTesting
  static void clearFallbackForTesting() {
    _fallbackStore.clear();
  }
}

/// Custom [LocalStorage] adapter for `supabase_flutter` so Supabase session
/// JSON (JWT access token + refresh token) is stored in hardware-backed
/// [SecureStorageService] instead of plain `SharedPreferences`.
class SecureSupabaseLocalStorage extends LocalStorage {
  SecureSupabaseLocalStorage() : super();

  @override
  Future<void> initialize() async {
    final existingSecure = await SecureStorageService.read(supabasePersistSessionKey);
    if (existingSecure != null && existingSecure.isNotEmpty) {
      return;
    }
    // One-time upgrade migration from legacy plain SharedPreferences storage
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final legacyKey in [supabasePersistSessionKey, 'supabase.auth.token']) {
        final legacyValue = prefs.getString(legacyKey);
        if (legacyValue != null && legacyValue.isNotEmpty) {
          await SecureStorageService.write(supabasePersistSessionKey, legacyValue);
          await prefs.remove(legacyKey);
          break;
        }
      }
    } catch (_) {
      // Ignore in headless tests without SharedPreferences platform channel
    }
  }

  @override
  Future<bool> hasAccessToken() => SecureStorageService.containsKey(supabasePersistSessionKey);

  @override
  Future<String?> accessToken() => SecureStorageService.read(supabasePersistSessionKey);

  @override
  Future<void> removePersistedSession() => SecureStorageService.delete(supabasePersistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      SecureStorageService.write(supabasePersistSessionKey, persistSessionString);
}
