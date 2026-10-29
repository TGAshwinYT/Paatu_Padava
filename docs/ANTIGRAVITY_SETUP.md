# Setup: making Antigravity build the mobile app reliably

## 1. Copy the files
Unzip this folder over the root of your repo (it mirrors your repo paths). Files that REPLACE existing ones:
`.antigravity/agents.json`, `mobile/analysis_options.yaml`, `mobile/pubspec.yaml` (only adds `integration_test`),
`.github/workflows/ci.yml` (only the two mobile commands change). Everything else is new.
Then: `cd mobile && flutter pub get`.

## 2. Run the new tests ONCE and expect failures
```bash
cd mobile
flutter test test/ui_layout_matrix_test.dart
```
Each failure names a screen, device size and text scale — those are REAL overflow bugs that were already in the app.
Fix them one at a time with the `/fix-ui` workflow (do not loosen the test). If a screen fails for a *setup* reason
(plugin, missing fixture) rather than layout, move it to `exemptScreenFiles` with a reason.

## 3. Make sure Antigravity actually loads the rules
- Skills/rules/workflows were written to BOTH `.agent/` and `.antigravity/` because I could not verify which folder your
  Antigravity version reads. In Antigravity open the Customizations / Rules & Workflows panel and check that
  `definition-of-done`, `mobile-ui-guidelines` and the workflows (`/plan-feature`, `/implement-plan`, `/fix-ui`, `/verify`)
  are listed. Keep whichever location shows up and delete the duplicate.
- `agents.json` is a custom file: confirm it is something your setup reads; if not, the `.agent/` rules are what matter.

## 4. Add the Dart & Flutter MCP server (lets the agent see real errors)
Needs a recent Flutter/Dart SDK. In Antigravity: Agent panel -> "..." -> MCP Servers -> Manage -> View raw config, add:
```json
{ "mcpServers": { "dart": { "command": "dart", "args": ["mcp-server"] } } }
```
(If your Dart is older and `dart mcp-server` is unknown, upgrade Flutter first.)
The agent can then read analyzer errors, runtime errors and the widget tree and trigger hot reload.

## 5. Daily workflow
1. `/plan-feature` -> read the plan in `plans/<name>.md`, edit it, approve.
2. `/implement-plan`  (use Planning mode, not Fast mode, for features).
3. `/verify` yourself before merging, or watch CI.
UI looks wrong? `/fix-ui` and attach a screenshot.

## 6. Goldens (optional, later)
```bash
cd mobile
flutter test --update-goldens --tags golden   # creates test/goldens/files/*.png  -> review, commit
flutter test --tags golden                    # later runs compare against them
```

## 7. Emulator smoke test (optional)
Complete onboarding once on the emulator, then:
`cd mobile && flutter test integration_test/app_smoke_test.dart -d <emulator-id>`
Manual CI version: `.github/workflows/mobile-integration.yml` (untested template).

## 8. Next refactors (biggest payoff)
`search_screen.dart` (1,110 lines), `settings_screen.dart` (1,099), `home_screen.dart` (956),
`full_player_screen.dart` (872): split each into feature widgets under `lib/ui/widgets/<feature>/`, one per session.
