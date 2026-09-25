import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/song.dart';

class SupabaseService {
  // Configurable Supabase credentials
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pqqrklvvdzsfuxaocvvi.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.placeholder_anon_key',
  );

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

  static Future<void> init() async {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        debug: kDebugMode,
      );
      _isInitialized = true;
      debugPrint('[SupabaseService] Initialized successfully');
    } catch (e) {
      debugPrint('[SupabaseService] Init notice (running in offline/resilient mode): $e');
    }
  }

  /// Sign Up with Email and Password
  /// Throws standard or recognized error messages (e.g. "User already registered")
  static Future<AuthResponse?> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    final c = client;
    if (c == null) return null;

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
    final c = client;
    if (c == null) return null;

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

  /// Native Google Sign-In with Supabase OAuth Token Exchange
  static Future<AuthResponse?> signInWithGoogle() async {
    final c = client;
    if (c == null) return null;

    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null; // User cancelled

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'Missing Google ID Token';
      }

      final res = await c.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      return res;
    } catch (e) {
      debugPrint('[SupabaseService] Google Sign-In error: $e');
      rethrow;
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

  /// Fetch user preferences (e.g. preferred languages) from table `user_preferences`
  static Future<List<String>> fetchUserPreferences(String userId) async {
    final c = client;
    if (c == null || userId.isEmpty || userId == 'guest') return [];

    try {
      final data = await c
          .from('user_preferences')
          .select('preferred_languages')
          .eq('user_id', userId)
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

  /// Fetch favorite artists from table `favorite_artists`
  static Future<List<Map<String, dynamic>>> fetchFavoriteArtists(String userId) async {
    final c = client;
    if (c == null || userId.isEmpty || userId == 'guest') return [];

    try {
      final List<dynamic> data = await c
          .from('favorite_artists')
          .select('artist_name, artist_image, genres')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('[SupabaseService] fetchFavoriteArtists error: $e');
    }
    return [];
  }

  /// Save / Upsert user music preferences and favorite artists
  static Future<void> saveUserTaste({
    required String userId,
    required List<String> languages,
    required List<String> artistNames,
  }) async {
    final c = client;
    if (c == null || userId.isEmpty || userId == 'guest') return;

    try {
      // 1. Upsert user preferences
      await c.from('user_preferences').upsert({
        'user_id': userId,
        'preferred_languages': languages,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 2. Insert favorite artists
      if (artistNames.isNotEmpty) {
        final artistRows = artistNames.map((name) => {
          'user_id': userId,
          'artist_name': name,
          'created_at': DateTime.now().toIso8601String(),
        }).toList();

        await c.from('favorite_artists').upsert(
          artistRows,
          onConflict: 'user_id, artist_name',
        );
      }
    } catch (e) {
      debugPrint('[SupabaseService] saveUserTaste error: $e');
    }
  }

  /// Record playback event to table `user_history`
  static Future<void> recordUserHistory(String userId, Song song) async {
    final c = client;
    if (c == null || userId.isEmpty || userId == 'guest') return;

    try {
      await c.from('user_history').insert({
        'user_id': userId,
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
