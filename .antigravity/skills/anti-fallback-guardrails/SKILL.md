---
name: anti-fallback-guardrails
description: Enforces strict root-cause debugging, prevents lazy mock fallbacks, and maintains clean state-machine architecture across Flutter and FastAPI.
---

# Autonomous Engineering Guardrails

## 1. Anti-Fallback Rule (Mandatory)
* **Never comment out tests or failing assertions:** A failing test is ground truth.
* **Never insert dummy returns:** Functions returning `Future<T>` or `Result<T>` must either succeed cleanly or return structured domain errors (`AppError`).
* **Never switch dependencies impulsively:** Do not replace audio or HTTP libraries when experiencing errors—resolve the concurrency or contract bug in the current implementation.

## 2. Audio State Machine Protocol
* Flutter `AudioHandler` must never be directly manipulated from UI widgets.
* All audio transitions must proceed sequentially:
  `Connecting` -> `Buffering` -> `Ready/Playing` -> `Completed`.
* Network timeouts or stream exceptions must trigger an exponential backoff retry on the current stream source before reporting an error state.

## 3. Data Contract Enforcement
* Backend models (`backend-data-hf/models.py`) and Mobile entities (`mobile/lib/domain/models/track_entity.dart`) must stay in 1:1 synchronization.
* Every endpoint return dictionary must pass strict validation before network serialization.

## 4. Verification Checkpoint
Before declaring any task complete:
1. Run targeted unit/integration tests for touched files.
2. Verify zero regressions in memory-sensitive paths (audio streams, image caching, local SQLite/Hive sync).