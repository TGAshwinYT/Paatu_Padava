# Paatu Padava Mobile — Architecture & Phased Implementation Plan

## Executive Summary
This document provides the verified findings and comprehensive architectural roadmap for refining the Flutter mobile application of Paatu Padava. It addresses critical queue synchronization flaws, notification UX, selectable next-song algorithms, typo-tolerant search and robust lyrics validation, battery and LRU caching hygiene, real-time collaborative playlists, and multi-device synchronized audio playback.

---

## 1. Verification of Static Review Findings

All 5 static review items have been inspected and verified against the live codebase:

| # | Component | File & Lines | Live Code Verification | Conclusion |
|---|---|---|---|---|
| **1** | **Queue Index Drift & Double Skip** | [audio_queue_handler.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/logic/audio_queue_handler.dart#L275-L287) & [player_handler.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/services/player_handler.dart#L185-L189) | `loadQueue()` creates `ConcatenatingAudioSource` with only 1 child (`activeSource` at player index 0), while `_queue` index is set to `initialIndex`. Preloading appends upcoming tracks at player indices 1, 2... When player completes track 0, it advances to player index 1, updating `_currentIndex = 1` in `_queue` (the 2nd song of the original queue instead of the 6th). `jumpToIndex()` has the exact same flaw. Additionally, `AudioQueueHandler` (L232) and `PaatuAudioHandler` (L185) **both** listen to `ProcessingState.completed` and call `skipToNext()`, causing a double skip. Both `_sequenceStateSub` (L188) and `_currentIndexSub` (L198) write `_currentIndex`. | **Confirmed & Agreed** |
| **2** | **Search Flooding Queue** | [search_screen.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/ui/screens/search_screen.dart#L937) & [search_screen.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/ui/screens/search_screen.dart#L1194) | Tapping any song in search calls `audioHandler.playSong(song, queue: queue)` where `queue` is `state.songs` (all 25 search results). Search results completely overwrite the playback queue. | **Confirmed & Agreed** |
| **3** | **Notification Icon & Controls** | [main.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/main.dart#L60) & [player_handler.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/services/player_handler.dart#L156-L161) | `androidNotificationIcon` is set to `'mipmap/ic_launcher'`, which is a full-color app icon. On Android 5.0+ and Android 13+, non-monochrome icons render as an opaque blank/white box. `controls` uses `MediaControl.stop` as the 4th action with no Like/Favorite action. | **Confirmed & Agreed** |
| **4** | **Unvalidated Lyrics Fetching** | [api_client.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/services/api_client.dart#L332-L398) | `fetchLyrics()` queries JioSaavn, backend `/api/music/lyrics`, and LRCLIB in order, immediately returning the first non-empty string with zero validation of title similarity, artist similarity, duration tolerance, or language/script correctness. | **Confirmed & Agreed** |
| **5** | **Fuzzy Search Restricted to Local Terms** | [fuzzy_search_service.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/services/fuzzy_search_service.dart#L21-L97) | `findCorrection()` only matches against `_candidateDictionary` (hardcoded set of ~75 artists/tracks + terms registered locally in session memory). It cannot correct queries for artists, songs, or terms not already loaded locally. | **Confirmed & Agreed** |

---

## 2. Baseline Test & Analysis Verification

- **Baseline Test Suite Status**: Ran `flutter test`. **All 68 existing tests passed** across all 9 test suites:
  - `audio_dsp_test.dart`: 10 passed
  - `auth_state_test.dart`: 4 passed
  - `collaborative_playlist_test.dart`: 10 passed
  - `coordination_logic_test.dart`: 7 passed
  - `discovery_recap_test.dart`: 8 passed
  - `offline_storage_test.dart`: 6 passed
  - `search_pipeline_test.dart`: 7 passed
  - `sync_reconciliation_test.dart`: 7 passed
  - `visual_interactions_test.dart`: 9 passed
- Zero test regressions will be tolerated throughout all phases.

---

## 3. Investigation: Spotify Web API Recommendation Endpoints

In late 2024, Spotify officially restricted and deprecated several Web API endpoints for standard and newly registered applications:
- `GET /v1/recommendations` (seed-based track/artist/genre recommendations)
- `GET /v1/recommendations/available-genre-seeds`
- Audio analysis / audio feature endpoints

**Current Paatu Padava implementation:**
- The app uses Spotify purely for metadata ingestion via `SpotifyImportService` (resolving Spotify playlist tracks to JioSaavn/YouTube 320kbps streams).
- The app does **not** depend on Spotify's restricted recommendation endpoint.
- For recommendation logic, Paatu Padava uses:
  1. Backend recommendation engine (`/api/music/recommendations/{songId}` and `/api/music/for-you`).
  2. Contextual JioSaavn related tracks (`SaavnClient.getRelatedSongs`).
  3. YouTube Music dynamic radio engine (`RadioEngine`).
  4. On-device Markov transition chains and skip/listen feedback scoring.

---

## 4. Detailed Phased Implementation Plan

### Phase 1: Queue Correctness (Highest Priority)
**Goals**: Perfect index alignment between player and queue, single source of truth, isolated track-completion handling, isolated index writing, smart queue auto-fill on tap, and structured Queue UI sections.

1. **Player & Queue Index Alignment (`AudioQueueHandler`)**:
   - Establish `_queue` (`List<Song>`) and `_playlistSource` (`ConcatenatingAudioSource`) as strictly 1-to-1 index-aligned: `_playlistSource.length == _queue.length` at all times.
   - When `loadQueue(songs, initialIndex: idx)` is called:
     - Pre-populate `_playlistSource` with audio sources matching every song in `_queue`.
     - Active track source is fully prepared; upcoming tracks are lazily prepared with `useLazyPreparation: true`.
     - Set audio source on player with `initialIndex: idx`. The player's active index is always identical to `_currentIndex`.
   - `jumpToIndex(int targetIndex)`:
     - Simply call `await player.seek(Duration.zero, index: targetIndex)`. Since `_playlistSource` is aligned, player transitions immediately without rebuilding or truncating `_playlistSource`.
   - Remove/Reorder/Insert operations:
     - `removeAt(index)`: removes from `_queue` and `_playlistSource.removeAt(index)`. If `index < _currentIndex`, decrement `_currentIndex` by 1. If `index == _currentIndex`, advance cleanly.
     - `reorder(oldIndex, newIndex)`: updates `_queue` and calls `_playlistSource.move(oldIndex, newIndex)`. Adjusts `_currentIndex` accurately.
     - `insertNext(song)`: inserts at `_currentIndex + 1` in both `_queue` and `_playlistSource.insert(insertIdx, source)`.
2. **Single Source of Truth, Single Index Writer & Completion Handler**:
   - **One Index Writer**: `player.currentIndexStream` is the *only* writer of `_currentIndex` and invokes `_syncState()`. `sequenceStateStream` only reads metadata tags without overwriting `_currentIndex`.
   - **One Completion Handler**: Remove the track completion listener from `PaatuAudioHandler`. Track completion is handled *only* in `AudioQueueHandler`.
3. **Tapping Song Anywhere (No Search Results Flooding)**:
   - In `search_screen.dart` (and home / catalog screens), tapping a song starts a **NEW queue** with that single song (`queue: null` or `[song]`), then immediately calls the next-song algorithm to populate **Up Next**.
   - User playlists and liked song collections can still pass full explicit queues.
4. **Queue UI Sections (`QueueSheet`)**:
   - **Played**: Previous songs (`0 .. _currentIndex - 1`). Collapsible tile (collapsed by default, shows count), auto-trimmed to the last 10 played tracks.
   - **Now Playing**: Current active song at `_currentIndex`. Highlighted with equalizer wave indicator, glowing accent border, and duration.
   - **Up Next**: Upcoming user-queued tracks. Drag handles for reordering, swipe-to-dismiss.
   - **Auto-Suggested**: Recommended tracks appended by the algorithm. Marked with an "Auto-Suggested" neon badge and sparkle icon.
5. **Unit Tests (`test/audio_queue_handler_test.dart`)**:
   - Play from middle of a list (`initialIndex: 3` in 7 songs) -> verifies player and queue start at index 3.
   - Jump to index -> verifies accurate seek without playlist re-instantiation.
   - Remove current song -> verifies player advances to next song.
   - Remove song before current -> verifies `_currentIndex` decrements by 1 and continues current song.
   - Reorder songs -> verifies index adjustments.
   - Insert next -> verifies insertion at `_currentIndex + 1`.
   - Track completion -> verifies single advance (advancing exactly one track, no double skip).

---

### Phase 2: Notification
**Goals**: Fix white box icon on Android 5.0-14+, replace stop button with interactive Like action, and ensure Android 13+ media notification compliance.

1. **Monochrome Notification Icon**:
   - Generate a clean, crisp, white-on-transparent monochrome drawable `ic_notification.png` (or XML vector drawable) from `mobile/assets/logo.png`.
   - Place in `mobile/android/app/src/main/res/drawable/` and respective density folders.
   - Update `lib/main.dart`: configure `androidNotificationIcon: 'drawable/ic_notification'`.
2. **Custom Like (Heart) Action**:
   - In `lib/services/player_handler.dart`:
     - Replace `MediaControl.stop` with custom Like `MediaControl`.
     - When liked: heart filled icon (`drawable/ic_heart_filled` or `customAction: 'toggle_like'`).
     - When not liked: heart outline icon.
     - Implement `customAction(String name, [Map<String, dynamic>? extras])` in `PaatuAudioHandler` to toggle favorite status in `FavoritesManager`.
     - Listen to `FavoritesManager.favoritesNotifier` and rebuild notification controls when favorite state changes or current song transitions.
3. **Android 13+ Media Notification Layout**:
   - Maintain `androidCompactActionIndices: const [0, 1, 2]` for compact quick-settings player.
   - Ensure `MediaItem` title, artist, duration, and high-resolution art URI are populated properly for Android SystemUI `MediaControlPanel`.

---

### Phase 3: Next-Song Algorithm (Selectable)
**Goals**: Strategy pattern for queue auto-population, Spotify-style vs YouTube Music-style radio, persistent settings, and auto-refill.

1. **`NextTrackStrategy` Abstraction**:
   ```dart
   abstract class NextTrackStrategy {
     String get id;
     String get displayName;
     String get description;
     Future<List<Song>> getNextTracks({
       required Song currentSong,
       required List<Song> queue,
       required List<String> sessionHistory,
       int count = 5,
     });
   }
   ```
2. **Implementations**:
   - **`SpotifyStyleStrategy`**:
     - User taste profile + backend recommender (`ApiClient.fetchRecommendations`) + positive/negative skip feedback (`recordPlaybackFeedback`).
     - Interleaves recommended tracks into queue with acoustic similarity Markov chains.
     - Fallback to JioSaavn related tracks if backend is unreachable.
   - **`YtMusicStyleStrategy`**:
     - Seed-based radio: similar tracks, mix of familiar and fresh, anti-repeat (no songs played in last 50 tracks), strict sliding window artist diversity (no same artist back-to-back within 3 tracks).
     - Sourced via `RadioEngine` (YouTube Music mix) with fallback to `SaavnClient.getRelatedSongs`.
3. **Settings Persistence**:
   - Add `nextTrackStrategy` property in `SettingsManager` (stored in Hive `settings_box`).
   - Add selector tile in `settings_screen.dart` with explanations of both modes.
4. **Auto-Refill Trigger**:
   - When upcoming tracks count drops below 5 (`upcomingCount < 5`), automatically invoke active strategy to fetch and append 5 new candidate tracks, tagging them with `isSmartRecommended = true`.

---

### Phase 4: Search and Lyrics
**Goals**: Broad typo-tolerant search with Tamil phonetic support, dedicated Artists section, and multi-stage validated synchronized lyrics.

1. **Typo-Tolerant Search**:
   - Implement Levenshtein edit distance and phonetic normalizer for Tamil words written in English (Tanglish phonetics: e.g. "th" <-> "t", "zh" <-> "l", double vowels "aa" <-> "a", "oo" <-> "u").
   - Query remote suggestion endpoint (`ApiClient.searchSuggestions` and Saavn suggestions) in addition to local candidates so typo correction is never restricted to local terms.
   - "Did you mean...?" suggestion banner that performs instant search on tap.
   - Parallel search: query JioSaavn and YouTube concurrently, merge results using canonical grouping (`groupCanonicalSongs`), and rank using composite relevance scoring.
2. **Artists Section**:
   - Include dedicated "Artists" results in the "All" tab (horizontal avatars) and full list in the "Artists" tab.
   - Tapping an artist opens `ArtistScreen`.
3. **Lyrics Pipeline & Validation**:
   - Multi-stage validation for lyrics candidates:
     1. Title token similarity $\ge 70\%$.
     2. Artist token intersection.
     3. Duration tolerance: candidate duration must be within $\pm 15$ seconds of song duration.
     4. Script/language verification: if song is regional (e.g. Tamil), reject non-matching scripts (e.g. Spanish/Hindi).
   - Prefer synchronized LRC (`syncedLyrics`) with timestamp tags `[mm:ss.xx]`.
   - Local caching: cache validated lyrics by song ID in Hive to prevent redundant network calls.
   - Race condition guard: compare active song ID before setting lyrics to ignore late responses for skipped tracks.
   - Action: Add "Wrong lyrics? Pick another" sheet to manually search or pick from alternative lyric providers.

---

### Phase 5: Battery and Cache
**Goals**: Optimize foreground service lifecycle, crossfade-only position listeners, single-track preloading, size-capped LRU cache, and user-configurable cache settings.

1. **Battery SLA & Service Teardown**:
   - Downgrade foreground notification shortly after pausing (e.g. 60 seconds of pause) and release CPU wakelocks.
   - On Android task swipe-away (`onTaskRemoved`), stop foreground service cleanly if playback is paused.
   - Position & crossfade listener: only subscribe to continuous high-frequency position ticks when `SettingsManager.crossfadeSeconds > 0`. When crossfade is 0, use throttled 1-second position ticks.
   - Preloading: preload only the immediate next track (1 track ahead instead of 3).
2. **Size-Capped LRU Cache (`CacheManager`)**:
   - Implement LRU cache tracking access time (`atime` or metadata log) for cached audio chunks.
   - Background periodic worker: check cache size against configured limit; evict oldest least-recently-used files when limit is reached.
   - Add cache size selector in `StorageSettingsScreen` (e.g. 250 MB, 500 MB, 1 GB, 2 GB) persisted in `SettingsManager`.

---

### Phase 6: Collaborative Playlist
**Goals**: Audit `collaborative_playlist_service.dart` and `join_playlist_dialog.dart`, implement live updates, user attribution, role permissions, duplicate prevention, and Supabase RLS policies.

1. **Audit & Service Completion**:
   - Connect Supabase Realtime channel for live track additions, removals, and reordering across all joined members.
   - Track attribution: add `added_by` (user ID and name) to playlist track models so UI displays who added each track.
   - Collaborative permissions: only playlist owner can delete the playlist or remove other users' tracks; collaborators can add tracks and remove their own tracks.
   - Duplicate prevention: check canonical deduplication key before appending to prevent accidental duplicate additions.
2. **Supabase RLS Rules**:
   - Provide SQL migration script defining Row Level Security policies for `playlists` and `playlist_tracks` tables:
     - `SELECT`: allowed for owner, or if `is_public = true`, or if user is a member with the valid invite code.
     - `INSERT / UPDATE`: allowed for owner and verified collaborators.
     - `DELETE`: tracks deletable by owner or the user who inserted them.

---

### Phase 7: Multi-Phone Synchronized Playback
**Goals**: Design and build low-latency synchronized playback across multiple devices (Host/Joiner model) with clock-offset synchronization, scheduled starts, continuous drift correction, and unit tests.

1. **Architecture & Handshake**:
   - **Host / Joiner Model**: Host controls the master queue and playback state. Joiners follow.
   - **Clock-Offset Handshake**: Joiner sends ping packets to host (via local Wi-Fi UDP/TCP socket, with Supabase Realtime as fallback). Computes RTT and host time offset:
     $$\Delta t = t_{\text{host}} - (t_{\text{request}} + \frac{\text{RTT}}{2})$$
2. **Scheduled Start & Continuous Drift Correction**:
   - Scheduled Start: Host broadcasts play event with future timestamp $T_{\text{start}} = T_{\text{now}} + 400\text{ms}$. Both host and joiners trigger `player.play()` at $T_{\text{start}}$.
   - Drift Correction: Joiner compares local playback position with host position every 2 seconds.
     - If drift $\le 20\text{ms}$: no action (in sync).
     - If drift between $20\text{ms}$ and $150\text{ms}$: apply micro-rate correction (`player.setSpeed(0.98)` or `1.02`) until drift is eliminated.
     - If drift $> 150\text{ms}$: hard seek to host position.
   - Per-device manual delay adjustment slider ($\pm 500\text{ms}$) in UI to compensate for Bluetooth/hardware audio latency.
3. **Realistic Accuracy Documentation**:
   - Document Bluetooth latency (A2DP typical latency 100-250ms, SBC vs AAC) and Android audio buffer variations.
4. **Unit Tests (`test/synchronized_playback_test.dart`)**:
   - Clock offset calculation test with simulated network jitter.
   - Drift correction speed adjustment verification.
   - Fallback and reconnection handling.

---

## 5. Execution Protocol & Agent Scopes

- **Path Scope Compliance**:
  - `mobile/**`, `plans/**`: handled under `mobile_engineer` scope.
  - `backend-data-hf/**`: handled under `backend_engineer` scope if backend adjustments are needed.
- **Workflow Sequence**:
  1. Present this plan and obtain explicit user approval.
  2. Implement Phase 1 -> run `flutter test` and `flutter analyze` -> summarize changes.
  3. Obtain approval before proceeding to each subsequent phase.
