/// Centralized Application Configuration & Build-Time Environment Defines
class AppConfig {
  /// Base URL for the Paatu Padava FastAPI backend on Hugging Face Spaces.
  /// Overridable at build time via `--dart-define=BACKEND_URL=https://...`
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://tgashwinyt-paatu-padava.hf.space',
  );

  /// App Version String
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '2.2.0',
  );

  /// Enable Google Sign In
  static const bool enableGoogleSignIn = bool.fromEnvironment(
    'ENABLE_GOOGLE_SIGN_IN',
    defaultValue: false,
  );

  /// Optional build-time override for Spotify Client ID (empty by default for security)
  static const String spotifyClientId = String.fromEnvironment(
    'SPOTIFY_CLIENT_ID',
    defaultValue: '',
  );

  /// Optional build-time override for Spotify Client Secret (empty by default for security)
  static const String spotifyClientSecret = String.fromEnvironment(
    'SPOTIFY_CLIENT_SECRET',
    defaultValue: '',
  );
}
