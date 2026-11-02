---
name: mobile-audit-engine
description: Comprehensive diagnostic audit engine for Paatu Padava Mobile. Performs deep static, architectural, DSA, System Design, and regression ripple-effect analysis, comparing mobile behavior against industry benchmarks (Spotify, Apple Music, YouTube Music). Use whenever auditing code, triaging bugs, or planning fixes to ensure zero unintended side effects and zero token waste.
---

# Mobile Audit Engine (Paatu Padava)

This skill provides an autonomous, rigorous framework for auditing, debugging, and enhancing the Paatu Padava Flutter mobile application without relying on expensive, context-truncated external audits.

---

## 1. Audit Taxonomy & Severity Rating

When auditing a reported issue or PR proposal, categorize findings according to this severity rubric:

* **P0 — Critical (Immediate Blocker)**:
  * Application crashes, unhandled async exceptions after `dispose()`, audio playback stoppage on network handover.
  * Memory leaks (unclosed streams, unbounded cache growth, leaking animations or controllers).
  * Data loss or desynchronization (unpersisted user mutations, silent Supabase failures).
* **P1 — High (Core System Design / Algorithmic Flaw)**:
  * Multi-language bias or language silo exclusion (restricting global search to `.first` language).
  * Network request storms while typing (insufficient debounce, uncancelled parallel futures).
  * Algorithmic degradation ($O(N^2)$ string matching on large catalogs, heavy calculations on the 120Hz UI thread).
  * Returning user re-onboarding loops.
* **P2 — Medium (UX & Benchmark Disparity)**:
  * Fixed cutoff pagination where Spotify / Apple Music provides progressive infinite scroll.
  * Lack of ThumbHash / LQIP placeholders causing jarring white image flashes.
  * Unpadded lists hidden beneath the persistent mini-player or navigation bar.
* **P3 — Low (Code Cleanliness & Architectural Hygiene)**:
  * Files $> 400$ lines violating project constraints.
  * Redundant or duplicate GoogleFonts calls.
  * Dead code, unused private methods, or missing docstrings.

---

## 2. DSA (Data Structures & Algorithms) Audit Protocol

Evaluate all data structures and algorithms using this checklist:

```
[ ] Algorithmic Complexity:
    - Are search or catalog filtering operations O(N) or O(log N)?
    - Are membership checks using HashSet / Set (O(1)) rather than List.contains() (O(N))?
    - Are duplicate song checks using 64-bit MinHash signatures rather than quadratic pairwise title comparisons?

[ ] Metric Space & Typo Correction:
    - Does typo correction use SymSpell (O(1) delete dictionary) for fast path (<= 2 edits)?
    - Is BK-Tree (Burkhard-Keller) correctly used for discrete metric space lookups?
    - Is the Trigram index applied for phonetic Tanglish transliteration rather than naive substring matching?

[ ] Cache Bounding:
    - Does every in-memory and disk cache enforce a hard capacity limit (e.g. LRU with max entries)?
    - Do Bloom filters or visited sets have a fixed ring-buffer capacity to prevent runaway memory leaks?

[ ] Render Thread Budget (8.33ms / 120Hz):
    - Are lists with dynamic items using virtualized render extents (`itemExtent: 72.0` or `SliverFixedExtentList`)?
    - Is build() strictly pure, with zero file I/O, heavy sorting, or regex compilation inside the widget tree?
```

---

## 3. System Design (SD) Audit Protocol

Audit system components for resilience, scalability, and state coherence:

```
[ ] SWR (Stale-While-Revalidate) Cache Coherence:
    - Does the UI display cached data immediately (< 15ms) while revalidating in the background?
    - Is cached metadata sanitized so expiring pre-signed URLs or dynamic timestamps are not persisted as permanent facts?

[ ] Offline Durability & Mutation Queues:
    - Are user taste preferences, likes, and playlist edits persisted to Hive locally before remote API calls?
    - If a network error or socket timeout occurs, does the catch block queue a pending retry task rather than swallowing the error?
    - Does SyncManager.syncAll() automatically flush pending queues on connectivity restoration?

[ ] Audio Engine & Lifecycle:
    - Is AudioHandler the single authority for playback state?
    - Does onTaskRemoved() respect the persistent background playback user setting?
    - Are streams pre-warmed responsibly (< 3 items, debounced >= 450ms, submit-only)?
    - Does stream resolution fail over seamlessly to alternative providers (Saavn -> YouTube -> Audius) without UI disruption?

[ ] Bidirectional State Mirroring:
    - Does AuthManager synchronize user preferences to SettingsManager on login and session refresh?
    - Does logging out cleanly preserve or isolate guest preferences without data corruption?
```

---

## 4. Industry Benchmark Comparison Matrix

Compare Paatu Padava against industry leaders during every feature evaluation:

| Dimension | Spotify Standard | YouTube Music Standard | Apple Music Standard | Paatu Padava Requirement |
|---|---|---|---|---|
| **Search Experience** | Instant suggestion chips; unconstrained global catalog; 1-tap inline preview. | Resilient video-to-audio failover; robust typo handling. | Unbiased multi-language exploration; composer & year precision. | No hardcoded language restrictions unless user chooses a chip; multi-language relevance boost. |
| **Feed Scrolling** | Infinite progressive virtualized scroll with smooth load-more triggers. | Grouped vertical carousels with horizontal snap. | Spatial typography; persistent playback bar clearance. | `SearchPaginatedSongsView` with `itemExtent: 72.0` and infinite scroll up to catalog bounds. |
| **Cover Art Loading** | ThumbHash / Color placeholder $\to$ progressive high-res handover. | WebP dynamic scaling based on viewport width. | High-fidelity album artwork with ambient glow extraction. | 3-tier `CascadingCoverImage` (ThumbHash $\to$ low-res thumbnail $\to$ studio 500x500). |
| **Queue & Radio** | Smart Shuffle with Poisson artist distribution (no back-to-back repeats). | Autoplay mix based on active track sonic embeddings. | Seamless track crossfade and gapless playback. | `RadioEngine` with composer boost, era proximity ($\pm 4$ years), and recent history anti-fatigue. |

---

## 5. Ripple-Effect & Regression Prevention Protocol

Before writing or modifying ANY code to resolve an audit item, complete this 4-step impact analysis:

### Step 1: Upstream Invariant Check
* *Where does the input originate?*
* *Can the argument be null, empty, or contain special characters/Tanglish transliterations?*
* *Does this behavior change affect Guest listeners differently than Authenticated users?*

### Step 2: Second-Order Downstream Analysis
* *If we modify search relevance scoring, will favorite songs drop too low, or will exact matches get buried?*
* *If we relax language filtering, will Bollywood Hindi overwhelm Tamil folk results?*
* *If we change audio cache eviction, will active offline downloads be deleted?*
* *If we alter a screen's state management, will the persistent mini-player overlap the bottom tiles?*

### Step 3: Viewport & Accessibility Boundary
* *Does the UI render without RenderFlex overflow at 360x640 dp with 1.5x font scale?*
* *Are all interactive elements sized with a minimum 48x48 dp hit target?*
* *Are all long strings wrapped in Expanded/Flexible with `overflow: TextOverflow.ellipsis`?*

### Step 4: Verification Checklist
1. **Analyze Files**: Run `dart-mcp-server` tool `analyze_files` on all modified files. Expect **0 errors**.
2. **File Size Check**: Ensure files $> 400$ lines count remains $\le 55$.
3. **GoogleFonts Check**: Ensure total GoogleFonts calls remain $\le 383$.
4. **Regression Unit Test**: Add or update unit tests under `mobile/test/` validating both the fix and the non-regression invariant.
