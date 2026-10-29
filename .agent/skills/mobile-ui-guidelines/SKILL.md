---
name: mobile-ui-guidelines
description: Flutter UI/layout rules for Paatu Padava Mobile. Use whenever creating or editing anything under mobile/lib/ui/ (screens, widgets, sheets, theme). Prevents overflow, overlapping mini-player/nav bar, broken small-phone and large-text layouts, and giant unmaintainable screen files.
---

# Mobile UI Guidelines (Flutter)

Read this BEFORE touching `mobile/lib/ui/**`. It complements `mobile-guidelines`
(architecture/audio) — that skill says *where* code goes, this one says *how UI must behave*.

## 0. Look before you build
- Search `lib/ui/widgets/**` for an existing widget first (`home_song_tile`, `home_song_card`,
  `mini_player`, `queue_sheet`, `player_controls`, ...). Reuse or extend; do not create a near-duplicate.
- Read `lib/ui/theme/app_theme.dart`. All colours come from `AppColors`, all text styles from the theme.
  Never hardcode `Color(0xFF...)` or `fontSize` in a screen.

## 1. Layout survival rules (the #1 source of "broken UI")
Every screen must render with NO overflow at **360x640 dp** and at **text scale 1.5**.
- A `Text` inside a `Row` must be wrapped in `Expanded`/`Flexible` and set `maxLines` + `overflow: TextOverflow.ellipsis`.
- A `ListView`/`GridView` inside a `Column` must be wrapped in `Expanded` (or `shrinkWrap: true` with a physics decision).
- Content that can exceed the screen goes in a scroll view (`ListView`, `CustomScrollView`, `SingleChildScrollView`). Never a bare `Column` with fixed-height children.
- No fixed pixel heights for text containers. Use `ConstrainedBox(minHeight)` / padding / `IntrinsicHeight` sparingly.
- Prefer `LayoutBuilder` / `MediaQuery.sizeOf(context)` over magic numbers. Grids use `SliverGridDelegateWithMaxCrossAxisExtent` so tablets work.
- Buttons/tappables: minimum 48x48 dp hit area.
- Keyboard: screens with text fields use `resizeToAvoidBottomInset` correctly and scroll when the keyboard is open.

## 2. Safe areas & the persistent bars
- Wrap top-level screen bodies in `SafeArea` (or use `MediaQuery.paddingOf`) — status bar, notch, gesture bar.
- The **mini player** and **bottom navigation** are persistent. Scrollable content must have bottom padding equal to
  `miniPlayerHeight + bottomNavHeight + safe-area bottom`, otherwise the last item is hidden. Reuse the existing
  constant/helper; if none exists, create ONE and use it everywhere (do not copy numbers).
- Bottom sheets: `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)`; content scrollable; max height respected.

## 3. State & async (UI must not crash after await)
- After any `await` in a `State`, check `if (!mounted) return;` before `setState` / `context` use.
- Audio state comes from streams/`ValueListenable` (`StreamBuilder`/`ValueListenableBuilder`). UI widgets NEVER call
  `AudioHandler` internals directly (see anti-fallback-guardrails §2).
- Cancel every `StreamSubscription`, `Timer`, `AnimationController`, `TextEditingController`, `ScrollController` in `dispose()`.
- Do not do I/O, parsing, or heavy sorting inside `build()`.
- `setState` in a big screen rebuilds everything. Extract the changing part into its own small widget.

## 4. File size & structure
- A screen file should stay **under ~300 lines**. Existing offenders (`search_screen`, `settings_screen`,
  `home_screen`, `full_player_screen`) must shrink, never grow: when you edit one, extract the section you touch into
  `lib/ui/widgets/<feature>/`.
- One widget per file for anything reused. Private `_Foo` widgets are preferred over helper methods that return Widgets.
- No business logic, HTTP, or Hive/DB writes inside widgets — go through `services/` or `logic/`.

## 4b. Images
- Network images use `CachedNetworkImage` with BOTH `placeholder` and `errorWidget`, a fixed aspect ratio (`AspectRatio`) and
  `memCacheWidth` for lists, so there is no layout jump or crash on a 404.
- Never rely on an image being present for layout size.

## 5. Every state must be designed
For each screen/list, implement and look at all of: loading, empty, error (with retry), offline, populated, and
"very long title / very long artist name / non-Latin text (Tamil, Hindi)".

## 6. Testing contract (mandatory)
- New screen => add a `ScreenCase` in `mobile/test/ui_layout_matrix_test.dart` (a guard test fails if you forget).
- New reusable widget with non-trivial layout => widget test pumped through `pumpAndCollectLayoutErrors`
  (`test/helpers/layout_harness.dart`) at `kDevices` x `kTextScales`.
- Bug fix => write the failing test FIRST, then fix. Never delete or loosen an assertion to go green
  (see anti-fallback-guardrails §1).
- Visual change you intend => update goldens: `flutter test --update-goldens --tags golden`, and say so in the summary.

## 7. Definition of done for UI work
Run from `mobile/`:
```bash
flutter analyze --no-fatal-infos
flutter test test/ui_layout_matrix_test.dart
flutter test --exclude-tags golden
```
All must pass. In your final message list: files changed, tests added, commands run + results, and anything NOT verified
(e.g. "not tried on a real device"). Do not claim "fixed" for something you did not run.
