# Rule: Strict File Size & Modularity Limits (Byte Cap)

## Hard Size Limits (New & Edited Files)
Every source file must stay focused on a single responsibility and remain below these byte/line limits:

| Layer / File Type | Soft Limit (Plan Split) | Hard Limit (Block Edit) |
| :--- | :--- | :--- |
| **Dart / Flutter (`mobile/lib/`)** | 15 KB (~350 lines) | **25 KB (~600 lines)** |
| **React / TypeScript (`frontend-react/src/`)** | 12 KB (~300 lines) | **20 KB (~500 lines)** |
| **FastAPI Routers (`backend-data-hf/routers/`)** | 12 KB (~300 lines) | **20 KB (~500 lines)** |
| **Backend Services (`backend-data-hf/services/`)** | 18 KB (~450 lines) | **30 KB (~750 lines)** |

*(Exceptions: Auto-generated files, `package-lock.json`, static seed data in `mobile/lib/data/catalog_*_seed.dart`, and test suites.)*

## Enforcement Rules for AI Agents
1. **No Growing Legacy Monoliths:** If you edit an existing file that is ALREADY over the Hard Limit (e.g., `audio_queue_handler.dart`, `AudioContext.tsx`, `youtube_client.dart`, `party_sync_coordinator.dart`, `player_handler.dart`), **do not add net-new bytes to it**. Extract the new logic—or an adjacent helper—into a dedicated sibling module first so the monolith shrinks.
2. **Pre-Edit Check:** Before adding a new feature to any file over the Soft Limit, propose a clean module extraction in your plan before writing code.
3. **Zero Silent Truncation:** Never delete working code, comments, or error handling just to hit a byte limit. Always reduce file size by **extracting cohesive modules/widgets/hooks**, not by stripping logic.
4. **Definition of Done:** Before finishing any task, check the byte size of every modified file (`wc -c` / file size). If any file exceeds its Hard Limit or grew a legacy monolith, refactor it before reporting completion.