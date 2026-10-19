import 'dart:core';

/// High-integrity HTTP headers and User-Agent utilities for YouTube & Googlevideo CDN streams.
class YouTubeHeaderUtils {
  static const String vrUserAgent =
      'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 2; Build/SQ3A.220605.009.A1) gzip';
  static const String androidUserAgent =
      'com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UQ1A.240205.004) gzip';

  /// High-integrity HTTP headers for Googlevideo CDN streams.
  /// Enforces ANDROID_VR User-Agent and keep-alive to avoid connection drops and 403 Forbidden errors.
  static Map<String, String> get streamingHeaders => const {
    'Range': 'bytes=0-',
    'User-Agent': vrUserAgent,
    'Accept': '*/*',
    'Connection': 'keep-alive',
  };

  /// True for URLs served by YouTube's media CDN / manifest endpoints.
  static bool isYouTubeStreamUrl(String url) =>
      url.contains('googlevideo.com') || url.contains('youtube.com/api/manifest');

  /// Returns the User-Agent that matches the client which issued [url].
  static String userAgentForUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      final c = uri?.queryParameters['c']?.toUpperCase();
      if (c == 'ANDROID_VR') return vrUserAgent;
      if (c == 'IOS' || url.contains('.m3u8')) {
        return 'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)';
      }
      if (c == 'ANDROID') {
        return 'com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UQ1A.240205.004) gzip';
      }
      if (c == 'WEB_REMIX' || url.contains('music.youtube.com')) {
        return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
      }
    } catch (_) {}
    return vrUserAgent;
  }

  /// HTTP headers the PLAYER or download manager must send for a YouTube stream [url].
  static Map<String, String> headersForUrl(String url) {
    return {
      'User-Agent': userAgentForUrl(url),
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };
  }

  /// Returns true if a Googlevideo stream URL's expire parameter is within 60 seconds of expiring or already expired.
  static bool isLinkExpired(String? url) {
    if (url == null || url.isEmpty) return true;
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return true;
      final expireStr = uri.queryParameters['expire'];
      if (expireStr == null) return false;
      final expireSec = int.tryParse(expireStr);
      if (expireSec == null) return false;
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return nowSec >= (expireSec - 60);
    } catch (_) {
      return false;
    }
  }
}
