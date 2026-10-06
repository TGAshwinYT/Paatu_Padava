# 📋 Paatu Padava — Architecture & Status Summary
**Project:** Paatu Padava (பாட்டு பாடவா) — v2.1.0  
**Last Updated:** October 6, 2026  
**Status:** Phase 0 & Phase 1 Complete — 3-Tier Queue, Autoplay Engine, 132/132 Flutter tests pass, 32/32 Backend tests pass, 0 analyzer issues

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
| **Mobile App** | `mobile/` | Flutter player with background audio, 3-tier queue, endless autoplay, smart shuffle |
| **Backend API** | `backend-data-hf/` | Python FastAPI on HuggingFace Spaces — search, recommendations, yt-dlp |
| **Cloud DB** | Supabase | User auth, history, playlists, favorites sync |
| **React Web** | `archive/frontend-react/` | **Archived** — superseded by mobile-first approach |

---

## 2. Current Health

| Metric | Value |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **132/132 passed (100%)** |
| `python -m unittest discover -s tests` | **32/32 passed (100%)** |
| Total Tests | **164/164 passed (100%)** |

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
- **Archived**: `frontend-react/` → `archive/frontend-react/`

---

## 4. Agent Scopes

Defined in `.antigravity/agents.json`:

| Agent | Scope | Denied |
|---|---|---|
| `mobile_engineer` | `mobile/**`, `plans/**` | `backend-data-hf/**` |
| `backend_engineer` | `backend-data-hf/**` | `mobile/**`, `frontend-react/**` |

---

## 5. Recent Completed Milestones

- **Phase 0D Complete**: Accurate, specific error messages and AppError domain models across search, player, lyrics, home feed, and downloads.
- **Phase 1 Complete**: Spotify & Echo-Music-inspired 3-tier queue architecture (Now Playing, User Queue Stack, Up Next / Autoplay Context), endless autoplay refills, 50-track Song Radio, 3-state Smart Shuffle, OEM background stability, and dual-ingestion mutex lock.
- **Phase 2 Complete**: Modular presentation layer refactor across widgets (`home/`, `player/`, `search/`, `settings/`, `library/`, `lyrics/`, `recap/`).

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
