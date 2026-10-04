# 📋 Paatu Padava — Architecture & Status Summary
**Project:** Paatu Padava (பாட்டு பாடவா) — v2.0.0  
**Last Updated:** October 4, 2026  
**Status:** Phase 0 (Security & Cleanup) Complete — All 106 tests pass, 0 analyzer issues

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
| **Mobile App** | `mobile/` | Flutter player with background audio, offline downloads, smart shuffle |
| **Backend API** | `backend-data-hf/` | Python FastAPI on HuggingFace Spaces — search, recommendations, yt-dlp |
| **Cloud DB** | Supabase | User auth, history, playlists, favorites sync |
| **React Web** | `archive/frontend-react/` | **Archived** — superseded by mobile-first approach |

---

## 2. Current Health

| Metric | Value |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **106/106 passed** |
| `python -m unittest discover -s backend-data-hf/tests` | **32/32 passed** |
| Unused dependencies removed | `flutter_lyric`, `intl`, `permission_handler` |
| Dead code files deleted | `discord_rpc_service.dart`, `catalog_repository.dart` |
| Dead methods deleted | `reRankSongs`, `buildLanguageBiasedQuery`, `playSongRadio`, `addSong` (alias), `clearLocal` |

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

## 5. Remaining Work (Future Phases)

Phases 0D and 1+ are defined in the user's original issue list and not yet started:
- **Phase 0D**: Accurate, specific error messages (search, player, lyrics, home feed, downloads)
- **Phase 1**: Queue/playback alignment fixes (the original index drift bugs)
- **Phase 2+**: Feature work TBD

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
