import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

class AuthUser {
  final String id;
  final String username;
  final String email;
  final bool isGuest;

  AuthUser({
    required this.id,
    required this.username,
    required this.email,
    this.isGuest = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'is_guest': isGuest,
  };

  factory AuthUser.fromJson(Map<dynamic, dynamic> json) => AuthUser(
    id: json['id']?.toString() ?? '',
    username: json['username']?.toString() ?? json['name']?.toString() ?? 'Listener',
    email: json['email']?.toString() ?? '',
    isGuest: json['is_guest'] == true,
  );

  factory AuthUser.guest() => AuthUser(
    id: 'guest',
    username: 'Guest Listener',
    email: 'guest@paatupaadava.app',
    isGuest: true,
  );
}

class AuthManager {
  static const String boxName = 'auth_box';
  static const String baseUrl = 'https://tgashwinyt-paatu-padava.hf.space';

  static final ValueNotifier<String?> tokenNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<AuthUser?> authNotifier = ValueNotifier<AuthUser?>(null);

  static AuthUser? get currentUser => authNotifier.value;
  static AuthUser? get user => currentUser;
  static String? get token => tokenNotifier.value;
  static bool get isLoggedIn => token != null && token!.isNotEmpty && !(currentUser?.isGuest ?? true);

  static Box get _box => Hive.box(boxName);

  static Future<void> init() async {
    await Hive.openBox(boxName);
    final savedToken = _box.get('jwt_token') as String?;
    final savedUser = _box.get('user_profile');

    if (savedToken != null && savedToken.isNotEmpty) {
      tokenNotifier.value = savedToken;
      if (savedUser is Map) {
        authNotifier.value = AuthUser.fromJson(savedUser);
      }
      // Refresh in background
      fetchCurrentUser();
    }
  }

  static Future<bool> login(String email, String password) async {
    try {
      final uri = Uri.parse('$baseUrl/api/auth/login');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email.trim(), 'password': password}),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final jwt = data['access_token'] ?? data['token'];
        if (jwt != null) {
          final userJson = data['user'] is Map ? data['user'] : {'email': email, 'name': email.split('@').first};
          final user = AuthUser.fromJson(userJson);
          await _saveSession(jwt.toString(), user);
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> register(String username, String email, String password) async {
    try {
      final uri = Uri.parse('$baseUrl/api/auth/register');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': username.trim(),
          'email': email.trim(),
          'password': password,
        }),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final jwt = data['access_token'] ?? data['token'];
        if (jwt != null) {
          final userJson = data['user'] is Map ? data['user'] : {'name': username, 'email': email};
          final user = AuthUser.fromJson(userJson);
          await _saveSession(jwt.toString(), user);
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> loginAsGuest() async {
    final guest = AuthUser.guest();
    authNotifier.value = guest;
    await _box.put('user_profile', guest.toJson());
  }

  static Future<void> fetchCurrentUser() async {
    if (!isLoggedIn) return;
    try {
      final uri = Uri.parse('$baseUrl/api/auth/me');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final userJson = json.decode(response.body);
        if (userJson is Map) {
          final user = AuthUser.fromJson(userJson);
          authNotifier.value = user;
          await _box.put('user_profile', user.toJson());
        }
      }
    } catch (_) {}
  }

  static Future<void> _saveSession(String jwt, AuthUser user) async {
    await _box.put('jwt_token', jwt);
    await _box.put('user_profile', user.toJson());
    tokenNotifier.value = jwt;
    authNotifier.value = user;
  }

  static Future<void> logout() async {
    await _box.delete('jwt_token');
    await _box.delete('user_profile');
    tokenNotifier.value = null;
    authNotifier.value = null;
  }
}
