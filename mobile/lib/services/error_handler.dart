import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/app_error.dart';

/// Centralized Exception and HTTP Status Code resolver.
/// Guarantees that users never see raw exception strings, stack traces, or guesswork,
/// while providing full debug telemetry to debugPrint.
class ErrorHandler {
  /// Resolves any arbitrary error/exception into an actionable AppError
  static AppError resolve(dynamic error, {StackTrace? stackTrace, String? context}) {
    if (stackTrace != null) {
      debugPrint('[ErrorHandler] ${context != null ? "[$context] " : ""}Error: $error\n$stackTrace');
    } else {
      debugPrint('[ErrorHandler] ${context != null ? "[$context] " : ""}Error: $error');
    }

    if (error is AppError) {
      return error;
    }

    // 1. Network / Socket / Offline Exceptions
    if (error is SocketException) {
      return AppError.offline(debugDetails: error.toString());
    }

    if (error is http.ClientException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('connection refused') ||
          msg.contains('failed host lookup') ||
          msg.contains('network is unreachable') ||
          msg.contains('connection closed') ||
          msg.contains('software caused connection abort')) {
        return AppError.offline(debugDetails: error.toString());
      }
      return AppError(
        category: AppErrorCategory.offline,
        userMessage: 'Unable to connect to the server. Please check your internet connection.',
        actionLabel: 'Retry',
        actionType: AppActionType.retry,
        errorCode: 'ERR_CLIENT_NETWORK',
        debugDetails: error.toString(),
      );
    }

    if (error is TimeoutException) {
      return AppError.timeout(debugDetails: error.toString());
    }

    // 2. Dio Exceptions (used in DownloadManager and HTTP clients)
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return AppError.timeout(debugDetails: error.message);
        case DioExceptionType.connectionError:
          return AppError.offline(debugDetails: error.message);
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          return resolveHttpStatus(statusCode, responseBody: error.response?.data, debugDetails: error.message);
        case DioExceptionType.cancel:
          return const AppError(
            category: AppErrorCategory.unknown,
            userMessage: 'The download was cancelled.',
            errorCode: 'ERR_CANCELLED',
          );
        default:
          final msg = (error.message ?? '').toLowerCase();
          if (msg.contains('socket') || msg.contains('network') || msg.contains('connection')) {
            return AppError.offline(debugDetails: error.message);
          }
          return AppError(
            category: AppErrorCategory.unknown,
            userMessage: 'A network error occurred. Please try again.',
            actionLabel: 'Retry',
            actionType: AppActionType.retry,
            errorCode: 'ERR_DIO_UNKNOWN',
            debugDetails: error.message,
          );
      }
    }

    // 3. Supabase / GoTrue Auth Exceptions
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      final statusCode = error.statusCode;

      if (msg.contains('network') || msg.contains('failed host lookup') || msg.contains('socket') || msg.contains('connection')) {
        return AppError.offline(debugDetails: error.toString());
      }

      if (statusCode == '400' && (msg.contains('invalid login credentials') || msg.contains('invalid credentials') || msg.contains('invalid email or password'))) {
        return const AppError(
          category: AppErrorCategory.authInvalidCredentials,
          userMessage: 'Incorrect email or password. Please verify your credentials.',
          actionLabel: 'Retry',
          actionType: AppActionType.retry,
          errorCode: 'ERR_AUTH_INVALID_CREDENTIALS',
        );
      }

      if (msg.contains('already registered') || msg.contains('already exists') || msg.contains('user already registered')) {
        return const AppError(
          category: AppErrorCategory.authEmailExists,
          userMessage: 'This email is already registered. Please sign in instead.',
          actionLabel: 'Sign In',
          actionType: AppActionType.signIn,
          errorCode: 'ERR_AUTH_EMAIL_EXISTS',
        );
      }

      if (msg.contains('password') && (msg.contains('least') || msg.contains('short') || msg.contains('characters') || msg.contains('weak'))) {
        return const AppError(
          category: AppErrorCategory.authWeakPassword,
          userMessage: 'Password is too weak. Please use at least 6 characters.',
          actionLabel: 'Retry',
          actionType: AppActionType.retry,
          errorCode: 'ERR_AUTH_WEAK_PASSWORD',
        );
      }

      if (msg.contains('email') && (msg.contains('invalid') || msg.contains('format') || msg.contains('valid email'))) {
        return const AppError(
          category: AppErrorCategory.authInvalidEmail,
          userMessage: 'Please enter a valid email address.',
          actionLabel: 'Retry',
          actionType: AppActionType.retry,
          errorCode: 'ERR_AUTH_INVALID_EMAIL',
        );
      }

      return AppError(
        category: AppErrorCategory.unknown,
        userMessage: error.message.isNotEmpty ? error.message : 'Authentication failed. Please try again.',
        actionLabel: 'Retry',
        actionType: AppActionType.retry,
        errorCode: 'ERR_AUTH_${statusCode ?? "FAIL"}',
        debugDetails: error.toString(),
      );
    }

    // 4. FileSystemException (Storage / Disk / Permissions)
    if (error is FileSystemException) {
      final msg = error.message.toLowerCase();
      final osError = error.osError?.message.toLowerCase() ?? '';
      if (msg.contains('no space left') || osError.contains('enospc') || msg.contains('disk full')) {
        return const AppError(
          category: AppErrorCategory.storageFull,
          userMessage: 'Device storage is full. Please free up space to continue downloading.',
          actionLabel: 'Open Settings',
          actionType: AppActionType.openSettings,
          errorCode: 'ERR_STORAGE_FULL',
        );
      }
      if (msg.contains('permission denied') || osError.contains('eacces') || msg.contains('access denied')) {
        return const AppError(
          category: AppErrorCategory.permissionDenied,
          userMessage: 'Storage permission denied. Please enable storage access in settings.',
          actionLabel: 'Open Settings',
          actionType: AppActionType.openSettings,
          errorCode: 'ERR_PERMISSION_DENIED',
        );
      }
      return AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'File system error occurred while saving music.',
        errorCode: 'ERR_FS',
        debugDetails: error.toString(),
      );
    }

    // 5. String-based errors from legacy throws
    if (error is String) {
      final lower = error.toLowerCase();
      if (lower.contains('socket') || lower.contains('network') || lower.contains('connection')) {
        return AppError.offline(debugDetails: error);
      }
      if (lower.contains('already registered') || lower.contains('user already exists')) {
        return const AppError(
          category: AppErrorCategory.authEmailExists,
          userMessage: 'This email is already registered. Please sign in instead.',
          actionLabel: 'Sign In',
          actionType: AppActionType.signIn,
          errorCode: 'ERR_AUTH_EMAIL_EXISTS',
        );
      }
      if (lower.contains('timeout')) {
        return AppError.timeout(debugDetails: error);
      }
      return AppError(
        category: AppErrorCategory.unknown,
        userMessage: error,
        errorCode: 'ERR_STRING',
      );
    }

    return AppError(
      category: AppErrorCategory.unknown,
      userMessage: 'An unexpected error occurred. Please try again.',
      actionLabel: 'Retry',
      actionType: AppActionType.retry,
      errorCode: 'ERR_UNKNOWN',
      debugDetails: error.toString(),
    );
  }

  /// Resolves HTTP status code directly to an AppError
  static AppError resolveHttpStatus(int? statusCode, {dynamic responseBody, String? debugDetails}) {
    if (statusCode == null) {
      return AppError.offline(debugDetails: debugDetails);
    }

    int? retryAfter;
    Map<String, dynamic>? errorMap;
    if (responseBody is Map<String, dynamic>) {
      errorMap = responseBody;
    } else if (responseBody is Map) {
      errorMap = Map<String, dynamic>.from(responseBody);
    } else if (responseBody is String && responseBody.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(responseBody);
        if (decoded is Map) {
          errorMap = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    if (errorMap != null) {
      final err = errorMap['error'] ?? errorMap['detail'];
      if (err is Map) {
        final code = err['code']?.toString();
        final message = err['message']?.toString();
        if (err['retry_after'] != null) {
          retryAfter = int.tryParse(err['retry_after'].toString());
        }
        if (code == 'UPSTREAM_UNAVAILABLE' || code == 'ERR_UPSTREAM_UNAVAILABLE') {
          return AppError(
            category: AppErrorCategory.upstreamUnavailable,
            userMessage: message ?? 'Upstream music provider is currently unavailable.',
            actionLabel: 'Retry',
            actionType: AppActionType.retry,
            errorCode: code!,
            debugDetails: debugDetails,
          );
        }
        if (code == 'NOT_FOUND') {
          return AppError(
            category: AppErrorCategory.notFound,
            userMessage: message ?? 'The requested item could not be found.',
            errorCode: code!,
            debugDetails: debugDetails,
          );
        }
        if (message != null && message.isNotEmpty) {
          return AppError(
            category: (statusCode == 502 || statusCode == 503)
                ? AppErrorCategory.upstreamUnavailable
                : AppErrorCategory.unknown,
            userMessage: message,
            actionLabel: 'Retry',
            actionType: AppActionType.retry,
            errorCode: code ?? 'ERR_HTTP_$statusCode',
            debugDetails: debugDetails,
          );
        }
      }
    }

    switch (statusCode) {
      case 429:
        return AppError.rateLimited(retryAfterSeconds: retryAfter, debugDetails: debugDetails);
      case 502:
      case 503:
        return AppError.serverWaking(debugDetails: debugDetails);
      case 404:
        return const AppError(
          category: AppErrorCategory.notFound,
          userMessage: 'The requested song or playlist could not be found.',
          errorCode: 'ERR_NOT_FOUND',
        );
      case 500:
      case 504:
        return AppError(
          category: AppErrorCategory.upstreamUnavailable,
          userMessage: 'The music provider is temporarily unreachable. Please try another track.',
          actionLabel: 'Retry',
          actionType: AppActionType.retry,
          errorCode: 'ERR_UPSTREAM_500',
          debugDetails: debugDetails,
        );
      default:
        return AppError(
          category: AppErrorCategory.unknown,
          userMessage: 'Server returned error $statusCode. Please try again.',
          actionLabel: 'Retry',
          actionType: AppActionType.retry,
          errorCode: 'ERR_HTTP_$statusCode',
          debugDetails: debugDetails,
        );
    }
  }
}
