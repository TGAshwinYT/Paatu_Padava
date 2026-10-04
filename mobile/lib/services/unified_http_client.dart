import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'error_handler.dart';

/// Resilient HTTP client wrapper providing:
/// - Configurable request timeouts (default 10s)
/// - Automatic retry with exponential backoff on transient network & 5xx server drops
/// - Integrated error translation via ErrorHandler into actionable AppErrors
class UnifiedHttpClient {
  static final http.Client _client = http.Client();

  /// Executes an HTTP GET request with retries and timeout
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 2,
  }) async {
    return _executeWithRetry(
      () => _client.get(url, headers: headers).timeout(timeout),
      context: 'GET ${url.path}',
      maxRetries: maxRetries,
    );
  }

  /// Executes an HTTP POST request with retries and timeout
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 2,
  }) async {
    return _executeWithRetry(
      () => _client.post(url, headers: headers, body: body).timeout(timeout),
      context: 'POST ${url.path}',
      maxRetries: maxRetries,
    );
  }

  /// Low-level retry harness with exponential backoff
  static Future<http.Response> _executeWithRetry(
    Future<http.Response> Function() action, {
    required String context,
    int maxRetries = 2,
  }) async {
    int attempt = 0;
    int delayMs = 500;

    while (true) {
      attempt++;
      try {
        final response = await action();

        // If server returns 502 or 503 (e.g. HuggingFace cold boot), retry if budget permits
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
