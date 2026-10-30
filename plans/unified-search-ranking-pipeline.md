# Plan: Fast Typeahead & Unified Multi-Factor Search Ranking

Status: DONE
Owner agent: mobile_engineer

## 1. Goal (one sentence, user-visible)
Make search feel instant (<150ms typeahead) with typo-tolerant Romanized Tamil/Tanglish matching and intelligent multi-factor relevance ranking (45% string similarity + 35% source popularity + 20% user affinity) that completely eliminates cross-provider duplicates.

## 2. Non-goals (what we are NOT doing)
- We are NOT resolving audio streams during typing or search result display (streams stay deferred to active play & pre-cache).
- We are NOT removing category tiles or recent search history.
- We are NOT breaking existing tab views (All, Songs, Albums, Artists, Playlists).

## 3. Current state (verified by reading code)
- **Files updated and verified**:
  - `mobile/lib/ui/screens/search_screen.dart`: Debounce tightened to 350ms, instant local PrefixTrie typeahead lookup + non-blocking remote autocomplete.
  - `mobile/lib/services/search_service.dart`: Multi-factor relevance formula implemented, deduplicateAndRankUnified implemented.
  - `mobile/lib/services/saavn_client.dart`: Added `getSearchSuggestions` querying `autocomplete.get`.
  - `mobile/lib/services/youtube_client.dart`: Optimized `getSearchSuggestions` to handle both `client=youtube` and `client=firefox`.
  - `mobile/lib/logic/search_query_planner.dart`: Cross-source canonical fingerprinting and multi-source query planning.
  - `mobile/lib/domain/models/track_entity.dart`: Word-boundary regex for `versionTag` (prevents "Chilla" being tagged as "Lofi").
  - `mobile/test/search_ranking_relevance_test.dart`: 16 comprehensive unit tests verifying the 4 stages.

## 4. Design
### Stage 1: Instant Debounced Typeahead (< 150ms)
- When user types:
  1. Immediately check local `PrefixTrie` (populated with search history, favorite tracks, and downloaded library) in < 1ms.
  2. Fire lightweight client-side requests directly to YouTube Suggest (`suggestqueries.google.com/complete/search?client=youtube&ds=yt&q=...`) and JioSaavn autocomplete in parallel.
  3. Never resolve audio streams or full heavy entities while user is actively typing.

### Stage 2: Parallel Multi-Source Fetch (350ms Debounce)
- When user pauses for 350ms or presses Submit:
  - Query JioSaavn (`SaavnClient.search`, `SaavnClient.searchAlbums`, `SaavnClient.searchPlaylists`) and YouTube Music InnerTube (`YouTubeClient.searchTracks`, `YouTubeClient.searchPlaylists`) in parallel via `Future.wait`.

### Stage 3: Normalization & Cross-Source Canonical Fingerprint Deduplication
- Clean titles using regex & `SearchQueryPlanner.cleanTitle` (strip `[Official Video]`, `Lyrical`, `(From ...)`, etc.).
- Generate canonical fingerprint: `fingerprint = "${canonicalTitle}|${primaryArtist}"`.
- When a track exists in both JioSaavn and YouTube Music:
  - Keep JioSaavn version as primary for 320kbps audio and clean studio square artwork.
  - Attach YouTube version as alternate stream/source fallback in `versions`.
  - Zero duplicate cards in the search results list.

### Stage 4: Multi-Factor Relevance Scoring
- Score every candidate across all sources in a single unified list:
  $$\text{Score} = (0.45 \times \text{StringSimilarity}) + (0.35 \times \text{SourcePopularity}) + (0.20 \times \text{UserAffinity})$$
  - **StringSimilarity (0.45)**:
    - Levenshtein metric distance from `BkTree.levenshteinDistance` + token containment.
    - Accurately matches Romanized Tamil / Tanglish typos (e.g. "kanave kanave", "aathichoodi", "waseegara").
  - **SourcePopularity (0.35)**:
    - Official Topic / verified artist badge (`hasOfficialAlbumArt`).
    - JioSaavn studio release or YouTube VEVO/Topic channel.
    - Duration penalty for extreme duration deviations (<45s or >600s).
  - **UserAffinity (0.20)**:
    - Checks `HistoryManager` and `FavoritesManager`.
    - If user has played or liked songs from this artist, assign maximum affinity bonus.
- Sort entire unified list descending by `Score`. The absolute best match is always #1.

## 5. Verification
- `flutter analyze lib/services/search_service.dart lib/logic/search_query_planner.dart lib/services/saavn_client.dart lib/services/youtube_client.dart lib/ui/screens/search_screen.dart test/search_ranking_relevance_test.dart`: 0 issues found.
- `flutter test test/search_ranking_relevance_test.dart test/search_query_planner_test.dart test/search_engine_revamp_test.dart test/search_pipeline_test.dart test/search_history_and_screen_test.dart test/ui_layout_matrix_test.dart`: 161/161 tests passed.
