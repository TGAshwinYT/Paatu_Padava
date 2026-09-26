import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/song.dart';

class SupabaseService {
  // Raw credentials injected via --dart-define in CI/CD or local runs
  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseUrl {
    final trimmed = _envUrl.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return 'https://placeholder.supabase.co';
  }

  static String get supabaseAnonKey {
    final trimmed = _envAnonKey.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return 'placeholder-anon-key';
  }

  /// Whether valid live Supabase credentials were provided
  static bool get isConfigured {
    final uri = Uri.tryParse(supabaseUrl);
    final hasValidHost = uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        !supabaseUrl.contains('placeholder');
    final hasValidKey = supabaseAnonKey.isNotEmpty &&
        !supabaseAnonKey.contains('placeholder');
    return hasValidHost && hasValidKey;
  }

  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  static SupabaseClient? get client {
    if (!_isInitialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Current authenticated Supabase user
  static User? get currentUser => client?.auth.currentUser;

  /// Stream of Supabase authentication state changes
  static Stream<AuthState>? get authStateChanges => client?.auth.onAuthStateChange;

  static Future<void> init() async {
    if (!isConfigured) {
      debugPrint('[SupabaseService] Offline Mode: Supabase credentials not configured ($supabaseUrl).');
      _isInitialized = false;
      return;
    }

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        debug: kDebugMode,
      );
      _isInitialized = true;
      debugPrint('[SupabaseService] Initialized successfully with $supabaseUrl');
    } catch (e) {
      debugPrint('[SupabaseService] Init notice (running in offline/resilient mode): $e');
      _isInitialized = false;
    }
  }

  /// Sign Up with Email and Password
  /// Throws standard or recognized error messages (e.g. "User already registered")
  static Future<AuthResponse?> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    if (!isConfigured || client == null) {
      throw 'Cloud sync is offline. Supabase credentials are not configured on this build.';
    }
    final c = client!;

    try {
      final res = await c.auth.signUp(
        email: email.trim(),
        password: password,
        data: username != null ? {'username': username.trim()} : null,
      );
      return res;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') || msg.contains('user already exists') || e.statusCode == '422') {
        throw 'User already registered';
      }
      throw e.message;
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('already registered') || err.contains('user already exists')) {
        throw 'User already registered';
      }
      rethrow;
    }
  }

  /// Sign In with Email and Password
  static Future<AuthResponse?> signIn({
    required String email,
    required String password,
  }) async {
    if (!isConfigured || client == null) {
      throw 'Cloud sync is offline. Supabase credentials are not configured on this build.';
    }
    final c = client!;

    try {
      final res = await c.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return res;
    } on AuthException catch (e) {
      throw e.message;
    }
  }

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '651588945329-odttbp9ilg38qf0ji42978l8mkto9f5u.apps.googleusercontent.com',
  );

  /// Native Google Sign-In with Supabase OAuth Token Exchange
  static Future<AuthResponse?> signInWithGoogle() async {
    if (!isConfigured || client == null) {
      throw 'Cloud sync is offline: Supabase credentials are not configured on this build.';
    }
    final c = client!;

    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: googleWebClientId.isNotEmpty ? googleWebClientId : null,
        scopes: ['email', 'profile'],
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null; // User cancelled cleanly

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw 'Google Sign-In did not return a valid authentication token. Please use email and password sign-in.';
      }

      final res = await c.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      return res;
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      debugPrint('[SupabaseService] Google Sign-In error: $e');
      final errStr = e.toString();
      if (errStr.contains('ApiException: 10') ||
          errStr.contains('sign_in_failed') ||
          errStr.contains('DEVELOPER_ERROR') ||
          errStr.contains('PlatformException')) {
        throw 'Google Sign-In is not enabled on this APK or the SHA-1 fingerprint is still registering in Google Cloud. Please sign in with email and password.';
      }
      throw 'Google Sign-In was cancelled or failed. Please try again or use email sign-in.';
    }
  }

  /// Sign Out
  static Future<void> signOut() async {
    try {
      final c = client;
      if (c != null) {
        await c.auth.signOut();
      }
      final googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
    } catch (_) {}
  }

  /// Fetch user preferences (e.g. preferred languages) from table `profiles`
  static Future<List<String>> fetchUserPreferences([String? userId]) async {
    final c = client;
    final user = currentUser;
    if (c == null || user == null) return [];

    final targetId = (userId != null && userId.isNotEmpty && userId != 'guest') ? userId : user.id;

    try {
      final data = await c
          .from('profiles')
          .select('preferred_languages')
          .eq('id', targetId)
          .maybeSingle();

      if (data != null && data['preferred_languages'] != null) {
        final raw = data['preferred_languages'];
        if (raw is List) {
          return raw.map((e) => e.toString().trim()).toList();
        }
      }
    } catch (e) {
      debugPrint('[SupabaseService] fetchUserPreferences error: $e');
    }
    return [];
  }

  /// Fetch favorite artists from table `user_favorite_artists`
  static Future<List<Map<String, dynamic>>> fetchFavoriteArtists([String? userId]) async {
    final c = client;
    final user = currentUser;
    if (c == null || user == null) return [];

    final targetId = (userId != null && userId.isNotEmpty && userId != 'guest') ? userId : user.id;

    try {
      final List<dynamic> data = await c
          .from('user_favorite_artists')
          .select('artist_name, artist_image_url')
          .eq('user_id', targetId)
          .order('created_at', ascending: false);

      return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('[SupabaseService] fetchFavoriteArtists error: $e');
    }
    return [];
  }

  /// Save user favorite artists directly to Supabase table `user_favorite_artists`
  static Future<void> saveUserFavoriteArtists({
    String? userId,
    required List<Map<String, String>> artists,
  }) async {
    final c = client;
    final user = currentUser;
    if (c == null || user == null) return;

    final targetId = (userId != null && userId.isNotEmpty && userId != 'guest') ? userId : user.id;

    try {
      final rows = artists.map((a) => {
        'user_id': targetId,
        'artist_name': a['name'] ?? '',
        'artist_image_url': a['image'] ?? '',
      }).where((r) => (r['artist_name'] as String).isNotEmpty).toList();

      if (rows.isNotEmpty) {
        await c.from('user_favorite_artists').upsert(
          rows,
          onConflict: 'user_id, artist_name',
        );
      }
    } catch (e) {
      debugPrint('[SupabaseService] saveUserFavoriteArtists error: $e');
    }
  }

  /// Save / Upsert user music preferences and favorite artists
  static Future<void> saveUserTaste({
    String? userId,
    required List<String> languages,
    required List<String> artistNames,
  }) async {
    final c = client;
    final user = currentUser;
    if (c == null || user == null) return;

    final targetId = (userId != null && userId.isNotEmpty && userId != 'guest') ? userId : user.id;

    try {
      // 1. Upsert profile preferences
      await c.from('profiles').upsert({
        'id': targetId,
        'email': user.email ?? '',
        'preferred_languages': languages,
      });

      // 2. Insert favorite artists into user_favorite_artists
      if (artistNames.isNotEmpty) {
        final artistRows = artistNames.map((name) => {
          'user_id': targetId,
          'artist_name': name,
        }).toList();

        await c.from('user_favorite_artists').upsert(
          artistRows,
          onConflict: 'user_id, artist_name',
        );
      }
    } catch (e) {
      debugPrint('[SupabaseService] saveUserTaste error: $e');
    }
  }

  /// Record playback event to table `user_history` (strictly requiring authenticated Supabase session)
  static Future<void> recordUserHistory(String? userId, Song song) async {
    final c = client;
    final user = currentUser;
    if (c == null || user == null) return;

    final targetId = (userId != null && userId.isNotEmpty && userId != 'guest') ? userId : user.id;

    try {
      await c.from('user_history').insert({
        'user_id': targetId,
        'song_id': song.id,
        'title': song.title,
        'artist': song.artist,
        'cover_url': song.coverUrl,
        'source': song.source,
        'played_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[SupabaseService] recordUserHistory error: $e');
    }
  }
}
