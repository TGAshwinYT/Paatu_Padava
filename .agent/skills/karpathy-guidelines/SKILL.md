---
name: karpathy-guidelines
description: Core operational discipline and anti-failure principles derived from Andrej Karpathy's guidelines for LLM software development. Enforces rigorous problem understanding, simplicity first, surgical code changes, and goal-driven verification across all tasks.
---

# Operational Discipline & Anti-Failure Principles (Andrej Karpathy)

> *"The failure mode of current models is that they are too eager to write code, too confident in their assumptions, and too casual about changing things they shouldn't."* — Andrej Karpathy

These four universal principles govern every engineering intervention in the codebase:

---

## 1. Think Before Coding

* **No Assumption Jumping**: Never guess user intent or infer hidden requirements without examining code traces, API payloads, and caller invariants first.
* **Trace Data Flow End-to-End**: Identify upstream inputs, intermediate state transformations, and downstream consumers before modifying a single line of logic.
* **Surface Tradeoffs Explicitly**: When multiple solutions exist, identify latency, memory, and architectural tradeoffs before acting.
* **Clarify Ambiguities**: If requirements or observed behaviors conflict, ask for clarification or isolate the diagnostic hypothesis rather than guessing.

---

## 2. Simplicity First

* **Minimal Implementation**: Write the absolute minimum code necessary to solve the problem completely and robustly.
* **No Speculative Abstractions**: Avoid introducing speculative helper classes, wrapper factories, or future-proof generics that are not required by the current task.
* **Preserve Architectural Idioms**: Follow the established conventions of the repository (`AppTheme`, `AppColors`, `CatalogDatabase`, `PlayerHandler`) instead of inventing new paradigms.
* **Sub-Millisecond & Bounded Memory**: Ensure all algorithms and caching structures run in bounded space ($O(1)$ amortized) without bloating the UI thread.

---

## 3. Surgical Changes

* **Minimal Blast Radius**: Touch only the exact lines, methods, and files strictly necessary to fix the bug or implement the feature.
* **Zero Drive-By Refactoring**: Do not reformat unrelated code, reorder imports, or rewrite existing docstrings unless specifically instructed.
* **Preserve Existing Comments**: Retain all existing inline comments, reasoning notes, and license headers.
* **Clean Up Temporary Artifacts**: Remove all temporary diagnostic scripts, scratch files, and debug logging before concluding tasks.

---

## 4. Goal-Driven Execution

* **Define Verification Criteria First**: Establish how success will be measured before writing code (e.g. static analysis exit code, unit test pass, layout survivability).
* **Execute Verification Gates**: Run `analyze_files` (requiring 0 errors) and relevant unit/widget tests on every modified file.
* **Verify Edge Cases**: Explicitly check nullability, empty collections, offline fallback, and small viewport (360x640dp) constraints.
* **Never Stop on Failures**: If an analyzer warning or runtime test fails, diagnose the root cause immediately and resolve it surgically before declaring completion.
