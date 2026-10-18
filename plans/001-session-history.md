# Restore native session history parity

Planned at `9423e08` on 2026-10-13. Status: RELEASED for independent Athkar work on 2026-10-14; the user superseded the full-settlement hold.
Executor: GPT-6.1 Sol xhigh on Luna. Independent final reviewer: task 002, from the other model family.
Dependencies: None.

## Current state

SessionState.swift currently declares `public static let historyLimit = 7`. Its normalization copies the first seven string dates. SessionRules.rolled prefixes seven entries. Four checked-in PWA load/roll fixture cases fail because the PWA now sanitizes and retains history over 31 local dates.

## Goal

Pass every existing session fixture unchanged. Match the actual PWA normalization and date-window retention, including ordering, duplicate dates, future/invalid dates and local calendar boundaries. Keep native SQL completion history unbounded. Envelope-v1 backup history has an explicit seven-entry contract and must keep it.

## Scope

ios/AthkarCore/Sources/AthkarCore/Sessions/SessionState.swift; Sessions/SessionRules.swift; Storage/AdhkarSessionStore.swift; focused Sessions and Storage tests and spec/schema.md bridge description if necessary.

Do not edit religious text, content pack versions, PWA behavior, golden fixtures, Apple identity/authentication, or features gated after Slice 4. This task fixes existing implementation or its approved deck workflow. No App Store Connect, TestFlight, bundle ID reservation, authentication migration or new fleet credentials.

## Steps

Read the current PWA normalizeState, rollStateToDate and existing fixture cases first. Reproduce the four failures with the session test filter. Port the exact current history rules; distinguish a date window from an entry-count cap. Review the SQL bridge separately so it does not erase or unintentionally hide saved history. Add focused regression tests only for uncovered boundaries. Run the full core suite.

Before editing, read AGENTS.md, NATIVE_APP_PLAN.md and the relevant existing tests. Compare the scoped files against the planned commit. If scope must expand, report the exact reason to the coordinator before editing overlapping files. Use the smallest necessary seams; avoid broad refactors and dependencies.

## Verification

swift test --package-path ios/AthkarCore --scratch-path "$ATHKAR_SCRATCH" --jobs 2 --filter Sessions; then full core suite. All fixture cases must pass with no golden fixture edits.

Run `git diff --check`. Content checks are `node tools/content-validate.mjs` and `node tools/content-export-pwa.mjs --check --ruqyah /home/t1nk33r/Projects/ruqyah-al-qareen/content.js` on Luna. Workers lacking the sibling checkout must state that and let the coordinator run the check. All new Swift/XCTest/SDK checks run on Linux under the coordinator queue, with /tmp/hikaya-build-suite.lock then /tmp/athkar-build-suite.lock acquired nonblocking and at most two jobs on Luna. Remote workers return source bundles. SDK compilation, executed portable tests and iOS runtime results are separate evidence; required unrun device cases remain open.

## Delivery

Use the assigned isolated worktree and branch. Commit source and tests after verification. Return a git bundle plus structured result with commit SHA, changed files, exact checks/results, skipped checks, owned processes and released locks. Do not push/merge, change main, remove worktrees or settle your own thread. The coordinator integrates serially after independent review. Do not update PROJECT_MAP.md or other tasks' plan files; coordinator owns those.

Stop and report if the selected model differs from the assigned family/effort, the predecessor gate is not released, a needed lane is busy, an out-of-scope product decision is required, or a shared resource has another owner. Never kill processes by name, stop shared daemons, shut down all simulators or remove another owner's lock. Preserve Eris on CPA and do not launch workers there or on Terra. Only stop PIDs/process groups started for this task.

## Done criteria

The stated goal is covered by meaningful regressions; relevant existing tests pass; no unintended product/content changes; all source committed in the assigned worktree; verification evidence matches the commit; no owned tests/dev servers/lane locks remain running. Final completion additionally requires the opposite-family review and serial merge by the coordinator.
