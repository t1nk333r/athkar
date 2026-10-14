# Keep reading settings consistent when SQLite rejects a change

Planned at `9423e08` on 2026-10-13. Status: RELEASED for independent Athkar work on 2026-10-14; the user superseded the full-settlement hold.
Executor: GPT-6.1 Sol xhigh on Luna. Independent final reviewer: task 004, from the other model family.
Dependencies: 010 app-unit-test target.

## Current state

SettingsModel's theme/textSize/lineSpacing/haptics/homePrayerRow didSet observers call write(), which reports errors but retains the changed value. setLongOrder changes memory before write and AppModel always reorders cards. markLongOrderPromptAnswered also marks memory answered on a failed write.

## Goal

The visible setting and long-order deck behavior always reflect the last committed value. Failed changes report one error, revert safely without recursive writes, and allow a later successful change. The one-time prompt is considered answered only after successful persistence.

## Scope

ios/Athkar/App/AppModel.swift SettingsModel and long-order methods only; ios/AthkarCore/Sources/AthkarCore/Storage/SettingsStorage.swift a narrow atomic long-order-decision method if needed; new ios/AthkarTests/SettingsPersistenceTests.swift and focused Settings storage regressions.

Do not edit religious text, content pack versions, PWA behavior, golden fixtures, Apple identity/authentication, or features gated after Slice 4. This task fixes existing implementation or its approved deck workflow. No App Store Connect, TestFlight, bundle ID reservation, authentication migration or new fleet credentials.

## Steps

Use real SQLite with a controlled failure to test each setting family. Make writes return success or use candidate commit setters while preserving SwiftUI bindings. Prevent observer recursion on rollback. Apply deck reordering only after long-order save succeeds. Save the two prompt-response settings atomically, using a narrow repository method if necessary, without schema changes. A failed prompt decision must leave both persisted values and the deck ordering unchanged.

Before editing, read AGENTS.md, NATIVE_APP_PLAN.md and the relevant existing tests. Compare the scoped files against the planned commit. If scope must expand, report the exact reason to the coordinator before editing overlapping files. Use the smallest necessary seams; avoid broad refactors and dependencies.

## Verification

Run focused core settings storage regressions on Linux. Propose the smallest production seam for SettingsPersistenceTests and obtain coordinator scope approval before editing shared package files. Request SDK compilation of AppModel. App-unit and existing DeckUITests/DeckRegressionUITests settings and long-order cases require iOS runtime evidence and stay open when unrun. Existing successful settings reload behavior must pass.

Run `git diff --check`. Content checks are `node tools/content-validate.mjs` and `node tools/content-export-pwa.mjs --check --ruqyah /home/t1nk33r/Projects/ruqyah-al-qareen/content.js` on Luna. Workers lacking the sibling checkout must state that and let the coordinator run the check. All new Swift/XCTest/SDK checks run on Linux under the coordinator queue, with /tmp/hikaya-build-suite.lock then /tmp/athkar-build-suite.lock acquired nonblocking and at most two jobs on Luna. Remote workers return source bundles. SDK compilation, executed portable tests and iOS runtime results are separate evidence; required unrun device cases remain open.

## Delivery

Use the assigned isolated worktree and branch. Commit source and tests after verification. Return a git bundle plus structured result with commit SHA, changed files, exact checks/results, skipped checks, owned processes and released locks. Do not push/merge, change main, remove worktrees or settle your own thread. The coordinator integrates serially after independent review. Do not update PROJECT_MAP.md or other tasks' plan files; coordinator owns those.

Stop and report if the selected model differs from the assigned family/effort, the predecessor gate is not released, a needed lane is busy, an out-of-scope product decision is required, or a shared resource has another owner. Never kill processes by name, stop shared daemons, shut down all simulators or remove another owner's lock. Preserve Eris on CPA and do not launch workers there or on Terra. Only stop PIDs/process groups started for this task.

## Done criteria

The stated goal is covered by meaningful regressions; relevant existing tests pass; no unintended product/content changes; all source committed in the assigned worktree; verification evidence matches the commit; no owned tests/dev servers/lane locks remain running. Final completion additionally requires the opposite-family review and serial merge by the coordinator.
