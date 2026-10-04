import 'app_error.dart';

enum LyricsStatus {
  idle,
  loading,
  loaded,
  notFound,
  error,
  rejectedMismatch,
}

/// Strongly-typed lyrics state distinguishing loading, loaded, not-found,
/// connection failures, and mismatched tracks.
class LyricsState {
  final LyricsStatus status;
  final String? lyrics;
  final AppError? error;

  const LyricsState({
    required this.status,
    this.lyrics,
    this.error,
  });

  const LyricsState.idle()
      : status = LyricsStatus.idle,
        lyrics = null,
        error = null;

  const LyricsState.loading()
      : status = LyricsStatus.loading,
        lyrics = null,
        error = null;

  const LyricsState.loaded(String lrc)
      : status = LyricsStatus.loaded,
        lyrics = lrc,
        error = null;

  const LyricsState.notFound()
      : status = LyricsStatus.notFound,
        lyrics = null,
        error = null;

  const LyricsState.error(AppError err)
      : status = LyricsStatus.error,
        lyrics = null,
        error = err;

  const LyricsState.rejectedMismatch()
      : status = LyricsStatus.rejectedMismatch,
        lyrics = null,
        error = null;

  bool get hasLyrics => (lyrics != null && lyrics!.trim().isNotEmpty);
}
