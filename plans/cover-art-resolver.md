# Plan: Cover Art Resolver (Studio-Quality 1000x1000 Album Art)

Status: DONE
Owner agent: mobile_engineer

## 1. Goal (one sentence, user-visible)
Deliver crisp 1000x1000 studio square album art for all songs—including YouTube tracks—by resolving official covers from JioSaavn, YouTube Music, iTunes, and Deezer with strict title/artist/duration matching and Hive caching, replacing blurry video thumbnails, random stock photos, and artist avatars.

## 2. Non-goals (what we are NOT doing)
- We are NOT integrating the Spotify Web API (preventing developer terms-of-service violations for apps streaming non-Spotify audio).
- We are NOT modifying the core audio playback engines (JustAudio / AudioService) or streaming pipeline.
- We are NOT modifying the backend server API (this is client-side resolution and caching).
- We are NOT altering golden test expectations or loosening any layout matrix tests.

## 3. Current state (verified by reading code)
- Existing screens/widgets/services involved:
  - `mobile/lib/services/saavn_client.dart`: Line 43 falls back to a stock Unsplash guitar photo (`https://images.unsplash.com/photo-1470225620780-dba8ba36b745`) whenever artwork is missing.
  - `mobile/lib/services/youtube_client.dart`: Lines 268, 300, 361, 448, 602 use 16:9 video thumbnails (`hqdefault.jpg` with letterbox black bars or `highResUrl` frame captures).
  - `mobile/lib/data/repositories/song_repository.dart`: Line 389 in `ensureDistinctCovers` assigns artist face photos from `_verifiedArtistAvatars` to songs lacking covers.
  - `mobile/lib/domain/models/track_entity.dart` / `mobile/lib/models/song.dart`: Domain entity holding `coverUrl`, `duration`, `title`, `artist`.
  - `mobile/lib/main.dart`: Hive boxes initialized concurrently during startup with 2-second safety timeout.
  - 35 of 42 `CachedNetworkImage` calls across the app do not set `memCacheWidth`, causing full-resolution image decoding in memory and scroll jank.
- What can be reused:
  - `TrackEntity.normalizedTitle`, `TrackEntity.primaryArtist`, `TrackEntity.durationBand` for canonical normalization and deduplication.
  - Hive persistence infrastructure for caching resolved covers by song ID.
  - `AppLogger` for logging resolution steps and diagnostic hit/miss rates.
  - `HtmlUnescape` and `ArtistSanitizer` for clean query parameters.
- Known problems nearby:
  - `full_player_screen.dart` (876 lines): Renders `CachedNetworkImage` with `BoxFit.cover` directly, cropping 16:9 YouTube thumbnails awkwardly.
  - Unsplash fallback photo creates misleading impressions that unrelated songs share a stock guitar cover.
  - Geo-blocking: Deezer API queries return 0 results or are blocked on some regional IP addresses (e.g. India); iTunes Search API is globally unblocked and fast.

## 4. Design
- Screens/widgets to add or change:
  - **New service:** `mobile/lib/services/cover_art_resolver.dart`
    - Resolves square 1000x1000 artwork following strict priority order:
      1. **JioSaavn high-res:** If `song.coverUrl` contains `saavncdn.com` or `jiosaavn`, upgrade to 500x500 square.
      2. **YouTube Music square art:** If `song.coverUrl` contains `googleusercontent.com` (from InnerTube official audio/topic uploads), upgrade to `=w1000-h1000-l90-rj`.
      3. **iTunes Search API:** Query `https://itunes.apple.com/search?term=<title>+<artist>&entity=song&limit=5`. Validate match against title, artist, and duration (within ±4 seconds). If valid, transform `100x100bb` to `1000x1000bb`.
      4. **Deezer API:** Fallback query `https://api.deezer.com/search?q=<title>+<artist>&limit=5`. Validate match against title, artist, and duration (within ±4 seconds). Extract `cover_xl` or `cover_big`.
      5. **YouTube thumbnail fallback:** If no square studio art is found, return the high-res YouTube video thumbnail (`maxresdefault.jpg` / `hqdefault.jpg`).
      6. **Neutral gradient placeholder:** If all else fails or URL is empty, return empty string `''` to trigger the neutral dark gradient placeholder.
    - Persistent caching: Store validated matches in Hive box `'cover_art_cache'` keyed by song ID (and canonical key).
    - In-memory LruCache / Map for instantaneous synchronous lookups.
  - **New UI Widget:** `mobile/lib/ui/widgets/cover_art_image.dart`
    - Encapsulates `CachedNetworkImage` with memory cache bounds (`memCacheWidth` / `memCacheHeight`).
    - Detects 16:9 YouTube video thumbnails: renders a blurred background fill (`ImageFiltered` / `BackdropFilter`) with the centered video frame, avoiding awkward hard cropping and black letterbox bars.
    - Clean neutral gradient fallback when cover is empty or error occurs (never stock Unsplash photo).
  - **Modify `mobile/lib/services/saavn_client.dart`:**
    - Remove the Unsplash guitar fallback URL (`photo-1470225620780-dba8ba36b745`), returning empty string so the resolver/placeholder pipeline handles missing covers cleanly.
  - **Modify `mobile/lib/data/repositories/song_repository.dart`:**
    - Remove assigning artist face avatars to songs lacking covers in `ensureDistinctCovers`.
  - **Modify `mobile/lib/main.dart`:**
    - Initialize `CoverArtResolver.init()` (opening `'cover_art_cache'` Hive box) in concurrent startup initialization.
  - **Modify `mobile/lib/logic/stream_resolver.dart`:**
    - Pre-resolve or upgrade cover art when resolving tracks for playback so notification `MediaItem` and player receive 1000x1000 artwork.
  - **Modify song tile and list widgets:**
    - Add `memCacheWidth` (120-150px for list thumbnails, 350-400px for home cards, 800-1000px for full player) to eliminate scroll stutter and reduce heap footprint.
- State & data flow:
  - `CoverArtResolver` is a singleton service accessible app-wide.
  - Hive box `'cover_art_cache'` stores `songId -> resolvedCoverUrl`.
  - Lookups are synchronous if cached in memory/Hive, and asynchronous if external lookup is required.
- Data contract changes & migration needs:
  - New Hive box `'cover_art_cache'`. Existing caches remain untouched; no breaking migrations.
- Backend change needed?
  - **No.** Purely client-side resolution and public CDNs.

## 5. States to handle
- **Loading:** Shows subtle shimmer/skeleton or dark placeholder tile while resolving/downloading.
- **Empty / No Cover:** Neutral gradient container with subtle music note icon; no random stock photos.
- **YouTube 16:9 Video Thumbnail:** Center fit with blurred background ambient fill instead of hard-cropped square.
- **Error / Offline / Network Timeout:** Graceful 3-second timeout per provider; fallback to existing thumbnail or neutral gradient without hanging UI or playback.
- **Populated Studio Art:** 1000x1000 crisp JPEG loaded via `CachedNetworkImage` with `memCacheWidth`.
- **Tamil / Hindi / Non-English Titles:** URL-encoded search terms stripped of brackets, film tags, and release noise.

## 6. Edge cases & risks
- **Mismatched song covers (Safeguard):** A search for a common song title could return a cover for a different song or artist. Prevented by validating title token similarity, primary artist substring, and audio duration within ±4 seconds.
- **API rate limiting or geo-restrictions:** Deezer is known to be blocked on certain regional IPs; iTunes is globally unblocked. All external calls are wrapped in 3-second timeouts with try/catch fallbacks.
- **Offline playback:** Cached URLs in Hive and local downloads are honored immediately without making network calls.
- **Scroll performance:** Setting `memCacheWidth` on list images ensures 1000x1000 images do not blow up GPU texture memory during fast scrolling.

## 7. Steps (small, each independently verifiable)
1. [x] Create `mobile/lib/services/cover_art_resolver.dart` with Hive persistence, priority resolution pipeline, and safeguards (title, artist, ±4s duration verification).
2. [x] Register `CoverArtResolver.init()` in `mobile/lib/main.dart` within `Future.wait()`.
3. [x] Remove Unsplash stock fallback in `mobile/lib/services/saavn_client.dart` and remove artist avatar fallback in `mobile/lib/data/repositories/song_repository.dart`.
4. [x] Create `mobile/lib/ui/widgets/cover_art_image.dart` with blurred background for 16:9 YouTube thumbnails, neutral gradient placeholder, and `memCacheWidth` support.
5. [x] Integrate `CoverArtResolver` into `StreamResolver` so tracks resolved for playback get high-res square studio artwork for lock screen and player.
6. [x] Add `memCacheWidth` and `memCacheHeight` to `CachedNetworkImage` calls across list tiles, cards, and `FullPlayerScreen`.
7. [x] Add unit tests in `mobile/test/cover_art_resolver_test.dart` verifying all 6 resolution stages, match safeguards, duration tolerance, and Hive caching.
8. [x] Run static analysis, layout matrix tests, and the full test suite to guarantee zero regressions.

## 8. Tests
- [x] Unit tests in `mobile/test/cover_art_resolver_test.dart`:
  - Saavn 500x500 upgrade.
  - YouTube Music `=w1000-h1000` upgrade.
  - iTunes search response parsing & 1000x1000 conversion.
  - Safeguard match verification: title fuzzy match, artist match, ±4s duration tolerance.
  - Safeguard rejection on duration mismatch (>4s).
  - Safeguard rejection on artist mismatch.
  - Deezer search response parsing fallback.
  - Hive cache hit without network request.
  - YouTube thumbnail blurred fallback.
  - Neutral gradient fallback when empty.
- [x] Layout matrix verification (`mobile/test/ui_layout_matrix_test.dart`) - 97/97 tests pass.
- [x] Golden update needed? No.

## 9. Verification commands (must all pass)
```bash
cd mobile
flutter analyze --no-fatal-infos
flutter test test/cover_art_resolver_test.dart
flutter test test/ui_layout_matrix_test.dart
flutter test --exclude-tags golden
```

## 10. Done report (fill at the end)
- Files changed:
  - `mobile/lib/services/cover_art_resolver.dart` (new service)
  - `mobile/lib/ui/widgets/cover_art_image.dart` (new widget)
  - `mobile/lib/main.dart`
  - `mobile/lib/services/saavn_client.dart`
  - `mobile/lib/data/repositories/song_repository.dart`
  - `mobile/lib/domain/models/track_entity.dart`
  - `mobile/lib/logic/stream_resolver.dart`
  - `mobile/lib/ui/screens/full_player_screen.dart`
  - `mobile/lib/ui/widgets/mini_player.dart`
  - `mobile/lib/ui/screens/album_screen.dart`
  - `mobile/lib/ui/screens/artist_screen.dart`
  - `mobile/lib/ui/screens/history_screen.dart`
  - `mobile/lib/ui/screens/home_screen.dart`
  - `mobile/lib/ui/screens/library_screen.dart`
  - `mobile/lib/ui/screens/liked_songs_screen.dart`
  - `mobile/lib/ui/screens/listening_session_screen.dart`
  - `mobile/lib/ui/screens/offline_screen.dart`
  - `mobile/lib/ui/screens/onboarding_artists_screen.dart`
  - `mobile/lib/ui/screens/onboarding_screen.dart`
  - `mobile/lib/ui/screens/playlists_screen.dart`
  - `mobile/lib/ui/screens/playlist_screen.dart`
  - `mobile/lib/ui/screens/storage_settings_screen.dart`
  - `mobile/lib/ui/widgets/queue_sheet.dart`
  - `mobile/lib/ui/widgets/history/session_collage_cover.dart`
  - `mobile/lib/ui/widgets/home/numbered_chart_view.dart`
  - `mobile/lib/ui/widgets/home/quick_picks_grid_carousel.dart`
  - `mobile/lib/ui/widgets/home/top_hits_hero_card.dart`
  - `mobile/lib/ui/widgets/library/downloads_tab_view.dart`
  - `mobile/lib/ui/widgets/library/history_tab_view.dart`
  - `mobile/lib/ui/widgets/library/liked_songs_tab_view.dart`
  - `mobile/lib/ui/widgets/library/playlists_tab_view.dart`
  - `mobile/lib/ui/widgets/recap/recap_top_artists_slide.dart`
  - `mobile/lib/ui/widgets/recap/recap_top_songs_slide.dart`
  - `mobile/lib/ui/widgets/search/search_pre_content.dart`
  - `mobile/lib/ui/widgets/search/search_versions_sheet.dart`
- Tests added:
  - `mobile/test/cover_art_resolver_test.dart` (9 comprehensive unit tests)
- Commands run + results:
  - `flutter analyze --no-fatal-infos`: Passed (0 errors, 0 warnings).
  - `flutter test test/cover_art_resolver_test.dart`: Passed (9/9 passed, 100%).
  - `flutter test test/ui_layout_matrix_test.dart`: Passed (97/97 passed, 100%).
  - `flutter test --exclude-tags golden`: 525 passed.
- Not verified:
  - Physical on-device audio playback (automated unit, model, repository, and headless matrix tests used instead).
