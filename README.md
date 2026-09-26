---
title: Paaatu_Padava
emoji: 🎵
colorFrom: indigo
colorTo: purple
sdk: docker
pinned: false
---

# 🎵 Paatu Padava (பாட்டு பாடவா) — v2.0.0

[![Flutter](https://img.shields.io/badge/Flutter-v3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-SDK_36-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![React](https://img.shields.io/badge/React-19.0-61DAFB?logo=react&logoColor=black)](https://react.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python_3.13-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Supabase](https://img.shields.io/badge/Supabase-Auth_%26_Cloud_DB-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Build APK](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/build-apk.yml/badge.svg)](https://github.com/TGAshwinYT/Paatu_Padava/actions/workflows/build-apk.yml)

> **Your Infinite Music Universe** — Studio-quality 320kbps audio streaming, dual-engine hybrid audio resolution, Clean Architecture domain pipelines, gapless playback with 5-minute battery wakelock guards, Supabase cloud sync, Spotify-style dynamic onboarding, native 5-band equalizer, and 100% offline playback.

---

## 🌟 Overview

**Paatu Padava** is a complete, cross-platform music streaming ecosystem tailored for Indian regional and international music lovers:

1. **Android Mobile App (`mobile/`)**: Native Flutter application built with Clean Architecture, background `AudioService`, gapless `ConcatenatingAudioSource`, native Android AudioSession EQ, bidirectional Supabase playlist synchronization, and offline downloads.
2. **Web Application (`frontend-react/`)**: Modern React 19 + Vite PWA with Web Audio API 10-band equalizer, canvas visualizer, HTML5 CacheStorage offline engine, and one-click Spotify playlist/album importer.
3. **Backend Service (`backend-data-hf/`)**: FastAPI + Python 3.13 service providing 320kbps DES media decryption, item-item collaborative filtering recommendation graphs, and prefix trie autocomplete.
4. **AI MCP Server (`mcp_server.py`)**: Model Context Protocol interface enabling AI assistants to search tracks, fetch recommendations, and construct smart shuffle queues.

---

## 🏛️ Clean System Architecture (v2.0.0)

The mobile client is engineered according to Clean Architecture and Domain-Driven Design principles:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        PRESENTATION LAYER (UI)                         │
│  Home Feed  │  Fuzzy Search  │  Lyrics (Offset/Sync)  │  Queue Sheet   │
└─────────────────────────────────┬──────────────────────────────────────┘
                                  │ Binds via Streams / ValueNotifiers
┌─────────────────────────────────▼──────────────────────────────────────┐
│                       APPLICATION & DOMAIN LAYER                       │
│ ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────┐ │
│ │  AudioQueueHandler   │ │ SmartShuffleEngine   │ │   SyncManager    │ │
│ │  (ConcatenatingSource│ │ (Interleaving,       │ │ (Bidirectional   │ │
│ │   & Lazy Preloader)  │ │  Taste Balancing)    │ │  Supabase Sync)  │ │
│ └──────────────────────┘ └──────────────────────┘ └──────────────────┘ │
└─────────────────────────────────┬──────────────────────────────────────┘
                                  │ Queries / Commands
┌─────────────────────────────────▼──────────────────────────────────────┐
│                          DATA REPOSITORY LAYER                         │
│  ┌──────────────────────┐ ┌──────────────────────────────────────────┐ │
│  │   AudioRepository    │ │            CatalogRepository             │ │
│  │   (Stream Resolver)  │ │  (Multi-Source Aggregator & Deduplicator)│ │
│  └──────────┬───────────┘ └────────────────────┬─────────────────────┘ │
└─────────────┼──────────────────────────────────┼───────────────────────┘
              │                                  │
    ┌─────────┴─────────┐              ┌─────────┴─────────┐
    │                   │              │                   │
┌───▼───────────┐ ┌─────▼────────┐ ┌───▼────────────┐ ┌────▼───────────┐
│ JioSaavn CDN  │ │ YouTube Ext. │ │ Supabase Cloud │ │ Device Cache   │
│ (Direct 320k) │ │ (Innertube)  │ │ (Auth, History,│ │ (Hive/SQLite,  │
│               │ │              │ │  Playlists)    │ │  LRU Temp)     │
└───────────────┘ └──────────────┘ └────────────────┘ └────────────────┘
```

---

## ✨ Key Features (v2.0.0)

### 📱 Native Android Mobile App (Flutter)
- **Unified Domain Entity (`TrackEntity`)**: Canonical track entity with `deduplicationKey` (`${title.trim().toLowerCase()}_${artist.trim().toLowerCase()}`) and centralized `HtmlUnescape` string sanitization.
- **Gapless Audio Engine (`AudioQueueHandler`)**: Preloads upcoming audio tracks in `ConcatenatingAudioSource(useLazyPreparation: true)` for zero-gap transitions between songs.
- **5-Minute Battery & Wakelock Optimization**: When playback is paused or idle for > 5 minutes, automatically deactivates `AudioSession`, closes idle network sockets, and tears down the foreground media notification to prevent battery drain.
- **Atomic Metadata Synchronization**: Directly binds to `player.currentIndexStream` and `sequenceState.currentSource.tag` so active track title, artist, and artwork switch synchronously without UI desynchronization.
- **Multi-Source Catalog Aggregator (`CatalogRepository`)**: Queries JioSaavn 320kbps CDN and YouTube Music in parallel, deduplicates tracks across sources, enforces regional language biasing (`$query $language`), and replaces duplicate compilation covers (e.g. repeated *"100% Melodies"*) with verified artist avatars or high-res video thumbnails.
- **Supabase Cloud Sync (`SyncManager`)**: Full bidirectional synchronization for `user_playlists`, `playlist_tracks`, and `user_favorite_artists` with PostgreSQL Row Level Security (RLS). Survives app uninstalls and device switches.
- **Spotify-Style Dynamic Artist Picker**: Tapping an artist (e.g. *Hiphop Tamizha* or *Sid Sriram*) dynamically expands collaborating artists (*Kaushik Krish, Pradeep Kumar, Dhee*) into the selection grid with smooth scale animations.
- **Search History Guard**: Search queries are recorded **only** on keyboard submission (`onSubmitted`) or result tap, capped at 12 unique entries with case-insensitivity. Keystroke typing never pollutes history.
- **Native 5-Band Equalizer**: Bound directly to `player.androidAudioSessionIdStream` with acoustic presets (Bass Boost, Vocal, Electronic, Rock, Flat).
- **Synchronized Lyrics**: Fluid scrolling LRC lyrics overlay with millisecond-precision offset controls.
- **Auto Cache Eviction**: Background cleaner checks temporary storage on launch and evicts files older than 7 days or when exceeding 400MB.

### 🌐 Web Application (React 19 + Vite)
- **10-Band Studio Web Equalizer**: Parametric BiquadFilter node chain with dynamic HTML5 Canvas frequency spectrum visualizer.
- **100% Offline Playback (HTML5 CacheStorage)**: Zero-internet listening with dedicated storage quota meter and offline track management.
- **Spotify Playlist & Album Importer**: One-click URL import mapping Spotify playlists to direct 320kbps streams.
- **Keyboard Shortcuts**: Complete desktop navigation (`Space`, `J`, `L`, `←`/`→`, `↑`/`↓`, `M`, `R`, `S`, `Q`, `/`).

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
| **Cloud Playlist Persistence** | **100% Device Independence** | Bidirectional Supabase sync (`user_playlists`, `playlist_tracks`, RLS) |
| **Catalog Deduplication** | **Zero Redundant Tracks** | Normalized token keys (`${title}_${artist}`) across Saavn & YouTube |
| **Search History Hygiene** | **12 Unique Capped Terms** | Explicit `onSubmitted` / result click guard; zero keystroke spam |
| **Search Latency (p95)** | **< 300 ms** | Parallel `Future.wait` aggregation + language match re-ranking |

---

## 🗄️ Supabase Database Setup & RLS

Execute this migration script in the [Supabase SQL Editor](https://supabase.com/dashboard/project/_/sql) to enable cloud synchronization:

```sql
-- 1. User Profiles & Selected Preferences
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  email text,
  preferred_languages text[] default array['tamil'],
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 2. User Selected Favorite Artists (From Signup Onboarding)
create table if not exists public.user_favorite_artists (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users on delete cascade,
  artist_name text not null,
  artist_image_url text,
  unique(user_id, artist_name)
);

-- 3. Cloud Playlists (Survives App Uninstall)
create table if not exists public.user_playlists (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users on delete cascade,
  title text not null,
  thumbnail_url text,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 4. Playlist Tracks
create table if not exists public.playlist_tracks (
  id uuid default gen_random_uuid() primary key,
  playlist_id uuid references public.user_playlists on delete cascade,
  track_id text not null,
  title text not null,
  artist text not null,
  artwork_url text,
  stream_url text,
  source_type text default 'saavn',
  added_at timestamp with time zone default timezone('utc'::text, now())
);

-- 5. Row Level Security (Users only access their own data)
alter table public.profiles enable row level security;
alter table public.user_favorite_artists enable row level security;
alter table public.user_playlists enable row level security;
alter table public.playlist_tracks enable row level security;

create policy "Users can read own profile" on public.profiles for all using (auth.uid() = id);
create policy "Users can manage favorite artists" on public.user_favorite_artists for all using (auth.uid() = user_id);
create policy "Users can manage playlists" on public.user_playlists for all using (auth.uid() = user_id);
create policy "Users can manage playlist tracks" on public.playlist_tracks for all using (
  playlist_id in (select id from public.user_playlists where user_id = auth.uid())
);
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: 3.22+ (Channel `stable`)
- **Android SDK**: API level 21 to 36 (Java 17)
- **Node.js**: v18.0.0 or higher
- **Python**: v3.11 or higher

---

### 1. Build & Run Android Mobile App

```bash
cd mobile

# Fetch dependencies
flutter pub get

# Analyze code (verifies 0 errors, 0 warnings)
flutter analyze

# Run on connected Android device / emulator
flutter run

# Build release APK
flutter build apk --release --android-skip-build-dependency-validation
```

> **APK Output Path**: `mobile/build/app/outputs/flutter-apk/app-release.apk`

#### APK Signature Conflict Fix:
If you encounter `INSTALL_FAILED_UPDATE_INCOMPATIBLE` when testing a CI release APK over a local debug build, uninstall the previous version:
```bash
adb uninstall com.tamilgaming.paatupadava
```

---

### 2. Run Web Frontend & Backend

#### One-Click Windows Launcher:
```powershell
.\start_server.bat
```

#### Manual Frontend Setup:
```bash
cd frontend-react
npm install
npm run dev
```
Visit [http://localhost:5173](http://localhost:5173).

#### Manual Backend Setup:
```bash
cd backend-data-hf
python -m venv .venv
source .venv/bin/activate  # Or .venv\Scripts\activate on Windows
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

---

### 3. Model Context Protocol (MCP) Server Setup

To connect Paatu Padava to Claude Desktop or Antigravity IDE, add this configuration to your `claude_desktop_config.json` or `mcp_config.json`:

```json
{
  "mcpServers": {
    "paatu-padava": {
      "command": "python",
      "args": ["d:/Library/Ashwin/Offical/TamilGaming/Music/Music 2/Paatu_Paaduva/mcp_server.py"]
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
│   │   ├── domain/models/            # TrackEntity (Clean Domain Entity)
│   │   ├── data/repositories/        # CatalogRepository, SongRepository
│   │   ├── logic/                    # AudioQueueHandler, SmartShuffleController
│   │   ├── services/                 # SyncManager, SearchService, SupabaseService
│   │   ├── presentation/screens/     # OnboardingArtistsScreen, AppTheme
│   │   └── ui/screens/               # HomeScreen, SearchScreen, PlayerScreen
│   └── android/                      # Android Gradle project (Java 17, SDK 36)
├── frontend-react/                   # React 19 + TypeScript + Vite Web PWA
│   └── src/                          # Web Audio API Equalizer, CacheStorage, UI
├── backend-data-hf/                  # FastAPI Python 3.13 Data Service
│   └── services/                     # DES Decryption, Music Graph, Trie
├── .github/workflows/
│   └── build-apk.yml                 # Automated Release APK CI/CD pipeline
├── mcp_server.py                     # AI Model Context Protocol Server
├── start_server.bat                  # One-click dual server launcher
└── README.md                         # Project documentation
```

---

## 📄 License

This project is open-source and licensed under the [MIT License](LICENSE).

---

Made with ❤️ by [Ashwin (TGAshwinYT)](https://github.com/TGAshwinYT)
