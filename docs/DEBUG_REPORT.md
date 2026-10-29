# Mobile app debug report (static audit)

**Method.** I could NOT run Flutter here (SDK and pub.dev are blocked in my sandbox), so nothing below was compiled or
executed. I audited all 165 Dart files (56k lines) with scripted scans (async-gap/`mounted`, undisposed
controllers/timers/subscriptions, Row/Column layout hazards, unguarded `firstWhere`, Hive access, HTTP timeouts,
secrets/TLS) and then READ the code around every hit. I did **not** read the 2,383-line `audio_queue_handler.dart`
line by line, so queue/shuffle *logic* bugs may remain. Patched files are in `mobile/lib/` of this bundle (same paths as your repo).
Brackets were checked to balance against the originals; please run `flutter analyze` + `flutter test` before merging.

## Fixed (confirmed by reading the code)

| # | Severity | File | Bug | Fix |
|---|----------|------|-----|-----|
| 1 | **High** | `services/player_handler.dart` `stop()` | `stop()` cancelled `_becomingNoisySub`, `_interruptionSub`, `_playerStateSub`, which are created ONCE in the constructor. After the user swipes the media notification away, the idle timeout fires, or the sleep timer stops playback, they were never re-created: headphones/Bluetooth unplug no longer auto-pauses (music blasts from the speaker), phone calls no longer pause music, until the app is killed. | Removed those cancels from `stop()`; they are released only in `dispose()`/`disposeAudioHandler()`. |
| 2 | Med | `player_handler.dart` `dispose()` | Left `_playbackEventSub`, `_durationSub`, `_throttledPositionSub` running. | Cancelled too. |
| 3 | Med | `services/youtube_client.dart:222` | `client.send(request)` for the streaming source had no timeout; a stalled connection hangs playback forever. | `.timeout(20s)` |
| 4 | Med | `ui/widgets/party_mode_sheet.dart` | `setState` after `await joinParty` with no `mounted` check -> "setState() called after dispose" if the sheet is closed while joining. | `if (!mounted) return;` |
| 5 | Low | `ui/widgets/spotify_import_dialog.dart` | same, after clipboard await | `mounted` check |
| 6 | Low | `ui/screens/settings_screen.dart` (5 places) | `setState(() {})` after `await Navigator.push` | `mounted` check |
| 7 | Low | `ui/widgets/batch_download_button.dart` | `ScaffoldMessenger.of(context)` after a loop of awaited deletes | capture messenger before the loop |
| 8 | Low | `ui/widgets/swipeable_song_tile.dart` | `context` used after `await toggleFavorite` | `context.mounted` check |

### Fixed: layout overflows (the "broken UI")
Dynamic or long text directly inside a `Row` with no `Expanded`/`Flexible` -> yellow/black overflow stripes on small phones, long names, or large font size:
- `full_player_screen.dart` "Listening on <device name>" chip (long Bluetooth names)
- `spotify_import_dialog.dart` live matching status text (`_currentStatus` can be a long track title)
- `sleep_timer_sheet.dart` info chip and the "Start Sleep Timer (...)" button label
- `playlist_screen.dart` "LIVE COLLAB • <code>" badge
- `batch_download_button.dart` "All N Tracks Downloaded" title
- `home_screen.dart` "New <language> Releases" header (collided with "Play All")

Regression tests: `test/ui_widget_layout_test.dart` (SleepTimerSheet, all devices x text scales).

## Clean (checked, no action needed)
- All State classes dispose their controllers/timers/subscriptions.
- No `Column > ListView` without `Expanded`; no `Row > TextField/ListView` hazards.
- All `firstWhere` calls have `orElse` or a `try/catch`.
- All HTTP calls have timeouts (except #3). No TLS-bypass code. Scrubber slider values are clamped.

## Not fixed - needs your decision
1. **107 empty `catch (_) {}`** (e.g. `auth_manager.dart:48,158,290`, `player_handler.dart` x8, `party_sync_coordinator.dart` x4). Errors vanish silently; at least log via `AppLogger.recordError`. Worth doing in a dedicated pass.
2. **`lyrics_playback_bar.dart`** calls `audioHandler.seek()` on every `onChanged` drag event (seek spam). Use `onChangeEnd` like `player_scrubber.dart` does.
3. **Sliders can assert in debug** if a stored value is outside min/max (EQ band gain, crossfade). Clamp on load in `SettingsManager.init()`.
4. **`android/app/google-services.json` is committed.** Normal for Firebase, but restrict the API key by package name + SHA-1 in Google Cloud console.
5. **Giant files** (`audio_queue_handler` 2,383 lines, `player_handler` 1,352, `search_screen` 1,110, `settings_screen` 1,099): the main reason AI edits break things. Split gradually.
6. **Unverified:** queue/shuffle/crossfade index math, party-sync logic, download manager. Next step: run the new layout tests and the existing suite, paste failures, and I'll dig into those.
