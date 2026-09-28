---
name: mobile-guidelines
description: Flutter Clean Architecture, background AudioService lifecycle, 5-minute battery wakelock guards, and offline caching protocols for Paatu Padava Mobile.
---

# Mobile Engineering Guidelines (Flutter & Android SDK 36)

## 1. Clean Architecture & Layer Isolation
Structure mobile modules into strict layers:
1. **Domain Layer (`lib/domain/`)**:
   - Entities (`TrackEntity`, `ArtistEntity`, `PlaylistEntity`) completely independent of external packages, UI, or database models.
   - Centralized string sanitation (e.g. `HtmlUnescape`) and deduplication keys:
     ```dart
     String get deduplicationKey => "${title.trim().toLowerCase()}_${artist.trim().toLowerCase()}";
     ```
2. **Data Layer (`lib/data/` & `lib/services/`)**:
   - Repositories (`CatalogRepository`, `AudioRepository`) aggregating multi-source streams (JioSaavn + YouTube).
   - Data sources: Remote HTTP/Supabase REST clients and local Hive boxes.
3. **Logic / Application Layer (`lib/logic/`)**:
   - `AudioQueueHandler` extending `BaseAudioHandler` for background playback.
   - `SmartShuffleController` for taste balancing and anti-repeat queue generation.
4. **Presentation Layer (`lib/ui/`)**:
   - Pure UI widgets, listening to reactive state through `ValueListenableBuilder` or `StreamBuilder`.
   - Never embed direct database writes or raw HTTP calls inside Flutter widget trees.

## 2. Background Audio Engine & Gapless Playback
- Use `just_audio` with `ConcatenatingAudioSource(useLazyPreparation: true)` to avoid buffering entire queues in memory.
- Synchronize track metadata atomically with `player.currentIndexStream` and `sequenceState.currentSource.tag` to prevent UI lag during song transitions.

## 3. 5-Minute Battery & Wakelock Guard (Critical SLA)
- To prevent battery drain when playback is paused or left idle:
  ```dart
  void handlePlaybackStateChange(PlaybackState state) {
    if (!state.playing) {
      _batteryTimer = Timer(const Duration(minutes: 5), () {
        AudioSession.instance.then((session) => session.setActive(false));
        stopForegroundService();
        closeIdleConnections();
      });
    } else {
      _batteryTimer?.cancel();
    }
  }
  ```

## 4. Offline Caching & Storage Hygiene
- Persist offline downloaded audio tracks to `getApplicationDocumentsDirectory()` with metadata recorded in Hive boxes.
- Enforce periodic cache pruning: evict temporary audio chunks older than 7 days or when total cache exceeds 400MB.

## 5. Synchronized LRC Lyrics
- Implement sub-second synchronized lyrics highlighting using `flutter_lyric`.
- Support user-adjustable millisecond offset sliders (range: -5000ms to +5000ms) with instant reactive rerendering.

## 6. Testing & Quality Verification
- Run Flutter test suite before every release commit:
  ```bash
  flutter test
  ```
- Ensure zero errors or unhandled asynchronous stream exceptions.
