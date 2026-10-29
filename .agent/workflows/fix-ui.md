---
description: Diagnose and fix a broken mobile UI screen with a reproducing test first
---
1. Ask me for: which screen, what looks wrong, and (if possible) a screenshot or the error text.
2. Find the screen/widget file(s). Read them fully plus `.agent/skills/mobile-ui-guidelines/SKILL.md`.
3. Reproduce with a test: add or extend a case in `mobile/test/ui_layout_matrix_test.dart` (or a focused widget test using
   `pumpAndCollectLayoutErrors`). Run it and confirm it FAILS for the reason I described.
4. Fix the root cause following the layout rules (Expanded/ellipsis, scroll views, safe areas, bottom padding for mini player).
5. Re-run the test (must pass) then the full verification from `.agent/rules/definition-of-done.md`.
6. Report the cause in one or two sentences and what you ran.
