# 🎵 Paatu Padava Mobile v2.4.0

Welcome to **Paatu Padava v2.4.0**! This major release delivers a massive search performance boost with persistent socket pooling, dynamic multi-resolution / DPI adaptation across all phone sizes, intelligent album extraction, and iOS 15+ readiness.

---

## ✨ Highlights & New Features

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

---

## 🐛 Bug Fixes & Improvements

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
| **`Paatu-Padava-v2.4.0-arm64-v8a.apk`** | 64-bit ARM (`arm64-v8a`) | **Recommended for ~95% of Android devices** (Android 8.0+). Smaller file size and optimized CPU performance. |
| **`Paatu-Padava-v2.4.0-universal.apk`** | Universal (All architectures) | Compatible with **all** Android devices, tablets, and emulators. |
| **`Paatu-Padava-v2.4.0-armeabi-v7a.apk`** | 32-bit ARM (`armeabi-v7a`) | For older 32-bit Android phones. |

> [!TIP]
> If you are unsure which file your phone uses, choose **`Paatu-Padava-v2.4.0-arm64-v8a.apk`**. If it fails to install, use the **`universal`** build.

---

## 🔐 Checksums & Verification

All release binaries are signed and provided with SHA-256 integrity hashes in `SHA256SUMS.txt`.

---

## ⚖️ Disclaimer

Paatu Padava is a free, non-commercial, open-source educational project licensed under MIT. It does not host, store, or distribute copyrighted music files. All media is retrieved client-side from public third-party endpoints. All copyrights and trademarks belong to their respective owners.
