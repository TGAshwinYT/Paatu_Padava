---
title: Paatu_Padava
emoji: 🎵
colorFrom: indigo
colorTo: purple
sdk: docker
pinned: false
---

# 🎵 Paatu Padava (பாட்டு பாடவா) — v2.2.0+3

[![Flutter](https://img.shields.io/badge/Flutter-v3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-SDK_36-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python_3.13-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Supabase](https://img.shields.io/badge/Supabase-Auth_%26_Cloud_DB-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![Firebase](https://img.shields.io/badge/Firebase-Core_%26_Analytics-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![Audius](https://img.shields.io/badge/Audius-Decentralized_Audio-CC1166?logo=audius&logoColor=white)](https://audius.co)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Build APK](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/build-apk.yml/badge.svg)](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/build-apk.yml)
[![Tests: 100% Green](https://img.shields.io/badge/Tests-323%20Flutter%20%7C%2036%20Backend%20Passing-brightgreen.svg)](#-engineering-metrics)

> **Your Infinite Music Universe** — Studio-quality 320kbps audio streaming, Adaptive Bitrate (ABR) streaming with buffer-stall dynamic downscale rescue, multi-format progressive fallback ($320 \to 160 \to 96$ kbps), remote InnerTube client version rotation, triple-engine hybrid audio resolution (JioSaavn CDN, YouTube Explode, Audius decentralized MP3), sub-200ms synced LRC lyrics via direct LRCLIB with auto-stretching, secure Spotify Developer playlist importer with server-side OAuth proxy, Spotify/Echo-Music-inspired 3-tier queue management (Now Playing, User Queue Priority Stack, Dynamic Up Next/Autoplay), continuous endless playback with battery wakelock guards, 50-track seed-based Song Radio discovery, 3-state Markov Smart Shuffle with feedback learning, real-time collaborative playlists, Android Auto dashboard media browsing, Google Firebase telemetry, Supabase cloud sync, redesigned Glassmorphic Sleep Timer, and 100% offline downloads.

---

## 🌟 Overview

**Paatu Padava** is a mobile-first, high-fidelity music streaming ecosystem tailored for Indian regional and international music lovers:

1. **Android Mobile App (`mobile/`)**: Native Flutter application built with Clean Architecture, background `AudioService`, gapless `ConcatenatingAudioSource`, 3-tier queue architecture modeled after Spotify and modern open-source players (Bloomee, Echo-Music), Adaptive Bitrate Streaming (ABR) with zero-loading buffer stall rescue, remote InnerTube client rotation, endless autoplay refill, Android Auto media hierarchy, real-time collaborative playlists, native Android AudioSession EQ, bidirectional Supabase playlist synchronization, direct LRCLIB synced lyrics with auto-stretching, Audius decentralized streaming, Google Firebase integration, 3-state smart shuffle with feedback learning, modern glassmorphic sleep timer, and advanced offline downloads.
2. **Backend Service (`backend-data-hf/`)**: FastAPI + Python 3.13 service providing 320kbps DES media decryption, item-item collaborative filtering recommendation graphs, secure Spotify OAuth token proxy, asynchronous SQLAlchemy with Greenlet, and sub-5ms prefix trie autocomplete.
3. **AI MCP Server (`mcp_server.py`)**: Model Context Protocol interface enabling AI assistants (Claude Desktop, Gemini CLI, Antigravity IDE) to search tracks, fetch recommendations, and construct smart shuffle queues.

---

## 🏛️ System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                 PRESENTATION LAYER (UI)                                 │
│  Home Feed  │  Fuzzy Search  │  Lyrics (Offset/Sync)  │  Queue Sheet  │  Recap Stories  │
│  Fluid Mesh Gradients  │  Swipeable Song Tiles  │  Storage Breakdown & Download Manager │
│  Glassmorphic Sleep Timer  │  Dynamic Bitrate Badge  │  Up Next Floating Bottom Bar     │
│  Modular Components: ui/widgets/{home, player, search, settings, library, lyrics, recap}│
└────────────────────────────────────────────┬────────────────────────────────────────────┘
                                             │ Binds via Streams / ValueNotifiers
┌────────────────────────────────────────────▼────────────────────────────────────────────┐
                                APPLICATION & DOMAIN LAYER                               │
 ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────┐ ┌──────────────┐ │
 │  AudioQueueHandler   │ │ SmartShuffleController│ │   SyncManager    │ │ RadioEngine  │ │
 │  (3-Tier Queue, Stall│ │ (3-State Markov,     │ │ (Bidirectional   │ │ (50-Track    │ │
 │   Rescue, Autoplay)  │ │  Feedback & Diversity│ │  Supabase Sync)  │ │  Song Radio) │ │
 └──────────────────────┘ └──────────────────────┘ └──────────────────┘ └──────────────┘ │
 ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────┐ ┌──────────────┐ │
 │ CollaborativeService │ │  AndroidAutoService  │ │ConnectivityService│ │ SleepTimer   │ │
 │ (Supabase Realtime)  │ │ (MediaBrowserService)│ │ (ABR & Latency)  │ │ (Countdown)  │ │
 └──────────────────────┘ └──────────────────────┘ └──────────────────┘ └──────────────┘ │
 ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────┐ ┌──────────────┐ │
 │ InnerTubeConfigServ  │ │  SaavnBitrateHelper  │ │  RecapService    │ │ Downloader   │ │
 │ (Remote JSON Clients)│ │ (Progressive Step-D) │ │  (Story Stats)   │ │ (Batch Task) │ │
 └──────────────────────┘ └──────────────────────┘ └──────────────────┘ └──────────────┘ │
└────────────────────────────────────────────┬────────────────────────────────────────────┘
                                             │ Queries / Commands
┌────────────────────────────────────────────▼────────────────────────────────────────────┐
│                                   DATA REPOSITORY LAYER                                 │
│  ┌──────────────────────┐ ┌──────────────────────────────────────────────────────────┐  │
│  │  UnifiedHttpClient   │ │                    SongRepository                        │  │
│  │  (Retries, Backoff)  │ │   (Multi-Source Aggregator, Deduplication, Script Prior) │  │
│  └──────────┬───────────┘ └────────────────────────────┬─────────────────────────────┘  │
└─────────────┼──────────────────────────────────────────┼────────────────────────────────┘
              │                                          │
    ┌─────────┴─────────┐                      ┌─────────┴─────────┐
    │                   │                      │                   │
┌───▼───────────┐ ┌─────▼────────┐        ┌────▼────────────┐ ┌────▼───────────┐
│ JioSaavn CDN  │ │ YouTube Ext. │        │ Supabase Cloud  │ │ Device Storage │
│ (Direct 320k, │ │ (InnerTube & │        │ (Auth, Realtime,│ │ (Hive, Scoped  │
│  160k, 96k)   │ │  YTExplode)  │        │  Postgres RLS)  │ │  Storage, LRU) │
└───┬───────────┘ └──────────────┘        └─────────────────┘ └────────────────┘
```

---

## ✨ Key Features & Capabilities (v2.2.0+3)

### 📶 Adaptive Bitrate (ABR) & Buffer-Stall Dynamic Rescue
- **Auto (Adaptive) Bitrate Mode**: Intelligently adjusts audio streaming bitrates to live network capabilities:
  - **Wi-Fi / Ethernet (< 250ms latency)**: Streams in uncompressed **320 kbps Studio Fidelity**.
  - **Cellular (4G/3G) / Moderate latency (250–400ms)**: Automatically streams at **160 kbps High Quality** (saving 50% data while retaining indistinguishable fidelity on mobile earphones).
  - **Weak Networks / High latency (> 400ms)**: Streams at **96 kbps Data Saver** to guarantee immediate start and zero stutter.
- **Buffer-Stall Dynamic Rescue (Zero-Loading Protection)**:
  - When network dips in an elevator, moving vehicle, or weak signal area, a stall watchdog monitors playback.
  - If ExoPlayer remains stalled in `buffering` for **> 3.5 seconds**, the app captures the exact current playback timestamp (`player.position`), seamlessly steps down the bitrate ($320 \to 160$ or $160 \to 96$), re-attaches the audio source with `initialPosition: currentPos`, and resumes playing immediately.
- **Dynamic Quality Badge**: The player header displays the actual live streaming quality badge (`320 KBPS`, `160 KBPS`, `96 KBPS`, `YOUTUBE`, `LOSSLESS`) next to the song title in real time.

---

### 🛡️ Progressive Bitrate Step-Down & Forced-320 Fix
- **Elimination of the Forced-320 Bug**: Older or regional JioSaavn songs often only exist on the CDN at 160kbps or 96kbps. The decrypted media URL preserves its genuine bitrate, eliminating HTTP 404 Not Found errors on Saavn CDNs.
- **Saavn Progressive Step-Down (`SaavnBitrateHelper`)**: If a 320kbps stream encounters an HTTP 403/404, it automatically cascades through candidate bitrates:
  $$\text{320 kbps} \longrightarrow \text{160 kbps} \longrightarrow \text{96 kbps} \longrightarrow \text{YouTube Fallback}$$
- **YouTube Stream Candidate Priority Chain**: Dual-tier extractor sorts candidate formats in strict order of playback reliability and hardware decoding efficiency:
  $$\text{itag 140 (128k AAC)} \longrightarrow \text{itag 251 (160k Opus)} \longrightarrow \text{itag 250 (70k Opus)} \longrightarrow \text{itag 249 (50k Opus)} \longrightarrow \text{Muxed 18/22}$$
  Every stream candidate is validated with a live non-blocking HTTP probe before being passed to ExoPlayer.

---

### 🔄 Remote InnerTube Client Version Rotation
- **Remote Configuration Engine (`InnerTubeConfigService`)**: Decouples YouTube client definitions from the compiled binary.
- **6 Built-in Client Fallbacks**: Automatically rotates across `IOS`, `IOS_UPDATED`, `ANDROID_VR`, `ANDROID`, `WEB_REMIX`, and `TVHTML5_SIMPLY_EMBEDDED_PLAYER`.
- **Dynamic Remote JSON Sync**: Automatically checks [innertube_clients.json](innertube_clients.json) via GitHub raw. If YouTube introduces cipher changes or client deprecations, new client versions can be deployed remotely without needing users to update their APK from the app store.

---

### 🛠️ ExoPlayer Diagnostic Status Capture & Clean Segregation
- **Underlying HTTP Code Extraction**: When ExoPlayer throws a generic `PlatformException(0, Source error)`, `diagnosePlaybackError` probes the target endpoint to surface real diagnostic codes (HTTP 403 Forbidden, HTTP 416 Range Not Satisfiable, CleartextNotPermitted, or SSLHandshakeException).
- **Strict Host-Based Header Segregation**: Headers are applied strictly based on `uri.host.contains('googlevideo.com')`. JioSaavn and other Akamai/Cloudflare CDNs receive `null` headers, preventing CDN rejections caused by spoofed Google headers.
- **Clean Native Byte-Range Requests**: Removed manual `&range=` query string parameter hacks; ExoPlayer natively requests byte ranges cleanly without HTTP 416 collisions.
- **Reset Retry Budget**: The retry flag (`_hasRetriedCurrentTrack = false`) resets cleanly on every track change, preventing subsequent songs from being locked out of error recovery.

---

### 🌙 Redesigned Glassmorphic Sleep Timer
- **Aesthetic Glassmorphic UI**: Frosted backdrop blur (`sigma: 30`) with an ambient indigo night rim (`#6366F1`) and curved modern sheet corners (`Radius.circular(32)`).
- **2-Column Preset Grid**: One-tap selection of popular sleep timer intervals:
  - ⚡ **15 Min** – Quick Power Nap
  - 🌙 **30 Min** – Recommended Standard
  - 🌌 **45 Min** – Deep Rest
  - ⏳ **1 Hour** – Full Album
  - 💤 **1.5 Hours** – Extended Session
  - 🎵 **End of Track** – Concludes after the current song finishes
- **Custom Duration Slider & Micro-Steppers**: Continuous slider (5 to 120 minutes) with tactile `-5m` and `+5m` stepper controls.
- **Glowing Circular Countdown Dial**: Animated circular progress ring with gradient sweep (`#818CF8` to `#C084FC`), bold tabular countdown numerals (`24:18`), and ambient pulsing moon icon.
- **Gentle 5-Second Fade-Out**: Detects when 5 seconds remain and initiates a smooth exponential volume fade-out.
- **Quick Extension Pills**: Fast one-tap `+5 min`, `+15 min`, and `+30 min` extension buttons.

---

### 🔀 3-Tier Queue & Continuous Autoplay Engine (Spotify & Echo-Music Architecture)
- **3-Tier Queue Model**:
  - **Now Playing**: Active track with instantaneous position and playback state synchronization.
  - **User Priority Queue Stack**: Tracks explicitly queued by the user via swipe gestures or context menu actions (*"Play Next"*, *"Add to Queue"*) are prioritized as an immutable user stack. Background recommendation algorithms will **never** displace, clobber, or alter user-queued songs.
  - **Dynamic Up Next / Context Tier**: Album, playlist, or recommendation context that naturally plays and replenishes in the background without disturbing user priority items.
- **Continuous Endless Autoplay Engine**:
  - Automatically activates when playback reaches the end of the queue (`ProcessingState.completed`).
  - Fetches 6 context-aware similar tracks via `NextTrackStrategy` and continues seamless playback without pausing or tearing down the media session.
  - Configurable toggle in *Settings > Audio & Playback Settings* (`SettingsManager.autoplayNotifier`).
- **Thread-Safe Dual-Ingestion Mutex Lock**:
  - Gated by `_isIngesting` mutex lock to prevent race conditions and duplicate track additions when tapping new songs while background auto-refill triggers.

---

### 📻 Dynamic Song Radio & Contextual Mixes
- **50-Track Seed Song Radio (`RadioEngine.buildSongRadio`)**: One-tap discovery modal available on Full Player Screen, Home Feed song cards, and Search option sheets. Constructs an expansive 50-track playlist balancing genre, tempo, artist affinity, and regional collaborative graphs.
- **Dynamic 10-Track Queue Injection (`addRadioMix`)**: Instantly injects 10 fresh, musically related tracks into the active session directly from the queue bottom sheet or full player.

---

### 🧠 3-State Markov Smart Shuffle & Feedback Learning
- **3-State Shuffle Control**: Effortlessly cycles across **Off** (dimmed), **Standard Shuffle** (indigo), and **Smart Shuffle** (emerald green badge) with direct `shuffleModeNotifier` bindings.
- **Strict Queue Isolation**: Mathematical Markov graph guarantees that only songs within the current target queue are reordered, eliminating rogue or foreign track injection.
- **Real-Time Feedback Learning**: Skips (< 30 seconds) apply negative recommendation weights, while full listens (> 30 seconds) strengthen artist and genre affinity weights.
- **Artist Diversity Cap**: Guarantees at most 1 song per artist within any 5 consecutive queue tracks.
- **Anti-Repeat Guards**: Comprehensive exclusion set checking active queue, recent playback history, and user favorites.

---

### 📱 Hardware Media Controls & OEM Background Reliability
- **Full MediaSession Compliance**: Explicitly registers `play`, `pause`, `stop`, `skipToNext`, and `skipToPrevious` in `playbackState.systemActions` so Android Auto, OEM lock screens (OnePlus OxygenOS, Xiaomi HyperOS, Samsung One UI), and Bluetooth headset buttons remain 100% responsive.
- **5-Minute Battery & Wakelock Guard**: Automatically deactivates `AudioSession`, closes idle network sockets, and tears down the foreground media notification when paused or idle for > 5 minutes to prevent battery drain.
- **Fatal Error Recovery**: Dedicated recovery UI allows one-tap audio engine restart in the rare event of an unrecoverable platform channel fault.

---

### 🔍 Multi-Source Hybrid Catalog & Smart Search Pipeline
- **Unified Domain Entity (`TrackEntity`)**: Canonical track entity with `deduplicationKey` and centralized `HtmlUnescape` string sanitization.
- **Multilingual Script & Language Detection**: Automatically detects native scripts (Tamil, Telugu, Hindi, Malayalam, Kannada, Bengali, Punjabi, Latin) and handles phonetic Tanglish searches.
- **Canonical Song Version Grouping**: Identifies and groups alternate versions (Remix, Lofi, Acoustic, Live, Film version) into a single canonical track entry with an expandable versions sheet.
- **Language Prior & Quality Re-Ranking**: Ranks JioSaavn 320kbps streams first with dynamic language prior boosting based on user preferences.
- **Artwork Fallback & Anti-Duplication**: Replaces generic compilation covers with verified artist portraits or high-resolution video thumbnails.
- **Categorized Error States**: Search distinguishes offline, timeout, server cold-start, and genuine empty results with actionable UI messages.

---

### 📜 Direct Synced LRC Lyrics Engine (LRCLIB & Auto-Stretching)
- **Direct Public LRCLIB Integration**: Queries `https://lrclib.net/api` directly from the mobile client for sub-200ms synced lyrics resolution.
- **Client-Side Line Auto-Stretching**: Dynamically stretches active line display durations during vocal pauses, instrumental solos, and preludes so the highlighted lyrics stay visible until the next vocal cue begins.
- **Precision Microsecond Offset Calibration**: Interactive calibration sheet allowing users to advance or delay lyrics timing (-5.0s to +5.0s), persisted per-track in local Hive storage.
- **Offline Synced Lyrics Cache**: Cached lyrics are saved locally for offline playback without network access.

---

### 🔐 Secure Spotify Importer & 4-Tier Zero-Auth Pipeline
- **Server-Side Token Proxy**: Mobile client fetches short-lived 1-hour Bearer tokens from backend proxy (`/api/music/spotify-token`). Sensitive developer secrets (`SPOTIFY_CLIENT_SECRET`) reside exclusively on the server and are never bundled into the APK binary.
- **Zero-Auth Direct Embed Scraper**: If official Spotify Web API access is restricted (e.g., Spotify's 2024 Developer 403 Premium policy), the importer automatically falls back to scraping `open.spotify.com/embed/...`, parsing `__NEXT_DATA__` JSON to extract tracks, artists, and artwork in ~200ms without requiring user credentials.
- **Multi-Tier Robustness**: Cascades through Tier 1 (Official Web API) $\rightarrow$ Tier 2 (Direct Embed JSON Scraper) $\rightarrow$ Tier 3 (oEmbed API) $\rightarrow$ Tier 4 (Jina Reader fallback).

---

### 🔥 Google Firebase Telemetry & Cloud Diagnostics
- **Cross-Platform Initialization**: Safe `Firebase.initializeApp` with `DefaultFirebaseOptions.currentPlatform` guarded for Android and cross-platform targets.
- **Diagnostic Logging**: Structured crash and lifecycle recording bridged to `AppLogger` for deterministic troubleshooting.
- **Android Gradle Services Integration**: Native `google-services.json` registration ensuring compatibility with Firebase Analytics and crash telemetry.

---

### 🎧 Audiophile Playback Engine & 5-Band Equalizer
- **Studio-Quality 320kbps Audio**: Direct decrypted JioSaavn CDN AAC streams paired with YouTube Music and Audius fallbacks.
- **Gapless Audio Engine (`AudioQueueHandler`)**: Preloads upcoming audio tracks in `ConcatenatingAudioSource(useLazyPreparation: true)` for seamless zero-gap transitions between songs.
- **Native 5-Band Equalizer**: Bound directly to `player.androidAudioSessionIdStream` with acoustic presets (Bass Boost, Vocal, Electronic, Rock, Flat) and customizable EQ curves.
- **Volume Normalization (ReplayGain / EBU R128)**: Calibrates hot studio masters to standard ~ -2.0 dB (0.80 volume factor) for consistent loudness across tracks.

---

### 👥 Real-Time Collaborative Playlists
- **Instant Invite Codes**: One-click generation of 6-character alphanumeric join codes (e.g. `PP-9K2M`).
- **Supabase Realtime Sync**: Collaborative playlists automatically listen to live PostgreSQL table changes via Supabase Realtime Channels for immediate updates across all collaborator devices.
- **Track Attribution**: `added_by` field tracks which collaborator added each song.

---

### 📊 Paatu Recap (Music Wrapped Experience)
- **5-Slide Story Experience**: Animated full-screen story mode with auto-advancing progress bars and touch hold-to-pause gestures.
- **Deep Listening Analytics**: Visualizes top 5 played tracks on a 3D-styled podium visualizer, top artists, and total listening minutes.
- **Listening Persona Archetypes**: Dynamically computes personalized listener personas (*"The Sonic Explorer"*, *"The Melodic Purist"*, *"The Night Owl"*, *"The Genre Hopper"*).

---

### 🚗 Android Auto Integration
- **Automotive Media Hierarchy (`MediaBrowserServiceCompat`)**: Full dashboard media browsing for Android Auto head units.
- **Structured Categories**: Browse categories include Recently Played, Cloud Playlists, Offline Downloads, and Daily Mixes.

---

### 💾 Advanced Storage & Offline Manager
- **Storage Telemetry**: Real-time breakdown of audio cache, downloaded tracks, app metadata, and free device storage space.
- **Batch Download Queue**: Concurrent batch downloading with live progress indicators and pause/resume/cancel controls.
- **Scoped Audio Cache Eviction**: Background cleaner targets only `just_audio_cache` directory — never wipes Flutter engine caches, shaders, or image caches.

---

### 🎨 Modern Visual Design System
- **Fluid Dynamic Mesh Gradients (`FluidMeshGradient`)**: Ambient background gradients dynamically extracted from album artwork.
- **Swipeable Song Action Tiles (`SwipeableSongTile`)**: Swipe gestures with haptic feedback for fast "Play Next" and "Add to Queue".
- **Interactive Player Sheet**: Bottom "Up Next" preview bar, embedded queue drawer, sleep timer indicator, and lyrics sheet.

---

## 📊 Engineering Metrics

| Dimension | Benchmark / SLA | Implementation Details |
|---|---|---|
| **Audio Bitrate** | **320 kbps Studio Fidelity** | Decrypted JioSaavn CDN direct AAC streams via DES cipher |
| **Adaptive Streaming (ABR)** | **Sub-Second Downscale** | Buffer stall rescue ($320 \to 160 \to 96$) at `initialPosition` if buffering > 3.5s |
| **Bitrate Fallback Chain** | **Zero HTTP 404s** | Progressive $320 \to 160 \to 96$ on Saavn; 140 $\to$ 251 $\to$ 250 $\to$ 249 $\to$ muxed 18/22 on YouTube |
| **Remote InnerTube Sync** | **Zero-App-Update Rotation** | `innertube_clients.json` remote raw GitHub sync with 6 client fallbacks |
| **Mobile Memory Footprint** | **Lazy Buffer Allocation** | `ConcatenatingAudioSource(useLazyPreparation: true)` |
| **Battery Life Protection** | **5-Minute Wakelock Guard** | Automatic `AudioSession.setActive(false)` and foreground service teardown |
| **Cloud Playlist Persistence** | **100% Device Independence** | Clean 6-table relational PostgreSQL schema with RLS |
| **Catalog Deduplication** | **Zero Redundant Tracks** | Normalized token keys (`${title}_${artist}`) across Saavn, YouTube & Audius |
| **Search Latency (p95)** | **< 300 ms** | Parallel `Future.wait` aggregation + language match re-ranking |
| **Collaborative Sync Latency** | **< 100 ms** | Supabase Realtime WebSocket subscription channels |
| **Flutter Test Suite** | **323 / 323 Tests Passing (100%)** | Comprehensive unit, widget, coordination, queue resilience, ABR, and sleep timer tests across 28 suites |
| **Backend Test Suite** | **36 / 36 Tests Passing (100%)** | API contracts, recommender graphs, security, trie autocomplete, and search tests |
| **Total Test Suite** | **359 / 359 Tests Passing (100%)** | End-to-end verification across mobile and backend |
| **Static Analysis** | **0 Errors, 0 Warnings** | Strictly enforced via `flutter analyze` |

---

## 🔒 Security

- **Zero Client Credential Exposure**: Spotify Developer Client Secret (`SPOTIFY_CLIENT_SECRET`) is confined exclusively to the backend `.env` environment; Flutter client requests short-lived 1-hour Bearer tokens via server proxy.
- **Firebase Key Isolation**: Client identifiers in `firebase_options.dart` and `google-services.json` are public Android app IDs protected by Firebase App Check and granular security rules.
- **No cleartext traffic**: `android:usesCleartextTraffic` disabled; all stream and media URLs forced to HTTPS.
- **No storage permissions**: Uses Android scoped storage (`getApplicationDocumentsDirectory()`).
- **Release signing**: Loaded from `key.properties` or environment variables, never committed.
- **ProGuard**: Minification and resource shrinking enabled for release builds.
- **JWT separation**: Backend uses `SUPABASE_JWT_SECRET` exclusively without fallback.

---

## 🗄️ Supabase Database Setup & RLS

Execute this complete migration script in the [Supabase SQL Editor](https://supabase.com/dashboard/project/_/sql) to set up the clean 6-table schema with strict Row Level Security (RLS), collaborative playlist support, and deduplication constraints:

```sql
-- =========================================================================
-- PAATU PADAVA - PRODUCTION DATABASE SCHEMA
-- =========================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Helper function to auto-update 'updated_at' column
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1. PROFILES (Linked directly to Supabase Auth users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT,
    email TEXT,
    avatar_url TEXT,
    preferred_languages TEXT[] DEFAULT ARRAY['Tamil', 'English'],
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

CREATE OR REPLACE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Auto-create profile trigger on auth signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, username)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1))
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. PLAYLISTS (Supports personal and collaborative playlists)
CREATE TABLE IF NOT EXISTS public.playlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    cover_url TEXT,
    is_public BOOLEAN DEFAULT false,
    is_collaborative BOOLEAN DEFAULT false,
    invite_code TEXT UNIQUE,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

CREATE OR REPLACE TRIGGER update_playlists_updated_at
    BEFORE UPDATE ON public.playlists
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 3. PLAYLIST_TRACKS (Ordered tracks inside playlists)
CREATE TABLE IF NOT EXISTS public.playlist_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES public.playlists(id) ON DELETE CASCADE,
    song_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    artwork_url TEXT,
    stream_url TEXT,
    duration_seconds INT DEFAULT 0,
    source TEXT DEFAULT 'saavn',
    added_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    position INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    UNIQUE(playlist_id, song_id)
);

-- 4. COLLABORATIVE_MEMBERS (Access controls for shared playlists)
CREATE TABLE IF NOT EXISTS public.collaborative_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES public.playlists(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'editor' CHECK (role IN ('editor', 'viewer')),
    joined_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    UNIQUE(playlist_id, user_id)
);

-- 5. FAVORITES (Liked songs per user)
CREATE TABLE IF NOT EXISTS public.favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    song_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    artwork_url TEXT,
    stream_url TEXT,
    duration_seconds INT DEFAULT 0,
    source TEXT DEFAULT 'saavn',
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    UNIQUE(user_id, song_id)
);

-- 6. LISTENING_HISTORY (Recent track scrobbles)
CREATE TABLE IF NOT EXISTS public.listening_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    song_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    artwork_url TEXT,
    duration_seconds INT DEFAULT 0,
    source TEXT DEFAULT 'saavn',
    played_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- =========================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =========================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.playlist_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collaborative_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listening_history ENABLE ROW LEVEL SECURITY;

-- Profiles: Anyone can view usernames, only owner can update
CREATE POLICY "Public profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Playlists: Owner has full access, collaborators can view/edit, public can view
CREATE POLICY "Users can view own playlists" ON public.playlists FOR SELECT 
    USING (auth.uid() = user_id OR is_public = true OR id IN (
        SELECT playlist_id FROM public.collaborative_members WHERE user_id = auth.uid()
    ));
CREATE POLICY "Users can insert own playlists" ON public.playlists FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own or collaborative playlists" ON public.playlists FOR UPDATE 
    USING (auth.uid() = user_id OR id IN (
        SELECT playlist_id FROM public.collaborative_members WHERE user_id = auth.uid() AND role = 'editor'
    ));
CREATE POLICY "Users can delete own playlists" ON public.playlists FOR DELETE USING (auth.uid() = user_id);

-- Playlist Tracks: Accessible by owner or collaborative editors
CREATE POLICY "View playlist tracks" ON public.playlist_tracks FOR SELECT 
    USING (playlist_id IN (
        SELECT id FROM public.playlists WHERE auth.uid() = user_id OR is_public = true OR id IN (
            SELECT playlist_id FROM public.collaborative_members WHERE user_id = auth.uid()
        )
    ));
CREATE POLICY "Modify playlist tracks" ON public.playlist_tracks FOR ALL 
    USING (playlist_id IN (
        SELECT id FROM public.playlists WHERE auth.uid() = user_id OR id IN (
            SELECT playlist_id FROM public.collaborative_members WHERE user_id = auth.uid() AND role = 'editor'
        )
    ));

-- Collaborative Members: Viewable by members, manageable by playlist owner
CREATE POLICY "View members" ON public.collaborative_members FOR SELECT 
    USING (playlist_id IN (SELECT id FROM public.playlists WHERE auth.uid() = user_id) OR user_id = auth.uid());
CREATE POLICY "Manage members" ON public.collaborative_members FOR ALL 
    USING (playlist_id IN (SELECT id FROM public.playlists WHERE auth.uid() = user_id));

-- Favorites: Strictly private to user
CREATE POLICY "Users manage own favorites" ON public.favorites FOR ALL USING (auth.uid() = user_id);

-- Listening History: Strictly private to user
CREATE POLICY "Users manage own history" ON public.listening_history FOR ALL USING (auth.uid() = user_id);
```

---

## 🚀 Getting Started & Local Development

### 1. Mobile Client (Flutter)

#### Prerequisites:
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (`>= 3.0.0 < 4.0.0`)
- [Android Studio](https://developer.android.com/studio) / Android SDK 36 (Java 17)

#### Setup & Run:
```bash
cd mobile

# Fetch dependencies
flutter pub get

# Run static analysis
flutter analyze

# Execute complete test suite (323 tests)
flutter test

# Run app on connected Android device/emulator
flutter run
```

---

### 2. Backend Service (FastAPI + Python 3.13)

#### Prerequisites:
- Python 3.13+
- Virtualenv

#### Setup & Run:
```bash
cd backend-data-hf

python -m venv venv
# Windows:
venv\Scripts\activate
# Linux/macOS:
source venv/bin/activate

pip install -r requirements.txt

# Run backend service
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

#### Run Backend Test Suite:
```bash
# Run backend test suite (36 tests)
python -m unittest discover -s tests
```

---

### 3. Model Context Protocol (MCP) Server Setup

To connect Paatu Padava to Claude Desktop, Gemini CLI, or Antigravity IDE, add this configuration to your `claude_desktop_config.json` or `mcp_config.json`:

```json
{
  "mcpServers": {
    "paatu-padava": {
      "command": "python",
      "args": ["path/to/Paatu_Padava/mcp_server.py"]
    }
  }
}
```

---

## 📂 Project Structure

```
Paatu_Padava/
├── mobile/                           # Native Flutter Android Application (v2.2.0+3)
│   ├── lib/
│   │   ├── core/                     # AppConfig (centralized backend URL, versioning)
│   │   ├── domain/models/            # TrackEntity, AppError, LyricsState
│   │   ├── data/repositories/        # SongRepository (Multi-source aggregation)
│   │   ├── logic/                    # AudioQueueHandler (3-tier queue, stall rescue, preloading),
│   │   │                             # SmartShuffleController (3-state Markov, feedback learning),
│   │   │                             # NextTrackStrategy (recommendation refills), HomeFeedProvider
│   │   ├── services/                 # ConnectivityService (ABR, latency & interface monitoring),
│   │   │                             # InnerTubeConfigService (remote & cached client configs),
│   │   │                             # SaavnBitrateHelper (progressive 320->160->96 step-down),
│   │   │                             # YouTubeClient (multi-itag priority fallback & probe),
│   │   │                             # SleepTimerService (countdown, volume fade-out),
│   │   │                             # SyncManager, RadioEngine, UnifiedHttpClient, DownloadManager,
│   │   │                             # EqualizerService, ErrorHandler, SpotifyImportService, AudiusClient
│   │   ├── ui/
│   │   │   ├── screens/              # HomeScreen, SearchScreen, FullPlayerScreen, LibraryScreen,
│   │   │   │                         # StorageSettingsScreen, ListeningRecapScreen, SettingsScreen,
│   │   │   │                         # AudioQualitySettingsScreen
│   │   │   └── widgets/              # Modular UI Component System:
│   │   │       ├── home/             # HomeSongCard, HomePlaylistCard, HomeQuickPicks
│   │   │       ├── player/           # SleepTimerSheet (glassmorphic countdown), QueueSheet,
│   │   │       │                     # PlayerScrubber, MusicVideoPlayerView, PlayerGestureDetector
│   │   │       ├── search/           # SearchSongOptionsSheet, SearchResultsList
│   │   │       ├── settings/         # AudioQualitySettingsCard, StorageSettingsCard
│   │   │       ├── library/          # Playlist cards, download lists
│   │   │       ├── lyrics/           # Synced lyrics rendering, offset pills
│   │   │       ├── recap/            # Story slides, persona badges
│   │   │       └── ...               # FluidMeshGradient, SwipeableSongTile, MiniPlayer
│   │   ├── firebase_options.dart     # Cross-platform Firebase initialization options
│   │   └── main.dart                 # App Entrypoint, Firebase Init, AudioService Init, Fatal Error Recovery
│   ├── assets/
│   │   └── innertube_clients.json    # Bundled fallback InnerTube client configurations
│   ├── test/                         # 323 Comprehensive Unit, Widget & Integration Tests (28 Suites)
│   ├── android/                      # Android Gradle project (Java 17, SDK 36, Automotive XML)
│   │   └── app/google-services.json  # Google Services Firebase Android configuration
│   └── firebase.json                 # Firebase project configuration
├── backend-data-hf/                  # FastAPI Python 3.13 Data Service
│   ├── services/                     # DES Decryption, Music Graph, Trie Autocomplete, Spotify Proxy & Scraper
│   ├── tests/                        # 36 Backend, Security & Recommender Test Suites
│   ├── requirements.txt              # FastAPI, SQLAlchemy[asyncio], Greenlet, Requests, Cryptography
│   └── .env                          # Server Secrets (SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, SUPABASE_JWT_SECRET)
├── innertube_clients.json            # Dynamic remote InnerTube client configurations
├── plans/                            # Architecture specs, migration scripts, summaries
├── .github/workflows/
│   └── build-apk.yml                 # Automated Release APK CI/CD pipeline
├── mcp_server.py                     # AI Model Context Protocol Server
└── README.md                         # Project documentation
```

---

## 📄 License

This project is open-source and licensed under the [MIT License](LICENSE).

---

Made with ❤️ by [Ashwin (TGAshwinYT)](https://github.com/TGAshwinYT)
