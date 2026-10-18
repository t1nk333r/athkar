# Serialize reminder replans so obsolete requests cannot return

Planned at `9423e08` on 2026-10-13. Status: RELEASED for independent Athkar work on 2026-10-14; the user superseded the full-settlement hold.
Executor: Claude Opus 5.5 xhigh on Mars. Independent final reviewer: task 009, from the other model family.
Dependencies: 010 app-unit-test target.

## Current state

replan() cancels the old Task and starts another. performReplan awaits several notification-center methods, then removes pending requests before checking cancellation again. Its `for item in plan` loop awaits center.add without a cancellation check per item. An obsolete task can therefore finish adding requests after a newer plan disables them.

## Goal

Rapid rule changes, permission changes, completion/reopening and location changes converge to the latest plan. Older work must never delete or re-add requests after the latest plan has settled. Preserve stable IDs, owned-prefix filtering and unrelated notifications.

## Scope

ios/Athkar/Reminders/ReminderModel.swift; new ios/AthkarTests/ReminderReplanTests.swift; a focused notification-center test seam beside the model.

Do not edit religious text, content pack versions, PWA behavior, golden fixtures, Apple identity/authentication, or features gated after Slice 4. This task fixes existing implementation or its approved deck workflow. No App Store Connect, TestFlight, bundle ID reservation, authentication migration or new fleet credentials.

## Steps

Add a narrow notification-center protocol/test implementation with controllable suspended calls. Reproduce disable-during-add and completion-during-replan races deterministically. Implement one serialized worker with coalesced dirty state or equivalent proven ordering. Treat non-cancellable center.add correctly: drain old mutation before final cleanup. Permission failure must be observable and save failure must not trigger success. Do not add new notification product features.

Before editing, read AGENTS.md, NATIVE_APP_PLAN.md and the relevant existing tests. Compare the scoped files against the planned commit. If scope must expand, report the exact reason to the coordinator before editing overlapping files. Use the smallest necessary seams; avoid broad refactors and dependencies.

## Verification

Run core ReminderPlannerTests on Linux. Propose the smallest production seam needed for Linux XCTest of replan ordering, and obtain coordinator scope approval before editing shared package files. Request SDK compilation of the real reminder adapter. ReminderReplanTests that depend on UserNotifications, existing ReminderUITests, and physical termination/reboot delivery remain required unrun iOS runtime cases.

Run `git diff --check`. Content checks are `node tools/content-validate.mjs` and `node tools/content-export-pwa.mjs --check --ruqyah /home/t1nk33r/Projects/ruqyah-al-qareen/content.js` on Luna. Workers lacking the sibling checkout must state that and let the coordinator run the check. All new Swift/XCTest/SDK checks run on Linux under the coordinator queue, with /tmp/hikaya-build-suite.lock then /tmp/athkar-build-suite.lock acquired nonblocking and at most two jobs on Luna. Remote workers return source bundles. SDK compilation, executed portable tests and iOS runtime results are separate evidence; required unrun device cases remain open.

## Delivery

Use the assigned isolated worktree and branch. Commit source and tests after verification. Return a git bundle plus structured result with commit SHA, changed files, exact checks/results, skipped checks, owned processes and released locks. Do not push/merge, change main, remove worktrees or settle your own thread. The coordinator integrates serially after independent review. Do not update PROJECT_MAP.md or other tasks' plan files; coordinator owns those.

Stop and report if the selected model differs from the assigned family/effort, the predecessor gate is not released, a needed lane is busy, an out-of-scope product decision is required, or a shared resource has another owner. Never kill processes by name, stop shared daemons, shut down all simulators or remove another owner's lock. Preserve Eris on CPA and do not launch workers there or on Terra. Only stop PIDs/process groups started for this task.

## Done criteria

The stated goal is covered by meaningful regressions; relevant existing tests pass; no unintended product/content changes; all source committed in the assigned worktree; verification evidence matches the commit; no owned tests/dev servers/lane locks remain running. Final completion additionally requires the opposite-family review and serial merge by the coordinator.
