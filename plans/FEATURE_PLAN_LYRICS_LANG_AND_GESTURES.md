# 🎵 Paatu Padava — Feature Architecture & Implementation Plan: Dual-Language Lyrics & Player Gestures

**Project:** Paatu Padava (பாட்டு பாடவா) — v2.1.0  
**Scope:** Mobile App (`mobile/`)  
**Target Features:**
1. **Dual-Language Lyrics System** (Default Native Language vs. Only English)
2. **Full-Player Touch Gestures** (Horizontal Swipe for Prev/Next, Vertical Swipe for Volume Rise/Down)

---

## 1. Feature 1: Dual-Language Lyrics System

### 1.1 Objective & Requirements (Confirmed by User)
- Support exactly two language modes for song lyrics:
  1. **Default Language**: The original, native language and script of the song (e.g., தமிழ் script for Tamil songs, Devanagari हिन्दी for Hindi songs, Telugu, Malayalam, Japanese, Korean, Spanish, etc.).
  2. **Only English**: **Romanized Transliteration** (phonetic English words preserving exact `[mm:ss.xx]` synchronized karaoke timing line-by-line, e.g., *"Kanmani Anbodu Kadhalan"*).
  3. If a song is natively in English, the system automatically detects this and presents English seamlessly as both Default and English.

### 1.2 Architectural Breakdown

```
┌─────────────────────────────────────────────────────────────────┐
│                          Lyrics Fetcher                         │
│  (LRCLIB Backend / LRCLIB Public API / JioSaavn Lyrics API)     │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Dual-Lyrics Container                      │
│                                                                 │
│  • defaultLyrics: String? (Original LRC / Plain Text)           │
│  • englishLyrics: String? (Romanized / English LRC)             │
│  • detectedLanguage: String? (e.g., 'ta', 'hi', 'en')           │
└────────────────────────────────┬────────────────────────────────┘
                                 │
          ┌──────────────────────┴──────────────────────┐
          ▼                                             ▼
┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│      LRCLIB Script Matching      │   │  On-Device Indic Romanizer       │
│  Queries Romanized + Native LRC  │   │  Converts Native LRC -> English  │
│  entries from LRCLIB candidates  │   │  Preserves [mm:ss.xx] Timestamps │
└──────────────────────────────────┘   └──────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│             PlayerHandler & Lyrics Presentation Layer           │
│                                                                 │
│  • activeLyricsLanguageNotifier: ValueNotifier<LyricsLanguage>  │
│  • Toggle Pill: [ Default (தமிழ்) | English ]                   │
│  • Instant zero-lag toggle in LyricsScreen & SyncedLyricsEmbed │
└─────────────────────────────────────────────────────────────────┘
```

#### A. Data Model & State Changes
1. **Domain Model (`lyrics_state.dart` & `song.dart`)**:
   - Introduce `LyricsLanguage` enum: `LyricsLanguage.defaultLang`, `LyricsLanguage.english`.
   - Update `LyricsState` to hold both lyric variants:
     ```dart
     enum LyricsLanguage { defaultLang, english }

     class DualLyrics {
       final String defaultLyrics;
       final String englishLyrics;
       final String languageCode; // e.g., 'ta', 'te', 'hi', 'en'
       final bool isSynced;
     }
     ```
2. **PlayerHandler (`player_handler.dart`)**:
   - Add `ValueNotifier<LyricsLanguage> lyricsLanguageNotifier = ValueNotifier(LyricsLanguage.defaultLang);`
   - Add `ValueNotifier<DualLyrics?> dualLyricsNotifier = ValueNotifier(null);`
   - Persist user's preferred lyrics language across tracks in `SettingsManager` (`lyrics_preferred_language: 'default' | 'english'`).

#### B. Lyrics Sourcing & Transliteration Strategy
1. **Source Sifting**:
   - LRCLIB search frequently returns multiple entries for popular Indian songs: one in Romanized script (e.g. Tanglish/Hinglish) and one in native script (Unicode Indic).
   - If both are returned in candidate search, map both into `DualLyrics`.
2. **Synchronized Indic Romanizer Engine**:
   - For tracks where only native script LRC is available (e.g. Tamil, Hindi, Telugu, Malayalam, Kannada), an offline, deterministic phonetic transliterator converts the text to Romanized English while **preserving line timestamps `[mm:ss.xx]` strictly intact**.
   - Example:
     ```
     Input:  [00:14.50] கண்மணி அன்போடு காதலன்
     Output: [00:14.50] Kanmani anbodu kaadhalan
     ```
   - This ensures **100% of songs** have synchronized English lyrics with zero API overhead and offline capability.

#### C. Presentation & UI Integration
1. **Full Lyrics Page (`LyricsScreen` & `LyricsTopBar`)**:
   - Add a sleek dual-segment selector pill in `LyricsTopBar`:
     `[ தமிழ் | English ]` (dynamically displaying the native script name or "Default" vs "English").
   - Tapping switches `activeLyricsLanguageNotifier`.
   - The active timestamp and line scroll position are preserved seamlessly across language switching.
2. **Cover / Embed Lyrics (`SyncedLyricsEmbed`)**:
   - Add a compact floating toggle pill `[ Default | EN ]` allowing instant language toggle without leaving the player screen.

---

## 2. Feature 2: Interactive Player Gestures

### 2.1 Objective & Requirements (Confirmed by User)
1. **Track Navigation (Horizontal Swipes)**:
   - **Swipe Left (Right to Left)**: Advance to **Next Song** (`skipToNext()`).
   - **Swipe Right (Left to Right)**: Return to **Previous Song** (`skipToPrevious()`).
   - Accompanied by tactile haptic feedback (`HapticFeedback.lightImpact()`).
2. **Volume Control (Vertical Swipes)**:
   - **Swipe Up**: **Volume Rise** (increase in-app player volume smoothly).
   - **Swipe Down**: **Volume Down** (decrease in-app player volume smoothly).
   - **Visual Feedback**: Sleek floating glassmorphic Volume HUD pill over the artwork with dynamic volume level icon and percentage bar, auto-fading after 1.2s. Zero native permission overhead and immediate cross-platform responsiveness.

### 2.2 Architectural Breakdown

```
┌─────────────────────────────────────────────────────────────────┐
│               FullPlayerScreen Artwork Viewport                 │
│               (Wrapped in PlayerGestureDetector)                │
└────────────────────────────────┬────────────────────────────────┘
                                 │
           ┌─────────────────────┴─────────────────────┐
           ▼                                           ▼
┌─────────────────────────────────────┐   ┌─────────────────────────────────────┐
│       Horizontal Drag / Fling       │   │        Vertical Drag / Delta        │
├─────────────────────────────────────┤   ├─────────────────────────────────────┤
│ • Direction: Left -> skipToNext()   │   │ • Drag Up: Volume += delta          │
│ • Direction: Right -> skipToPrev()  │   │ • Drag Down: Volume -= delta        │
│ • Min Distance: 45 dp               │   │ • Clamp: 0.0 to 1.0 (or System Vol) │
│ • Haptic: lightImpact()             │   │ • Shows Volume HUD Overlay (1.2s)   │
│ • Animated Artwork Slide            │   │ • Haptic on min/max limit           │
└─────────────────────────────────────┘   └─────────────────────────────────────┘
```

#### A. Gesture Recognition & Conflict Resolution
1. **Gesture Target Zone**:
   - Placed on the Artwork container (`_buildArtworkView`) during Cover mode.
   - When Cover tab is active, there is no scroll view, so horizontal and vertical gestures are completely free of conflict.
   - When Lyrics tab is active, vertical gestures are reserved for lyric scrolling, while horizontal swiping can remain active on the bottom playback bar.
2. **Gesture Mechanics**:
   - Use `GestureDetector` with `onHorizontalDragEnd` and `onVerticalDragUpdate` or a custom `PanGestureRecognizer`.
   - **Thresholds**:
     - Horizontal: Swipe trigger requires `dx.abs() > 40` or velocity `> 300 px/s`.
     - Vertical: Accumulated `dy` maps smoothly to volume delta: `delta = -dy / viewportHeight`.
     - 1 full viewport swipe = 100% volume transition.

#### B. Volume HUD Overlay
- A floating glassmorphic indicator positioned over the player artwork:
  - Dynamic icon:
    - `0%`: `Icons.volume_off_rounded`
    - `1-33%`: `Icons.volume_mute_rounded`
    - `34-66%`: `Icons.volume_down_rounded`
    - `67-100%`: `Icons.volume_up_rounded`
  - Sleek horizontal or vertical progress bar with percentage (`78%`).
  - Auto-dismisses with an ease-out fade after 1.2 seconds of no touch.

#### C. Audio Engine Volume Handling
- Primary: In-app playback volume via `audioHandler.player.setVolume(double)`.
  - Instant, zero permissions required, cross-platform (Android/iOS).
  - Preserves volume normalization scaling.
- Optional / Alternative: System hardware volume via method channel or volume plugin.

---

## 3. Implementation Steps & File Modifications

| Step | Area | Files Modified | Description |
|---|---|---|---|
| **1** | Lyrics Data | [lyrics_state.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/domain/models/lyrics_state.dart) | Add `LyricsLanguage` enum and `DualLyrics` model. |
| **2** | Transliteration Engine | `mobile/lib/logic/lyrics/indic_romanizer.dart` | Build deterministic, offline Indic-to-English transliterator preserving `[mm:ss.xx]` sync. |
| **3** | Lyrics Service | [api_client.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/services/api_client.dart), [player_handler.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/services/player_handler.dart) | Fetch and store dual lyrics (`default` & `english`), notify listeners. |
| **4** | Lyrics UI | [lyrics_top_bar.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/ui/widgets/lyrics/lyrics_top_bar.dart), [lyrics_screen.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/ui/screens/lyrics_screen.dart), [synced_lyrics_embed.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/ui/widgets/player/synced_lyrics_embed.dart) | Add language toggle buttons and reactive switching. |
| **5** | Gestures & HUD | `mobile/lib/ui/widgets/player/player_gesture_detector.dart`, `mobile/lib/ui/widgets/player/volume_hud_overlay.dart` | Build swipe detector (next/prev & volume) and volume indicator overlay. |
| **6** | Player Screen | [full_player_screen.dart](file:///d:/Library/Ashwin/Offical/TamilGaming/Music/Music%202/Paatu_Paaduva/mobile/lib/ui/screens/full_player_screen.dart) | Wrap artwork with gesture detector and volume HUD overlay. |
| **7** | Tests | `mobile/test/lyrics_language_test.dart`, `mobile/test/player_gesture_test.dart` | Full unit & widget test suites for dual-language lyrics & gesture logic. |
