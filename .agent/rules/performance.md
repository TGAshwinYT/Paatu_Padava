# Performance Rules (always apply)

These rules are permanent engineering guardrails to keep Paatu Padava fast, smooth (60/120 fps), memory-bounded, and lean. Antigravity must never violate or regress these rules.

---

### 1. No `GoogleFonts` Inside `build()`
- **Rule**: Never call `GoogleFonts.<fontFamily>()` inside any widget's `build()` method, tile builder, or item callback.
- **Why**: `GoogleFonts.xxx()` performs dynamic style lookups and can trigger runtime network font fetching, leading to frame drops, layout thrashing, and first-frame flicker.
- **Enforcement**:
  - Reference styles via `Theme.of(context).textTheme` or static styles defined in `AppTheme` (`mobile/lib/ui/theme/app_theme.dart`).
  - Font families must be bundled as local assets or statically declared at the theme level with fallback chains for regional scripts (Tamil, Hindi, Telugu, Malayalam).

---

### 2. Always Set Image Cache Sizes (`memCacheWidth` / `memCacheHeight`)
- **Rule**: Every `CachedNetworkImage` or `Image.network` widget **must** explicitly specify `memCacheWidth` and/or `memCacheHeight` scaled to the actual render viewport.
- **Standard Dimensions**:
  - List / Queue Thumbnails (48–64 dp): `memCacheWidth: 120–160`
  - Grid Cards / Album Art (120–180 dp): `memCacheWidth: 300–360`
  - Full Player Artwork (300–400 dp): `memCacheWidth: 800–1000`
- **Preferred Component**: Use `CoverArtImage` (`mobile/lib/ui/widgets/cover_art_image.dart`) which automatically calculates optimal memory bounds.
- **Global Memory Cap**: Maintain global image cache caps in `main.dart`:
  ```dart
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024; // 64 MB
  PaintingBinding.instance.imageCache.maximumSize = 100; // max 100 cached images
  ```

---

### 3. No Heavy GPU Blur in Lists or Scroll Views
- **Rule**: Never place `BackdropFilter` or `ImageFilter.blur()` inside repeating list items, `ListView.builder`, `GridView.builder`, or animated scroll delegates.
- **Why**: Multi-pass Gaussian blur shaders force offscreen GPU render passes. In a scrolling list, this causes severe stutter on mid-range and budget devices.
- **Permitted Uses**: Static overlay sheets (`MiniPlayer`, modal bottom sheets, full player ambient background). For lists and cards, use semi-transparent solid containers (`Colors.black.withOpacity(...)`) or pre-rendered gradients.

---

### 4. Heavy Computational Work Goes to Isolates (`compute()`)
- **Rule**: Any synchronous CPU-bound task taking > 5ms must run off the UI thread via Flutter's `compute()` or dedicated background isolates.
- **Applies to**:
  - Large JSON parsing/decoding (> 50 KB payloads from YouTube/JioSaavn/Spotify).
  - Palette color extraction (`PaletteGenerator.fromImageProvider`).
  - Fuzzy text matching and string distance algorithms (Levenshtein, token similarity across hundreds of tracks).
  - BK-Tree dictionary generation and bulk candidate scoring.
- Keep the main Dart isolate responsive to hit consistent 16.6ms (60 fps) and 8.3ms (120 fps) vsync deadlines.

---

### 5. No Screen Over ~300 Lines (Modular Component Architecture)
- **Rule**: Keep screen classes in `mobile/lib/ui/screens/` under approximately 300 lines of code.
- **Action**: When a screen grows larger, decompose it into focused, reusable widgets under `mobile/lib/ui/widgets/<feature>/`.
- **Why**:
  - Scopes widget rebuilds to small leaf subtrees instead of rebuilding entire screens.
  - Ensures testability and maintainability without accidental state coupling.

---

### 6. Sub-2-Second Cold Start (Non-Blocking Startup)
- **Rule**: `main()` must never await network calls, cloud syncing, log rotating, or non-essential initialization before calling `runApp()`.
- **Policy**:
  - **Pre-`runApp()` (Strictly Minimal)**: Only Flutter bindings (`WidgetsFlutterBinding.ensureInitialized`), local Hive boxes required for instant theme/settings rendering (`SettingsManager`), and image cache limits.
  - **Post-Frame / Background**: All secondary initializations (Supabase cloud sync, `AuthManager`, `DownloadManager` disk scanning, `InnerTubeConfigService`, `CoverArtResolver` cache priming) must execute concurrently in background tasks or via `WidgetsBinding.instance.addPostFrameCallback`.
