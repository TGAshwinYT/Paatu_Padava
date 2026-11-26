part of '../player_handler.dart';

extension PlayerLyricsExt on PaatuAudioHandler {
  void setLyricsLanguage(LyricsLanguage lang) {
    lyricsLanguageNotifier.value = lang;
    SettingsManager.setLyricsPreferredLanguage(lang == LyricsLanguage.english ? 'english' : 'default');
    final dual = dualLyricsNotifier.value;
    if (dual != null) {
      final selected = dual.getLyricsForLanguage(lang);
      currentLyricsNotifier.value = selected;
      lyricsStateNotifier.value = LyricsState.loaded(selected, dualLyrics: dual);
    }
  }

  void setCustomLyrics(String rawLyrics) {
    final dual = _buildDualLyrics(rawLyrics);
    dualLyricsNotifier.value = dual;
    final selected = dual.getLyricsForLanguage(lyricsLanguageNotifier.value);
    currentLyricsNotifier.value = selected;
    lyricsStateNotifier.value = LyricsState.loaded(selected, dualLyrics: dual);
  }

  Future<void> adjustLyricsOffset(int deltaMs) async {
    final curSong = currentSong;
    if (curSong == null) return;
    final newOffset = lyricsOffsetMsNotifier.value + deltaMs;
    lyricsOffsetMsNotifier.value = newOffset;
    await LyricsClient.instance.saveLyricsOffset(curSong.id, newOffset);
  }

  Future<void> resetLyricsOffset() async {
    final curSong = currentSong;
    if (curSong == null) return;
    lyricsOffsetMsNotifier.value = 0;
    await LyricsClient.instance.saveLyricsOffset(curSong.id, 0);
  }

  void toggleKaraokeMode() {
    final next = !isKaraokeModeNotifier.value;
    isKaraokeModeNotifier.value = next;
    if (next) {
      final target = vocalAttenuationNotifier.value > 0.0 ? vocalAttenuationNotifier.value : 0.85;
      vocalAttenuationNotifier.value = target;
      EqualizerService.setVocalAttenuation(target);
    } else {
      EqualizerService.setVocalAttenuation(0.0);
    }
  }

  void setVocalAttenuation(double factor) {
    final clamped = factor.clamp(0.0, 1.0);
    vocalAttenuationNotifier.value = clamped;
    EqualizerService.setVocalAttenuation(clamped);
  }

  DualLyrics _buildDualLyrics(String rawLyrics) {
    final isSynced = ApiClient.isSyncedLrc(rawLyrics);
    final script = IndicRomanizer.detectScript(rawLyrics);
    if (IndicRomanizer.hasIndicScript(rawLyrics)) {
      final romanized = IndicRomanizer.romanizeLyrics(rawLyrics);
      return DualLyrics(
        defaultLyrics: rawLyrics,
        englishLyrics: romanized,
        detectedScript: script,
        isSynced: isSynced,
      );
    } else {
      return DualLyrics(
        defaultLyrics: rawLyrics,
        englishLyrics: rawLyrics,
        detectedScript: 'latin',
        isSynced: isSynced,
      );
    }
  }

  Future<void> reloadLyrics({Song? targetSong}) async {
    final song = targetSong ?? currentSong;
    if (song == null) {
      lyricsStateNotifier.value = const LyricsState.idle();
      currentLyricsNotifier.value = null;
      dualLyricsNotifier.value = null;
      return;
    }

    if (song.lyrics != null && song.lyrics!.isNotEmpty) {
      final dual = _buildDualLyrics(song.lyrics!);
      dualLyricsNotifier.value = dual;
      final selected = dual.getLyricsForLanguage(lyricsLanguageNotifier.value);
      currentLyricsNotifier.value = selected;
      lyricsStateNotifier.value = LyricsState.loaded(selected, dualLyrics: dual);
      return;
    }

    lyricsStateNotifier.value = const LyricsState.loading();
    try {
      final state = await SongRepository.getLyricsForSong(song);
      if (currentSong?.id != song.id) return;
      lyricsStateNotifier.value = state;
      if (state.status == LyricsStatus.loaded && state.lyrics != null) {
        final dual = state.dualLyrics ?? _buildDualLyrics(state.lyrics!);
        dualLyricsNotifier.value = dual;
        final selected = dual.getLyricsForLanguage(lyricsLanguageNotifier.value);
        currentLyricsNotifier.value = selected;
      } else {
        currentLyricsNotifier.value = null;
        dualLyricsNotifier.value = null;
      }
    } catch (e, stack) {
      if (currentSong?.id != song.id) return;
      final appErr = ErrorHandler.resolve(e, stackTrace: stack, context: 'PaatuAudioHandler.reloadLyrics');
      lyricsStateNotifier.value = LyricsState.error(appErr);
    }
  }

  void _checkLyricsDurationReselection(Song song, int actualDurationSeconds) {
    if (actualDurationSeconds <= 0) return;
    if (_lastReselectedDurationSec == actualDurationSeconds) return;
    _lastReselectedDurationSec = actualDurationSeconds;

    unawaited(() async {
      final newState = await LyricsClient.instance.reselectForActualDuration(
        trackId: song.id,
        actualDurationSeconds: actualDurationSeconds,
      );
      if (newState != null && currentSong?.id == song.id) {
        lyricsStateNotifier.value = newState;
        if (newState.lyrics != null) {
          final dual = newState.dualLyrics ?? _buildDualLyrics(newState.lyrics!);
          dualLyricsNotifier.value = dual;
          final selected = dual.getLyricsForLanguage(lyricsLanguageNotifier.value);
          currentLyricsNotifier.value = selected;
        }
      }
    }());
  }
}
