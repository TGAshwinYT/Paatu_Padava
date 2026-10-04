---
title: Paatu_Padava
emoji: 🎵
colorFrom: indigo
colorTo: purple
sdk: docker
pinned: false
---

# 🎵 Paatu Padava (பாட்டு பாடவா) — v2.0.0

[![Flutter](https://img.shields.io/badge/Flutter-v3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-SDK_36-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python_3.13-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Supabase](https://img.shields.io/badge/Supabase-Auth_%26_Cloud_DB-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Build APK](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/build-apk.yml/badge.svg)](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/build-apk.yml)
[![Tests: 100% Green](https://img.shields.io/badge/Tests-110%20Flutter%20%7C%2032%20Backend%20Passing-brightgreen.svg)](#-engineering-metrics)

> **Your Infinite Music Universe** — Studio-quality 320kbps audio streaming, dual-engine hybrid audio resolution, Clean Architecture domain pipelines, real-time collaborative playlists, Android Auto dashboard media browsing, seed-based Song Radio discovery, smart shuffle with playback feedback, gapless playback with 5-minute battery wakelock guards, Supabase cloud sync, and 100% offline playback.

---

## 🌟 Overview

**Paatu Padava** is a mobile-first music streaming app tailored for Indian regional and international music lovers:

1. **Android Mobile App (`mobile/`)**: Native Flutter application built with Clean Architecture, background `AudioService`, gapless `ConcatenatingAudioSource`, Android Auto media hierarchy, real-time collaborative playlists, native Android AudioSession EQ, bidirectional Supabase playlist synchronization, smart shuffle with feedback learning, and advanced offline downloads.
2. **Backend Service (`backend-data-hf/`)**: FastAPI + Python 3.13 service providing 320kbps DES media decryption, item-item collaborative filtering recommendation graphs, and sub-5ms prefix trie autocomplete.
3. **AI MCP Server (`mcp_server.py`)**: Model Context Protocol interface enabling AI assistants (Claude Desktop, Gemini CLI, Antigravity IDE) to search tracks, fetch recommendations, and construct smart shuffle queues.

---

## 🏛️ System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                 PRESENTATION LAYER (UI)                                 │
│  Home Feed  │  Fuzzy Search  │  Lyrics (Offset/Sync)  │  Queue Sheet  │  Recap Stories  │
│  Fluid Mesh Gradients  │  Swipeable Song Tiles  │  Storage Breakdown & Download Manager │
└────────────────────────────────────────────┬────────────────────────────────────────────┘
                                             │ Binds via Streams / ValueNotifiers
┌────────────────────────────────────────────▼────────────────────────────────────────────┐
│                                APPLICATION & DOMAIN LAYER                               │
│ ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────┐ ┌──────────────┐ │
│ │  AudioQueueHandler   │ │ SmartShuffleController│ │   SyncManager    │ │ RadioEngine  │ │
│ │  (ConcatenatingSource│ │ (Feedback Learning,  │ │ (Bidirectional   │ │ (Graph-based │ │
│ │   & Lazy Preloader)  │ │  Artist Diversity)   │ │  Supabase Sync)  │ │  Discovery)  │ │
│ └──────────────────────┘ └──────────────────────┘ └──────────────────┘ └──────────────┘ │
│ ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────┐ ┌──────────────┐ │
│ │ CollaborativeService │ │  AndroidAutoService  │ │ConnectivityService│ │ RecapService │ │
│ │ (Supabase Realtime)  │ │ (MediaBrowserService)│ │ (Offline Banner) │ │ (Story Stats)│ │
│ └──────────────────────┘ └──────────────────────┘ └──────────────────┘ └──────────────┘ │
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
│ (Direct 320k) │ │ (Innertube)  │        │ (Auth, Realtime,│ │ (Hive, Scoped  │
│               │ │              │        │  Postgres RLS)  │ │  Storage, LRU) │
└───────────────┘ └──────────────┘        └─────────────────┘ └────────────────┘
```

---

## ✨ Key Features & Capabilities

### 🔍 Multi-Source Hybrid Catalog & Smart Search Pipeline
- **Unified Domain Entity (`TrackEntity`)**: Canonical track entity with `deduplicationKey` and centralized `HtmlUnescape` string sanitization.
- **Multilingual Script & Language Detection**: Automatically detects native scripts (Tamil, Telugu, Hindi, Malayalam, Kannada, Bengali, Punjabi, Latin) and handles phonetic Tanglish searches.
- **Canonical Song Version Grouping**: Identifies and groups alternate versions (Remix, Lofi, Acoustic, Live, Film version) into a single canonical track entry with an expandable versions sheet.
- **Language Prior & Quality Re-Ranking**: Ranks JioSaavn 320kbps streams first with dynamic language prior boosting based on user preferences.
- **Artwork Fallback & Anti-Duplication**: Replaces generic compilation covers with verified artist portraits or high-resolution video thumbnails.
- **Categorized Error States**: Search distinguishes offline, timeout, server cold-start, and genuine empty results with actionable UI messages.

### 🎧 Audiophile Playback Engine
- **Studio-Quality 320kbps Audio**: Direct decrypted JioSaavn CDN AAC streams paired with YouTube Music fallback.
- **Gapless Audio Engine (`AudioQueueHandler`)**: Preloads upcoming audio tracks in `ConcatenatingAudioSource(useLazyPreparation: true)` for seamless zero-gap transitions between songs.
- **5-Minute Battery & Wakelock Guard**: When playback is paused or idle for > 5 minutes, automatically deactivates `AudioSession`, closes idle network sockets, and tears down the foreground media notification to preserve battery life.
- **Native 5-Band Equalizer**: Bound directly to `player.androidAudioSessionIdStream` with acoustic presets (Bass Boost, Vocal, Electronic, Rock, Flat).
- **Fatal Error Recovery**: If the audio engine fails to initialize, a dedicated error screen with restart capability is shown instead of a crash.
- **HTTPS Enforcement**: All stream URLs auto-upgraded to HTTPS for security.

### 🧠 Smart Shuffle & Feedback Learning
- **Playback Feedback Loop**: `SmartShuffleController.recordPlaybackFeedback` wired into skip, queue-item jump, and natural track completion — skips (< 30s) are negative, full listens are positive.
- **Artist Diversity Cap**: Enforces at most 1 song per artist in any 5 consecutive tracks.
- **Anti-Repeat Guards**: Comprehensive exclusion set across current queue, recent history, and favorites.

### 👥 Real-Time Collaborative Playlists
- **Instant Invite Codes**: One-click generation of 6-character alphanumeric join codes (e.g. `PP-9K2M`).
- **Supabase Realtime Sync**: Collaborative playlists automatically listen to live PostgreSQL table changes via Supabase Realtime Channels for immediate updates across all collaborator devices.
- **Track Attribution**: `added_by` field tracks which collaborator added each song.

### 📊 Paatu Recap (Music Wrapped Experience)
- **5-Slide Story Experience**: Animated full-screen story mode with auto-advancing progress bars and touch hold-to-pause gestures.
- **Deep Listening Analytics**: Visualizes top 5 played tracks on a 3D-styled podium visualizer, top artists, and total listening minutes.
- **Listening Persona Archetypes**: Dynamically computes personalized listener personas (*"The Sonic Explorer"*, *"The Melodic Purist"*, *"The Night Owl"*, *"The Genre Hopper"*).

### 📻 Song Radio & Infinite Discovery Engine
- **Seed-Based Radio (`RadioEngine`)**: Generates an infinite dynamic queue from any seed song by combining item-item collaborative filtering, artist top hits, contextual recommendations, and regional trending tracks.

### 🚗 Android Auto Integration
- **Automotive Media Hierarchy (`MediaBrowserServiceCompat`)**: Full dashboard media browsing for Android Auto head units.
- **Structured Categories**: Browse categories include Recently Played, Cloud Playlists, Offline Downloads, and Daily Mixes.

### 🌐 Connection Resilience
- **Centralized Backend URL**: `AppConfig.backendUrl` via `String.fromEnvironment` for easy environment switching.
- **Connectivity Detection**: Background reachability polling with offline banner that taps to Library/Downloads.
- **Unified HTTP Client**: 10s timeout, exponential backoff retries on 502/503/network errors with categorized error resolution.

### 💾 Advanced Storage & Offline Manager
- **Storage Telemetry**: Real-time breakdown of audio cache, downloaded tracks, app metadata, and free device storage space.
- **Batch Download Queue**: Concurrent batch downloading with live progress indicators and pause/resume/cancel controls.
- **Scoped Audio Cache Eviction**: Background cleaner targets only `just_audio_cache` directory — never wipes Flutter engine caches, shaders, or image caches. Runs after Hive initialization to access settings.

### 🎨 Modern Visual Design System
- **Fluid Dynamic Mesh Gradients (`FluidMeshGradient`)**: Ambient background gradients extracted from album artwork.
- **Swipeable Song Action Tiles (`SwipeableSongTile`)**: Spotify-style swipe gestures with haptic feedback.

### ⚡ Backend & ML Services (FastAPI + Python 3.13)
- **JioSaavn 320kbps Decryption**: Real-time DES cipher decoding for direct high-bitrate AAC media links.
- **Co-Occurrence Music Graph**: Seed-based infinite radio queue balancing genre, tempo, and artist collaborative filtering.
- **Prefix Trie Autocomplete**: Ultra-fast, sub-5ms search suggestions.

### 🤖 Model Context Protocol (MCP Server)
- Exposes 5 production tools (`search_music`, `get_song_recommendations`, `get_smart_shuffle_order`, `get_trending_music`, `get_regional_languages`) for integration with Claude Desktop, Gemini CLI, and Antigravity IDE.

---

## 📊 Engineering Metrics

| Dimension | Benchmark / SLA | Implementation Details |
|---|---|---|
| **Audio Bitrate** | **320 kbps Studio Fidelity** | Decrypted JioSaavn CDN direct AAC streams via DES cipher |
| **Mobile Memory Footprint** | **Lazy Buffer Allocation** | `ConcatenatingAudioSource(useLazyPreparation: true)` |
| **Battery Life Protection** | **5-Minute Wakelock Guard** | Automatic `AudioSession.setActive(false)` and foreground service teardown |
| **Cloud Playlist Persistence** | **100% Device Independence** | Clean 6-table relational PostgreSQL schema with RLS |
| **Catalog Deduplication** | **Zero Redundant Tracks** | Normalized token keys (`${title}_${artist}`) across Saavn & YouTube |
| **Search Latency (p95)** | **< 300 ms** | Parallel `Future.wait` aggregation + language match re-ranking |
| **Collaborative Sync Latency** | **< 100 ms** | Supabase Realtime WebSocket subscription channels |
| **Flutter Test Suite** | **110 / 110 Tests Passing (100%)** | Unit, widget, coordination, queue alignment, and gesture tests |
| **Backend Test Suite** | **32 / 32 Tests Passing (100%)** | API contracts, recommender graphs, security, and search tests |
| **Static Analysis** | **0 Errors, 0 Warnings** | Strictly enforced via `flutter analyze` |

---

## 🔒 Security

- **No cleartext traffic**: `android:usesCleartextTraffic` removed; all stream URLs forced to HTTPS.
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

-- 2. PLAYLISTS (With User-Title Uniqueness and Collaboration Support)
CREATE TABLE IF NOT EXISTS public.playlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    cover_url TEXT DEFAULT '',
    external_id TEXT DEFAULT NULL,
    is_public BOOLEAN DEFAULT FALSE,
    is_collaborative BOOLEAN DEFAULT FALSE,
    invite_code TEXT DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),

    -- CONSTRAINT: Permanently prevents duplicate playlists with the same title for a user
    CONSTRAINT uq_user_playlist_title UNIQUE (user_id, title)
);

CREATE INDEX IF NOT EXISTS idx_playlists_user_id ON public.playlists(user_id);
CREATE INDEX IF NOT EXISTS idx_playlists_invite_code ON public.playlists(invite_code) WHERE invite_code IS NOT NULL;

CREATE OR REPLACE TRIGGER update_playlists_updated_at
    BEFORE UPDATE ON public.playlists
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 3. PLAYLIST TRACKS (With collaborator attribution)
CREATE TABLE IF NOT EXISTS public.playlist_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    playlist_id UUID NOT NULL REFERENCES public.playlists(id) ON DELETE CASCADE,
    track_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT DEFAULT '',
    artwork_url TEXT DEFAULT '',
    stream_url TEXT DEFAULT '',
    source_type TEXT DEFAULT 'saavn',
    duration INTEGER DEFAULT 0,
    position INTEGER DEFAULT 0,
    added_by TEXT DEFAULT NULL,
    added_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),

    -- CONSTRAINT: Prevents duplicate tracks inside a playlist
    CONSTRAINT uq_playlist_track UNIQUE (playlist_id, track_id)
);

CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id ON public.playlist_tracks(playlist_id);
CREATE INDEX IF NOT EXISTS idx_playlist_tracks_ordering ON public.playlist_tracks(playlist_id, position ASC);

-- 4. LIKED SONGS (User Favorites)
CREATE TABLE IF NOT EXISTS public.liked_songs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    track_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT DEFAULT '',
    cover_url TEXT DEFAULT '',
    audio_url TEXT DEFAULT '',
    source_type TEXT DEFAULT 'saavn',
    duration INTEGER DEFAULT 0,
    language TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),

    -- CONSTRAINT: One like per track per user
    CONSTRAINT uq_user_liked_track UNIQUE (user_id, track_id)
);

CREATE INDEX IF NOT EXISTS idx_liked_songs_user_id ON public.liked_songs(user_id);
CREATE INDEX IF NOT EXISTS idx_liked_songs_created ON public.liked_songs(user_id, created_at DESC);

-- 5. USER HISTORY (Streaming History)
CREATE TABLE IF NOT EXISTS public.user_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    song_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    cover_url TEXT DEFAULT '',
    source TEXT DEFAULT 'saavn',
    duration INTEGER DEFAULT 0,
    played_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_user_history_user_played ON public.user_history(user_id, played_at DESC);

-- 6. USER FAVORITE ARTISTS (Onboarding & Followed Artists)
CREATE TABLE IF NOT EXISTS public.user_favorite_artists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    artist_name TEXT NOT NULL,
    artist_image_url TEXT DEFAULT '',
    followed_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),

    -- CONSTRAINT: Artist followed only once per user
    CONSTRAINT uq_user_artist UNIQUE (user_id, artist_name)
);

CREATE INDEX IF NOT EXISTS idx_user_favorite_artists ON public.user_favorite_artists(user_id);

-- =========================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =========================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.playlist_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.liked_songs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_favorite_artists ENABLE ROW LEVEL SECURITY;

-- Profiles: Users view/update own profile
CREATE POLICY "Users view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Playlists: Own or collaborative or public playlists
CREATE POLICY "Users view accessible playlists" ON public.playlists
    FOR SELECT USING (auth.uid() = user_id OR is_public = TRUE OR is_collaborative = TRUE);
CREATE POLICY "Users insert own playlists" ON public.playlists
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own playlists" ON public.playlists
    FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users delete own playlists" ON public.playlists
    FOR DELETE USING (auth.uid() = user_id);

-- Playlist Tracks: Accessible if parent playlist is accessible
CREATE POLICY "Users view playlist tracks" ON public.playlist_tracks
    FOR SELECT USING (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid() OR is_public = TRUE OR is_collaborative = TRUE)
    );
CREATE POLICY "Users insert playlist tracks" ON public.playlist_tracks
    FOR INSERT WITH CHECK (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid() OR is_collaborative = TRUE)
    );
CREATE POLICY "Users delete playlist tracks" ON public.playlist_tracks
    FOR DELETE USING (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid() OR is_collaborative = TRUE)
    );
CREATE POLICY "Users update playlist tracks" ON public.playlist_tracks
    FOR UPDATE USING (
        playlist_id IN (SELECT id FROM public.playlists WHERE user_id = auth.uid() OR is_collaborative = TRUE)
    );

-- Liked Songs: Isolated to owner
CREATE POLICY "Users manage liked songs" ON public.liked_songs FOR ALL USING (auth.uid() = user_id);

-- User History: Isolated to owner
CREATE POLICY "Users manage user history" ON public.user_history FOR ALL USING (auth.uid() = user_id);

-- Favorite Artists: Isolated to owner
CREATE POLICY "Users manage favorite artists" ON public.user_favorite_artists FOR ALL USING (auth.uid() = user_id);

-- Enable Realtime publication for multi-device sync
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'playlists'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.playlists;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'playlist_tracks'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.playlist_tracks;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'liked_songs'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.liked_songs;
    END IF;
END $$;
```

> **Note:** The schema above already includes collaborative playlist columns (`is_collaborative`, `invite_code`, `added_by`). The separate `plans/MIGRATION_COLLABORATIVE_PLAYLISTS.sql` file is only needed if your Supabase DB was set up from an older version of this schema that didn't have those columns.

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: 3.22+ (Channel `stable`)
- **Android SDK**: API level 21 to 36 (Java 17)
- **Python**: v3.11 or higher

---

### 1. Build & Run Android Mobile App

```bash
cd mobile

# Fetch dependencies
flutter pub get

# Analyze code (verifies 0 errors, 0 warnings)
flutter analyze

# Run unit and widget test suite (110 tests)
flutter test

# Run on connected Android device / emulator
flutter run

# Build production release APK (requires key.properties — see key.properties.example)
flutter build apk --release
```

> **APK Output Path**: `mobile/build/app/outputs/flutter-apk/app-release.apk`

#### Release Signing Setup:
1. Copy `mobile/android/key.properties.example` to `mobile/android/key.properties`
2. Fill in `storeFile`, `storePassword`, `keyAlias`, `keyPassword`
3. **Never commit `key.properties`** — it's gitignored

#### APK Signature Conflict Fix:
If you encounter `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, uninstall the previous version:
```bash
adb uninstall com.tamilgaming.paatupadava
```

---

### 2. Run Backend

```bash
cd backend-data-hf
python -m venv .venv
source .venv/bin/activate  # Or .venv\Scripts\activate on Windows
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

#### Run Backend Test Suite:
```bash
python -m unittest discover -s backend-data-hf/tests
```

---

### 3. Model Context Protocol (MCP) Server Setup

To connect Paatu Padava to Claude Desktop or Antigravity IDE, add this configuration to your `claude_desktop_config.json` or `mcp_config.json`:

```json
{
  "mcpServers": {
    "paatu-padava": {
      "command": "python",
      "args": ["path/to/Paatu_Paaduva/mcp_server.py"]
    }
  }
}
```

---

## 📂 Project Structure

```
Paatu_Paaduva/
├── mobile/                           # Native Flutter Android Application (v2.0.0)
│   ├── lib/
│   │   ├── core/                     # AppConfig (centralized backend URL)
│   │   ├── domain/models/            # TrackEntity, AppError, LyricsState
│   │   ├── data/repositories/        # SongRepository
│   │   ├── logic/                    # AudioQueueHandler, SmartShuffleController,
│   │   │                             # NextTrackStrategy, HomeFeedProvider
│   │   ├── services/                 # SyncManager, RadioEngine, UnifiedHttpClient,
│   │   │                             # ConnectivityService, DownloadManager, CacheManager,
│   │   │                             # EqualizerService, ErrorHandler, SpotifyImportService
│   │   ├── ui/
│   │   │   ├── screens/              # HomeScreen, SearchScreen, PlayerScreen, LibraryScreen,
│   │   │   │                         # StorageSettingsScreen, ListeningRecapScreen, SettingsScreen
│   │   │   └── widgets/              # FluidMeshGradient, SwipeableSongTile, MiniPlayer,
│   │   │                             # BatchDownloadButton, AuthDialog
│   │   └── main.dart                 # App Entrypoint, AudioService Init, Fatal Error Recovery
│   ├── test/                         # 110 Comprehensive Unit & Widget Test Suites
│   └── android/                      # Android Gradle project (Java 17, SDK 36, Automotive XML)
├── backend-data-hf/                  # FastAPI Python 3.13 Data Service
│   ├── services/                     # DES Decryption, Music Graph, Trie Autocomplete
│   └── tests/                        # 32 Backend & Security Test Suites
├── archive/
│   └── frontend-react/               # Archived React 19 web app (superseded by mobile-first)
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
