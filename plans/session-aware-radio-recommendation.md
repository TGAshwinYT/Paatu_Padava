# Plan: Session-Aware Autoplay & Radio Recommendation Engine

Status: DRAFT
Owner agent: mobile_engineer

## 1. Goal (one sentence, user-visible)
Deliver natural, studio-quality radio and autoplay transitions that match Spotify and YouTube Music by replacing raw genre/artist polling with session-aware candidate generation (60% YouTube Automix + 30% JioSaavn Reco + 10% Local Markov), hard deduplication/quality filtering, multi-factor scoring (era ±4y, composer, artist anti-fatigue), and skip-aware seed persistence.

## 2. Non-goals (what we are NOT doing)
- We are NOT pushing to git (`git push`) until the user explicitly requests it.
- We are NOT removing user-queued tracks (user queue always takes FIFO priority over auto-generated radio tracks).
- We are NOT resolving all 40 streams upfront; only the active track and next 2 pre-cached slots resolve streams.

## 3. Current state (verified by reading code)
- `mobile/lib/services/radio_engine.dart`: Currently fetches from YouTube, JioSaavn, Artist search, Backend ML, and Trending, interleaving them mechanically.
- `mobile/lib/logic/next_track_strategy.dart`: Contains `SpotifyStyleStrategy`, `YtMusicStyleStrategy`, `MarkovCosineRadioStrategy`, and `NextTrackStrategyFactory`.
- `mobile/lib/logic/audio_queue_handler.dart`: Currently triggers lookahead recommendation pre-fetch at 80% progress or $\le 15$s remaining.
- `mobile/lib/services/queue_cooldown_manager.dart`: 75-song rolling cooldown buffer, artist cooling window.
- `mobile/lib/core/dsa/bloom_filter.dart`: Space-efficient probabilistic filter with zero false negatives.
- `mobile/lib/logic/track_quality_filter.dart`: Prunes teasers, compilations, mixes, and duration outliers.
- `mobile/lib/logic/markov_cosine_radio_strategy.dart`: Implements Markov transition probabilities and `SongFeatureVector` cosine similarity.

## 4. Design & Pipeline
```
[Current Song Playing]
        │
        ▼ (At 25% playback progress, trigger background fetch)
┌───────────────────────────────────────────────────────────┐
│ 1. CANDIDATE GENERATION (Fetch ~40 tracks)                │
│  • Source A (60%): YT Music "Up Next" / Automix API       │
│    (InnerTube `next` endpoint with `videoId` + `RDAMVM`)  │
│  • Source B (30%): JioSaavn `reco.getreco` by `pid`       │
│  • Source C (10%): Local History (`markov_cosine_radio`)  │
└───────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ 2. HARD FILTERING (Prune bad candidates)                  │
│  • Check `bloom_filter.dart` & `queue_cooldown_manager`   │
│    (Drop songs played in the last 50 tracks / 4 hours)    │
│  • Check `track_quality_filter.dart` (Drop <60s or >10m)  │
└───────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ 3. SESSION-AWARE SCORING & DIVERSITY RE-RANKING           │
│  • Boost same language & era (±4 years of seed song)      │
│  • Boost shared Music Director / Composer                 │
│  • PENALIZE if the same artist played in the last 2 songs │
└───────────────────────────────────────────────────────────┘
        │
        ▼
[Append Top 5 to Queue & Pre-resolve Next 2 Audio Streams]
```

### Stage 1: Candidate Generation (~40 tracks)
- Generate candidate pool in parallel with targeted ratios:
  - **Source A (60% ~ 24 tracks)**: `YouTubeClient.getRadioTracks` / `YouTubeClient.getUpNextAutomix` with `RDAMVM$videoId`.
  - **Source B (30% ~ 12 tracks)**: `SaavnClient.getRelatedSongs` with seed song ID (`reco.getreco`).
  - **Source C (10% ~ 4 tracks)**: Scored from local history & favorites via `SongFeatureVector` / Markov transition probabilities.

### Stage 2: Hard Filtering
- **History & Cooldown Filter**:
  - Check `BloomFilter` populated with current queue and last 50 tracks.
  - Check `QueueCooldownManager.isCoolingDown(candidate)` (tracks played within 75 songs or 4 hours).
- **Track Quality Filter**:
  - `candidate.duration < 60` (drop teasers/trailers) or `candidate.duration > 600` (drop 1-hour compilations/mixes).
  - `TrackQualityFilter.shouldKeep(title: candidate.title, durationSec: candidate.duration)`.
- **Anti-Dub & Language Lockdown**:
  - Drop cross-language dubs against seed song (`candidate.isSameSongOrDub(seedSong)`).
  - Reject explicit language mismatches against seed song / user preferred language.

### Stage 3: Session-Aware Scoring & Diversity Re-Ranking
- Refine the candidate pool:
  - **Language match**: Boost if candidate language matches seed song language.
  - **Era proximity**: Extract year; award bonus if within $\pm 4$ years of the seed song (`(candYear - seedYear).abs() <= 4`).
  - **Shared Music Director / Composer**: Detect shared composers (e.g., Anirudh, Rahman, Harris, Yuvan, Ilaiyaraaja, Santhosh Narayanan, etc.) and boost.
  - **Artist Diversity Penalty**: Check the last 2 played songs in the session / history. Apply heavy penalty if the candidate's primary artist played in the last 2 songs.
- Rank candidates descending by refined composite score.

### Stage 4: Queue Appending & Pre-resolving Streams
- Append Top 5 (or requested batch) to the queue (`addAutoSuggestions`).
- Pre-resolve next 2 audio streams (`preloadUpcomingTracks`) so track transitions have zero latency.

### Stage 5: The "Skip Signal" & Last Completed Seed
- In `AudioQueueHandler`:
  - When user skips a track under 30 seconds (`listenedSec < 30`):
    - Record negative feedback.
    - **Do NOT use the skipped song as the seed for the next radio fetch.**
    - Retain `_lastCompletedSeedSong` (the last song played for $\ge 30$ seconds or completed naturally) as the anchor seed!
  - At **25% playback progress** (instead of 80%), if upcoming tracks are running low ($\le 2$), trigger background pre-fetch.

## 5. Verification Steps
1. Add new test suite `mobile/test/session_aware_radio_test.dart` testing:
   - Candidate Generation ratios (60% YT Automix, 30% Saavn, 10% Local Markov).
   - Hard Filtering with BloomFilter, QueueCooldownManager, and TrackQualityFilter (<60s or >10m).
   - Session-aware scoring (±4y era boost, composer boost, last-2-artists penalty).
   - Skip signal preserving last completed seed on skips < 30s.
   - Lookahead pre-fetch triggering at 25% playback progress.
2. Run existing tests (`commercial_next_track_strategy_test.dart`, `audio_queue_handler_test.dart`, `ui_layout_matrix_test.dart`).
3. Run `flutter analyze` on modified files.
4. **DO NOT PUSH TO GIT**.
