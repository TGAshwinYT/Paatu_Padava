enum AppErrorCategory {
  offline,
  serverWaking,
  timeout,
  rateLimited,
  notFound,
  upstreamUnavailable,
  songUnavailable,
  authInvalidCredentials,
  authEmailExists,
  authWeakPassword,
  authInvalidEmail,
  storageFull,
  permissionDenied,
  unknown,
}

enum AppActionType {
  retry,
  openDownloads,
  skipSong,
  signIn,
  openSettings,
  none,
}

/// Unified domain error model representing actionable application-level errors
class AppError {
  final AppErrorCategory category;
  final String userMessage;
  final String? actionLabel;
  final AppActionType actionType;
  final String errorCode;
  final int? retryAfterSeconds;
  final String? debugDetails;

  const AppError({
    required this.category,
    required this.userMessage,
    this.actionLabel,
    this.actionType = AppActionType.none,
    required this.errorCode,
    this.retryAfterSeconds,
    this.debugDetails,
  });

  /// Factory helper for creating common offline errors
  factory AppError.offline({String? customMessage, String? debugDetails}) {
    return AppError(
      category: AppErrorCategory.offline,
      userMessage: customMessage ?? "You're offline. Check your internet connection or browse your offline downloads.",
      actionLabel: 'Open Downloads',
      actionType: AppActionType.openDownloads,
      errorCode: 'ERR_OFFLINE',
      debugDetails: debugDetails,
    );
  }

  /// Factory helper for server waking / cold start
  factory AppError.serverWaking({String? debugDetails}) {
    return AppError(
      category: AppErrorCategory.serverWaking,
      userMessage: 'The music server is starting up. Please give it a few seconds and try again.',
      actionLabel: 'Retry',
      actionType: AppActionType.retry,
      errorCode: 'ERR_SERVER_WAKING',
      debugDetails: debugDetails,
    );
  }

  /// Factory helper for timeout
  factory AppError.timeout({String? debugDetails}) {
    return AppError(
      category: AppErrorCategory.timeout,
      userMessage: 'The request took too long to complete. Please try again.',
      actionLabel: 'Retry',
      actionType: AppActionType.retry,
      errorCode: 'ERR_TIMEOUT',
      debugDetails: debugDetails,
    );
  }

  /// Factory helper for rate limits
  factory AppError.rateLimited({int? retryAfterSeconds, String? debugDetails}) {
    final secs = retryAfterSeconds ?? 30;
    return AppError(
      category: AppErrorCategory.rateLimited,
      userMessage: 'Too many requests. Please wait $secs seconds before trying again.',
      actionLabel: 'Retry',
      actionType: AppActionType.retry,
      errorCode: 'ERR_RATE_LIMITED',
      retryAfterSeconds: secs,
      debugDetails: debugDetails,
    );
  }

  /// Factory helper for unplayable song
  factory AppError.songUnavailable(String songTitle, {String? debugDetails}) {
    return AppError(
      category: AppErrorCategory.songUnavailable,
      userMessage: 'Unable to stream "$songTitle". Skipping to the next track.',
      actionLabel: 'Skip',
      actionType: AppActionType.skipSong,
      errorCode: 'ERR_SONG_UNAVAILABLE',
      debugDetails: debugDetails,
    );
  }

  /// Factory helper for not found errors
  factory AppError.notFound([String? message, String? debugDetails]) {
    return AppError(
      category: AppErrorCategory.notFound,
      userMessage: message ?? 'Requested item was not found.',
      actionLabel: 'Go Back',
      actionType: AppActionType.none,
      errorCode: 'ERR_NOT_FOUND',
      debugDetails: debugDetails,
    );
  }

  /// Factory helper for internal system or uninitialized state errors
  factory AppError.internal(String message, {String code = 'ERR_INTERNAL', String? debugDetails}) {
    return AppError(
      category: AppErrorCategory.unknown,
      userMessage: message,
      actionLabel: 'OK',
      actionType: AppActionType.none,
      errorCode: code,
      debugDetails: debugDetails,
    );
  }

  @override
  String toString() => 'AppError($errorCode: $userMessage)';
}
