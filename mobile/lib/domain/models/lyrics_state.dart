import 'app_error.dart';

enum LyricsStatus {
  idle,
  loading,
  loaded,
  notFound,
  error,
  rejectedMismatch,
}

/// Language selection mode for song lyrics
enum LyricsLanguage {
  defaultLang,
  english,
}

/// Encapsulates dual-language lyric variants: native script vs Romanized English
class DualLyrics {
  final String defaultLyrics;
  final String englishLyrics;
  final String detectedScript;
  final bool isSynced;

  const DualLyrics({
    required this.defaultLyrics,
    required this.englishLyrics,
    this.detectedScript = 'latin',
    this.isSynced = false,
  });

  /// Resolves effective lyrics for the given language mode
  String getLyricsForLanguage(LyricsLanguage lang) {
    if (lang == LyricsLanguage.english && englishLyrics.trim().isNotEmpty) {
      return englishLyrics;
    }
    return defaultLyrics;
  }

  /// True if distinct default and English variants are available
  bool get hasMultipleVariants =>
      englishLyrics.trim().isNotEmpty &&
      defaultLyrics.trim().isNotEmpty &&
      englishLyrics.trim() != defaultLyrics.trim();

  DualLyrics copyWith({
    String? defaultLyrics,
    String? englishLyrics,
    String? detectedScript,
    bool? isSynced,
  }) {
    return DualLyrics(
      defaultLyrics: defaultLyrics ?? this.defaultLyrics,
      englishLyrics: englishLyrics ?? this.englishLyrics,
      detectedScript: detectedScript ?? this.detectedScript,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

/// Strongly-typed lyrics state distinguishing loading, loaded, not-found,
/// connection failures, and mismatched tracks.
class LyricsState {
  final LyricsStatus status;
  final String? lyrics;
  final DualLyrics? dualLyrics;
  final AppError? error;

  const LyricsState({
    required this.status,
    this.lyrics,
    this.dualLyrics,
    this.error,
  });

  const LyricsState.idle()
      : status = LyricsStatus.idle,
        lyrics = null,
        dualLyrics = null,
        error = null;

  const LyricsState.loading()
      : status = LyricsStatus.loading,
        lyrics = null,
        dualLyrics = null,
        error = null;

  const LyricsState.loaded(String lrc, {this.dualLyrics})
      : status = LyricsStatus.loaded,
        lyrics = lrc,
        error = null;

  const LyricsState.notFound()
      : status = LyricsStatus.notFound,
        lyrics = null,
        dualLyrics = null,
        error = null;

  const LyricsState.error(AppError err)
      : status = LyricsStatus.error,
        lyrics = null,
        dualLyrics = null,
        error = err;

  const LyricsState.rejectedMismatch()
      : status = LyricsStatus.rejectedMismatch,
        lyrics = null,
        dualLyrics = null,
        error = null;

  bool get hasLyrics =>
      (lyrics != null && lyrics!.trim().isNotEmpty) ||
      (dualLyrics != null && dualLyrics!.defaultLyrics.trim().isNotEmpty);
}
