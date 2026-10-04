import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:paatu_padava_mobile/domain/models/app_error.dart';
import 'package:paatu_padava_mobile/services/error_handler.dart';

void main() {
  group('ErrorHandler.resolve', () {
    test('Resolves SocketException to offline AppError', () {
      final error = ErrorHandler.resolve(const SocketException('Failed host lookup'));
      expect(error.category, equals(AppErrorCategory.offline));
      expect(error.actionType, equals(AppActionType.openDownloads));
      expect(error.userMessage.toLowerCase(), contains('internet connection'));
    });

    test('Resolves TimeoutException to timeout AppError', () {
      final error = ErrorHandler.resolve(TimeoutException('Request timed out', const Duration(seconds: 8)));
      expect(error.category, equals(AppErrorCategory.timeout));
      expect(error.actionType, equals(AppActionType.retry));
      expect(error.userMessage.toLowerCase(), contains('took too long'));
    });

    test('Resolves http.ClientException to offline AppError with openDownloads action', () {
      final error = ErrorHandler.resolve(http.ClientException('Connection closed before full header was received'));
      expect(error.category, equals(AppErrorCategory.offline));
      expect(error.actionType, equals(AppActionType.openDownloads));
    });

    test('Resolves FileSystemException with ENOSPC to storageFull AppError', () {
      final error = ErrorHandler.resolve(const FileSystemException('No space left on device (ENOSPC)', '/music/song.m4a'));
      expect(error.category, equals(AppErrorCategory.storageFull));
      expect(error.actionType, equals(AppActionType.openSettings));
      expect(error.userMessage, contains('Device storage is full'));
    });

    test('Resolves existing AppError by returning itself', () {
      final original = AppError.notFound('Song was not found.');
      final resolved = ErrorHandler.resolve(original);
      expect(identical(resolved, original), isTrue);
    });

    group('AuthException resolution', () {
      test('Maps weak password (422) correctly', () {
        final error = ErrorHandler.resolve(const AuthException('Password should be at least 6 characters', statusCode: '422'));
        expect(error.category, equals(AppErrorCategory.authWeakPassword));
        expect(error.userMessage, contains('at least 6 characters'));
      });

      test('Maps email already registered (422) correctly', () {
        final error = ErrorHandler.resolve(const AuthException('User already registered', statusCode: '422'));
        expect(error.category, equals(AppErrorCategory.authEmailExists));
        expect(error.actionType, equals(AppActionType.signIn));
        expect(error.userMessage, contains('already registered'));
      });

      test('Maps invalid login credentials (400) correctly', () {
        final error = ErrorHandler.resolve(const AuthException('Invalid login credentials', statusCode: '400'));
        expect(error.category, equals(AppErrorCategory.authInvalidCredentials));
        expect(error.userMessage, contains('Incorrect email or password'));
      });

      test('Maps network/socket AuthException to offline', () {
        final error = ErrorHandler.resolve(const AuthException('Failed host lookup: network is down'));
        expect(error.category, equals(AppErrorCategory.offline));
        expect(error.actionType, equals(AppActionType.openDownloads));
      });
    });

    group('HTTP Status Code Resolution', () {
      test('Maps 429 to rateLimited', () {
        final error = ErrorHandler.resolveHttpStatus(429);
        expect(error.category, equals(AppErrorCategory.rateLimited));
        expect(error.userMessage, contains('Too many requests'));
      });

      test('Maps default 502 and 503 to serverWaking', () {
        final err502 = ErrorHandler.resolveHttpStatus(502);
        expect(err502.category, equals(AppErrorCategory.serverWaking));
        expect(err502.userMessage, contains('starting up'));

        final err503 = ErrorHandler.resolveHttpStatus(503);
        expect(err503.category, equals(AppErrorCategory.serverWaking));
      });

      test('Maps 404 to notFound', () {
        final error = ErrorHandler.resolveHttpStatus(404);
        expect(error.category, equals(AppErrorCategory.notFound));
      });

      test('Parses structured JSON response body from backend with UPSTREAM_UNAVAILABLE', () {
        const body = '{"detail":{"code":"UPSTREAM_UNAVAILABLE","message":"Saavn search service unreachable."}}';
        final error = ErrorHandler.resolveHttpStatus(502, responseBody: body);
        expect(error.category, equals(AppErrorCategory.upstreamUnavailable));
        expect(error.userMessage, equals('Saavn search service unreachable.'));
      });
    });
  });
}
