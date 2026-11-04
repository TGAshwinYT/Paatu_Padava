# 🎵 Paatu Padava Mobile — Release Notes

Welcome to the comprehensive release notes for **Paatu Padava Mobile**. This document tracks all features, performance improvements, and fixes across recent builds.

---

## 🚀 v2.5.0 (Latest Release)

This milestone release introduces **Search Result Single-Track Isolation**, a major **Queue Management Overhaul** (swipe-to-dismiss & "Save Queue as Playlist"), and an **Android Doze-Proof Wall-Clock Sleep Timer Engine**.

### ✨ Highlights & New Features (v2.5.0)

#### 🔍 Search Result Single-Track Isolation & Seamless Autoplay
* **Single-Track Playback Isolation**:
  * Tapping a song in search results now isolates playback to that chosen track alone (`preserveUserQueue: true`), eliminating the issue where 30 unrelated search results were dumped into the active queue.
  * Preserves any tracks previously queued by the user (*"Play Next"*, *"Add to Queue"*).
  * Seamlessly transitions to context-aware `RadioEngine` autoplay when the search track finishes.
* **Instant Typeahead & Zero-Latency SWR Cache**:
  * Optimized search debounce to **180 ms** for instantaneous keystroke suggestions.
  * In-memory SWR (Stale-While-Revalidate) pre-warming: hitting Enter displays confirmed search results in **0 ms**.
  * Decoupled parallel soundtrack & album extraction, eliminating blocking delays on short queries (e.g., *"Hi"*, *"Vikram"*).

#### 📑 Advanced Queue Architecture & Playlist Persistence
* **Swipe-to-Dismiss Queue Tracks**:
  * Added horizontal swipe gestures (`DismissDirection.endToStart`) on both user-queued and suggested queue tracks in the Queue Sheet.
  * Displays a smooth red trash indicator and triggers tactile haptic feedback on dismissal.
* **Save Queue as Playlist (`SaveQueueDialog`)**:
  * Direct one-tap "Save Queue as Playlist" icon (`Icons.bookmark_add_rounded`) in the Queue Sheet header.
  * Allows listeners to instantly snapshot active and upcoming queue tracks into a custom playlist.
  * Automatically persists to local device storage (Hive) and synchronizes to cloud storage (Supabase).
* **Two-Tier Immutable User Stack**:
  * Clear separation between User Priority Queue and Dynamic Autoplay / Radio Suggestions.
  * Smart Shuffle and Markov-Cosine algorithms reorder context tracks without clobbering user-prioritized songs.

#### 🌙 Wall-Clock Sleep Timer Engine (Android Doze-Proof)
* **Wall-Clock Target Epoch Architecture**:
  * Replaced naive 1-second countdown ticks with absolute wall-clock target calculations (`_targetEndTime = DateTime.now().add(duration)`).
  * Solved the issue where Android Doze mode and background CPU throttling paused Dart timers, preventing music from turning off when the phone was locked.
* **Audio Stream Expiration Watchdog**:
  * The ExoPlayer position stream evaluates `SleepTimerService.hasExpired` on every position tick.
  * Playback halts immediately at the scheduled second, cleanly surrendering foreground notifications and audio wake locks.
* **Gapless End-of-Track Boundary Interception**:
  * Fixed "End of Track" sleep stopping inside `AudioQueueHandler`.
  * Intercepts `just_audio` gapless track transitions (`ConcatenatingAudioSource`) to halt playback precisely at the song boundary without leaking into the next track.
* **New "End of Queue" Sleep Preset**:
  * Added a dedicated **End of Queue** option (`Icons.queue_music_rounded`) in `SleepTimerSheet`.
  * Allows the active queue to finish playing and cleanly stops playback before background Autoplay radio can trigger.
* **Public `triggerSleepNow()`**:
  * Immediate teardown of the audio pipeline, releasing wake locks and pausing the player instantly.

### 🐛 Bug Fixes & Stability Improvements (v2.5.0)

* **Search Engine**:
  * Prevented search race conditions where in-flight requests from cleared queries could overwrite active screens.
  * Added 15-minute TTL to in-memory search cache while blocking caching of degraded or empty network responses.
* **Audio Pipeline**:
  * Fixed consecutive track skipping bugs on stream errors with automatic progressive bitrate step-down (320k ➔ 160k ➔ 96k ➔ YouTube Fallback).
  * Cleaned up UI parameter artifacts in `SleepTimerSheet`.
  * Maintained volume normalization across provider switches between JioSaavn and YouTube Music.

---

## 📦 v2.4.0 (Cumulative Updates)

*Note: As v2.4.0 was held back for the combined Android and iOS release, all v2.4.0 features and enhancements are fully included in the v2.5.0 build below:*

### ✨ Highlights & Features (v2.4.0)

* **🚀 3x Search Speed Boost & Connection Pooling**:
  * **Persistent HTTP Keep-Alive Pooling**: Switched all upstream JioSaavn calls to a shared Keep-Alive socket pool, eliminating 150–250 ms cold TLS handshakes on every query.
  * **180 ms Responsive Debounce**: Shaved 120 ms off typing wait times for snappy, instant autocomplete.
  * **Decoupled Progressive Autocomplete**: Matching songs and albums (e.g., *"Hi"* by Jen Martin) stream and render immediately in ~100 ms without blocking on slower YouTube completions.
  * **Zero-Latency SWR Pre-Warming**: Queries are pre-warmed into memory during typing pauses; hitting Enter renders the search results page in **0 ms**.

* **📱 Dynamic Screen Resolution & DPI Engine (`AppDimensions`)**:
  * **Adaptive Viewport Breakpoints**: Automatically tailors padding, card widths, and tile heights across Compact (<360 dp), Standard (360–600 dp), and Tablet (≥600 dp) devices.
  * **Global Safe Text Scaling Gate**: Clamps system accessibility font scaling safely between 0.85x and 1.30x in `MaterialApp.builder`, preventing `RenderFlex` overflow stripes on devices with large system fonts while preserving readability.
  * **Flexible Full-Player Artwork**: Player artwork dynamically adapts (180 dp to 340 dp) based on available vertical space, eliminating bottom overflow on short screens (360x640 dp).
  * **Text-Scale Aware Carousels**: Home feed carousels calculate dynamic heights based on active typography metrics, preventing title/artist label clipping.

* **🎬 Global Album & Soundtrack Extraction**:
  * Solved missing album listings for movie OSTs: automatically synthesizes clean movie albums from single releases with `(From "Movie")` metadata.
  * Automated playlist generation: generates contextual playlists directly from search results when provider playlist endpoints return empty sets.

* **🌐 Multi-Language Parity & Regional Priority**:
  * Solved language flooding on Pan-Indian films (e.g., a Tamil user searching *"Hi Nanna"* receives the Tamil soundtrack prioritized over Telugu versions).
  * Preserved studio capitalization on artist names and album tags.

* **🍏 iOS 15+ Compatibility & Offline Container Migration**:
  * Aligned Podfile and Runner project deployment targets to iOS 15.0, resolving CocoaPods deployment warnings on modern Xcode 15/16.
  * Sandbox Container Migration: offline downloaded songs dynamically resolve relative file paths, surviving iOS container UUID reallocations across TestFlight and App Store updates.

* **📻 Smart Shuffle & Zero Back-to-Back Guarantees**:
  * Upgraded next-track selection engine with Poisson-spaced artist dispersion: eliminates repetitive tracks from the same artist in succession.
  * Contextual session-aware radio with composer recognition and release year proximity (±4 years).

* **🔄 Resilient Stream Engine & Failover**:
  * Instant two-way failover across JioSaavn 320 kbps, YouTube Music, and Audius. If any CDN stream expires or returns HTTP 403, the player automatically re-resolves and continues playback without interruption.
  * Configurable persistent background playback with lifecycle resilience for task-removed and notification-deleted states.

### 🐛 Bug Fixes & Improvements (v2.4.0)

* **Search Engine**:
  * Fixed search result state race conditions so in-flight requests from cleared queries never overwrite the active view.
  * Enclosed all flow control statements in curly braces for zero analyzer warnings.
  * Removed redundant null comparisons across search and tile widgets.
  * Added 15-minute TTL to in-memory search cache and blocked caching degraded or empty network responses.

* **Audio & Queue**:
  * Fixed consecutive track skipping bugs on stream errors.
  * Retained volume normalization across provider switches between JioSaavn and YouTube.
  * Fixed Android Auto `MediaBrowserService` categories (Liked, Recent, Playlists) for car head units.

---

## 📱 Which APK Should I Download?

| Package File | Target Architecture | Recommendation |
|:---|:---|:---|
| **`Paatu-Padava-v2.5.0-arm64-v8a.apk`** | 64-bit ARM (`arm64-v8a`) | **Recommended for ~95% of Android devices** (Android 8.0+). Smaller file size and optimized CPU performance. |
| **`Paatu-Padava-v2.5.0-universal.apk`** | Universal (All architectures) | Compatible with **all** Android devices, tablets, and emulators. |
| **`Paatu-Padava-v2.5.0-armeabi-v7a.apk`** | 32-bit ARM (`armeabi-v7a`) | For older 32-bit Android phones. |

> [!TIP]
> If you are unsure which file your phone uses, choose **`Paatu-Padava-v2.5.0-arm64-v8a.apk`**. If it fails to install, use the **`universal`** build.

---

## 🔐 Checksums & Verification

All release binaries are signed and provided with SHA-256 integrity hashes in `SHA256SUMS.txt`.

---

## ⚖️ Disclaimer

Paatu Padava is a free, non-commercial, open-source educational project licensed under MIT. It does not host, store, or distribute copyrighted music files. All media is retrieved client-side from public third-party endpoints. All copyrights and trademarks belong to their respective owners.
