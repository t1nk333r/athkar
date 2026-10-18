# Commit adhkar UI state only after a successful save

Planned at `9423e08` on 2026-10-13. Status: RELEASED for independent Athkar work on 2026-10-14; the user superseded the full-settlement hold.
Executor: Claude Opus 5.5 xhigh on Mars. Independent final reviewer: task 006, from the other model family.
Dependencies: 010 app-unit-test target.

## Current state

AdhkarSessionModel.tap and setTarget mutate `state`, call persist(), then return DeckChange. persist() catches and reports the write error but returns no success flag. resetCard/manual completion/scoped reset similarly publish the changed state after a failed save.

## Goal

A failed SQLite write must retain the previously committed counters, targets, completion flags and current-card behavior. It must report the error and produce no successful completion/advance. A failed day load must not replace saved state with an empty state.

## Scope

ios/Athkar/Deck/AdhkarDeckModel.swift; new ios/AthkarPortableTests/AdhkarPersistenceTests.swift; minimal test seams in this model only.

Do not edit religious text, content pack versions, PWA behavior, golden fixtures, Apple identity/authentication, or features gated after Slice 4. This task fixes existing implementation or its approved deck workflow. No App Store Connect, TestFlight, bundle ID reservation, authentication migration or new fleet credentials.

## Steps

Use the real database with a controlled failing writer or a narrow injected persistence seam. Cover tap, target, manual completion, reset, and rollover failure. Compute candidate state, persist it, then publish it on success. Preserve normal DeckChange behavior and the long-order focus contract. Return failure without haptics/completion. Test successful paths and recovery after a failed write.

Before editing, read AGENTS.md, NATIVE_APP_PLAN.md and the relevant existing tests. Compare the scoped files against the planned commit. If scope must expand, report the exact reason to the coordinator before editing overlapping files. Use the smallest necessary seams; avoid broad refactors and dependencies.

## Verification

Run production-source AdhkarPersistenceTests through tools/test-native-models.sh on Linux. Request the relevant SDK compilation from the coordinator. Existing DeckUITests and DeckRegressionUITests are required iOS runtime cases and stay open when unrun.

Run `git diff --check`. Content checks are `node tools/content-validate.mjs` and `node tools/content-export-pwa.mjs --check --ruqyah /home/t1nk33r/Projects/ruqyah-al-qareen/content.js` on Luna. Workers lacking the sibling checkout must state that and let the coordinator run the check. All new Swift/XCTest/SDK checks run on Linux under the coordinator queue, with /tmp/hikaya-build-suite.lock then /tmp/athkar-build-suite.lock acquired nonblocking and at most two jobs on Luna. Remote workers return source bundles. SDK compilation, executed portable tests and iOS runtime results are separate evidence; required unrun device cases remain open.

## Delivery

Use the assigned isolated worktree and branch. Commit source and tests after verification. Return a git bundle plus structured result with commit SHA, changed files, exact checks/results, skipped checks, owned processes and released locks. Do not push/merge, change main, remove worktrees or settle your own thread. The coordinator integrates serially after independent review. Do not update PROJECT_MAP.md or other tasks' plan files; coordinator owns those.

Stop and report if the selected model differs from the assigned family/effort, the predecessor gate is not released, a needed lane is busy, an out-of-scope product decision is required, or a shared resource has another owner. Never kill processes by name, stop shared daemons, shut down all simulators or remove another owner's lock. Preserve Eris on CPA and do not launch workers there or on Terra. Only stop PIDs/process groups started for this task.

## Done criteria

The stated goal is covered by meaningful regressions; relevant existing tests pass; no unintended product/content changes; all source committed in the assigned worktree; verification evidence matches the commit; no owned tests/dev servers/lane locks remain running. Final completion additionally requires the opposite-family review and serial merge by the coordinator.
