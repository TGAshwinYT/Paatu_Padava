# Plan: Decouple Metadata from Streams & Upstream Graph Recommendations

Status: DONE
Owner agent: mobile_engineer

## 1. Goal (one sentence, user-visible)
Deliver instantaneous search/home feed loads (<200ms) and infinite, zero-cold-start smart radio recommendations by decoupling metadata from stream URLs and leveraging upstream graph APIs (YouTube Music Next & JioSaavn Reco) with local client-side anti-fatigue re-ranking.

## 2. Non-goals (what we are NOT doing)
- We are NOT removing local offline caching (Hive `home_feed_cache`, `cover_art_cache`, `download_manager`).
- We are NOT removing the Python backend entirely; it remains available for optional sync/web frontend endpoints, but the mobile app will not block on it for search, home feed, or recommendations.
- We are NOT eliminating `StreamResolver`; rather, we ensure it is called strictly just-in-time (JIT) for the active playing track and the `index + 1` pre-cache slot.

## 3. Current state (verified by reading code)
- **Existing screens/widgets/services involved**:
  - `mobile/lib/services/search_service.dart`: Multi-source search (Saavn, YouTube, Audius).
  - `mobile/lib/services/youtube_client.dart`: Provides `searchTracks`, `getUpNextAutomix`, and `getRadioTracks`. Already returns `TrackEntity` with `streamUrl: ''` for search.
  - `mobile/lib/services/saavn_client.dart`: `search` and `getRelatedSongs` (`reco.getreco`). Currently decrypts DES media URL synchronously on parse.
  - `mobile/lib/logic/next_track_strategy.dart`: `SpotifyStyleStrategy` awaits `ApiClient.fetchRecommendations` (Hugging Face backend) with an 8-second timeout, causing delays on cold backends or niche Tamil songs.
  - `mobile/lib/logic/audio_queue_handler.dart`: Already implements two-tier queue, `useLazyPreparation: true`, and preloads upcoming tracks via `preloadUpcomingTracks`.
  - `mobile/lib/logic/stream_resolver.dart`: Implements 4-tier stream resolution with LRU cache.
- **What can be reused**:
  - `YouTubeClient.getUpNextAutomix(videoId)` (`POST https://music.youtube.com/youtubei/v1/next` with `RDAMVM$videoId`).
  - `SaavnClient.getRelatedSongs(songId)` (`reco.getreco`).
  - `TrackQualityFilter.shouldKeep` (drops >10m mixes, teasers, and dead streams).
  - `QueueCooldownManager` and `enforceArtistDispersionAndNoBackToBack`.
  - `StreamResolver.resolveStreamUrl` (JIT resolution).
- **Known problems nearby**:
  - `SpotifyStyleStrategy` awaits `ApiClient.fetchRecommendations` (Hugging Face) with an 8-second timeout. When HF is sleeping or cold, radio generation hangs for 8s and returns empty for niche songs.
  - Eager DES URL assignment in `SaavnClient` can lead to stale CDN tokens if a track sits in a queue or search results for hours before playing.

## 4. Design
- **1. Upstream Graph Piggybacking (BloomeeTunes Model)**:
  - In `SpotifyStyleStrategy`, replace blocking `ApiClient.fetchRecommendations` with fast parallel queries directly to upstream graph endpoints:
    1. YouTube Music's native `next` automix graph (`YouTubeClient.getUpNextAutomix`).
    2. JioSaavn's official related songs endpoint (`SaavnClient.getRelatedSongs`).
    3. JioSaavn artist hits query (`SaavnClient.search`).
  - Local client strictly performs:
    - **Filtering**: `TrackQualityFilter.shouldKeep`, language match check.
    - **Deduplication**: `canonicalBaseKey` and `cleanTitleKey` matching.
    - **Re-ranking**: `QueueCooldownManager` (5-track skip cooldown), zero back-to-back artist duplicates, and 60/40 session anchor shifting.
- **2. Metadata Decoupling from Stream URLs**:
  - Ensure search and home feed parsing treats `streamUrl` as optional lazy metadata.
  - If a track in search or home results originates from Saavn, preserve the track entity without eager network validation.
  - `AudioQueueHandler.loadQueue` and `preloadUpcomingTracks` will resolve streams strictly on demand:
    - Slot `i` (active): resolved when track is played.
    - Slot `i + 1` (pre-cache): resolved asynchronously by `preloadUpcomingTracks` during playback.
    - Slot `i + 2...N`: remains pure metadata until approaching playback.

## 5. States to handle
- **Niche/Indie Song (Zero Local History)**: Upstream graph query returns rich contextual tracks from YouTube Music and JioSaavn within 300ms without local cold-start failure.
- **Offline / Flight Mode**: Circuit breaker engages `getLocalFallbackTracks` (cached favorites, downloads, recent history).
- **Network Timeout on Upstream Graph**: Falls back to artist/album search and local circuit breaker within 3s.
- **Stale Stream URL**: If a track sat in queue > 3 hours, JIT expiration check in `stream_resolver.isExpired` re-resolves the stream URL seamlessly before playback.

## 6. Edge cases & risks
- **YouTube videoId missing for Saavn seed song**: `YouTubeClient.resolveVideoIdForSong` or clean title search finds the YouTube candidate in <400ms before calling `getUpNextAutomix`.
- **Duplicate tracks across YouTube and Saavn**: Normalized `canonicalBaseKey` (`title_artist`) and `cleanTitleKey` prune identical songs before candidate ranking.

## 7. Steps (small, each independently verifiable)
1. [ ] Remove blocking `ApiClient.fetchRecommendations` call from `SpotifyStyleStrategy` and replace with unified upstream graph fetching (`YouTubeClient.getUpNextAutomix` + `SaavnClient.getRelatedSongs`).
2. [ ] Audit `SearchService` and `SaavnClient` to ensure search and home feeds only emit pure JSON metadata without eager stream network checks.
3. [ ] Verify that `AudioQueueHandler` only invokes `streamResolver.resolveStreamUrl` for active and `index + 1` slots.
4. [ ] Add unit test verifying that radio generation produces diverse upstream graph recommendations for cold/niche seeds without calling backend-data-hf.
5. [ ] Run static analysis (`flutter analyze --no-fatal-infos`) and tests (`flutter test test/commercial_next_track_strategy_test.dart test/ui_layout_matrix_test.dart`).

## 8. Tests
- [ ] `mobile/test/commercial_next_track_strategy_test.dart`: Add tests verifying upstream graph candidate integration and zero-lag recommendation generation.
- [ ] `mobile/test/ui_layout_matrix_test.dart`: Layout matrix regression check.

## 9. Verification commands
```bash
cd mobile
flutter analyze --no-fatal-infos
flutter test test/commercial_next_track_strategy_test.dart
flutter test test/ui_layout_matrix_test.dart
```

## 10. Done report
- **Files changed**:
  - `mobile/lib/logic/next_track_strategy.dart`: Replaced blocking `ApiClient.fetchRecommendations` with parallel upstream graph queries (`YouTubeClient.getRadioTracks` + `SaavnClient.getRelatedSongs`), eliminating unused import.
  - `mobile/lib/logic/smart_shuffle_controller.dart`: Swapped HF backend recommendation call with direct `YouTubeClient.getRadioTracks`.
  - `mobile/lib/services/radio_engine.dart`: Added 1.5s non-blocking safety timeout on secondary backend ML recommendations.
  - `mobile/test/commercial_next_track_strategy_test.dart`: Added verification test for zero-backend-blocking upstream graph recommendation generation.
- **Commands run + results**:
  - `flutter analyze --no-fatal-infos`: **No issues found** (0 errors, 0 warnings).
  - `flutter test test/commercial_next_track_strategy_test.dart test/ui_layout_matrix_test.dart`: **111 / 111 tests passing**.
- **Not verified**: Physical device battery drain over 24-hour continuous playback.
