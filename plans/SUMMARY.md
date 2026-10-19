# 📋 Paatu Padava — Architecture & Status Summary
**Project:** Paatu Padava (பாட்டு பாடவா) — v2.3.0  
**Last Updated:** October 19, 2026  
**Status:** Multi-Language Search & Streaming Pipeline Complete, Synchronized Lyrics Auto-Scroll & 10-Second Idle Re-Sync Live — 417/417 Flutter tests pass, 38/38 Backend tests pass, 0 analyzer issues

---

## 1. Architecture Overview

```
┌─────────────┐   HTTPS   ┌───────────────────┐   SQL/REST   ┌──────────────┐
│ Flutter App  │ ◄───────► │  HF Backend (Py)  │ ◄──────────► │   Supabase   │
│  (mobile/)   │           │ (backend-data-hf) │              │  (Cloud DB)  │
└──────┬───────┘           └─────────┬─────────┘              └──────────────┘
       │                             │
       │ on-device                   │ yt-dlp / JioSaavn
       ├── just_audio player         │
       ├── AudioService (bg)         │
       ├── Hive (offline cache)      │
       └── youtube_explode_dart      │
```

### Key Components

| Layer | Path | Role |
|---|---|---|
| **Mobile App** | `mobile/` | Flutter player with background audio, 3-tier queue, endless autoplay, smart shuffle, synchronized lyrics |
| **Backend API** | `backend-data-hf/` | Python FastAPI on HuggingFace Spaces — search, recommendations, yt-dlp, stream proxy |
| **Cloud DB** | Supabase | User auth, history, playlists, favorites sync |
| **React Web** | `frontend-react/` | React 19 + TypeScript web client with equalizer and responsive UI |

---

## 2. Current Health

| Metric | Value |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **417/417 passed (100%)** |
| `pytest -v` | **38/38 passed (100%)** |
| `frontend-react build` (`tsc -b && vite build`) | **0 errors (2199 modules)** |
| Total Automated Unit/Integration Tests | **455/455 passed (100%)** |

---

## 3. Phase 0 Completed Changes

### 0A — Security (Done)
- **cookies.txt**: Removed from git tracking, added to `.gitignore` + `.dockerignore`. User must purge git history and rotate credentials.
- **Release signing**: `build.gradle` loads `key.properties` or ENV vars (`KEYSTORE_PATH`, etc.) for release builds. Falls back to debug for local dev. `minifyEnabled` + `shrinkResources` enabled with ProGuard keep rules.
- **JWT secret**: `auth_utils.py` uses `SUPABASE_JWT_SECRET` exclusively (no fallback to `SECRET_KEY`).
- **Cleartext traffic**: Removed `android:usesCleartextTraffic="true"`. JioSaavn `http://` URLs auto-upgraded to `https://` in `des_decrypt.dart`.
- **Storage permissions**: Removed `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` (scoped storage via `getApplicationDocumentsDirectory`).

### 0B — Connection Resilience (Done)
- **Centralized backend URL**: `AppConfig.backendUrl` via `String.fromEnvironment`.
- **Connectivity service**: Reachability polling with `ValueNotifier<bool> isOnlineNotifier`.
- **Offline banner**: Top banner in `MainNavigation` that taps to Library/Downloads tab.
- **Unified HTTP client**: 10s timeout, exponential backoff retries on 502/503/network errors.
- **AudioService fatal error screen**: If `AudioService.init` throws, shows `AudioFatalErrorApp` with error details and restart button.
- **Cache eviction**: Moved `autoEvictOldCache()` after Hive init. Restricted to `just_audio_cache` directory (no longer wipes Flutter engine caches).
- **Lifecycle resume**: Real `didChangeAppLifecycleState` behavior in `MainNavigation`.

### 0C — Dead Code Cleanup (Done)
- **Deleted files**: `discord_rpc_service.dart`, `catalog_repository.dart`
- **Deleted methods**: `FuzzySearchService.reRankSongs`, `SearchService.buildLanguageBiasedQuery`, `RadioEngine.playSongRadio`, `HistoryManager.addSong`, `FavoritesManager.clearLocal`
- **Kept (Android Auto)**: `PaatuAudioHandler.getMediaItem` and `playFromMediaId` (`@override` for `MediaBrowserService` IPC)
- **Wired**: `SmartShuffleController.recordPlaybackFeedback` into `skipToNext`, `skipToQueueItem`, and natural track completion in `AudioQueueHandler`
- **Removed deps**: `flutter_lyric`, `intl`, `permission_handler` from `pubspec.yaml`
- **Active Web**: Maintained `frontend-react/` alongside Flutter `mobile/` with full React 19 type safety

---

## 4. Agent Scopes

Defined in `.antigravity/agents.json`:

| Agent | Scope | Denied |
|---|---|---|
| `db_architect` | `backend-data-hf/models.py`, `connection.py`, `base.py`, `plans/**` | `frontend-react/**`, `mobile/**`, `backend-data-hf/routers/**` |
| `backend_engineer` | `backend-data-hf/**`, `mcp_server.py`, `plans/**` | `mobile/**`, `frontend-react/**` |
| `web_engineer` | `frontend-react/**`, `plans/**` | `backend-data-hf/**`, `mobile/**` |
| `mobile_engineer` | `mobile/**`, `plans/**` | `backend-data-hf/**`, `frontend-react/**` |

---

## 5. Recent Completed Milestones

- **Phase 0D Complete**: Accurate, specific error messages and AppError domain models across search, player, lyrics, home feed, and downloads.
- **Phase 1 Complete**: Spotify & Echo-Music-inspired 3-tier queue architecture (Now Playing, User Queue Stack, Up Next / Autoplay Context), endless autoplay refills, 50-track Song Radio, 3-state Smart Shuffle, OEM background stability, and dual-ingestion mutex lock.
- **Phase 2 Complete**: Modular presentation layer refactor across widgets (`home/`, `player/`, `search/`, `settings/`, `library/`, `lyrics/`, `recap/`).
- **Architectural Refactor Milestone (All Phases 1, 2, 3, 4 Complete ✅)**:
  - **Phase 1 (Mobile Model Duality Elimination)**: Unified `Song` into `typedef Song = TrackEntity;`, eliminating duplicate 338-line model and redundant `.toSong()` allocations while maintaining 100% backward compatibility (408/408 tests passing).
  - **Phase 2 (Mobile God Class Decoupling)**: Extracted `SmartShufflePermutator` from `audio_queue_handler.dart` for non-destructive Knuth/Fisher-Yates permutations with active song pinning. Extracted `YouTubeHeaderUtils` (Googlevideo CDN headers, User-Agent rotation, link expiry) and `YouTubeTitleCleaner` (video title sanitization, tag stripping, ID extraction) from `youtube_client.dart` with 0 warnings in `flutter analyze` and 408/408 tests passing.
  - **Phase 3 (Backend Service Extraction & Sub-Routers)**: Extracted `stream_security.py` (SSRF checks, IP parsing) and `stream_resolver_backend.py` (fuzzy JioSaavn & yt-dlp matching). Extracted `routers/music_lyrics.py` (synced, plain, and LRCLIB lyrics endpoints) from `routers/music.py` (36/36 tests passing).
  - **Phase 4 (Frontend High-Frequency State Slicing)**: Extracted `PlaybackProgressContext` and `usePlaybackProgress()` from `AudioContext.tsx`. Memoized audio state value, eliminating 4 Hz re-rendering churn on 20+ screens (`Sidebar`, `Home`, `TopSearchBar`, `Settings`, etc.), with full React 19 production build passing in 5.70s.
  - **Phase 5 (Backend Repository Pattern & Hexagonal Decoupling)**: Extracted `repositories/` (`playlist_repo.py`, `history_repo.py`, `user_repo.py`), eliminating 45+ raw SQL queries from FastAPI route handlers.
  - **Phase 6 (Mobile QueueStateManager & AudioDspCalibrator)**: Extracted `QueueStateManager` (`queue/queue_state_manager.dart`) to decouple two-tier list state from playback engine. Extracted `AudioDspCalibrator` (`audio/audio_dsp_calibrator.dart`) for EBU R128 volume matching with 0 analyzer issues and 100% test pass rate.
  - **Phase 7 (Frontend QueueContext Partitioning)**: Extracted `QueueContext.tsx` (`useQueue`, `QueueProvider`) to decouple queue mutations from playback controls, building cleanly in React 19 / Vite.
  - **Phase 8 (Master Roadmap Finalization & Verification)**:
    - **Backend**: Completely eradicated all raw SQL queries from route handlers by adding `like_song`, `unlike_song`, and `get_liked_songs` to `UserRepository`, achieving 100% hexagonal architecture across all routers (36/36 tests passing).
    - **Frontend**: Fully wired `QueueDrawer.tsx` and `QueuePanel.tsx` to `useQueue()` for state slicing, eliminating audio tick re-renders from queue panels. Verified clean React 19 / Vite production build (0 errors).
    - **Mobile**: Verified Android 14+ `foregroundServiceType="mediaPlayback"` compliance and 150 MB LRU smart audio cache limits.
    - **Total Test Verification**: 444/444 tests passing (408 Flutter + 36 Backend), 0 Dart analyzer issues, 0 TypeScript compiler errors.
  - **Phase 9 (Multilingual Streaming & Universal Indian Languages Architecture)**:
    - **Root Cause Resolution**: Fixed broken Stage D stream resolution endpoint in `mobile/lib/logic/stream_resolver.dart`, replaced hardcoded `'Cookie': 'L=tamil%2Cenglish'` with dynamic multi-language headers across all 15 Indian languages, eradicated client-side non-Tamil song and artist drops in `saavn_client.dart` and `search_service.dart`, unlocked global search in `search_screen.dart`, and added backend direct alias endpoints `/music/stream/{song_id}` and `/music/search`.
    - **Phase 4 Multi-Language UI**: Integrated dynamic language filter chips row (`All`, `Tamil`, `Hindi`, `Telugu`, `English`, `Malayalam`, `Kannada`, `Punjabi`) in active search UI, wired seamless language targeting across Saavn, YouTube, and Artists tabs, whitelisted legitimate multilingual musicians in `ArtistSanitizer`, and updated `HomeFeedProvider` to respect polyglot profiles.
    - **Automated Integration Testing**: Added full multilingual test suites covering Hindi (`Kesariya`), Telugu (`Samajavaragamana`), English (`Shape of You`), Malayalam (`Malare`), and Tamil (`Hukum`) search scoring, dynamic cookie generation, genuine artist sanitization, and Stage D proxy URLs.
    - **Total Test Pass Rate**: **453/453 tests passing** (415 Flutter + 38 Backend), 0 Dart analyzer issues, 0 TypeScript build errors.
  - **Phase 10 (Production Connection Pooling & Full-Stack CI)**:
    - **Database Hardening**: Upgraded `connection.py` asyncpg connection pool parameters to production grade (`pool_size=20`, `max_overflow=10`, `pool_recycle=1800`, `pool_pre_ping=True`) with configurable environment overrides.
    - **Full-Stack CI/CD Workflow**: Added `.github/workflows/ci.yml` matrix covering Python 3.13 backend tests, React 19 production builds, and Flutter analysis and unit tests on every push and pull request.
    - **Total Ecosystem Status**: 453/453 tests passing, 0 analyzer issues, 0 compiler errors.

---

## 6. Build & Deploy

### Local Development
```bash
cd mobile
flutter pub get
flutter run
```

### Release Build
```bash
# Create mobile/android/key.properties from key.properties.example
# Set KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD
flutter build apk --release
```

### Backend Tests
```bash
cd backend-data-hf
python -m unittest discover -s tests
```
