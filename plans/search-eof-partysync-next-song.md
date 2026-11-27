# Plan: Search Autoplay EOF Fix, PartySync Queue/Latency Hardening & Same-Language Next-Song Mode Selector

Status: DRAFT
Owner agent: mobile_engineer

## 1. Goal (one sentence, user-visible)
Fix Search single-song playback stalling at end-of-track, make PartySync play through the Host's full queue smoothly without jitter/stutter, and lock next-song recommendations to the current song's language (including English) with a user-selectable algorithm/vibe picker (Mix, Composer, Familiar, Discover, AI Engines) inside the live Audio Quality settings and Queue tuner bar.

## 2. Non-goals (what we are NOT doing)
- Rewriting the Supabase Realtime or LAN UDP socket transport layers (`PartyLanAccelerator` stays intact).
- Adding a backend proxy dependency for recommendations (all language inference and strategy execution remain on-device).
- Changing search ranking or Spotify import behavior (`SearchQueryPlanner`, `SpotifyImportService`).
- Modifying existing downloaded files or playlist schemas on Supabase.

## 3. Current state (verified by reading code)
- **Existing screens/widgets/services involved (with file paths)**:
  - Search & Autoplay EOF pipeline:
    - `mobile/lib/ui/widgets/search/search_body_content.dart` (tapping a search song calls `audioHandler.playSong(song, preserveUserQueue: true)`)
    - `mobile/lib/logic/audio/queue_listeners_ext.dart` (`_positionSub` 25% prefetch, `_currentIndexSub` gapless advance, `_playerStateSub` `ProcessingState.completed` lines 147–221)
    - `mobile/lib/logic/audio/queue_skip_ext.dart` (`_skipToNextImpl` — holds `_isTransitioning = true` at line 14 across `await handleAutoplayQueueEnd` at line 120, deadlocking `handleAutoplayQueueEnd -> skipToNext`)
    - `mobile/lib/logic/audio/queue_suggestions_ext.dart` (`_addAutoSuggestionsImpl` lines 48–90)
    - `mobile/lib/logic/audio/queue_mutation_ext.dart` (existing 305-line file, `part of '../audio_queue_handler.dart'`)
    - `mobile/lib/logic/audio/queue_source_builder.dart` (`preloadUpcomingTracks`)
    - `mobile/lib/services/player/player_recommendations_ext.dart` (`prefetchNextRecommendations`, `handleAutoplayQueueEnd`, `startSongRadio`)
  - PartySync pipeline:
    - `mobile/lib/services/party_sync_coordinator.dart` (`hostPlaySong`, `_handleRemoteQueue` lines 361–385, `notifyHostTrackTransition`, `_handleHeartbeatReconciliation` lines 545–593)
    - `mobile/lib/services/party/party_host_controls.dart` (`_notifyHostPlayImpl` lines 3–120, `_broadcastCurrentStateImpl`, `_hostTransitionToNextImpl`, `_notifyHostQueueUpdatedImpl`)
    - `mobile/lib/services/party/party_host_flow.dart` (`_startPartyImpl` — runs a separate `_hostHeartbeatTimer` every 2s; `_leavePartyImpl` lines 223–292)
    - `mobile/lib/services/party/party_joiner_flow.dart` (`_joinPartyImpl` — registers LAN switch at lines 61–80 & Supabase broadcast listeners at lines 85–115)
    - `mobile/lib/services/party/party_remote_handlers.dart` (`_handleRemotePrepareImpl`, `_handleRemotePlayImpl`, `_handleRemoteSeekImpl`)
    - `mobile/lib/logic/party_sync_engine.dart` (`NtpCalculator`, `DriftReconciler` lines 146–215, `ScheduledPlaybackCalculator`)
    - `mobile/lib/logic/audio/queue_loader_ext.dart` (`_loadQueueImpl` sets `isPartyDrivenLoad = true` at line 12 and **never resets it**; `finally` at lines 197–202 only resets `_isLoading`; also appends `nextTrack` to `_playlistSource`)
    - `mobile/lib/logic/audio/queue_playback_ext.dart` (`_playTrackEntityImpl` fires `onSongChanged` before `setAudioSource`/`play()`, and `_advanceToNextTrackFromPlayerStreamImpl` / `_sequenceStateSub` fires `onSongChanged` for Host gapless `ConcatenatingAudioSource` auto-advance)
    - `mobile/lib/services/player_handler.dart` (`PaatuAudioHandler` extends `BaseAudioHandler` without overriding `setSpeed(double)` anywhere in its 7 part files — `BaseAudioHandler.setSpeed` is a silent no-op; `setSpeed` override MUST be placed directly on `class PaatuAudioHandler` in `player_handler.dart`)
  - Next-Song Algorithm & Language Selection:
    - `mobile/lib/logic/next_track_strategy.dart` (`NextTrackStrategyMode`, `UnifiedSmartRadioStrategy`, `SpotifyStyleStrategy`, `YtMusicStyleStrategy`, `NextTrackStrategyFactory`, `getLocalFallbackTracks` — only 3/4 strategies call `getLocalFallbackTracks`; `MarkovCosineRadioStrategy` does not)
    - `mobile/lib/logic/markov_cosine_radio_strategy.dart` (`MarkovCosineRadioStrategy`, `SongFeatureVector`)
    - `mobile/lib/services/radio_engine.dart` (`_knownMusicDirectors`, `generateCandidatePool`, `applyHardFiltering`, `scoreAndReRankCandidates`, `buildSongRadio`, `shapeRadioQueue` — `buildSongRadio(current)` always prepends `seedSong`; when `shaped` is empty it returns `[current]` length 1, so `addAutoSuggestions` deduplicates `current` to 0 tracks and EOF stalls)
    - `mobile/lib/logic/smart_shuffle_controller.dart` (`ingestSmartRecommendations`)
    - `mobile/lib/logic/queue/queue_tuner_mode.dart` & `mobile/lib/logic/queue/queue_tuner_controller.dart` (`Mix`, `Familiar`, `Discover`, `Composer` — `modeNotifier` hardcoded to `QueueTunerMode.mix`; `filterAndRankCandidates` at line 76 has no `sameLanguageLock` param; `setTunerMode` at lines 44–54 invokes `strategy.getUpcomingTracks` / `RadioEngine.applyHardFiltering` upstream, which strips history/favorites before `_rankForFamiliar` runs)
    - `mobile/lib/data/catalog_artists_seed.dart` (`CatalogArtistsSeed.data` — multi-language artists: Shreya Ghoshal at tamil+hindi, Thaman S at tamil+telugu, Hesham Abdul Wahab at tamil+malayalam)
    - `mobile/lib/services/settings_manager.dart` (currently **397 lines**; `init()` reads EQ + `stereoBalance` at lines 131–152 and 183–184)
    - `mobile/lib/ui/screens/audio_quality_settings_screen.dart` (currently **604 lines**; renders inline `_buildAutoplaySection()`, `_buildCrossfadeSection()`, and `_buildPersistentBackgroundPlaybackSection()` — does **NOT** embed `AudioQualitySettingsCard`)
    - `mobile/lib/ui/widgets/settings/audio_quality_settings_card.dart` (**290 lines**; unused in `AudioQualitySettingsScreen`, has duplicate `autoplayNotifier` lines 54–72, `crossfadeDurationNotifier` lines 74–121, `nextTrackStrategyNotifier` lines 123–183, and 14+ hardcoded `Color(0xFF...)` / raw `fontSize` literals)
    - `mobile/lib/ui/widgets/queue/queue_tuner_bar.dart` (71 lines — accesses `audioHandler` global directly, no test params)
    - `mobile/lib/services/smart_gapless_precacher.dart` (`precacheTrackHeader` is a **deprecated no-op** — `return;` at line 63)
    - `mobile/lib/services/smart_cache_service.dart` (324 lines — has NO header-warm method)
- **What can be reused**:
  - `QueueTunerMode` (`mix`, `familiar`, `discover`, `composer`) and `QueueTunerController.filterAndRankCandidates`.
  - `CatalogArtistsSeed.data` and `SongRepository.tamilArtistSeeds` / `SongRepository.isLanguageMismatch` (Indic script regexes) — collecting multi-language artists as `Set<String>` keyed by normalized artist name.
  - `NtpCalculator`, `DriftReconciler`, `ScheduledPlaybackCalculator` in `party_sync_engine.dart`.
  - `AppColors` and `Theme.of(context).textTheme` tokens from `mobile/lib/ui/theme/app_theme.dart`.
  - `PartySyncCoordinator.resolveLocalDownloadedCopy(song)` (`mobile/lib/services/party_sync_coordinator.dart:287`) to check for local copy before prewarm.
- **Known problems nearby (verified)**:
  1. **Search EOF stuck**:
     - `queue_skip_ext.dart:14, 120` holds `_isTransitioning = true` across `await audioHandler.handleAutoplayQueueEnd(...)`; `handleAutoplayQueueEnd` (`player_recommendations_ext.dart:66`) calls `skipToNext(isUserInitiated: false)`, hitting `if (_isTransitioning) return;` (`queue_skip_ext.dart:10`) and silently aborting.
     - `player_recommendations_ext.dart:25` vs `:52`: if 25% prefetch is mid-flight when `ProcessingState.completed` fires, `handleAutoplayQueueEnd` races with it; `UnifiedSmartRadioStrategy` uses a `1500ms` timeout on `YouTubeClient.getRadioTracks` (`next_track_strategy.dart:855, 869`) while `SaavnClient.getRelatedSongs(ytId)` returns empty for YouTube search IDs.
     - `RadioEngine.buildSongRadio(current)` always prepends `seedSong`; when `shaped` is empty it returns `[current]` (length 1); `addAutoSuggestions` deduplicates `current` away → 0 new tracks → EOF stall.
     - If `addAutoSuggestions` finishes *after* ExoPlayer enters `ProcessingState.completed`, `preloadUpcomingTracks()` adds to `_playlistSource` without starting playback.
  2. **PartySync 1-song stop, different songs, and audio disturbance**:
     - `PaatuAudioHandler` (`player_handler.dart`) never overrides `setSpeed(double speed)` — `BaseAudioHandler.setSpeed` is a no-op.
     - `queue_loader_ext.dart:12` sets `isPartyDrivenLoad = true` and never resets it, so Host tracks after Song 1 stop triggering `notifyHostTrackTransition`.
     - Joiner appends `nextTrack` to `_playlistSource`, so ExoPlayer auto-advances via `ConcatenatingAudioSource` + `_sequenceStateSub` without Host permission; `queue_listeners_ext.dart:72` triggers `prefetchNextRecommendations` on Joiner too.
     - `_advanceToNextTrackFromPlayerStreamImpl` / `_sequenceStateSub` fires `onSongChanged` while Host ExoPlayer is already playing Song N+1 → triggers `notifyHostTrackTransition` → pauses after play.
     - On Host, `_playTrackEntityImpl` fires `onSongChanged` before `setAudioSource`/`play()`, colliding with `_notifyHostPlayImpl` barrier await.
     - `_pendingPrepareCmdId` is set in `_notifyHostPlayImpl` (line 16) and only cleared in `_leavePartyImpl` (`party_host_flow.dart:289`) — never reset after the barrier/stale-check, deadlocking `notifyHostTrackTransition` suppression check.
     - `_hostHeartbeatTimer` sends `sync_heartbeat` without `song`/`currentIndex`; `_notifyHostQueueUpdatedImpl` omits `PartyLanAccelerator.sendSyncEvent`; `_handleRemoteQueue` calls `playSong` even when `currentSong?.id == targetSong.id`.
  3. **English / Language mismatch & Next-Song selector**:
     - Strategy fallbacks use `prefLangs.firstOrNull` or literal `'tamil'` when `seedSong.language == null`.
     - `RadioEngine.applyHardFiltering` has no script check and skips filtering when `c.language == null`.
     - `QueueTunerController.setTunerMode` (`queue_tuner_controller.dart:44–54`) invokes upstream `strategy.getUpcomingTracks` / `applyHardFiltering`, stripping history/favorites before `_rankForFamiliar` runs.
     - Passing `null` targetLanguage to `RadioEngine` still hard-filters to `seedSong.language`; need explicit `enforceLanguage: bool`.
     - Multi-language artists in `CatalogArtistsSeed.data` will cause first-match misclassification.
  4. **Monolith file-size constraints (`.agent/rules/file-size-limits.md`)**:
     - `player_handler.dart` (692 lines), `party_sync_coordinator.dart` (597 lines), `next_track_strategy.dart` (1077 lines), `radio_engine.dart` (506 lines), `settings_manager.dart` (397 lines), and `audio_quality_settings_screen.dart` (604 lines) must not gain net-new bytes without extracting cohesive modules first.

## 4. Design
- **Files to add or change (strictly honoring file-size limits)**:
  - `[NEW]` `mobile/lib/logic/language_detector.dart` (`< 160` lines): `LanguageDetector.inferSongLanguage`, `LanguageDetector.isLanguageCompatible`, `LanguageDetector.composerLanguageMap`. Builds `Map<String, Set<String>>` from `CatalogArtistsSeed.data` collecting ALL language values per normalized artist name.
  - `[NEW]` `mobile/lib/services/settings_manager_eq_ext.dart` (`part of 'settings_manager.dart';`, `< 150` lines): top-level impl functions moved from `settings_manager.dart` (`_initEqFromBoxImpl(Box box)` covering lines 131–152 + `stereoBalance` lines 183–184, `_setEqPresetImpl`, `_setEqBandImpl`, `_setBassBoostImpl`, `_setVirtualizerImpl`, `_saveCustomEqPresetImpl`, `_deleteCustomEqPresetImpl`, `_setStereoBalanceImpl`). Inside `class SettingsManager`, `init()` calls `_initEqFromBoxImpl(_box);` and the static EQ/stereo methods become 1-line forwarders (`static Future<void> setStereoBalance(double b) => _setStereoBalanceImpl(b);`). Net reduction ~100 lines → `settings_manager.dart` stays under **350 lines** after adding `sameLanguageLock` & `preferredTunerMode`.
  - `[MODIFY]` `mobile/lib/services/settings_manager.dart` — add `sameLanguageLockNotifier` + `preferredTunerModeNotifier` (local Hive persistence only; not cloud-synced).
  - `[NEW]` `mobile/lib/logic/next_track_fallback_helper.dart` (`< 170` lines): extracts `getLocalFallbackTracks` helpers (~76 lines) AND `enforceArtistDispersionAndNoBackToBack` (~74 lines) out of `next_track_strategy.dart`.
  - `[MODIFY]` `mobile/lib/logic/next_track_strategy.dart`, `mobile/lib/logic/markov_cosine_radio_strategy.dart`, `mobile/lib/services/radio_engine.dart`, `mobile/lib/logic/smart_shuffle_controller.dart`, `mobile/lib/logic/queue/queue_tuner_controller.dart`
  - `[NEW]` `mobile/lib/services/radio_language_filter.dart` (`part of 'radio_engine.dart';`, `< 200` lines): extracts `applyHardFiltering` (~106 lines) + `_knownMusicDirectors` (~54 lines) + `isSharedMusicDirectorOrComposer` (~34 lines) = ~194 lines from `radio_engine.dart`, keeping `radio_engine.dart` under **350 lines**.
  - `[MODIFY]` `mobile/lib/logic/audio/queue_listeners_ext.dart`, `queue_skip_ext.dart`, `queue_loader_ext.dart`, `queue_playback_ext.dart`, `queue_mutation_ext.dart` (existing file), `queue_source_builder.dart`, `queue_suggestions_ext.dart`, `mobile/lib/logic/audio_queue_handler.dart`
  - `[NEW]` `mobile/lib/services/player/player_party_ext.dart` (`part of '../player_handler.dart';`, `< 100` lines): houses `_onActiveTrackChanged` extraction (~57 lines from `player_handler.dart:367-423`) for net-negative delta on `player_handler.dart`, plus `_inFlightPrefetchFuture` getter/setter wrapper and `_syncHostTrackTransition`. **`setSpeed` override is NOT here** — `@override Future<void> setSpeed(double speed) => _player.setSpeed(speed);` goes directly on `class PaatuAudioHandler` in `player_handler.dart`.
  - `[MODIFY]` `mobile/lib/services/player_handler.dart`, `mobile/lib/services/player/player_recommendations_ext.dart`
  - `[NEW]` `mobile/lib/services/party/party_drift_controller.dart` (`part of '../party_sync_coordinator.dart';`, `< 260` lines): declares top-level `_lookaheadAckedSongIds`, `_lookaheadPreparedIds`, `_lastAppliedSpeed`, `_lastScheduledPlayActualEpochMs`, `_driftSmoother`, and extracts `_handleHeartbeatReconciliationImpl`, `_prewarmUpcomingTracksImpl`, and post-start `2500ms` grace window out of `party_sync_coordinator.dart` (shrinking it below 20 KB). `PartySyncCoordinator` retains 1-line static forwarders `_prewarmUpcomingTracks` -> `_prewarmUpcomingTracksImpl` and `_handleHeartbeatReconciliation` -> `_handleHeartbeatReconciliationImpl`.
  - `[MODIFY]` `mobile/lib/logic/party_sync_engine.dart`, `mobile/lib/services/party/party_host_controls.dart`, `party/party_host_flow.dart`, `party/party_joiner_flow.dart`, `party/party_remote_handlers.dart`, `mobile/lib/services/party_sync_coordinator.dart`
  - `[NEW]` `mobile/lib/ui/widgets/settings/next_song_preferences_card.dart` (`< 240` lines): live card using `AppColors` + `Theme.of(context).textTheme` for **Same-Language Lock** toggle, **Next Song Mode** (`Mix`, `Composer`, `Familiar`, `Discover`), and **AI Matching Engine** selector (`Unified Smart Radio`, `Spotify Style`, `YT Music Style`, `Markov-Cosine`). Replaces `_buildAutoplaySection()` in `AudioQualitySettingsScreen`.
  - `[NEW]` `mobile/lib/ui/widgets/settings/playback_transitions_card.dart` (`< 180` lines): extracts Crossfade/DJ-Automix (`_buildCrossfadeSection`) + Persistent Background Playback (`_buildPersistentBackgroundPlaybackSection`) controls out of `AudioQualitySettingsScreen`.
  - `[MODIFY]` `mobile/lib/ui/screens/audio_quality_settings_screen.dart` — replace `_buildAutoplaySection()` with `const NextSongPreferencesCard()` and replace `_buildCrossfadeSection()` + `_buildPersistentBackgroundPlaybackSection()` with `const PlaybackTransitionsCard()` to drop below 300 lines. (Note: `AudioQualitySettingsScreen` does not embed `AudioQualitySettingsCard`, so both cleanups are independent.)
  - `[MODIFY]` `mobile/lib/ui/widgets/settings/audio_quality_settings_card.dart` — remove duplicate `autoplayNotifier` (lines 54–72), `crossfadeDurationNotifier` (lines 74–121), and `nextTrackStrategyNotifier` (lines 123–183) controls; migrate 14+ hardcoded `Color(0xFF...)` / raw `fontSize` literals to `AppColors`/`Theme.of(context).textTheme`.
  - `[MODIFY]` `mobile/lib/ui/widgets/queue/queue_tuner_bar.dart` — accept optional `ValueListenable<QueueTunerMode>?`, `ValueListenable<bool>? sameLanguageLockListenable`, and callbacks.

- **Exact State, Concurrency & Data Flow**:
  1. **Search EOF & Autoplay State**:
     - Store `Future<void>? _inFlightPrefetchFuture;` on `PaatuAudioHandler` (`player_handler.dart` — net-negative growth via `_onActiveTrackChanged` extraction to `player_party_ext.dart`). Inside `prefetchNextRecommendations(seedSong)`, expose `Completer` / assign `_inFlightPrefetchFuture` so `handleAutoplayQueueEnd(current)` awaits `_inFlightPrefetchFuture` first; if `_queueHandler.hasNext` is now `true`, call `await _queueHandler.skipToNext(isUserInitiated: false, bypassTransitionLock: true)` without firing duplicate network requests.
     - **Single concrete EOF advance method & forwarder**:
       - On `AudioQueueHandler` (`audio_queue_handler.dart:381`): `Future<void> skipToNext({bool isUserInitiated = true, bool bypassTransitionLock = false}) => _skipToNextImpl(isUserInitiated: isUserInitiated, bypassTransitionLock: bypassTransitionLock);`
       - `PaatuAudioHandler.skipToNext()` (`player_handler.dart:624`) remains `@override Future<void> skipToNext() => _skipToNextImpl();` (zero-arg `BaseAudioHandler` override).
       - In `queue_skip_ext.dart`: `Future<void> _skipToNextImpl({bool isUserInitiated = true, bool bypassTransitionLock = false}) async`:
         - Guard at line 10: `if (!bypassTransitionLock && _isTransitioning) { ... return; }`
         - Lock-ownership tracking: `final acquiredLock = !_isTransitioning; _isTransitioning = true; try { ... } finally { if (acquiredLock) _isTransitioning = false; }` (so an outer `_skipToNextImpl` retains lock ownership across `handleAutoplayQueueEnd`, while direct callers such as `_onTrackCompleted` or `addAutoSuggestions(autoAdvanceIfCompleted: true)` still release `_isTransitioning` cleanly).
       - `handleAutoplayQueueEnd` calls `await _queueHandler.skipToNext(isUserInitiated: false, bypassTransitionLock: true)`.
     - **Guarded `_onTrackCompleted` (`queue_listeners_ext.dart:147–221`)**:
       - Declare `bool _isHandlingCompleted = false;` on `class AudioQueueHandler` (`audio_queue_handler.dart`, alongside `_isAdvancing` and `_isTransitioning`).
       - Replace lines 147–221 of `queue_listeners_ext.dart` with:
         `if (state.processingState == ProcessingState.completed) { unawaited(_onTrackCompleted(currentSong)); }`
       - `Future<void> _onTrackCompleted(Song? current) async`:
         ```dart
         if (_isHandlingCompleted || _isAdvancing || _isTransitioning || (_currentTrack != null && _lastCompletedTrackId == _currentTrack!.id)) return;
         _isHandlingCompleted = true;
         _isAdvancing = true;
         _lastCompletedTrackId = _currentTrack?.id;
         try {
           // existing feedback recording, LoopMode.one, SleepTimer.stopAtEndOfTrack, PartySyncCoordinator.isJoiner
           // if (hasNext) await skipToNext(isUserInitiated: false);
           // else if (stopAtEndOfQueue) ...
           // else if (LoopMode.all) await handleRepeatAllLoop();
           // else if (isAutoplayEnabled && current != null) await audioHandler.handleAutoplayQueueEnd(_lastCompletedSeedSong ?? current);
           // else startIdleTimer();
         } finally {
           _isHandlingCompleted = false;
           _isAdvancing = false;
         }
         ```
     - **`_addAutoSuggestionsImpl` (`queue_suggestions_ext.dart:48`) & forwarder (`audio_queue_handler.dart:417`)**:
       - Public forwarder: `Future<void> addAutoSuggestions(List<dynamic> tracks, {bool autoAdvanceIfCompleted = false}) => _addAutoSuggestionsImpl(tracks, autoAdvanceIfCompleted: autoAdvanceIfCompleted);`
       - Impl: `Future<void> _addAutoSuggestionsImpl(List<dynamic> tracks, {bool autoAdvanceIfCompleted = false}) async`
       - At the end of `_addAutoSuggestionsImpl` (after `onQueueProgress?.call(...)`), ONLY if `autoAdvanceIfCompleted && !_isHandlingCompleted && player.processingState == ProcessingState.completed && !player.playing && !PartySyncCoordinator.isJoiner && SettingsManager.isAutoplayEnabled`, call `await preloadUpcomingTracks(currentIndex); await skipToNext(isUserInitiated: false, bypassTransitionLock: true);`.
       - `handleAutoplayQueueEnd` passes `autoAdvanceIfCompleted: false`; background 25% `prefetchNextRecommendations` passes `autoAdvanceIfCompleted: true`.
     - **`RadioEngine.buildSongRadio` dedup fix**: Strip `seedSong` from results before the `isEmpty` check: `tracks.where((s) => s.id != current.id).toList()`. If empty, cascade to `SaavnClient.search` → `YouTubeClient.search` → `getLocalFallbackTracks`.
     - Raise `YouTubeClient.getRadioTracks` timeout in `next_track_strategy.dart:855, 869` from `1500ms` to `3500ms`. Add `{bool allowLocalFallback = true}` to `NextTrackStrategy.getUpcomingTracks` (including `MarkovCosineRadioStrategy`); `handleAutoplayQueueEnd` passes `allowLocalFallback: false` first, then cascades `RadioEngine.buildSongRadio` (stripped of `seedSong`) → `try { await SaavnClient.search(...) } catch (_) {}` → `YouTubeClient.search(...)` → `getLocalFallbackTracks(...)`. Discover/Composer fallback threshold is `< 2 tracks` consistently.
  2. **PartySync Multi-Song Queue Lockstep & Anti-Jitter Smoothing**:
     - **Reset `isPartyDrivenLoad`**: In `queue_loader_ext.dart`, assign `isPartyDrivenLoad = isPartyDriven;` AFTER the two early returns (`if (tracks.isEmpty)` and `if (_isLoading && _currentTrack?.id == targetTrack.id)`), at line 35 alongside `_isLoading = true;`. In `finally` (lines 199–201), inside the existing token guard:
       ```dart
       if (_activeLoadSessionToken == token) {
         _isLoading = false;
         isPartyDrivenLoad = false;
       }
       ```
       Only the winning load session token clears `isPartyDrivenLoad`.
     - **Single-track `_playlistSource` during PartySync (Host + Joiner)**: In `queue_loader_ext.dart:106–112`, `queue_playback_ext.dart:213–220`, and `queue_source_builder.dart:13`, when `PartySyncCoordinator.isActive` is `true` (both Host and Joiner), do **NOT** insert `nextTrack` into `_playlistSource`. In `queue_listeners_ext.dart`: skip `prefetchNextRecommendations` when `PartySyncCoordinator.isJoiner` is `true`, and return early in `_sequenceStateSub` (`queue_listeners_ext.dart:16`) and `_currentIndexSub` (`queue_listeners_ext.dart:25`) when `PartySyncCoordinator.isActive` is `true`. This prevents ExoPlayer gapless auto-advance from desyncing `_currentTrack`/`_contextIndex` on Host or auto-advancing on Joiner; Host transitions cleanly via `ProcessingState.completed` → `_onTrackCompleted` → `skipToNext` → `_playTrackEntityImpl` → `notifyHostPlay`.
     - **Host gapless race (`_advanceToNextTrackFromPlayerStreamImpl`)**: Add `if (PartySyncCoordinator.isHost) return;` early return in `_advanceToNextTrackFromPlayerStreamImpl` (same pattern as Joiner guard at `queue_listeners_ext.dart:196–200`) as defense-in-depth alongside the `PartySyncCoordinator.isActive` guard above.
     - **Dedicated Lookahead Event (`sync_prepare_next`)**:
       - Declare `bool _hasSentPartyLookahead = false;` on `class AudioQueueHandler` (`audio_queue_handler.dart`, alongside `_hasTriggered25PctRecs`) and reset it in `_resetTrackMilestones()`.
       - In `queue_listeners_ext.dart` (`_positionSub`): when `remainingSec <= 10 && !_hasSentPartyLookahead && PartySyncCoordinator.isHost && nextTrack != null`, set `_hasSentPartyLookahead = true` and call `PartySyncCoordinator.notifyHostLookaheadPrepare(nextTrack!.toSong(), queue: queue, currentIndex: currentIndex + 1)`.
       - Add `static Future<void> notifyHostLookaheadPrepare(Song song, {List<Song>? queue, int? currentIndex}) => _notifyHostLookaheadPrepareImpl(song, queue: queue, currentIndex: currentIndex);` on `PartySyncCoordinator`, with `_notifyHostLookaheadPrepareImpl` in `party_host_controls.dart`: checks `isHost`, generates `cmdId = _uuid.v4()` and `seq = ++_currentHostSeq` (does **NOT** set `_pendingPrepareCmdId`), builds compact payload `{'cmdId': cmdId, 'seq': seq, 'token': _sessionSecret, 'song': song.toMap(), 'songId': song.id, 'streamUrl': directUrl, 'currentIndex': currentIndex ?? 0}`, and broadcasts `'sync_prepare_next'` over both `_partyChannel` and `PartyLanAccelerator.sendSyncEvent`.
       - Add `_handleRemotePrepareNextImpl(Map<String, dynamic> payload)` in `party_remote_handlers.dart` (with forwarder `_handleRemotePrepareNext` on `PartySyncCoordinator`): checks `resolveLocalDownloadedCopy(song)` first; if null, calls `DefaultStreamResolver.prewarmSongs([song])` only when `directUrl` is empty, else calls `DefaultStreamResolver.cacheStream(id, directUrl)` directly. Does NOT call `SmartCacheService` or touch `_player`/`_playlistSource`. Adds `song.id` to `_lookaheadPreparedIds` (declared in `party_drift_controller.dart`, shared part scope) and sends `peer_ready` with `'lookahead': true, 'songId': song.id`.
       - In `party_joiner_flow.dart`: add `case 'sync_prepare_next': await PartySyncCoordinator._handleRemotePrepareNext(payload); break;` to `PartyLanAccelerator.onSyncEventReceived` switch (after `sync_prepare`, line 64) AND `channel.onBroadcast(event: 'sync_prepare_next', ...)` with `_isValidSessionPayload` + `_shouldProcessEvent` guards (after line 101).
       - On Host, `_handlePeerReadyImpl` checks `payload['lookahead'] == true` **BEFORE** the `cmdId == _pendingPrepareCmdId` guard, recording `songId` into `_lookaheadAckedSongIds`. In `_notifyHostPlayImpl` (`party_host_controls.dart`), insert right after line 44 (`final isLan = ...`):
         `final barrierTimeoutMs = _lookaheadAckedSongIds.contains(song.id) ? 350 : (isLan ? 1200 : 3500);`
     - **Fix Host Transition Race, `_pendingPrepareCmdId` Deadlock & Heartbeat/Queue Sync**:
       - In `_notifyHostPlayImpl` (`party_host_controls.dart`): immediately AFTER the stale-cmdId check at lines 55–59 (`if (PartySyncCoordinator._pendingPrepareCmdId != cmdId) { ... return; }`) and before `final peerRtts = ...` at line 61, insert `PartySyncCoordinator._pendingPrepareCmdId = null;`.
       - In `_playTrackEntityImpl` (`queue_playback_ext.dart`): when `PartySyncCoordinator.isHost` is `true`, guard `player.play()` (line 239) with `if (!PartySyncCoordinator.isHost)` so Host remains paused until `_notifyHostPlayImpl` schedules playback, and after `setAudioSource` (line 231) succeeds, call `PartySyncCoordinator.notifyHostPlay(song, positionMs: 0, queue: queue, currentIndex: currentIndex)` **BEFORE** the deferred `onSongChanged?.call(song)` (line 169). Calling `notifyHostPlay` first sets `_lastAnnouncedSongId` / `_lastAnnouncedTimeMs` synchronously at `party_host_controls.dart:11–12` before `_onActiveTrackChanged` runs, suppressing duplicate `notifyHostTrackTransition`.
       - Unify periodic 2-second heartbeat (`party_host_flow.dart:182–218`) to call `_broadcastCurrentStateImpl()` directly; keep `PartyLanAccelerator.sendSyncEvent('sync_heartbeat', ...)` compact (under UDP 1472-byte IPv4 MTU, without full `queue` array), while adding `'currentIndex'` and relaxing `_notifyHostQueueUpdatedImpl` (`party_host_controls.dart:284`) from `if (!PartySyncCoordinator.isHost || PartySyncCoordinator._partyChannel == null) return;` to `if (!PartySyncCoordinator.isHost) return;` with `_partyChannel?.sendBroadcastMessage(...)` so `sync_queue` sends over **both** Supabase (full queue) and `PartyLanAccelerator.sendSyncEvent('sync_queue', compactPayload)` (stripping `lyrics`, `encryptedMediaUrl`, `streamUrl` for non-active tracks, `coverUrl`) even in Wi-Fi-only mode.
       - In `_handleRemoteQueue` (`party_sync_coordinator.dart:367`):
         - `if (currentSong?.id == targetSong.id)` → call `await audioHandler.queueHandler.updateContextQueuePreservingCurrent(songs, currentIndex: targetIndex);` (non-disruptive!).
         - `else if (isPlaying)` (lines 375–382, Joiner's active song differs from Host's queue index) → keep existing `await audioHandler.playSong(targetSong, queue: songs, preserveUserQueue: false, autoPlay: false, isPartySyncInternal: true);` so Joiner aligns to Host's active song.
       - **`updateContextQueuePreservingCurrent` (`queue_mutation_ext.dart`, existing file)**:
         - Public forwarder on `AudioQueueHandler`: `Future<void> updateContextQueuePreservingCurrent(List<dynamic> tracks, {required int currentIndex}) => _updateContextQueuePreservingCurrentImpl(tracks, currentIndex: currentIndex);`
         - Body: convert `tracks` via `AudioQueueHandler._toEntity`; preserve `_userQueue` and `_currentTrack`; `_contextQueue..clear()..addAll(entities);`; if `_isShuffleEnabled`, rebuild `_contextShuffleIndices` as `[0..entities.length - 1]`; recalculate `_contextIndex` from `_currentTrack` match in `_contextQueue` (fallback `currentIndex.clamp(0, math.max(0, _contextQueue.length - 1))`); call `_syncState();` and `onQueueProgress?.call(this.currentIndex, queue.length);`; skip `preloadUpcomingTracks()` when `PartySyncCoordinator.isJoiner`.
       - In `_leavePartyImpl`, clear all new state fields: `_lookaheadAckedSongIds.clear()`, `_lookaheadPreparedIds.clear()`, `_lastAppliedSpeed = 1.0`, `_lastScheduledPlayActualEpochMs = 0`, `_driftSmoother.reset()`, `_hasSentPartyLookahead = false`, `_pendingPrepareCmdId = null`.
     - **`PaatuAudioHandler.setSpeed` & `DriftSmoother` Anti-Jitter**:
       - Add `@override Future<void> setSpeed(double speed) => _player.setSpeed(speed);` directly on `class PaatuAudioHandler` in `player_handler.dart`. Track `double _lastAppliedSpeed = 1.0;` in `party_drift_controller.dart` and only call `audioHandler.setSpeed(targetSpeed)` when `(targetSpeed - _lastAppliedSpeed).abs() >= 0.002`.
       - Add `DriftSmoother` in `party_sync_engine.dart` wrapping `DriftReconciler.reconcileDrift`:
         ```dart
         class DriftSmoother {
           final List<int> _samples = [];
           int _consecutiveOutOfDeadband = 0;
           void addSample(int driftMs);
           DriftAction computeAction({
             required int currentPositionMs,
             required int expectedPositionMs,
             required int deadbandMs,
             required int microAdjustMaxMs,
             required bool wasInSync,
           });
           void reset();
         }
         ```
         - Hard-seek (`(currentPositionMs - expectedPositionMs).abs() >= microAdjustMaxMs`): delegates immediately to `DriftReconciler.reconcileDrift(..., seekLatencyMs: 80)` using raw drift (no 2-sample wait).
         - Otherwise uses median of last 3 `_samples`; computes `effectiveDeadband = wasInSync ? (deadbandMs + 15) : deadbandMs`. If `medianDrift.abs() < effectiveDeadband`, resets `_consecutiveOutOfDeadband = 0` (keeps `_samples`) and returns `inSync`. Else increments `_consecutiveOutOfDeadband++`; requires `>= 2` before delegating to `DriftReconciler.reconcileDrift(...)` for micro-speed adjust.
         - `reset()` clears `_samples` and `_consecutiveOutOfDeadband = 0`.
       - `DriftReconciler.calculateAdaptiveDeadband`: LAN = `40ms`, Cloud = `max(60, min(110, (rttMs * 0.4).round()))`. `DriftReconciler.reconcileDrift` line 187 hysteresis changes from `+ 10` to `+ 15` (keeping existing `deadbandMs = 30` default so existing tests compile unchanged).
       - In `party_drift_controller.dart`, `_handleHeartbeatReconciliation` feeds `drift` to `_driftSmoother.addSample(drift)` and uses `_driftSmoother.computeAction(...)`. Record `_lastScheduledPlayActualEpochMs` at the exact instant `audioHandler.play()` fires and skip reconciliation while `nowMs - _lastScheduledPlayActualEpochMs < 2500`.
  3. **Same-Language Next-Song Engine & Persistent Algorithm/Vibe Selector**:
     - Expose `RadioEngine.knownMusicDirectors` and build `LanguageDetector` (`mobile/lib/logic/language_detector.dart`):
       - **Multi-language artist handling**: Build `Map<String, Set<String>>` from `CatalogArtistsSeed.data` collecting ALL language values per normalized artist name (e.g. Shreya Ghoshal → `{'tamil', 'hindi'}`).
       - `composerLanguageMap`: explicit `const Map<String, String>` using `RadioEngine.knownMusicDirectors` entries with known languages.
       - `inferSongLanguage(Song song, {bool fallbackToPreferred = false})` & `isLanguageCompatible(Song candidate, String targetLang)`.
     - **`SettingsManager` keys & local persistence** (Hive only): `'same_language_lock'` (`bool`, default `true`) and `'preferred_tuner_mode'` (`String`, default `'mix'`).
     - **`QueueTunerController`**:
       - Constructor reads `SettingsManager.preferredTunerModeNotifier.value` for initial `modeNotifier` value.
       - Updated `filterAndRankCandidates` signature (`queue_tuner_controller.dart:76`):
         `static Future<List<Song>> filterAndRankCandidates({required Song seedSong, required List<Song> candidates, required QueueTunerMode mode, bool? sameLanguageLock})`
         (defaults to `sameLanguageLock ?? SettingsManager.sameLanguageLock`).
       - Familiar mode (`setTunerMode` at `queue_tuner_controller.dart:44–54`): bypass upstream `applyHardFiltering` when `newMode == QueueTunerMode.familiar` (or seed `filterAndRankCandidates` directly with `HistoryManager`/`FavoritesManager` tracks) so history/favorites are preserved before `_rankForFamiliar` scores them with `LanguageDetector.isLanguageCompatible`.
     - **`enforceLanguage` flag on `RadioEngine`**: Add `bool enforceLanguage = true` parameter to `applyHardFiltering` / `generateCandidatePool` / `buildSongRadio` / `shapeRadioQueue`.
     - **Consistent Language Propagation Everywhere**: All 3 strategies + `MarkovCosineRadioStrategy` (`{bool allowLocalFallback = true}`), `RadioEngine`, `SmartShuffleController`, `QueueTunerController`, `getLocalFallbackTracks`, and `PlayerRecommendationsExt`.
  4. **UI Compliance (`mobile-ui-guidelines`)**:
     - `NextSongPreferencesCard`, `PlaybackTransitionsCard`, `AudioQualitySettingsCard`, and `QueueTunerBar` use ONLY `AppColors` + `Theme.of(context).textTheme`, `48×48 dp` min hit targets, `Expanded` + `maxLines` + `TextOverflow.ellipsis`.

## 5. States to handle
- **Loading**: `NextSongPreferencesCard` initializes synchronously from Hive `SettingsManager`; `QueueTunerBar` reflects active tuner + Same-Lang toggle; PartySync shows `"Preparing next track..."` when lookahead caches Song `N+1`.
- **Empty**: If `Discover` or `Composer` + `Same-Language Lock` returns `< 2` tracks, relax tuner lens to `Mix` while keeping `Same-Language Lock`, then cascade to `RadioEngine.buildSongRadio` (stripped of `seedSong`) → wrapped `SaavnClient.search` → `YouTubeClient.search` → `getLocalFallbackTracks`.
- **Error + retry**: Wrap `SaavnClient.search` in `try/catch`, reset `_isHandlingCompleted` and `_isAdvancing` in `finally`, and auto-advance if background prefetch resolves after `completed`.
- **Offline**: `getLocalFallbackTracks` strictly filters local downloads/favorites/history by `LanguageDetector.isLanguageCompatible` when `sameLanguageLock` is ON.
- **Populated / Long text**: `Expanded`, `maxLines: 2`, `TextOverflow.ellipsis`, horizontal `SingleChildScrollView`, and `48dp` targets ensure 360×640 dp @ 1.5× text scale never overflows.

## 6. Edge cases & risks
1. **Mutual deadlock on `_isTransitioning` / `_isAdvancing`**: `bypassTransitionLock: true` passed from `handleAutoplayQueueEnd`; lock-ownership `acquiredLock = !_isTransitioning` ensures whichever `_skipToNextImpl` acquired `_isTransitioning` resets it in `finally`; `_onTrackCompleted` resets `_isHandlingCompleted` + `_isAdvancing` in `finally`.
2. **PartySync lookahead race**: `_handlePeerReadyImpl` checks `lookahead` flag BEFORE `cmdId` guard; `_notifyHostLookaheadPrepareImpl` does not touch `_pendingPrepareCmdId`.
3. **`_pendingPrepareCmdId` deadlock**: Reset to `null` in `_notifyHostPlayImpl` right after the stale-cmdId check passes (before line 61) and in `_leavePartyImpl`.
4. **Familiar mode history stripping**: `QueueTunerController.setTunerMode` bypasses upstream `applyHardFiltering` for `QueueTunerMode.familiar` and filters language only via `LanguageDetector.isLanguageCompatible`.
5. **Multi-language artists**: `CatalogArtistsSeed.data` keyed to `Map<String, Set<String>>` per normalized artist name.
6. **UDP MTU overflow**: `sync_queue` LAN packet strips `lyrics`, `encryptedMediaUrl`, non-active `streamUrl`, `coverUrl`.
7. **File size compliance**: `radio_language_filter.dart` `< 200` lines; `party_drift_controller.dart` `< 260` lines; `settings_manager_eq_ext.dart` `< 150` lines (moves ~100 lines out of `settings_manager.dart`); `player_party_ext.dart` `< 100` lines (extracts `_onActiveTrackChanged` so `player_handler.dart` has net-negative delta even with `setSpeed` override).
8. **`RadioEngine.buildSongRadio` dedup**: Strip `seedSong` from results before `isEmpty` check.
9. **Host gapless advance**: Guard `_advanceToNextTrackFromPlayerStreamImpl` with `if (PartySyncCoordinator.isHost) return;`.

## 7. Steps (small, each independently verifiable)
1. [ ] Create `mobile/lib/logic/language_detector.dart`; extract `mobile/lib/services/settings_manager_eq_ext.dart` (`_initEqFromBoxImpl`, EQ/stereo top-level impls + 1-line static forwarders); add `'same_language_lock'` + `'preferred_tuner_mode'` to `SettingsManager`; create `mobile/lib/ui/widgets/settings/playback_transitions_card.dart`.
2. [ ] Fix Search EOF stuck bug across `audio_queue_handler.dart` (`_isHandlingCompleted`, `skipToNext`/`addAutoSuggestions` forwarders), `queue_listeners_ext.dart` (`_onTrackCompleted` replacing lines 147–221), `queue_skip_ext.dart` (`bypassTransitionLock`), `queue_suggestions_ext.dart` (`autoAdvanceIfCompleted`), `player_party_ext.dart` (`_onActiveTrackChanged` extraction + `_inFlightPrefetchFuture`), `player_handler.dart` (`setSpeed` override directly on class), and `player_recommendations_ext.dart` (`handleAutoplayQueueEnd` awaits inflight, calls `skipToNext(bypassTransitionLock: true)`, strips `seedSong` from `buildSongRadio`, 3500ms YT timeout, `allowLocalFallback` cascade).
3. [ ] Fix PartySync multi-song queue transitions & anti-jitter smoothing: reset `isPartyDrivenLoad` after early returns in `queue_loader_ext.dart` (and inside `if (_activeLoadSessionToken == token)` in `finally`); enforce 1-track `_playlistSource` when `PartySyncCoordinator.isActive` (Host + Joiner) + guard `_sequenceStateSub`/`_currentIndexSub`/`_advanceToNextTrackFromPlayerStreamImpl`; defer `onSongChanged` after `notifyHostPlay` and guard `player.play()` in `_playTrackEntityImpl`; add `_hasSentPartyLookahead` on `AudioQueueHandler` + `notifyHostLookaheadPrepare` / `_handleRemotePrepareNextImpl` + LAN/Supabase `sync_prepare_next` wiring in `party_joiner_flow.dart`; reset `_pendingPrepareCmdId = null` after stale check in `_notifyHostPlayImpl`; implement `updateContextQueuePreservingCurrent` in `queue_mutation_ext.dart` (preserving `else if (isPlaying)` in `_handleRemoteQueue`); create `party_drift_controller.dart` with 1-line forwarders; add `DriftSmoother` + `+15ms` hysteresis + `40ms`/`60ms` deadbands in `party_sync_engine.dart`; clear all new state in `_leavePartyImpl`.
4. [ ] Extract `radio_language_filter.dart` (< 200 lines) and `next_track_fallback_helper.dart` (< 170 lines); add `enforceLanguage: bool` param to `RadioEngine`; wire `LanguageDetector` + persisted `QueueTunerMode` + `sameLanguageLock` param on `QueueTunerController.filterAndRankCandidates` (`setTunerMode` bypassing upstream `applyHardFiltering` for Familiar) into `RadioEngine`, `next_track_strategy.dart`, `markov_cosine_radio_strategy.dart`, `smart_shuffle_controller.dart`, `queue_tuner_controller.dart`, and `player_recommendations_ext.dart`.
5. [ ] Create `NextSongPreferencesCard` and `PlaybackTransitionsCard`; refactor `AudioQualitySettingsScreen` (< 300 lines, replacing `_buildAutoplaySection()` with `const NextSongPreferencesCard()` and crossfade/background sections with `const PlaybackTransitionsCard()`); refactor `AudioQualitySettingsCard` (remove duplicate Autoplay/Crossfade/Strategy controls, migrate colors/text to `AppColors`/theme tokens); update `QueueTunerBar`.
6. [ ] Add/update tests (`search_eof_autoplay_test.dart`, `party_sync_multi_song_test.dart`, `same_language_radio_test.dart`, `queue_tuner_test.dart:116–120`, `party_sync_test.dart:150–170`), then verify `flutter analyze --no-fatal-infos`, `ui_layout_matrix_test.dart`, `code_budget_guard_test.dart`, and full `flutter test --exclude-tags golden`.

## 8. Tests
- [ ] Layout matrix entry for any new screen: N/A (`AudioQualitySettingsScreen` already in `ui_layout_matrix_test.dart:48`; adding `pumpAndCollectLayoutErrors` tests for `NextSongPreferencesCard` and `QueueTunerBar`).
- [ ] Unit/widget tests for new logic:
  - `mobile/test/search_eof_autoplay_test.dart`: verifies `skipToNext(bypassTransitionLock: true)` does not deadlock, `_isHandlingCompleted` + `_isAdvancing` reset in `finally`, `addAutoSuggestions(autoAdvanceIfCompleted: true)` advances while `completed`, `buildSongRadio` strips `seedSong`.
  - `mobile/test/party_sync_multi_song_test.dart`: verifies `PaatuAudioHandler.setSpeed` delegates to player, `isPartyDrivenLoad` resets only for winning token, Joiner 1-track `_playlistSource`, Host `_advanceToNextTrackFromPlayerStreamImpl` early-returns, `_pendingPrepareCmdId` resets, `updateContextQueuePreservingCurrent` preserves playback, `DriftSmoother` 2-sample micro-adjust gate + raw hard-seek.
  - `mobile/test/same_language_radio_test.dart`: verifies `LanguageDetector` multi-language `CatalogArtistsSeed.data` map, `enforceLanguage: true/false`, `QueueTunerController.setTunerMode` Familiar bypasses upstream `applyHardFiltering`, `SettingsManager` Hive persistence, `QueueTunerController` init from `SettingsManager`, `NextSongPreferencesCard` + `QueueTunerBar` `pumpAndCollectLayoutErrors`.
  - `mobile/test/queue_tuner_test.dart` (MODIFY lines 116–120): pass `sameLanguageLock: false` to `QueueTunerController.filterAndRankCandidates` for cross-language Discover assertion.
  - `mobile/test/party_sync_test.dart` (MODIFY lines 150–170 + ADD): update hysteresis assertions for `+15ms` (`deadbandMs: 30, wasInSync: true` → effective `45ms`), and add `calculateAdaptiveDeadband` (`40ms` LAN / `60ms` Cloud) + `DriftSmoother` tests.
- [ ] Golden update needed? N.

## 9. Verification commands (must all pass)
```powershell
cd mobile
flutter analyze --no-fatal-infos
flutter test test/ui_layout_matrix_test.dart
flutter test --exclude-tags golden
```

## 10. Done report (fill at the end)
Files changed: / Tests added: / Commands run + results: / Not verified:
