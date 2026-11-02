# 🎵 Paatu Padava Mobile v2.4.0

Welcome to **Paatu Padava v2.4.0**! This major release brings a high-performance search engine revamp, seamless background audio stability, smart artist dispersion, and multi-language parity.

---

## ✨ Highlights & New Features

* **🧠 Intelligent Autocomplete & Typing Flow**:
  * Typing suggestions now remain completely stable while typing — 450 ms typing pauses will no longer unexpectedly flip the view away from autocomplete suggestions to full catalog tabs.
  * Instant Prefix Trie lookup ($< 1\text{ ms}$) paired with bounded $O(1)$ dictionary lookups for instant typing feedback.
  * Real-time history & favorites indexing: newly played and liked songs are immediately indexed into typing suggestions without requiring an app restart.

* **📻 Smart Shuffle & Zero Back-to-Back Guarantees**:
  * Upgraded next-track selection engine with Poisson-spaced artist dispersion: eliminates repetitive songs from the same artist in succession.
  * Contextual session-aware radio with composer recognition and release year proximity (±4 years).

* **🔄 Resilient Stream Engine & Failover**:
  * Instant two-way failover across JioSaavn 320 kbps, YouTube Music, and Audius. If any CDN stream expires or returns HTTP 403, the player automatically re-resolves and continues playback without interruption.
  * Configurable persistent background playback with lifecycle resilience for task-removed and notification-deleted states.

* **🌐 Multi-Language Parity**:
  * Fixed language-word stripping for compound movie titles like *"English Vinglish"* and *"Hindi Medium"*.
  * Automatic unconstrained fallback when restrictive language filters yield zero matches.
  * Support for Urdu tracks without false Arabic-script rejection.

---

## 🐛 Bug Fixes & Improvements

* **Search Engine**:
  * Eliminated double-search execution on rapid submit or chip taps by cancelling active debounce timers.
  * Fixed search result state race conditions so in-flight requests from cleared queries never overwrite the active view.
  * Corrected YouTube playlist ID detection regex (`PL`, `UU`, `LL`, `RD`) so normal typed words like *"Play"* or *"Planet"* are not mistaken for YouTube playlist URLs.
  * Preserved full versions sheet and unified multi-provider rankings without screen-level destructive re-sorting.
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
