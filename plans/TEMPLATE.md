# Plan: <feature name>

Status: DRAFT | APPROVED | IN PROGRESS | DONE
Owner agent: mobile_engineer

## 1. Goal (one sentence, user-visible)

## 2. Non-goals (what we are NOT doing)

## 3. Current state (verified by reading code)
- Existing screens/widgets/services involved (with file paths):
- What can be reused:
- Known problems nearby (large files, setState hot spots):

## 4. Design
- Screens/widgets to add or change (file paths):
- State & data flow (which service/stream/ValueNotifier owns what):
- Data contract changes (models, API, Hive keys) and migration needs:
- Backend change needed? (Y/N — if Y, list endpoints; keep models in sync per anti-fallback-guardrails §3)

## 5. States to handle
loading / empty / error+retry / offline / populated / long text & Tamil-Hindi text

## 6. Edge cases & risks
(e.g. app killed during playback, no network, duplicate taps, rotation, back-button behaviour, mini-player overlap)

## 7. Steps (small, each independently verifiable)
1. [ ] ...
2. [ ] ...

## 8. Tests
- [ ] Layout matrix entry for each new screen (`mobile/test/ui_layout_matrix_test.dart`)
- [ ] Unit/widget tests for new logic:
- [ ] Golden update needed? (Y/N)

## 9. Verification commands (must all pass)
```
cd mobile
flutter analyze --no-fatal-infos
flutter test --exclude-tags golden
```

## 10. Done report (fill at the end)
Files changed: / Tests added: / Commands run + results: / Not verified:
