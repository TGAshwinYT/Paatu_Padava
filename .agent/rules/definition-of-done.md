# Definition of Done (always apply)

1. **Plan first.** For any feature or non-trivial fix, create `plans/<short-name>.md` from `plans/TEMPLATE.md`
   and stop for the user's approval before writing code.
2. **Smallest change.** Touch only the files listed in the plan. One feature per task.
3. **Read before writing.** Open the files you will change and the existing widgets/services you could reuse.
4. **Verify, don't assume.** Before saying "done" run (from `mobile/`):
   - `flutter analyze --no-fatal-infos`
   - `flutter test --exclude-tags golden`
   - for any `lib/ui/**` change also `flutter test test/ui_layout_matrix_test.dart`
5. **New screen => register it** in `mobile/test/ui_layout_matrix_test.dart`.
6. **Never** comment out, delete, skip or loosen a failing test; never swap libraries to dodge an error; never return
   dummy data to make a screen "work". Find the root cause.
7. **Report honestly.** Final message = what changed, which commands you ran and their results, what you could NOT
   verify. If a command could not run, say so.
8. UI rules live in `.agent/skills/mobile-ui-guidelines/SKILL.md` — follow them for anything in `mobile/lib/ui/`.
