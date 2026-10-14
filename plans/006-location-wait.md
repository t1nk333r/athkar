# Bound one-shot location waits and reject invalid fixes

Planned at `9423e08` on 2026-10-13. Status: RELEASED for independent Athkar work on 2026-10-14; the user superseded the full-settlement hold.
Executor: GPT-6.1 Sol xhigh on Luna. Independent final reviewer: task 003, from the other model family.
Dependencies: 010 app-unit-test target.

## Current state

currentCoordinates waits on locationRequest until a delegate callback or caller cancellation. There is no fix deadline. didUpdateLocations returns without resuming when the array is empty, and accepts the last location without checking validity, age or horizontalAccuracy. Generation tracking only covers cancellation.

## Goal

After permission is answered, a one-shot location request reaches success, cancellation or a bounded unavailable result. Empty/invalid/stale fixes must not persist bad coordinates or leave the UI locating forever. Preserve two-decimal rounding, approximate permission and no background requests.

## Scope

ios/Athkar/DeviceLocation.swift; new ios/AthkarTests/DeviceLocationTests.swift; a minimal CoreLocation test seam beside the adapter.

Do not edit religious text, content pack versions, PWA behavior, golden fixtures, Apple identity/authentication, or features gated after Slice 4. This task fixes existing implementation or its approved deck workflow. No App Store Connect, TestFlight, bundle ID reservation, authentication migration or new fleet credentials.

## Steps

Keep the permission prompt free of a timeout as documented. Introduce a configurable fix deadline with a test clock/driver seam. Race cancellation, deadline, late callbacks and a following request. Validate fix coordinates/accuracy and define a documented freshness bound. Take continuations once and cancel only this adapter's request. Add deterministic tests, including denied/restricted authorization.

Before editing, read AGENTS.md, NATIVE_APP_PLAN.md and the relevant existing tests. Compare the scoped files against the planned commit. If scope must expand, report the exact reason to the coordinator before editing overlapping files. Use the smallest necessary seams; avoid broad refactors and dependencies.

## Verification

Propose the smallest production seam needed for Linux XCTest of timeout, concurrency and cancellation, and obtain coordinator scope approval before editing shared package files. Request SDK compilation of the real CoreLocation adapter. CoreLocation-dependent DeviceLocationTests and PrayerTimesUITests permission/manual-coordinate paths require iOS runtime evidence and stay open when unrun. Preserve real permission settings.

Run `git diff --check`. Content checks are `node tools/content-validate.mjs` and `node tools/content-export-pwa.mjs --check --ruqyah /home/t1nk33r/Projects/ruqyah-al-qareen/content.js` on Luna. Workers lacking the sibling checkout must state that and let the coordinator run the check. All new Swift/XCTest/SDK checks run on Linux under the coordinator queue, with /tmp/hikaya-build-suite.lock then /tmp/athkar-build-suite.lock acquired nonblocking and at most two jobs on Luna. Remote workers return source bundles. SDK compilation, executed portable tests and iOS runtime results are separate evidence; required unrun device cases remain open.

## Delivery

Use the assigned isolated worktree and branch. Commit source and tests after verification. Return a git bundle plus structured result with commit SHA, changed files, exact checks/results, skipped checks, owned processes and released locks. Do not push/merge, change main, remove worktrees or settle your own thread. The coordinator integrates serially after independent review. Do not update PROJECT_MAP.md or other tasks' plan files; coordinator owns those.

Stop and report if the selected model differs from the assigned family/effort, the predecessor gate is not released, a needed lane is busy, an out-of-scope product decision is required, or a shared resource has another owner. Never kill processes by name, stop shared daemons, shut down all simulators or remove another owner's lock. Preserve Eris on CPA and do not launch workers there or on Terra. Only stop PIDs/process groups started for this task.

## Done criteria

The stated goal is covered by meaningful regressions; relevant existing tests pass; no unintended product/content changes; all source committed in the assigned worktree; verification evidence matches the commit; no owned tests/dev servers/lane locks remain running. Final completion additionally requires the opposite-family review and serial merge by the coordinator.
