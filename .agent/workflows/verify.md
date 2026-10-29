---
description: Run the full mobile verification and summarise results
---
From `mobile/` run, in order, and show the real output tail of each:
1. `flutter pub get`
2. `flutter analyze --no-fatal-infos`
3. `flutter test --exclude-tags golden`
Summarise: pass/fail counts, the first failing test with its message, and a proposed root-cause (not a workaround).
Do not modify tests to make them pass.
