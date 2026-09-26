import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'supabase_service.dart';
import 'sync_manager.dart';

class AuthUser {
  final String id;
  final String username;
  final String email;
  final String avatarUrl;
  final List<String> preferredLanguages;
  final List<String> favoriteArtists;
  final bool isGuest;

  AuthUser({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl = '',
    this.preferredLanguages = const ['tamil', 'english'],
    this.favoriteArtists = const [],
    this.isGuest = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'avatar_url': avatarUrl,
    'preferred_languages': preferredLanguages,
    'favorite_artists': favoriteArtists,
    'is_guest': isGuest,
  };

  factory AuthUser.fromJson(Map<dynamic, dynamic> json) {
    List<String> parseList(dynamic val) {
      if (val is List) return val.map((e) => e.toString()).toList();
      if (val is String && val.isNotEmpty) {
        try {
          final decoded = jsonDecode(val);
          if (decoded is List) return decoded.map((e) => e.toString()).toList();
        } catch (_) {}
      }
      return [];
    }

    return AuthUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? json['name']?.toString() ?? 'Listener',
      email: json['email']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString() ?? json['avatar']?.toString() ?? '',
      preferredLanguages: parseList(json['preferred_languages'] ?? json['preferredLanguages']).isNotEmpty
          ? parseList(json['preferred_languages'] ?? json['preferredLanguages'])
          : ['tamil', 'english'],
      favoriteArtists: parseList(json['favorite_artists'] ?? json['favoriteArtists']),
      isGuest: json['is_guest'] == true,
    );
  }

  factory AuthUser.fromSupabase(supa.User user, {List<String>? languages, List<String>? artists}) {
    final meta = user.userMetadata ?? {};
    final username = meta['username']?.toString() ??
        meta['full_name']?.toString() ??
        meta['name']?.toString() ??
        (user.email != null && user.email!.contains('@') ? user.email!.split('@').first : 'Listener');
    final avatar = meta['avatar_url']?.toString() ?? meta['picture']?.toString() ?? '';

    return AuthUser(
      id: user.id,
      username: username,
      email: user.email ?? '',
      avatarUrl: avatar,
      preferredLanguages: languages ?? ['tamil', 'english'],
      favoriteArtists: artists ?? [],
      isGuest: false,
    );
  }

  factory AuthUser.guest() => AuthUser(
    id: 'guest',
    username: 'Guest Listener',
    email: 'guest@paatupaadava.app',
    isGuest: true,
  );
}

/// Unified Identity Manager driven strictly by Supabase Auth.
/// Completely eliminates dual-backend desynchronization and silent sync failures.
class AuthManager {
  static const String boxName = 'auth_box';

  static final ValueNotifier<String?> tokenNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<AuthUser?> authNotifier = ValueNotifier<AuthUser?>(null);

  static AuthUser? get currentUser => authNotifier.value;
  static AuthUser? get user => currentUser;
  static String? get token => tokenNotifier.value;
  static bool get isLoggedIn => SupabaseService.currentUser != null && !(currentUser?.isGuest ?? true);

  static Box get _box => Hive.box(boxName);
  static StreamSubscription? _authSub;

  static Future<void> init() async {
    await Hive.openBox(boxName);

    // 1. Initial State from Supabase Client
    final supaUser = SupabaseService.currentUser;
    if (supaUser != null) {
      final sessionToken = SupabaseService.client?.auth.currentSession?.accessToken;
      tokenNotifier.value = sessionToken;
      await _loadCachedUserOrSupabase(supaUser);
    } else {
      final savedUser = _box.get('user_profile');
      if (savedUser is Map && savedUser['is_guest'] == true) {
        authNotifier.value = AuthUser.fromJson(savedUser);
      } else {
        await loginAsGuest();
      }
    }

    // 2. Listen to Supabase Auth state stream
    _authSub?.cancel();
    _authSub = SupabaseService.authStateChanges?.listen((data) async {
      final user = data.session?.user ?? SupabaseService.currentUser;
      if (user != null) {
        tokenNotifier.value = data.session?.accessToken;
        await _loadCachedUserOrSupabase(user);
        // Automatically sync cloud library on sign in / session refresh
        SyncManager.syncAll();
      } else if (data.event == supa.AuthChangeEvent.signedOut) {
        tokenNotifier.value = null;
        await loginAsGuest();
      }
    });
  }

  static Future<void> _loadCachedUserOrSupabase(supa.User supaUser) async {
    final savedUser = _box.get('user_profile');
    List<String> langs = ['tamil', 'english'];
    List<String> artists = [];

    if (savedUser is Map && savedUser['id'] == supaUser.id) {
      final cached = AuthUser.fromJson(savedUser);
      langs = cached.preferredLanguages;
      artists = cached.favoriteArtists;
    }

    // Load preferences from Supabase profiles
    try {
      final remoteLangs = await SupabaseService.fetchUserPreferences(supaUser.id);
      if (remoteLangs.isNotEmpty) langs = remoteLangs;
    } catch (_) {}

    final authUser = AuthUser.fromSupabase(supaUser, languages: langs, artists: artists);
    authNotifier.value = authUser;
    await _box.put('user_profile', authUser.toJson());
  }

  static Future<bool> login(String email, String password) async {
    final res = await SupabaseService.signIn(email: email, password: password);
    if (res?.user != null) {
      tokenNotifier.value = res?.session?.accessToken;
      await _loadCachedUserOrSupabase(res!.user!);
      SyncManager.syncAll();
      return true;
    }
    return false;
  }

  static Future<bool> register(String username, String email, String password) async {
    final res = await SupabaseService.signUp(
      email: email,
      password: password,
      username: username,
    );
    if (res?.user != null) {
      tokenNotifier.value = res?.session?.accessToken;
      await _loadCachedUserOrSupabase(res!.user!);
      SyncManager.syncAll();
      return true;
    }
    return false;
  }

  static Future<bool> loginWithGoogle([String? idToken]) async {
    final res = await SupabaseService.signInWithGoogle();
    if (res?.user != null) {
      tokenNotifier.value = res?.session?.accessToken;
      await _loadCachedUserOrSupabase(res!.user!);
      SyncManager.syncAll();
      return true;
    }
    return false;
  }

  static Future<void> loginAsGuest() async {
    final guest = AuthUser.guest();
    authNotifier.value = guest;
    tokenNotifier.value = null;
    await _box.put('user_profile', guest.toJson());
  }

  static Future<void> logout() async {
    await SupabaseService.signOut();
    tokenNotifier.value = null;
    await loginAsGuest();
  }

  static Future<bool> updateLanguagePreferences(List<String> languages) async {
    final current = currentUser;
    if (current != null) {
      final updated = AuthUser(
        id: current.id,
        username: current.username,
        email: current.email,
        avatarUrl: current.avatarUrl,
        preferredLanguages: languages,
        favoriteArtists: current.favoriteArtists,
        isGuest: current.isGuest,
      );
      authNotifier.value = updated;
      await _box.put('user_profile', updated.toJson());

      if (isLoggedIn) {
        await SupabaseService.saveUserTaste(
          languages: languages,
          artistNames: current.favoriteArtists,
        );
      }
    }
    return true;
  }

  static Future<bool> updateArtistPreferences(List<String> artists) async {
    final current = currentUser;
    if (current != null) {
      final updated = AuthUser(
        id: current.id,
        username: current.username,
        email: current.email,
        avatarUrl: current.avatarUrl,
        preferredLanguages: current.preferredLanguages,
        favoriteArtists: artists,
        isGuest: current.isGuest,
      );
      authNotifier.value = updated;
      await _box.put('user_profile', updated.toJson());

      if (isLoggedIn) {
        await SupabaseService.saveUserTaste(
          languages: current.preferredLanguages,
          artistNames: artists,
        );
      }
    }
    return true;
  }
}
