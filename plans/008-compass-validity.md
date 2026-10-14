# Stop reporting Qibla alignment from invalid or stale headings

Planned at `9423e08` on 2026-10-13. Status: RELEASED for independent Athkar work on 2026-10-14; the user superseded the full-settlement hold.
Executor: GPT-6.1 Sol xhigh on Jupiter. Independent final reviewer: task 007, from the other model family.
Dependencies: 010 app-unit-test target.

## Current state

didUpdateHeading publishes degrees even with headingAccuracy < 0, merely sets needsCalibration. stop() leaves degrees set, and failures are ignored. QiblaView considers any nonnil degrees live and calls Haptics.shared.playCompletion() on alignment without consulting the user's haptics setting.

## Goal

Invalid, stopped or stale compass readings cannot announce confident alignment or fire an alignment haptic. Valid readings recover normally. All Qibla haptics respect the existing global setting. Preserve true/magnetic-north disclosure and no permission request on this screen.

## Scope

ios/Athkar/Qibla/DeviceHeading.swift; QiblaView.swift; ios/Athkar/Screens/HomeView.swift call site only; new ios/AthkarTests/DeviceHeadingTests.swift; focused Qibla UI tests.

Do not edit religious text, content pack versions, PWA behavior, golden fixtures, Apple identity/authentication, or features gated after Slice 4. This task fixes existing implementation or its approved deck workflow. No App Store Connect, TestFlight, bundle ID reservation, authentication migration or new fleet credentials.

## Steps

Introduce the smallest testable heading-reading policy or injectable adapter. Validate accuracy and finite heading, clear/suppress stale state on lifecycle/failure and handle late callbacks after stop. Pass the existing haptics setting to QiblaView rather than adding another preference. Test invalid accuracy, valid recovery, lifecycle, magnetic/true headings and haptics disabled. Do not change the Qibla bearing math.

Before editing, read AGENTS.md, NATIVE_APP_PLAN.md and the relevant existing tests. Compare the scoped files against the planned commit. If scope must expand, report the exact reason to the coordinator before editing overlapping files. Use the smallest necessary seams; avoid broad refactors and dependencies.

## Verification

Run core QiblaTests on Linux. Propose a minimal production seam for portable validity/alignment tests and obtain coordinator scope approval before editing shared package files. Request SDK compilation of the real heading adapter and UI. CoreLocation-dependent DeviceHeadingTests, QiblaUITests and physical sensor/haptic cases require iOS runtime evidence and stay open when unrun.

Run `git diff --check`. Content checks are `node tools/content-validate.mjs` and `node tools/content-export-pwa.mjs --check --ruqyah /home/t1nk33r/Projects/ruqyah-al-qareen/content.js` on Luna. Workers lacking the sibling checkout must state that and let the coordinator run the check. All new Swift/XCTest/SDK checks run on Linux under the coordinator queue, with /tmp/hikaya-build-suite.lock then /tmp/athkar-build-suite.lock acquired nonblocking and at most two jobs on Luna. Remote workers return source bundles. SDK compilation, executed portable tests and iOS runtime results are separate evidence; required unrun device cases remain open.

## Delivery

Use the assigned isolated worktree and branch. Commit source and tests after verification. Return a git bundle plus structured result with commit SHA, changed files, exact checks/results, skipped checks, owned processes and released locks. Do not push/merge, change main, remove worktrees or settle your own thread. The coordinator integrates serially after independent review. Do not update PROJECT_MAP.md or other tasks' plan files; coordinator owns those.

Stop and report if the selected model differs from the assigned family/effort, the predecessor gate is not released, a needed lane is busy, an out-of-scope product decision is required, or a shared resource has another owner. Never kill processes by name, stop shared daemons, shut down all simulators or remove another owner's lock. Preserve Eris on CPA and do not launch workers there or on Terra. Only stop PIDs/process groups started for this task.

## Done criteria

The stated goal is covered by meaningful regressions; relevant existing tests pass; no unintended product/content changes; all source committed in the assigned worktree; verification evidence matches the commit; no owned tests/dev servers/lane locks remain running. Final completion additionally requires the opposite-family review and serial merge by the coordinator.
