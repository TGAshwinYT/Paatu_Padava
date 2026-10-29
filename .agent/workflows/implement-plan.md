---
description: Implement an approved plan in small verified steps
---
1. Open the approved `plans/<name>.md`. If none is approved, run /plan-feature first.
2. Implement ONE step of the plan at a time, only touching files in the plan.
3. After each step run `cd mobile && flutter analyze --no-fatal-infos` and fix what you introduced.
4. Add/extend tests listed in the plan (layout matrix entry for every new screen).
5. When all steps are done run the full verification from `.agent/rules/definition-of-done.md`.
6. Report: files changed, tests added, command results, anything unverified. Tick the checklist in the plan file.
