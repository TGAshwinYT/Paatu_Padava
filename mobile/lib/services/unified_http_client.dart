import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_manager.dart';
import 'error_handler.dart';

/// Resilient HTTP client wrapper providing:
/// - HTTP 401 Unauthorized silent refresh retry interceptor
/// - Configurable request timeouts (default 10s)
/// - Automatic retry with exponential backoff on transient network & 5xx server drops
/// - Integrated error translation via ErrorHandler into actionable AppErrors
class UnifiedHttpClient {
  static final http.Client _client = http.Client();

  /// Executes an HTTP GET request with 401 silent refresh interceptor, retries, and timeout
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 2,
  }) async {
    return _executeWithAuthInterceptor(
      (h) => _client.get(url, headers: h).timeout(timeout),
      context: 'GET ${url.path}',
      initialHeaders: headers,
      maxRetries: maxRetries,
    );
  }

  /// Executes an HTTP POST request with 401 silent refresh interceptor, retries, and timeout
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 2,
  }) async {
    return _executeWithAuthInterceptor(
      (h) => _client.post(url, headers: h, body: body).timeout(timeout),
      context: 'POST ${url.path}',
      initialHeaders: headers,
      maxRetries: maxRetries,
    );
  }

  /// Low-level retry harness with HTTP 401 silent refresh interceptor and exponential backoff
  static Future<http.Response> _executeWithAuthInterceptor(
    Future<http.Response> Function(Map<String, String>? headers) action, {
    required String context,
    Map<String, String>? initialHeaders,
    int maxRetries = 2,
  }) async {
    Map<String, String>? currentHeaders = initialHeaders != null ? Map<String, String>.from(initialHeaders) : null;
    int attempt = 0;
    int delayMs = 500;
    bool hasAttemptedRefresh = false;

    while (true) {
      attempt++;
      try {
        final response = await action(currentHeaders);

        // HTTP 401 Silent Refresh Interceptor:
        // Intercept token expiration, silently call /auth/refresh, update secure storage, and replay
        if (response.statusCode == 401 && !hasAttemptedRefresh) {
          hasAttemptedRefresh = true;
          debugPrint('[UnifiedHttpClient] 401 Unauthorized on $context. Silently refreshing token...');
          final newToken = await AuthManager.silentRefresh();
          if (newToken != null && newToken.isNotEmpty) {
            currentHeaders ??= {};
            currentHeaders['Authorization'] = 'Bearer $newToken';
            debugPrint('[UnifiedHttpClient] Silent refresh succeeded. Replaying request on $context...');
            continue; // Replay immediately without erroring or interrupting user
          }
        }

        // If server returns 502 or 503 (e.g. cold boot), retry if budget permits
        if ((response.statusCode == 502 || response.statusCode == 503) && attempt <= maxRetries) {
          debugPrint('[UnifiedHttpClient] $context returned ${response.statusCode}. Retrying attempt $attempt/$maxRetries in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs *= 2;
          continue;
        }

        return response;
      } catch (e, stack) {
        final isRetryable = e is SocketException ||
            e is http.ClientException ||
            e is TimeoutException;

        if (isRetryable && attempt <= maxRetries) {
          debugPrint('[UnifiedHttpClient] $context threw $e. Retrying attempt $attempt/$maxRetries in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs *= 2;
          continue;
        }

        // Final failure: resolve via ErrorHandler
        final appError = ErrorHandler.resolve(e, stackTrace: stack, context: context);
        debugPrint('[UnifiedHttpClient] $context failed permanently after $attempt attempts: ${appError.userMessage}');
        throw appError;
      }
    }
  }

  /// Closes the underlying HTTP client
  static void close() {
    _client.close();
  }
}
