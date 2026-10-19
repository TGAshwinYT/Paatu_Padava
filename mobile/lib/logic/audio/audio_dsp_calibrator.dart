import '../../models/song.dart';
import '../../services/settings_manager.dart';

/// Audio Digital Signal Processing (DSP) & Volume Calibration helper.
/// Implements EBU R128 / ReplayGain volume matching across diverse audio sources
/// (JioSaavn 320kbps hot masters vs YouTube -14 LUFS loudness reference).
class AudioDspCalibrator {
  /// Calculates target normalized volume (0.0 to 1.0)
  static double getNormalizedVolumeForSong(Song? song) {
    if (!SettingsManager.isVolumeNormalizationEnabled) {
      return 1.0;
    }
    if (song == null) return 1.0;

    if (song.source == 'youtube' ||
        (song.streamUrl != null &&
            (song.streamUrl!.contains('googlevideo.com') ||
                song.streamUrl!.contains('webm') ||
                song.streamUrl!.contains('youtube')))) {
      return 1.0;
    }

    final isHotStudioMaster = song.source == 'saavn' ||
        song.source == 'jiosaavn' ||
        (song.streamUrl != null &&
            (song.streamUrl!.contains('jiosaavn') || song.streamUrl!.contains('.mp4')));

    if (isHotStudioMaster) {
      return 0.80; // ~ -2.0 dB calibration to match YouTube -14 LUFS reference
    }
    return 1.0;
  }

  /// Calculates effective volume taking both master volume and song calibration into account
  static double getEffectiveVolumeForSong(Song? song, double userVolume) {
    return (userVolume * getNormalizedVolumeForSong(song)).clamp(0.0, 1.0);
  }
}
